# 管理保存写真の専用能力契約（review-only）

基準local `131012ca`。既存管理写真candidateと同じqueue／同じaction APIの最小拡張。製品mainにこの能力契約はまだなく、既存本人向けphoto_capabilityを管理権限の証拠にしない。

新actionは `admin_saved_photo_capability`、入力は `{company_id:<exact UUID>}`。既存personal_qualification_submissionから既存管理helperへdispatchし、新RPC／関数／queue／uploadは追加しない。

|応答key|契約|
|---|---|
|version|整数1|
|contract|qualification_admin_saved_photos|
|company_id|要求したexact会社UUID|
|actor_id|現在のauth.uid UUID|
|photo_submission_available|現在同社owner/admin所属と既存has_company_feature(can_manage_people)がtrueの時だけtrue|
|photo_upload_allowed|false|
|max_photos|整数20|
|self_approval_allowed|false|

現在account不許可／不明／未認証は拒否、会社UUID不正・不足は拒否。他会社／一般member／feature OFFはavailable=false。会社に所属する別actorへ応答を使い回さない。能力は時点の表示用情報であり、管理prepare／submit／approveの既存実行時検査を省略するtokenではない。

後続clientは上記8keysと型・値・会社・actorを厳密照合する。不在／旧本人応答／旧version／未知version／未知marker／余分なfield／upload=true／自己承認=trueは管理利用不可。今回追加したfixture内consumer oracleはこの受理契約の検査であり、製品clientがすでに実装・有効化されたという意味ではない。本人photo_capabilityのkey／値／upload判定の意味は変更せず、baseとprepared capability-only deltaの各構成で追加前後のresponse完全一致を検査した。

PGlite0.3.14で管理candidateの2構成が成功。旧backendで新actionが能力を返さないこと、厳密response、現membership／feature OFF／account停止、旧本人能力と不正応答の拒否、能力取得後の権限変更によるprepare拒否を検査。既存queueの保存写真→別reviewer承認、初回INSERT、本人photo／legacy metadata承認、CAS／history／ticket／lock順source契約／retry検査も同じfixtureに維持した。無変更のpersonal-photo verifier、prepared-upload verifierも成功。

実行ログ：`qualification-admin-capability.log`、`qualification-capability-personal-baseline.log`、`qualification-capability-upload-baseline.log`（scratch）。合成permission/account helperと単一接続、prepared capability-only deltaの限界は従来どおり。実production helper／全RLS／実JWT／実Storage／nativePG競合／maintenance・DELETE／manager個別許可／管理metadata編集UI／実機の未検証を解消しない。導入HOLDを維持する。

Supabase skillと公式Database functions資料を参照済み。変更はreview-only SQL、隔離fixture、本資料だけ。既存のqualification_admin_saved_photos_candidate_20261019.mdの「能力応答未実施」は当時の記録として保持し、本資料がlocal能力設計の到達点だけを更新する。製品migration／本番／RLS適用／認証／権限設定／公開push／SDKは変更ゼロ。


## account helperがNULLの場合の追補

管理helperの共通入口を `uid is null or private.account_access_allowed() is not true` に統一し、能力分岐内の重複したhelper呼出を除去した。元の本人APIの判定は変更していない。

既存draftを作った後、隔離fixture内だけでaccount helperをNULL返却へ一時置換し、管理能力・新prepare・既requestのget／submit／cancel／approve／rejectが全て42501で拒否されることを検査。正式rowとqueue全rowのJSONが完全一致のままであることをassertした。元helperのpg_get_functiondefを復元して能力再取得と既存2構成の全検査が成功。無変更personal-photo／prepared-upload verifierも成功した。本番helperや製品migrationは変更していない。

最終ログ：qualification-admin-capability-null.log／qualification-capability-null-personal.log／qualification-capability-null-upload.log。
