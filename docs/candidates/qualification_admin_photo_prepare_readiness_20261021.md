# 資格写真prepare：基準写真CASの配備を識別する専用readiness契約

**別候補・未接続・本番導入不可。** PR1309へは混ぜない。旧管理能力v1だけでprepareを許可しないための追加契約。

## 原本と後方互換

前提は既管理保存写真candidate、`97c57e6e` のordered baseline CAS、原support client `70a0378f`（再利用commit `6a9f1f96`）、pure payload `1859338c` とlint追補 `3b9d3bb8`。推測した関数を新規作成せず、保存済み関数原本の局所差分を使う。

- 既 `photo_capability` と `admin_saved_photo_capability` の応答を変更しない。
- 別read action `admin_saved_photo_prepare_readiness` を既存 `personal_qualification_submission` routerから既管理関数へdispatchする。
- 返す専用contractは `qualification_admin_photo_prepare_baseline`、version=1、baseline_guard_version=1、prepare_action=`prepare_admin_saved_photos`。
- 会社UUID・actorUUID・現在のphoto_submission_available、upload=false、max_photos=20、self_approval=falseを含む10keyの応答だけを受理する。
- 旧serverが新actionを持たない、権限拒否、通信失敗、旧capability応答、未知key/version/action/型/他scopeはOFF。別actionへfallbackしない。

既管理関数とrouterのMD5を両方完全照合した後だけ局所置換する。管理関数の許可MD5はbaseline CAS補修済みの本文だけなので、CASを持たない旧candidateへreadinessだけを追加できない。既関数のOID/owner/ACL/search_path/security-definerを保持する。新function、GRANT、RLS、Auth設定、table/schemaは追加しない。二回適用・未知本文は55000でtransaction全体を拒否する。

## client境界

`AdminSavedQualificationPhotoPrepareReadiness` は厳密な専用parser。旧v1管理capabilityをreadyと誤認しない。既未接続capability repositoryにread methodを追加するが、既定OFFとscope失効ルールを共有し、製品画面から呼ばない。

pure prepare commandは生成時にreadiness、payload取得時にcurrentReadinessを必須とし、管理capabilityと両方のscope一致を要求する。後からreadinessが失効するとcommandを不可逆失効し、旧snapshotが戻っても復帰しない。これらはサーバー認可の代用ではなく、既prepare/submit/approveの現在権限・基準CAS・別actor承認はそのまま必要。

## 実行結果

- PGlite 0.3.14：`verify_qualification_admin_photo_prepare_readiness.mjs` がbase photo / prepared capability deltaの2構成で成功。
- 既baseline verifierを再利用し、旧candidateのprepare前表示差を再現→CAS補修→新readinessを適用して検査。CAS前への適用拒否、旧serverで新action未提供、専用応答、旧2応答の不変、現在feature OFF/他actor/他社/未指定会社/不正UUID/account false・NULL拒否、readによる正式row/queue/Storage metadata不変、既関数metadata保持、CAS継続、二回適用拒否を確認。
- 純粋Dart：既payload31項目と専用readiness29項目が成功。package:sk_works importとstdout.writelnを使用。一時package configだけで実行し、Flutter起動なし。
- node --check / formatter構文読取 / diff-check成功。
- repositoryの既定OFF・専用actionのみ・旧応答/例外でfallbackなし・late actor ABA・disposeのFlutter用4testsを追加したが、Flutter analyze/testは**未実行**。formatterには既存flutter_lints未解決警告あり。未実行を成功扱いしない。

初回の新SQL verifierは、JS文字列置換に含む `$$` が置換メタ構文で単一`$`に変換され、合成account helper再定義時に42601となった。fixture挿入をcallback置換へ修正し、同じ2構成が最終成功。製品SQLや本番に起因する失敗ではない。

## 残る条件

- 本番の原本・所有者・ACL・helper意味論・既削除/保守影響・backup/restore・native並列検証を完了していない。既candidateの導入blockerはそのまま。
- readinessは配備時の契約表明であり、以後の未知server変更や通信相手の真偽をクライアント単独で証明しない。正規認証/TLSとサーバー側認可が前提。
- 正式prepare送信、応答ID/対象照合、明示submit、結果確認、commit不明時の同一request復旧、製品画面への接続は未実施。
- 写真全除外は資格本体DELETEではなく承認付き添付変更。Storage原本や資格本体を削除しない。
- 本番接続/DDL/DML・Auth/RLS変更・実招待/通知・GitHub送信・PR1309共有ファイル変更・Release作成/導入は0。
