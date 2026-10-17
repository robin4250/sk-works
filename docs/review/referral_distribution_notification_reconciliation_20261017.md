# SKO-020／031／038：既存成果と残件の読取照合

基準source：Draft #1234 `3aa57d2fb0b9be74187ba4ea9023d70fb5d4d784`／tree `9410240e7413e012b9a3c47b08845b695ca902c2`。既存main `de0470d616b480d98ee84ec47fb67ee4b5ea036e` に含まれる成果を照合した文書のみ。本番照会・変更、機能有効化、外部送信、Mac操作、製品・DB/Auth/RLS/権限・給与数量の変更は0。親#1234のbranch/headを変更しない。

| 管理項目 | 実装済みの根拠 | 依然残るもの |
| --- | --- | --- |
| SKO-020 紹介登録・ポイント・管理者通知 | [#1046](https://github.com/robin4250/sk-works/pull/1046) head `3136bb2c743fd9d0c456631c67f40510cc6d4253` はmerge済み。`app_referral_repository.dart`／本人・Master入口／ホーム「SKO招待」が存在し、履歴・can_invite・公開OFF・SMS作成状態を扱う。#1046に本番基盤の適用報告あり。 | trusted onboardingによる本人確認・最終紹介者確定、二重付与防止、実ポイント付与・プロフィール反映、登録完了時のマスター通知。source dispatchはprepare/opened/settings/snapshot/masterだけで、通知ON/OFF保存は登録イベントとの接続を意味しない。 |
| SKO-031 社員へのTestFlight／WEB URL追加案内 | 旧[#1081](https://github.com/robin4250/sk-works/pull/1081)はDraftだが、修正版[#1110](https://github.com/robin4250/sk-works/pull/1110) head `6b4a7cb6d23f2079a9e3c1841a094aecce8ee555` はmerge済み。初回登録作成済み行の「URLを追加送信」→employee目的の既存AppReferralPageへ名前・電話を渡し、QR／passwordを再発行しない。 | 新channel APIと正式URLの利用条件、初回登録の会社別URLとの一本化、旧flags保存read→write競合、実機。TestFlight配布HOLD。実SMS／共有／メール等は行わない。新RPC未検出だけの限定fallbackと友達への旧試験URL送信禁止を保持。 |
| SKO-038 全通知の対象直結 | [#1085](https://github.com/robin4250/sk-works/pull/1085)の通知強調／対象遷移、[#1105](https://github.com/robin4250/sk-works/pull/1105) head `d80e73ee97e27de9df836f7a8fd62b65cd8aa3de` の車両ID直結、[#1109](https://github.com/robin4250/sk-works/pull/1109) head `4e65ca2998a690e9b0d2d7ba31d65b04da92ee09` の打刻ID／JST対象日直結がmerge済み。 | `site_map`は汎用map、`worker_personnel_change_completed`はPeople一覧、`document_register`は書類一覧、chat招待はgroup一覧、`company_document_delivery`はrouter caseなし。給与は対象月までで特定社員を選ばない。遷移先で読取失敗しても既読化し得る既存順序・実機確認も残る。 |

## 重複実装を防ぐsource照合

main de0470は#1110／#1105／#1109各最終headをancestorとして保持。以下の各blobは最終PR headと現mainで一致し、#1234でも対象sourceは変更されていない。

- #1110：`lib/features/referrals/app_referral_repository.dart`、`lib/features/people/employee_initial_registration_page.dart`、`test/app_distribution_repository_fallback_test.dart`。
- #1105：`lib/features/operations/vehicle_route_page.dart`、`test/vehicle_document_notification_target_test.dart`。
- #1109：`lib/features/attendance/attendance_notification_page.dart`、`test/attendance_notification_target_test.dart`。

通知routerの現sourceは `vehicle_documents` に `initialVehicleId`、`attendance_today` に `verificationId`を渡す。[旧棚卸し（Issue #273 comment 6207903182）](https://github.com/robin4250/sk-works/issues/273#issuecomment-6207903182)のこの2系統の「一覧fallback」は当時の記録で、現在の未実装事項として再作成しない。その他の残件は上表のとおり。source包含は実機・本番RLS・配信成功の証明ではない。

紹介基盤の本番反映は#1046に保存された報告を参照する。今回そのledger・設定値・招待件数を独立取得していない。新規登録帰属・ポイント・登録完了通知はsourceでも未接続であり、基盤適用報告から完成と推論しない。`docs/app-referral-rollout.md` の古い未適用／入口未接続表現だけを訂正した。

検証：固定headのGit ancestry、上記7pathのblob一致、現notification routeと紹介dispatchの読取を確認。新規fixture／UI／通知resolverの実装、既存CIの再実行はしていない。旧成功CIを新候補のruntime成功として転用しない。
