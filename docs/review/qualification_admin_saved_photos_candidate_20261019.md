# 管理側資格写真編集：既存queue拡張の隔離候補

基準 `a08d4175`。**review-only／本番導入不可**。新しいsubmission queueやupload APIを作らず、既存private.qualification_submissionsに管理保存写真modeを追加し、既存personal_qualification_submission action dispatchから利用する候補。UI・製品migration・本番設定は未変更。

## 今回証明した最小範囲

owner/adminの登録済み資格に対する保存済み写真の並替・除外（全写真除外を含む）だけを先行した。prepare_admin_saved_photosはexact company/target/request IDと既存path slotsを取り、既存qualification_photo_submission_resultの形を返す。submit／approve／reject／get_photos／cancel_photosは既存action名とqueue IDを利用する。extension slotsは拒否し、新uploadは常にOFF。delegate managerの個別許可はまだ有効にしない。

prepare時・submit時に現在の同社owner/admin＋can_manage_people＋accountを再確認。審査時には別の同社owner/admin／既存approval assigneeという審査基盤に加え、現在can_manage_peopleを要求し、自己承認を禁止する。申請者の現在owner/admin所属とaccount許可も再照合する。対象workerは現在同社かつactive、資格masterも同社、旧qualification全snapshotが一致することをsubmit／approveで検査する。

元has_company_featureの保存されたSQL（20260920022000_harden_attendance_and_approval_privacy.sql）はowner/adminならtrue、一般／managerはmember_feature_permissions等から決める。今回はこのowner/admin分岐に範囲を絞った。**fixtureのfeature/account helperは合成stubであり、本番現行helperの同等性・会社機能OFF・権限管理仕様の保証ではない。** actor別featureを任意の申請者に対して調べる新APIやauth.uid偽装を作っていない。現行production helperの定義・会社機能設定との照合は導入阻止ゲートのまま。

## 正式row更新の保護

登録済みworker_qualificationsへの実内容UPDATEは、非公開一回permitがなければ拒否する。permitはactor／transaction／request／target／旧snapshot／期待new snapshotと一致し、queueがpendingで別申請者の場合だけ消費する。GUC単独の許可ではない。直接roleのpermit INSERT・helper実行は不可。正式承認の直前だけ既存関数へ最小アンカーpatchを入れ、既存photo approveと旧single-photo metadata approveの正規UPDATEを通す。

初回INSERTと内容不変のtimestamp-only UPDATEは保持する。no-op承認でもpermitを先に消費し、残留しないことを検査した。直接DELETEは承認経路がないため候補では拒否する。このDELETE／maintenance制限の本番影響は未調査であり、そのまま導入してはならない。DB ownerの運用更新もguard対象となるため、バックフィル・保守・退職／削除処理との統合レビューが必須。

既存2関数のbody MD5を最初に固定照合。photo bodyは元photo版と保存prepared-upload migrationのcapability-only差分版の2つだけを許可する。アンカーがない／drift／依存helper不存在ならtransactionのDDL前で停止する。既存関数全体を推測で再作成せず、pg_get_functiondefの既存属性とACLを保持して局所差分を適用する。今回の候補は再適用migrationとして完成しておらず、2回適用は拒否される。

## 検証結果と限界

PGlite0.3.14 disposable fixtureの2構成が成功：元photo source／prepared capability-only delta。同queueの管理申請→submit→別reviewer approve→写真反映、初回INSERT、本人photo contractと旧single-photo metadata contractのprepare→submit→approve互換、全写真除外、旧snapshot CAS、他会社拒否、申請者権限剥奪・account停止、reviewer権限剥奪、worker/company/master/active変更、feature OFF時prepare/submit/approve拒否、自己承認拒否、直接metadata変更拒否、permit直接INSERT拒否／残留ゼロ、photo history保持、Storage access原典不変を検査した。drift時はpermit表も作られないことを検査した。

既存fixtureは変更せず別途再現成功：

- verify_personal_qualification_photo_submission.mjs：固定prepare/submit retry、CAS、対象限定承認、旧契約互換、全写真除外、pilot OFF、証跡保持。
- verify_qualification_prepared_upload.mjs：限定upload・account/actor/state拒否・保持・Storage policy合成2順序。

