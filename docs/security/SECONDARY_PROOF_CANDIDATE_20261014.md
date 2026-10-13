# 第2パスワード変更proof候補（ベータ版・隔離検査専用）

このPRは設計候補と専用PostgreSQL 17検査です。本番migration、Edge、Flutterの変更を含みません。既存Face ID再設定を拒否する更新を本番へ適用しません。検査成功は本番防御の完成を意味しません。

## 現行機能を維持する前提

初期設定・変更・忘れた際の復旧が同じ `set_secondary_password` を使用しています。再設定画面はFace ID/Touch IDまたは本パスワードの確認を先に行いますが、その成功証跡をサーバーへ渡していません。本パスワード検証の一時Authセッションは元アプリセッションと別で、終了されます。生体認証成功booleanや新しいJWT発行時刻を本人再確認の代用にはできません。

## 最小候補

| 操作 | 候補のサーバー条件 | 検査範囲 |
| --- | --- | --- |
| 初期設定 | 現actor/session有効、資格情報がまだない。既存行への上書きを拒否。 | 合成auth.sessions、SQLロール。 |
| 第2パスワードで変更 | サーバー内で既存verifyを実行し、成功時だけticketを発行。失敗はnullで返し既存失敗回数をcommit。 | 実bcrypt/SQL関数。 |
| 本パスワードで復旧 | EdgeがAuthへ本パスワードを検証し、検証結果user IDと元actorを一致させ、元sessionを確認してservice-only issuerを呼ぶ。 | このPRはissuer権限だけ検査。Auth呼出し・Edgeは未実装。 |
| Face ID/Touch IDで復旧 | サーバーに登録された端末鍵で短命challengeへ署名するなどの別契約が必要。 | このPRでは未対応。成功フラグを信頼しない。現行機能の移行方法が決まるまで本番導入不可。 |

ticketは32byte乱数、サーバーにはSHA-256だけ保存。actor、元session、変更操作、既存資格情報の版を結び付けます。5分はSKO候補の選択値です。消費と資格情報変更を一つのtransactionにし、単回消費、失効・期限切れ、他actor/他session、古い版を拒否します。credential→ticketのロック順で並行消費を直列化します。

fixtureでは `auth.sessions` の本人行をshare lockし、削除済みsessionを拒否します。合成のaccount restriction表も拒否条件です。**本番のアカウント削除barrier/helperとAuthのsession寿命・失効は、この合成表で証明したことにはなりません。** 本番統合時は既存pre-request/Edge制限helperを維持し、実際のsession schema・期限・取消とraceを別検査します。

## 本番導入前に必要な作業

1. 忘れた際のFace ID復旧を維持する方式を決める。端末鍵なしに現行の操作をサーバー保証できると主張しない。
2. 本パスワードissuerのEdgeを実装し、Auth失敗、user mismatch、元session取消、短命proof、秘密の非ログ化と一時session終了を検査する。
3. 現行setの既存上書き経路を閉じるmigrationとFlutter切替を同時に用意する。このPRのfixtureだけを適用して閉じたと扱わない。
4. ticketの保存期間・期限切れ掃除・発行頻度・誤検知解除を定める。ticketをログ/資料/クリップボードへ保存しない。
5. 本番定義guard、隔離CI、正常初回設定/本パスワード復旧/Face ID復旧と実機検査を完了し、統括担当が適用する。

検査は実秘密・社員・会社・本番接続を使いません。匿名/直接private呼出し/クライアントからservice issuer呼出し、欠損・偽ticket・短いパスワード、期限、再送、他actor/session、資格情報更新後、制限中、取消session、実ロック待ちを検査します。
