# 書類・資格の編集承認と表示設定（2026-10-19 JST）

## 今回の要求

初回登録後の書類・資格の変更は承認後に反映する。社員資格書類から必要書類の表示・非表示を設定し、非表示の項目は本人の書類登録に出さない。非表示は削除ではなく、保存済み提出内容・写真を保持する。

## 表示設定のローカル実装

既存 document_requirements.is_active を利用し、新規schemaや権限を追加しない。WorkerDocumentPage.settings だけが管理権限確認後に非表示も取得し、確認ダイアログを経て表示/非表示を切り替える。通常の社員別一覧・本人一覧は表示項目だけ取得する。本人画面も is_active=false を除外する。復帰は同一IDに限定し、会社ID・actor・期待する旧表示値を確認する。提出済みstatus/写真やStorageは変更しない。

## 承認の現状（未完了）

- 本人資格の初回登録は QualificationCloudRepository.insertOwnQualification で登録する。写真の変更は既存 own_qualification_photo_submission_repository / qualification_photo_submission_review_repository と personal_qualification_photo_submission 契約を再利用する。
- 書類は WorkerDocumentRepository.saveOwnDocumentPhotos/saveOwnDocument/updateOwnStatus/saveAttachmentPhotos(own:true) から登録済み正式rowに直接反映する。管理側の saveManagedDocumentPhotos/updateStatus も直接反映する。既存mainには書類用の変更申請・承認契約がなく、今回のreview-only候補で準備した。
- 資格の管理側 QualificationCertificateRepository にも写真等の直接変更経路が残る。本人写真だけを承認制にしても全編集の承認必須を保証できない。
- 公開中PR #831/#833は本人写真upload停止/INSERT例外/保持の検証候補で、書類編集承認そのものではない。停止や保持条件を解除しない。

## 次の実装契約

1. 書類の正式rowと変更申請snapshotを分離する。初回登録と既存編集をサーバーで区別する。写真・期限・メモ・資格情報の変更範囲を一貫して扱う。
2. prepare時に会社/対象/actor/元revision・内容を固定し、申請IDによる再確認を可能にする。添付は新規immutable pathとし、既存写真の上書き・削除をしない。
3. submitでpendingへ移す。正式内容は変更しない。取消・却下でも元内容を保持する。
4. reviewで現在の所属・承認権限・対象会社・添付の存在・元内容一致を再確認する。競合は失敗にして再申請を促す。承認時だけ一括反映し、申請履歴を固定する。
5. 本人・管理側・旧APIの直接更新経路を含めて制御する。UIだけの制限で承認必須としない。自己承認等の既存承認条件を照合する。
6. 非表示に変更された対象の新規登録・申請・承認をサーバーでも再確認し、過去の提出履歴は保持する。
7. 対象の取り違え、別会社、actor切替、競合、同じ操作の再送、取消/却下、添付失敗、権限喪失を隔離fixtureで確認する。

専用申請backendと旧経路保護は docs/candidates/worker_document_change_20261019.sql.review-only に準備し、保存済みsourceの隔離PGliteで10境界組を検証した。製品migrationではなく、実PG17・全本番RLS・同時実行・既存初回互換・FK cascadeへの影響は未確認。本人・管理側の既存保存画面、固定command永続化、変更申請一覧・差分確認・承認却下UIはローカル接続済み（ae59d9df/e9e81e1e）。本番DB/RLS/Auth/Storage変更、公開push、CI起動、Macビルド、iPhone導入は行っていない。既存のバックアップ・隔離復元・承認条件を満たすまで本番適用しない。

## ローカル接続と残る適用条件

`worker_document_change_repository.dart` は新しい `worker_document_change` RPC専用の候補transport。固定申請ID・会社・社員・書類項目・申請者・元更新時刻・変更内容が一致する応答だけを受理する。新規upload/自己承認を許すcapabilityは拒否。ログイン変更（A→B→Aを含む）・Auth streamエラー・disposeで無効化し、二重commandを拒否する。結果不明時に自動再送せず、同一申請IDのdetailで確認する。API欠如時は利用不可とし、旧直接UPDATEへfallbackしない。

本人・管理側の登録済み内容は変更申請へ進む。初回prepare前に固定commandを端末保存し、不明なsubmit結果は同IDで確認する。承認一覧は同会社の社員名・書類名と差分を確認し、承認直前にも再認可する。名前不明・自己申請・別actor・背景移行・競合は拒否する。API不在時に旧直接保存へ戻らない。新しい写真upload、実機での承認、本番適用は未実装/未検証。資格管理側の直接更新保護も別途必要。


2026-10-19 JSTの追加検証: 書類表示・承認transport・経費通知を合わせた13ファイル120テストが成功。書類backend候補10境界組は統合後に再実行成功。既存の本人資格写真承認は再利用候補で、管理側資格の直接更新をこの書類候補で保護したとは扱わない。

統合後の共通検証は通知・書類18ファイル158PASS（skip0）、解析16対象問題なし。全通知は本文説明を先に開き、関連対象は従来のID・権限・利用設定を再確認する。背景移行で通知セッションを失効させ、遅い対象読取の帰着後も既読保存・遷移を続行しない。リンクのない通常通知だけ本文表示後に既読保存する。未知・不正対象を別申請へ置換せず、対象解決失敗時の未読保持と業務状態は区別する。