新fixtureはprepared migration全体を適用した本番相当Storage環境ではなく、既存保存sourceから抽出したcapability deltaと合成helperで共存を検査する。元prepared-upload migration全体の既存fixture成功と混同しない。実JWT／実Storage／全本番RLS／ネイティブPG並列競合／本番advisorsは未検証。

初版 `8c5dae6f` のprepareはadvisory/qualification→request、approveはrequest→advisory/qualificationで逆転していた。ローカル修正候補では、既存personal photo prepare原典（`20261010233011_personal_qualification_photo_submission.sql`）と同じく、対象の無lock読取後にrequestをFOR UPDATEで先取りし、advisory→qualification FOR UPDATEの後はrequestを通常再読取する。現在の所属・owner/admin・feature・account・target identity・snapshot CASと承認条件の検査は移動も緩和もしていない。最初にrequestが存在すればrequest→advisory→qualification、存在しなければrequest行lockなし→advisory→qualification→通常再読取になる。不存在行にgap lockがあるという前提は置いていない。

この局所修正により、既存requestのretry prepareがqualification lockを持ったまま同requestをlockする経路を除いた。既存photo prepare/旧metadata approveの保存原典は変更していない。旧実装と共存した真の二接続検査は依然未実施で、INSERT一意制約待ち・複数対象を同じtransactionから触る場合を含めdeadlock非発生を主張しない。権限・所属・account変更との並行commit境界も本番同等に保証していない。**ロック順sourceの逆転修正とネイティブPG競合保証は別であり、導入不可を維持する。**

### ロック順修正の隔離検証

既存verifierへ、実際にcandidateを適用した`pg_proc.prosrc`からprepareのrequest lock→advisory→qualification lock→非lock request再読取の順序と、submit/approve側のrequest-firstを調べるsource契約を追加した。元candidateのままではrequest読取が1個しかなく期待2個に対して失敗するREDを保存し、上記2SQL文の差分後はbase photo／prepared capability-only delta双方で成功した。これはsource構造の回帰検査であり、並列lock取得を実観測した試験ではない。

同じPGlite fixtureの既存権限/CAS/permit/全写真除外/直接変更拒否/互換試験を保持し、同UUID・別slotsの23505拒否、pendingとapprovedでの同UUID retry、approved retryで正式row不変を追補して双方成功。無変更のpersonal-photo verifierとprepared-upload verifierも再実行成功。PGlite0.3.14の合成stub・単一接続という限界、production helper・full RLS・実JWT／Storage・native PGの未確認は変わらない。

一次資料：[PostgreSQL 17 Explicit Locking](https://www.postgresql.org/docs/17/explicit-locking.html)、[Supabase Database functions](https://supabase.com/docs/guides/database/functions)、[Supabase breaking-change index](https://supabase.com/changelog?types=breaking-change)。複数資源を一貫した順序でlockする原則を参照したが、資料から当該候補の全競合安全性を推定していない。

## 未完のまま残す範囲

- 管理者のcertificate_number／issuer／issued_at／expires_at／notes等を同じqueueへ申請するUI/API拡張は未完。直接変更を塞ぐ候補を作っただけで、管理側編集全体を完了扱いしない。
- 新upload、delegate manager、能力応答・UI接続、通知、実機確認は未実施。
- production function定義／所有者／ACL／RLS／worker.status enum／削除・退職・保守、backup/restore、既存承認条件との照合が必要。

公式Supabase changelogとDatabase functions、PostgreSQL trigger visibility資料を確認。SQLを実行したのはこの隔離fixtureのみで、製品migration生成／本番RLS適用／公開push／CI dispatch／実通知はゼロ。

実行ログはscratchのqualification-admin-candidate.log／qualification-existing-photo-baseline.log／qualification-existing-upload-baseline.log。失敗した追加fixtureでは初回INSERTのテストがreviewer roleのままだったためownerへ戻す操作を修正。さらに同内容写真の承認で一回permitが残る境界を検出し、no-op判定より先にpermitを消費する修正を入れ、最終成功を確認した。
