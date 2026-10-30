# 承認編集の将来修正と既存session再開の原子的導入候補

本番HOLD。新しいUI・認証変更は含まない。PR1636 head209feeの署名再開coreをSHA256固定し、既4 CASEのwriter修正と同じtransactionへ組み合わせる。4 CASE部分は既候補とbyte一致を試験し、別実装を作らない。

- 将来の承認開始: `bf537e2cac395236c2f8d3d245ffc639` → `075b62ee12e02f4aeb04f6c20bbfd3d3`。変更は署名保持CASEの条件4箇所だけ。
- 既にused/draftとなった編集: live actor/SID/request、元データと残存署名の一致を再確認して明示再開する新2関数を追加する。新しい申請を作らない。
- 後半の関数属性/ACL確認が失敗した場合は、先に置き換えたwriterも原文・全catalog属性へrollbackし、半端な導入にしない。
- 正常導入では既存日報・メンバー・申請・session原本・給与行を一切変更しない。既存の壊れたデータを一括修復するSQLではない。

専用native PostgreSQL17検証は既old-writer RED/4 CASE正常化/原本保持の実SQL連鎖を拡張し、unknown default ACLでの全rollback、正常の単transaction導入、履歴row不変、使わない停止区間source-only復旧のrehearsalを追加する。合成認証/providerであり、実GoTrueや本人の不具合日報そのものの成功保証ではない。

`atomic-core.sql.review-only` は隔離fixture向けcompositionであり、本番へそのまま適用しない。今回READ ONLY採取した全table/column/constraint/trigger/function/defaultACLとwriterの完全属性を固定した非公開guarded forwardと、未使用source-only復旧候補を別途準備している。新関数にもexact owner/ACL/SECURITY/search_path/bodyのpostassertを要求する。正式migrationの作成・本番適用は明確な承認後に別工程。

復旧はwriter停止とinflight終了を確認し、対象source/属性がまだ一致する場合だけ新たに判断する。日報を既に編集・再署名した場合、関数コードを戻しても元データは戻らない。署名・給与・勤怠・請求の自動巻き戻しや一括削除は行わない。原本と履歴は維持する。

実機の旧画像対象はsigned/approved/サーバーholdなし・active sessionなしであり、この既stranded状態ではない。新しい音声報告の対象行は同一と未確認。別状態の復旧を本人の不具合原因確定・実機完了と扱わない。
