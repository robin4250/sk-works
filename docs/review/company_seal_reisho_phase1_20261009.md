# 真正隷書の会社設定：phase1

新任意書体 `aoyagi_reisho` と従来 `legacy`。既存会社default legacy、既存ON/OFF不変更、既存確定明細/合意/税/会社元データのbackfill無し。会社設定で実会社登録名のPDFプレビュー・印刷・共有・書体保存、作者利用条件/解説を開く。プレビューは一回生成した同じbytesを使用。残る4種類は未完成表示。

このphaseでは3帳票サービスへ新書体を接続していない。画面とヘルプに試験用で現在の印影を変更しないと明示する。phase2で新帳票のfuture-only snapshotへ接続し、過去確定印影へ現在設定を後付けしない。

新RPCは会社ID明示、既存owner/adminとaccount_access_allowedのみ。新列はdefault legacy・enumCHECK、既存RLSとrole変更0。既存ON/OFFロードと新style/assetエラーは別管理。複数membershipの場合に会社を推測しない。style保存は会社行lock後、権限とプレビュー時の会社名を再照会してreject、未対応字/長名reject。新migrationはCLI2.120.0 migration newで作成、本番未適用。

最小32pt角印に対する4.5pt glyph寸法は試験用の小さすぎる文字を拒否する技術的閾値。全社名の実印刷可読性保証ではない。現在16文字まで、未対応字や長い24字社名は保存拒否するがPDFで問題を確認可能。将来の帳票寸法やバランス改善で再検証する。社名省略/法人格変更/普通書体fallback無し。既存legacy配置とフォントは維持。

PGliteでdefault・exactcompany・owner/subadmin/otheradmin/blocked/anon・不明style・会社名変更・欠字・長名・privatehelperACL・既存switch/保存済snapshot不変更を検証成功。ローカルFlutter SDK無し、実FlutterPDF/PNGは専用CIで生成し目視予定。実機導入/本番DB/TestFlight公開は未完。

関連：研究PR #808に正規font取得・実寸旧3列比較資料。CODH画像はここへ採用していない。
