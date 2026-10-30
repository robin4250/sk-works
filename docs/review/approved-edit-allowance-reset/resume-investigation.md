# 承認後に責任者サインを再入力できない問題の再開条件

対象ソース: main `2d9e02981d02d2f9e4a017f65af1af84a3a8394a`。今回の実機報告は不具合継続として扱う。本人端末のDB行はまだ照会していないため、下記の隔離再現と実対象の原因を同一視しない。

## 既に再現済みのサーバー不整合

現在採取済みの writer (`bf537e2cac395236c2f8d3d245ffc639`) は会社共通手当がある日報の内容不変の承認編集開始で、申請を approved → used、日報を signed → draft と進めるが、代表者・責任者の旧サイン4欄を保持する。既存 native PostgreSQL 試験 `tool/verify_approved_edit_allowance_reset.mjs` はこの RED 状態と、4 CASE 修正 (`075b62ee12e02f4aeb04f6c20bbfd3d3`) による将来の正常開始、元サインと手当履歴の保持を確認する。採取済み source は本番最新の保証ではない。

クライアント `_beginApprovedEdit` は「draftかつ旧署名が消えた」ことを要求するため、このケースでは開始成功として扱わない。責任者カードは保存済み署名のプレビュー（閉じるのみ）になる。正常な未署名状態になる前にクライアントだけで署名ボタンを強制有効にしてはならない。

## 3状態を混ぜない

| 状態 | 必要な処理 | 禁止する近道 |
| --- | --- | --- |
| signed、未使用の承認あり、明示確定履歴なし | 既4 CASE修正後に正規の開始を1回実施 | 旧署名を画面だけで消す |
| draft、承認used、旧署名が残存、同一actor/SIDのactive編集sessionあり | 既sessionに固定した再開・正常化。旧署名・old_report・old_roster・old_annexは保存したまま新署名を取得 | usedをapprovedへ戻す、再申請を強制する、一般draft writerを復旧RPC代わりに再送する |
| 明示確定済み／管理者修正対象 | 勤怠管理の正規修正・再署名経路を確認。現行finalized保護は維持 | generic approved editに戻す、finalized guardを外す |

## 再開機能に必要なサーバー契約

1. `shared_report_edit_private.current_session` / `evidence` により live actor、実JWT session_id、会社、report、request、used、activeを照合する。クライアントのSharedPreferencesや公開申請のusedだけで許可しない。
2. reportをlockし、expected_updated_atと現在の署名scopeをCAS照合する。会社所属とlive sessionを同じ処理内で再照合する。
3. immutable old_report の両署名と現在の残存署名が一致し、対象・日付・作業内容・メンバー・時間・手当が開始時の原本と一致することを照合する。新しい署名や変更済み内容は復旧操作で消さない。
4. finalizedイベント／management_reports対象を拒否する。関連する金融・給与・勤怠は書き換えず、rolloutを有効化しない。
5. 正規のサーバー側更新で「旧current署名4欄だけnull」のdraftへ進める。old_report等の原本は一切変更しない。開始が既に済んだ再試行は同じ結果を読み取り、新規申請や二重確定を作らない。
6. クライアントは返却されたreport/request/actor/会社と未署名draftを再読込で確認してから「報告者→責任者→編集完了」へ接続する。取消・ログアウト・別SID・scope変更は中止する。

現時点で上記の新再開RPCは実装・適用されていない。4 CASEの将来修正だけを既に壊れたdraftの救済と報告しない。新しいserver mutationは本番HOLDの対象であり、fresh原典・依存catalog・隔離試験・復旧手順・明示承認が揃うまで適用しない。

## 必要な試験

旧writerによる承認消費＋署名残存から、同じ既sessionで再開→新報告者サイン→新責任者サイン→完了する実SQL連鎖。元署名history、手当receipt、勤怠・給与・請求の保全を検査する。別actor、別SID、失効、別会社、別request、新しい署名、内容変更、finalized、応答消失と再試行を拒否／冪等性で検査する。UIはpreview-only旧サインと編集入口を明確に分け、キーボードと空欄・点サイン防止を保持する。
