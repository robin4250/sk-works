# 資格編集承認の再利用範囲（2026-10-19 JST）

基準: cb7543641f1d762561330d49354d53bdc10da44c。書類の新しい申請契約で資格側まで完了したとは扱わない。既存の本人資格写真申請を再利用し、同じ機能の別queueを作らない。

| 経路 | 保存先・契約 | 到達点 |
| --- | --- | --- |
| 本人資格の初回 | OwnQualificationRegistrationPage._addQualification → QualificationCloudRepository.insertOwnQualification | 初回INSERT。登録後の写真変更とは区別する |
| 本人の登録済み写真 | OwnQualificationPhotoSubmissionRepository → personal_qualification_submission / prepare_photos・submit | 既存の固定request・旧snapshot・承認後反映を再利用 |
| 資格写真の審査 | QualificationPhotoSubmissionReviewRepository/Page → approve/reject | 既存。書類のreview UIと対象IDを混用しない |
| 管理側の表/裏/追加写真 | QualificationCertificateRepository.uploadCertificate/uploadCertificateBack/uploadExtraCertificate 等 | 現状は正式rowへ直接UPDATE。新しい要求に対して未完 |
| 管理側の写真除外 | 同repo.removeCertificate/removeCertificateBack/removeExtraCertificate | 現状は直接UPDATE。ファイル保持だけでは承認必須化の代用にならない |

管理側を既存の本人photo APIへそのまま送ると、prepareの本人worker一致検査により拒否される。資格の管理権限を持つという理由だけで検査を削除しない。管理側の変更案も同じ既存申請履歴へ固定し、現在の会社・対象社員・対象資格・元snapshot・申請者の現在権限を審査時に再確認できる拡張が必要。

また、旧client/APIの正式row直接変更を保護しない限り、UIだけ申請へ変更しても承認必須を保証できない。既存の承認RPC自身の正式UPDATEは許可された単一の承認処理として通す必要があり、直接変更を一律禁止するだけでは既存の正しい審査を壊す。初回INSERT・審査による反映・管理側直接編集の三経路を分けて検証する。自己承認の扱い、旧申請との互換性、全本番RLS/Storage共存は適用前に既存承認条件と照合する。

隔離PGlite 0.3.14で既存source fixtureを再実行し、次が成功した。

- verify_personal_qualification_photo_submission.mjs: 固定prepare/submit再確認、旧内容CAS、対象限定承認、保存済み写真再配置、全写真除外、送信停止、履歴保持。
- verify_qualification_prepared_upload.mjs: 保存済みmigrationによる限定下書きupload、actor/account/stateの拒否、保持、Storage policy合成順2通り。

これは既存契約を再利用できる根拠であり、実JWT/実Storageサーバー/全本番RLS/管理側編集承認の完了を示さない。今回、資格の製品コード・migrations・本番データ・RLS・Auth・Storageに変更はない。
