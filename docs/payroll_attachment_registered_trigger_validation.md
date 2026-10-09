# 給与確定と証跡添付の実 trigger 結合検証

source 専用。2026-10-09 本番 metadata 読取で取得した関数定義・trigger/FK定義を、main 採用済み給与 source の隔離 fixture に結合する。本番 DDL/DML は実行しない。既存 migration・共有 workflow は変更しない。

## 実行済みの範囲

`verify_payroll_attachment_trigger_boundary.mjs` は既存の実 calculator、resident tax、finalized snapshot、scope/normal API の fixture を読み、実 finalize RPC で正の保存済み document/history を1件作る。その前後で全 payroll_statements/documents/history を比較する。空の snapshot に対する保持保証ではない。

| 呼出 | 実原典と実 trigger の結合 |
|---|---|
| meter attach | staged migration の context/attach 本文を無変更抽出。実 claim/event を typed 前提テーブルへ保存し、roster に event/km が書かれる |
| group attach | staged anchor/attach 本文を無変更抽出。実 clock-in/out の link UPDATE が成功 |
| evidence attach | 本番実 private/public link RPC。写真ありの同日証跡 link が成功 |
| journey attach | staged schema/raw immutable trigger/link 本文。route 証跡 link 成功、payload 書換拒否 |
| roster/report 経由 | 本番登録の署名 clear 2関数と report_refresh_payroll を結合。status 不変なら給与 refresh 本文へ進まない |
| evidence guard | 本番登録の validate_attendance_shift_evidence と trigger を結合。chronology 書換拒否 |
| 旧親 cascade | captured FK の17選択 edgesを結合。会社削除で active PS 消失、論理 doc/history は同一保持。元 owner session の個人 RPC は0件、private source直読は拒否 |
| 通知 sink | captured enqueue/upsert/warnings/refresh と実 app_notifications型。初回通知欠落を再現、active重複0、解消後再開の実 INSERT確認 |

通知初回欠落の改善は別 Draft #864。ここでは原典の欠落を正確に記録し、改善後と取り違えない。

## 境界と継続条件

本番には meter/group/journey attach 関数は未登録。ここでの成功は staged source と本番登録 trigger 境界を隔離で組み合わせた証拠であり、本番機能の完成ではない。claims/rollout等の typed prerequisite は synthetic fixture、権限/RLSの本番全体を再現したものではない。

24 registered triggers 全部や134 FK全部を保証しない。今回直接作用する4 registered triggersと関連17 FKを対象とする。INSERT-only chat/location通知、請求書/payment計算、status遷移による旧/新worker集合、全親graphの削除、実端末は継続条件。外部通知送信は含まない。

generation-setting-issues sink と給与確定の native 2session 同時操作は未検証で、単独 lifecycle と混同しない。専用 workflow は PGlite と実 PostgreSQL 17 の同一 harness を実行する。PG17 起動/検証前の失敗を検証成功として扱わない。
