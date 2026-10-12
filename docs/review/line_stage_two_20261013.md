# LINEトーク 第2段階

第1段階#952（標準トーク受信/保存/閲覧）を基底に、トークボタンの下へ「出勤表」「請求書」を追加する。トークは常時利用。追加2機能はMasterが個別ON/OFF、初期OFF。OFFでも過去データ・受信は残る。

## 操作

- グループと対象月を選ぶ。受信済みのテキストを再取込、またはユーザーが書き出したLINE履歴を貼り付ける。
- 日付・現場・作業員が明確な行を抽出。読取不能、同日重複、未照合、元投稿変更は要確認。作業員/現場ID、人工、残業、早出、勤務区分、登録手当名を修正する。
- 個人別表示と確認済み集計。LINEノートの集計を貼り付けて照合し、確認したdraftを保存。未変更の元投稿の修正は再取込後も保持する。手動履歴と新受信を併用し、履歴を受信再取込で消さない。
- 出勤：選択作業員または100件以内の確認済み行を署名して通常の過去勤怠申請へ送る。既存承認待ちとなり、ここでは出勤を自動確定しない。
- 請求：登録済み設定による取引会社別/月別/現場別の金額を確認し、普通の請求書下書きを作る。通常の承認手順を維持する。既存同取引会社/月の請求書を上書きしない。

## 保護と保存

- 新規private設定/draft/command receipt/正式登録receiptを分離。既存Master設定・認証関数・給与計算・給与承認関数・route日報を置換しない。
- flagsは既存`is_current_user_master_admin()`でMasterだけ変更可能。draft編集は既存勤怠管理権限、請求は管理者＋既存請求管理権限。一般閲覧は本人worker IDの確認済み行だけ。元のトーク全文や他社員の候補/LINEノート本文は返さない。
- 受信元は実在する同会社/同グループのLINE message ID/body/timeを確認。過去履歴はユーザー提供の手動資料として区別。異なるsource kindを混在保存可能。
- command UUIDは内容に結び付け、同じ再送は同じ結果。期待revisionで編集競合を拒否。ログイン変更後の古い画面からの書込みも拒否。
- 正式出勤は既存requests/entriesとLINE receiptを確認し、NOWAIT table locksで既存手動申請との隙間を閉じて通常RPCを呼ぶ。既存writerと循環待ちにしない。LINE申請済みの日に限定した入力guardで、後続の通常申請・実績INSERTによる二重登録も拒否する（給与計算/既存approval bodyは不変更）。同日登録は拒否し、勤務修正で既存データを確認する。却下された申請は古いreceipt履歴を保持して再申請できる。
- LINE請求の入力根拠をprivateで保存し、一般invoice計算の登録方法・共通rate helper・単価overrides・会社税率・現場福利率・登録手当を使う。旧一般計算ブロックのbody部分hashを移行時に確認。未登録・ゼロ単価の手当は金額作成前に要確認として拒否する。初期15%/10%を全社へ固定しない。
- ルート請求の実日報証拠を偽造しない。invoice lockを取得して全体を原子的に生成、同月の既存請求書を拒否。確認した金額fingerprintが設定変更で変わった場合は再確認。会社/現場/取引会社設定はquote中SHARE NOWAITで保護し、invoice scopeもtry-lockにする。確定請求書/過去給与を書き換えない。

## 検証

`tool/verify_line_import_drafts_sql.mjs`はCLI生成migrationをPGlite0.3.14/PG17へ実行。OFF保持/Master限定/一般本人のみ/他社拒否/源変更/同日重複/期待revision/immutable retryを確認。実際の既存`submit_past_attendance_request`で署名→承認待ち、二重申請拒否、出勤実績は未登録のままを確認。

請求は合成2人工、現場単価20,000円、福利8%、会社税10%で47,520円。実際の現在`refresh_automatic_invoice`で同じ数量を計算したsitesと金額に一致。単価変更後の未確認生成を拒否。普通のdraft、再送1件、同取引先/月の二重作成拒否を確認。

専用CIでPG17二接続の同command待機/同receipt、独立二重作成拒否、Master OFF待機、既存請求/出勤writerの逆順lockと同日二接続INSERTを検証する。Flutter候補・再取込・月集計・公開トーク/追加ボタン・時間ラベルのテストと解析、通常Flutter/iOS/Secret CIを最新headで確認する。

## 未実施と本番導入

本番第2段階migrationは適用していない。実LINE投稿/一般本人・管理者・Masterの実JWT確認、請求PDF/印刷/共有と署名申請のiPhone実機操作は未実施。コード/fixture/CIと本番・実機は区別する。

本番は既存対象function body、ACL、関連表/請求/勤怠/給与のdigestを退避・保持確認してから同migrationを適用。第1段階のEdge復旧とは別工程。既存のsource hashが異なる場合は最新差分を再確認し、旧functionを押し戻さない。
