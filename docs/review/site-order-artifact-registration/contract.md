# 押印注文書・請書の原本登録：最小再利用契約（未接続）

追加の外部署名基盤・producer鍵・新しい配送網は導入しない。
既存の認証、会社・管理者権限、登録角印、正規の会社連携、canonical承認本文、
不変の承認記録と原本ハッシュを利用する。

## 再利用する既存候補

`trade_document_consent_private.prepare_document` は本人の会社と一意のaccepted会社連携、
版/CAS、会社の向き、登録名を検証する。`decide` が登録自社角印の明示同意と本文版を
記録し、`render_approved` は承認済み本文・登録角印snapshot・body_hash/render_hashを
返す。受信者は発行者の角印を再利用して自社請書を発行してはならない。

`trade_document_confirmation_api_private.actor` は現UID・JWT claims・auth.sessionsを
照合する。この再利用候補のowner/admin条件をmanagerへ黙って緩和しない。
サブ管理者の許可は独立hubの正規権限契約と合わせて別途適用・検証する。

これらはリポジトリにあるreview-only候補であり、本番導入済みではない。
2026-10-30のpg_procメタデータ照合では、指定したconsent/confirmation API関数は
存在せず、`public.company_uploaded_seal_settings(uuid)`だけを確認した。
書類・給与等の実データは照会していない。従って既存本番APIを直結したという
扱いはしない。候補コードと本番導入状況を分離する。

## 登録までの順序

1. 現在の会社・本人・live session・管理権限・master設定・現場・相手の会社連携を
   検証したcommandから、保存済み承認書類の正確なdocument ID/revisionを取得する。
2. サーバーが`render_approved`を呼び、approved本文・角印・render_hashをジョブへ固定。
   クライアントが作った`sealed:true`、任意の会社情報、PDF hashだけではジョブを作らない。
3. 内部のcanonical rendererが、そのジョブの不変本文・採用済み条項・登録角印snapshot
   だけから正式PDFの実bytesを生成する。既存`TradeDocumentFormRenderer.canonical`
   と同じ正式デザインを再利用し、別レイアウトを勝手に採用しない。
4. private登録関数がジョブと承認原本を再照合し、実bytesからSHA-256と長さを計算。
   immutable原本と登録receiptを同時保存する。同じジョブ・同じbytesの再実行は同receipt、
   異なるbytesは拒否し原本を上書きしない。
5. 共有・承認・請書返送はこの原本ID/版/hashに結び付け、会社・現場別画面は同じ原本を
   参照する。一般sitesやnotesへ金額・原本URLをコピーしない。

## 実不足と接続を止める条件

現行の正式PDF renderer はFlutter/client経路であり、サーバーでcanonical PDFの実bytesを
生成してprivate登録まで行うadapterは未提供。登録関数にuser uploadを直接通す公開API、
またはservice_role所持だけをcanonical描画の証明にする近道は採らない。
private関数はクライアントへgrantせず、内部renderer commandが実装・検証されるまで
availabilityはOFFのままにする。これは新しい外部鍵を要求する問題ではなく、既存正式
rendererを実行するサーバーadapterが不足しているという一つの接続課題である。

原本の受注会社ID・正式名・発行側登録trade ID・実際の接続状態のopaque fingerprintを
ジョブとreceiptへ固定する。company_connectionsには整数version列がないので仮の1を
発行しない。指定された正規trade IDと承認原本の相手ID・役割・linked状態、一意accepted
会社接続を再照合し、接続rowと登録リンク/正式名のserver側SHA-256を版として返す。
会社名や登録先・接続状態が変わった後の旧jobの新登録を拒否し、旧原本は書き換えない。
user操作はdraft確定→相手選択→その宛先入り最終原本prepare→単価/会社/版の再確認→共有。

オフラインfixtureは既存の実際のconsent候補SQLと合成Auth/sessionを利用する。
テスト用PDF bytesによるhash/不変性の試験を、正式PDFの視覚一致や本番JWT、
実サーバーrenderer、実配送の証明に読み替えない。

## review-only SQLの対象

`private-register.sql.review-only` は新しいprivate schemaへ不変render_jobsとpdf_records、
`prepare_job` と内部専用 `register_canonical_pdf` を追加する候補。
既存actor/require_actor/render_approvedと共有mastergateのsource MD5・owner・SECURITY
DEFINER・search_path・匿名/client EXECを照合してから導入する。既存関数は置き換えない。
共通mastergateはC候補の `private.require_trade_documents_master_feature()` を再利用する。

prepare_jobは現在の自社現場と承認済みの正式条項metadataを確認し、callerのPDFや
sealフラグは受け取らない。登録PDFのhashはDBがbyteaの実内容から生成する。
原本bytesをbyteaとして保管する構造候補であり、本番のprivate storage移行を実施した
という意味ではない。将来storageを使う場合も同じ原本hash/不変receipt/アクセス境界を
維持し、任意URLやobject metadataだけを内容検証の代わりにしない。

この内部関数をclient/service_roleへgrantすることを接続方法としてはならない。
内部renderer commandが承認済みevidenceだけを読んでbytesを生成することが必要。
生成処理が未提供なので、SQL単独を本番適用したりcapabilityをONにしない。

テストは専用driverが既存canonical manifestの全blobを照合し、元harnessを変更せず
一時moduleへ追加fixture呼び出しだけを挿入して実行する。終了時に一時moduleは削除。
旧source-bound gateのmanifestや原本harnessの固定hashを緩和・更新しない。

## 実測

2026-10-30 PGliteで初期登録fixture **23 checks passed**。
同時に既存consent **238 checks**、採用原文save **18 checks** が成功。
対象は原本hash・同request再実行・別bytes拒否・別actor/site/SID拒否・session削除拒否・
masterOFF拒否・client/service EXEC拒否・原本更新削除拒否・既存guard属性/金融値不変。

`site_order_master_gate.fixture.sql` はC候補gateのbodyをそのまま利用し、source MD5
`0dc45a5f0611ccbd832b77a03c0beb1a`を登録候補が照合する。周辺reauth関数は既存API.actor
の合成claims/auth.sessions検証へ委譲するfixtureであり、本番reauth helperの代用品を
デプロイしたわけではない。ネイティブPostgreSQL17と実rendererは別の未確認段階。
