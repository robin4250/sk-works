# 管理側資格写真：選択結果からprepare payloadへの純粋client slice

別候補。アプリ画面・ネットワーク・本番DBへは未接続。資格本体やStorageの削除処理を追加しない。

## 再利用元

既存 `origin/support/admin-saved-photo-client-20261019` / `70a0378f0c635b31fe9665a50ce603a54cb5d9f5` の8ファイルを、内容を再実装せず `6a9f1f96` としてcherry-pickした。既存の管理能力contractとローカルdraft選択UIを使う。

`AdminSavedQualificationPhotoDraft` の値クラスだけを未接続ページから `admin_saved_qualification_photo_draft.dart` へ移動し、元ページでimport/exportする。クラス名・constructor・immutable list・呼出側の既存import APIを保持し、製品画面とルーティングは変更しない。Flutter annotationは純粋モデルから外したが、listの実行時unmodifiable保護はそのまま。

## 追加する生成・検証

`AdminSavedQualificationPhotoPrepare.fromDraft` は既draft値・管理専用capability・固定request UUIDと現在scope/target/表示済み基準写真を受け取り、immutableな申請値を固定する。`toPayload` でも最新capability・scopeActive・会社/actor/target・順序付き基準写真を再照合する。scope不一致を一度観測したcommandは失効し、同じactorへ戻ったABAでも復帰しない。

payloadは以下の5項目だけ。

- company_id
- target_id
- request_id
- expected_photo_paths：表示済み基準写真の順序付き配列
- photo_slots：選択後の順序に並べた `{existing_path: ...}` のみ

capability/会社/actor/target/申請UUIDの不正、基準が空・20枚超・重複・空白、選択写真の重複・未知path、現在の基準写真の追加/順序差を拒否する。選択が空ならphoto_slots=[]として全写真除外申請を表す。actorの権限主張、upload、Storage delete、資格本体deleteはpayloadへ含めない。同じcommandからは固定request IDを再利用する。

payload map、基準配列、slots配列、個々のslotもunmodifiable。元draftや入力listの変更は固定済みcommandへ伝播しない。

## 検証

`dart --packages=<一時package_config.json> tool/verify_qualification_admin_photo_prepare.dart`

Flutter起動・pub get・通信を含まない純粋Dart実行で31項目成功。正しいordered payload、全写真除外、入力list変更、deep immutability、scope/target/基準差、能力失効、ABA失効、固定request IDを検査した。formatter構文読取とgit diff-checkも成功。依存解決未実施のためformatterは既存flutter_lints解決警告を出した。Flutter analyze/widget testは未実行で、既UI移動の型互換をFlutterで検証済みとはしない。

## 接続前に必要な残条件

- backendは先行 `97c57e6e` の表示基準CAS補修が前提。旧candidateはexpected_photo_pathsを無視するため、このpayloadを旧backendへ送信して安全になった扱いにしない。
- 管理capability version1自体はCAS補修の有無を区別しない。本番接続時は対応版を証明するserver readiness/契約を別途確定し、旧serverへのfallbackを行わない。
- 既UIのscope監視・不可逆失効と、最新の正式row/写真取得を正規callerから渡す。純粋commandは実認証や未観測の背景/actor変更を自力で保証しない。
- 正規prepare→応答対象確認→明示submit→結果確認・不明commit時の同一request復旧を未接続のまま残す。ネットワークを再試行していない。
- 本番導入・資格本体削除・新upload・既存製品画面変更・外部送信・GitHub pushなし。共通ヘルプ/翻訳/workflowはroot統合担当が接続時に更新する。

### lint追補

toolのlib参照をpackage:sk_works import、出力をdart:io stdout.writelnへ変更した。一時package configでsk_works rootUriだけをこのworktreeへ向け、Flutterを起動せず31項目を再確認した。本番・画面接続の境界は変わらない。

### readiness候補の追補

後続の `qualification_admin_photo_prepare_readiness_20261021.md` に、旧capabilityを変更しない専用read actionと、CAS補修済み本文だけへ適用できるreview-only契約を準備した。pure commandは生成時・payload取得時とも専用readinessを必須に変更。隔離検証済みの別候補であり、本番配備・画面接続済みではない。
