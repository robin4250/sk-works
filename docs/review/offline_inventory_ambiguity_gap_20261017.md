# Offline protected-inventory ambiguity review（local only）

基準main `b275e683cc65712f12527d165e429a60fbc90c5c`。#1235共通手当適用前レビューと未統合#1188 (`495cb95b9a3039a235fd56d8aeb74952a85b3a31`)、#1209 (`20a1f59ffe48ed08d46707ef8a4ac11f0985cbbd`)、#1213 (`65d9b8341c28306831e5cae125e4721df2b1eedf`) の既存照合を引き継ぐ。追加本番照会、archive取得/読取/復元、Mac操作、SQL実行、外部送信0。

## 既存成果と今回の範囲

#1188の `verify_local_capsule.py` と `test_local_capsule.py` を原commitから取得し、inventory関数の曖昧TOC受入だけを修正する。原候補・既存worktreeを変更しない。collector/資格情報取得/API/SQLコードを候補へ取り込まない。#1209の合成kernel境界、#1213の合成native PG17境界は実archive実行許可ではない。現main#1227の `entry_archive_map.py` は既にroot候補を保守検査するが、#1188の別inventoryには未反映だった。

旧inventoryは `1; 1259 42 TABLE auth users backup postgres` を `auth.users` と誤集計する。二重space（sanitizeされた末尾改行/空白を含む）、空白owner、quoted owner、重複TOC ID/表も拒否しない。現main mapperの `SIMPLE_OWNER` をimportし、raw anchored single-separator規則でtableを検査する。曖昧/未対応table、数値TOC ID重複（01と1を含む）、表identity重複はValueError→既存STOPとなる。TABLE DATA/ATTACH除外、inventory戻り値 `(tables, extensions)`、既存manifest fields/return codeは維持し、manifestに `table_identities_verified=false` を追加する。正常10 protected表とextension集計も維持する。

PostgreSQL17一次source [PrintTOCSummary](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/bin/pg_dump/pg_backup_archiver.c) と [sanitize_line](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/bin/pg_dump/dumputils.c) に関する既存#1227レビューを踏襲する。TOCはschema/tag/ownerを自動解析可能にquoteせず、改行をspaceへ変換する。正当なquoted/非ASCII/空白付き識別子・ownerも現段階では保守拒否する。通過してもstructured metadata/catalog OIDの別照合が必要で、identity verifiedとはしない。extensionも候補名集計に留まり、安全性を判断しない。

## 検証と残条件

専用workflow候補はPython3.9で `python -m unittest test_local_capsule test_entry_archive_map` を実行する。新inventory回帰を含む5件＋現main mapper16件（旧private-only12件を含む）＝**21 tests PASS**。対象4 Python filesはPython3.9 grammar解析PASS。実Python3.9 runtime/remote CIは未実行。依存install/fixture複製は不要。

#1188全Python test filesと原必要sourceを一時dirだけへ取り出し、修正verifier/testと現main mapper/testを重ねたローカル補足検証は **41 tests PASS**。原9filesはTEMPのみで保持しない。fake subprocess/mocked HTTP/keychainのみを使用。実DB/network/SQLを実行しない。再構成時の最終新3 methodsを旧parserへ当てると8 failures RED、修正後GREEN。以前の6 failures記録はduplicate検査拡張前の試験であり、今回件数と混同しない。`git diff --check` も成功。

REQUIREDは既存personnel/Auth/support10表であり、共通手当/identity8対象、roles/ACL、Auth provider/config、Storage bytesを網羅する完全保護inventoryではない。#1235の必要3RPC/8object不存在という保存観測は当時の存在確認で、新しい本番観測ではない。実backup・実復元、backup後時点差と現ID/provider保持、実JWT/DataAPI境界、nonemptyデータを捨てないrollback、具体影響承認の6gateは未充足。offline/P36成功は実archive実行・本番適用・保存の許可ではなく、R31結果待ちも迂回しない。

## 2026-10-18 再構成の保護記録

旧local作業dir、commits `f76473888195fc43115c5893a9eb8fd8bb558350` / `1d00fa1cddc86c4ad818e53393e46a179ecfc4d0` / `bd67146387bc83f15ba416899e6b50df71195e05` と対応treeを既存28repos・隣接scratch/TEMPで探索したが復旧できなかった。会話中のsource/workflowと原#1188からこの最小4filesを新規再構成した。旧tree `d668eab161de4c8627f35d79cab6a8eb6a971e47` とのobject比較は不可能で、同一identityは主張しない。このreviewには新しい再構成記録があるため旧tree再現を目的にしない。

sko-current親Git storeの新worktree/branchへ保存し、保護用manifest・gitbundleをroot outputsへ作る。GitHubへの新code exportは明示承認未受領のため行わない。
