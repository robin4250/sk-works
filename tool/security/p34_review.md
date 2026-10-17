# P34 — atomic personnel composition, review only
This new-file candidate reuses the exact three existing migrations (04441, 113335, 120458), not a new permission design. No original source, payroll, UI, user, company, provider, business row or production database is changed.

The generator has no database/network dependency. It accepts only SHA256-identical UTF-8 input and exact outer begin/commit bytes. It removes only those fixed outer bytes, retains every body byte in order, adds a single outer transaction with 5s lock/30s statement timeouts, preserves the original guard checks, and checks exact output function hashes and original OID/owner/ACL/config. No automatic fallback or migration ledger write is supplied.

Four target objects: two SELECT policies, private.employee_personnel_rows(), private.can_edit_worker_personnel(uuid). Public wrappers, payload/save/approval functions and legitimate OFF-manager approver path remain original. The policy contract remains authenticated PERMISSIVE SELECT; original exact body inputs are fixed by SHA256. It is not a ready-to-run production deployment command.

The new fixture hash-pins and reuses the existing personnel-write synthetic setup before its existing mutations. It deliberately omits the two prior standalone migration calls and tests the combined transaction instead. Existing direct-read, legacy-read and write suites run unchanged in separate empty databases via a CI matrix. New checks cover a deliberate exception after all four changes but before COMMIT, exact full rollback, legitimate role matrix, unchanged synthetic business/Auth/provider/master/company/ACL state, exact selected-original restoration and reapply. Existing HTTP suites retain the actual signed-JWT role tests; the added atomic fixture uses the same database adapter and reuses the hash-pinned existing direct/canonical HTTP matrix after applying the complete atomic transaction. Existing write/approval HTTP scenarios run unchanged in their separate suite.

## Pending / mandatory operational gates
CI success is pending until recorded for the exact PR head. No native production archive restoration has been verified here. Backup-time differences/current new recovery emails remain blockers. This fixture restore is synthetic, not actual recovery proof.
Before production: verify latest protected backup and isolated actual four-object/dependency ACL recovery; freeze all external DDL writers (advisory locks alone do not exclude them); compare fresh live baseline and admin/company/role/provider state; rehearse failure/limited rollback; get explicit approval with exact target SQL and interruption risk. Do not db-push unrelated migrations or change migration history blindly.
Restoring original policies reopens the known OFF-manager leak. It is an emergency restoration, not permission to distribute. LINE rollout is independent and remains separately blocked by R29 and later candidates. No full DB restore may overwrite newer recovery emails.

## Production change report template — not an approval request

Fill every pending field with private evidence before presenting approval. This section itself does not authorize execution.

### 提示する変更

- 対象project: ztktgquxvcxcjxtluspu
- 採用Git SHA: **未確定**。承認時のexact SHAと生成SQL SHA256を記録する。
- 生成SQLの現在固定値: `500e3aa4620a85ad193bd912f475044d8bf9ed84a8605a7932ce2389a5039fd7`。入力3本はgenerator内SHA256と一致必須。
- 変更対象は次の4件に限定。LINE境界、給与、ユーザー、会社所属、roles、Auth/provider、端末・復旧メール設定、他migrationは含めない。

| オブジェクト | 変更内容 | 正常利用への影響・比較 |
|---|---|---|
| public.worker_personnel_profiles / personnel profile read | SELECTをauthenticated＋既存canonical閲覧条件へ合わせる | 本人維持。正当admin/委任者維持。権限OFF managerの同僚住所等を拒否。viewerは既存active範囲を維持 |
| public.worker_family_members / worker family members read | 同条件を家族情報にも適用 | 上記と同じ。本人と正当閲覧者を拒否しないことをREST/RPC/画面で比較 |
| private.employee_personnel_rows() | legacy一括取得にもaccount accessとcan_manage_peopleを要求 | OFF managerの一括読取を拒否。元からrole制限のあるlegacy経路を一般従業員向けに拡張しない。本人読取は既存canonical/direct経路で維持 |
| private.can_edit_worker_personnel(uuid) | 本人または同社の正当編集担当者に限定 | 権限OFF managerの同僚変更・変更申請を拒否。登録済み承認担当者の独立した承認経路は維持 |

### 保存・復旧の実証欄

| 必須証拠 | 記入欄 |
|---|---|
| 変更直前の保存日時・DB/server/tool版・アーカイブhash | 未確認。古いdumpと現在の収集時点差を解消する |
| 4対象の元定義、policy role/permissive/cmd/qual/check、OID/owner/ACL/config | 最新liveとの一致未確認。秘密・個人値は公開ログに記載しない |
| 依存helper、schema/table/column ACL、workers/company_members、必要Auth/identityとMaster設定の復旧可能性 | actual protected backupからの隔離復元未確認 |
| actual復元環境での4件適用・late failure・限定rollback・再適用 | 未確認。CI合成試験を代用しない |
| 正当admin・会社所属・役割・provider ID・端末・復旧メールの前後一致 | actual復元・変更直前の両方で未確認 |
| Master/admin/委任manager/viewer/本人/他社/匿名/OFFmanager/OFF承認担当者の操作比較 | CIは合成で成功。actual復元および画面比較は未確認 |
| 想定停止時間／実測復旧時間／担当者／失敗連絡先 | 未確定。ACCESS EXCLUSIVE lockと全DDL writer調整を含め計測する |

### 実施条件と復旧説明

承認を提示できる条件は、上の未確認欄が証拠で埋まり、現行管理者・会社・役割を保てること、画面への影響が説明できること、exact変更と実測rollback結果が確認できた場合のみ。これが満たされる前に承認依頼や本番実行をしない。

- 実施直前は別のDDL writerを停止・調整し、保護した元catalogと3本のbaseline guardを照合する。advisory lockだけで第三者DDLを排除できるとは説明しない。
- 4件を単一transactionと有限lock/statement timeoutで扱う。前提driftや後段検査失敗ならCOMMITせず全件rollbackし、残りの変更を止める。広範なdb pushやRLS無効化、role昇格を復旧に使わない。
- COMMIT後の復旧が必要なら、変更時点に保存した元4対象だけを、隔離検証済みの順序で戻す。古い全DBdumpで新しい復旧メール・端末・従業員データを上書きしない。
- 元policyへ戻すと既知のOFFmanager漏出も戻る。復旧成功と安全な配布可能状態を区別し、TestFlightをHOLDする。
- 成功後もID/company/role/provider/復旧設定が一致し、通常作業が見え、OFFmanagerと他社・匿名が拒否されることを確認する。新たなログイン方法・パスワード・LINE公開設定は変更しない。
