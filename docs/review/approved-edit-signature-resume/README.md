# 同一承認sessionでの署名再開候補

未適用。製品側の明示再開呼び出しは候補内で接続し、本番RPCは未導入。新規承認を作らず、現在の `active` session と `used` request、live actor/SID、会社、日報の元データが完全一致する場合だけ、旧署名4欄の残存を正常な未署名draftへ進める。既old_report/old_roster/old_annex、元署名、手当receiptは変更しない。

`core.sql` は隔離試験用の関数定義。`resume.sql.review-only` は同じ定義と依存原典ガードを含む候補。両方とも本番適用権限ではない。catalog列・ACL/configを含むfresh前提と新オブジェクト不存在の厳密guardを追加し、独立レビュー後に適用対象として提示する。正式migrationを手書き日時で作らない。

`dependency-pins.json` はrootが今回READ ONLY採取した関数とテーブル列のmetadataから作成し、業務rowを含まない。本番の既存writerの4 CASE修正（将来の開始不具合）と、この再開（既にused/draft/署名残存となった状態）は別の適用対象である。

専用native PostgreSQL17試験は既存RED/fix連鎖を加工せず別driverで拡張する。full auth/provider E2Eではなく合成認証fixture。実機不具合のactual対象row原因は未照会・未確定。HOLD維持。

新2関数はowner/ACL/SECURITY DEFINER/search_path/volatility/bodyのpostassert付き。未知のcustom default ACLが残る場合はトランザクション全体を中止する。専用native試験にpublic/private schemaそれぞれの未知default ACLを作る隔離負例を含む。本番default ACLは事前に完全一致を要求し、変更しない。
