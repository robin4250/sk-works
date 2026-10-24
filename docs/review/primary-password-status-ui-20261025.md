# 第一パスワード三値表示（backend候補への接続）

基準main `fdef41a2ea98fcbb7db3019296cc1e8d08fcaa06` のPanel7 repository/testsをsnapshot `5502f67` に保存。page/testはメールguidance `2b4c22c` を保持するdependent候補で、root PR1376の同じ原典へ重ねる。main直接変更・本番DDL・setter重複なし。build14候補wyの保険/手当配布とは独立。

## 表示契約

`PanelSevenRepository.load()` は既getUserで検証した元tokenを明示して、引数なし `primary_password_configured` RPCを読む。結果が実boolの場合だけ採用する。bool true=設定済み、bool false=未設定、RPC未導入/拒否/通信失敗/型違い/timeout=取得不能null。メール認識やGoogle identity、AMR、第二pwから第一pw有無を推測しない。

新callの前後でもactor/token/期限を照合し、待機中の別actor/新tokenへ旧結果を適用しない。追加RPC以外の認証操作・session発行・ログアウト・refresh・password送信はない。未知状態でプロフィール全体を失敗させず、既Google/確認済みメール/電話/第二pw/Face IDの表示を保つ。

ページは設定済み/未設定/取得不能を分ける。#1351の現在のログインに限る保存receiptは保持し、取得不能の時でも完了した保存確認を取り消さない。新たな明示false応答が来た場合だけ旧receiptを消去し、falseを受けた後にRPC不明へ戻っても古い保存確認を復活させない。保存callback直後は後続read前の古いsnapshotより完了済み操作receiptを優先する。actor/session変化・背景化・遅延応答制御は既処理を保持する。

「？」ヘルプも三値の意味へ更新。既メールguidanceは保持する。認識済みメールを新登録させたり、表示確認のため同じ設定を繰り返させない。

## backend依存と未適用時

対象はPREPARE ONLY自己boolean SQL `ebc682c` / 専用remoteCI `f37534c` の `public.primary_password_configured()`。本番APIは現時点で未適用・本人status未読である。UIを先に配布しても404等はnullなので、本人画像の第一pwを未設定と断定しない。導入後の本人状態・実メール/passwordログイン完了も未確認。

rootがbackend専用GoTrue/PGlite結果、catalog/source/ACL guardsを確認し別工程で適用判断する。UI候補はbackend setterや既helperを変更せず、Booleanの真偽を自己アカウントだけで受け取る。

## 回帰候補

repository追加9件: true/falseの厳密保持、文字列false/null/object/404/403/503をunknownとする8形、primary RPC待機中のactor変更拒否。ループバックHTTPで元Bearer使用・既Google/メール/第二pw保持・元session同一・許可済み2RPCだけを検査する。既native生体能力読取試験も新RPC読取を期待へ含める。

widget追加4件: 三値それぞれの区別（3件）と、新しい明示falseが旧保存receiptを置換し後のunknownで復活しないこと。既1351の成功receipt/actor切替消去、背景・遅延応答、メール案内の試験を保持。

`git diff --check` 成功。localFlutter禁止に従いanalyze/tests未実行。rootがPR1376 baseの別PRへ公開してremoteCIで検証する。本番credential/本人session/実SMSやメール送信は操作していない。
