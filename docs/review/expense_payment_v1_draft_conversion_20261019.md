# 既存経費加算draftの明示的な差引変更（適用前レビュー専用）

PR #1244のsourceを変更せず、独立branchへ保存した。既v1を自動v2変換する処理は追加しない。既存の方向v2 envelope/guard、計算行、原額component、明細reader、確定時freeze/消費処理をそのまま再利用する。新規SQLは`docs/candidates/expense_payment_v1_draft_conversion_20261019.sql.review-only`、検証は`tool/verify_expense_payment_v1_draft_conversion.mjs`。製品migration・本番適用・公開RPC・給与変更はゼロ。

## 変更対象と条件

対象は会社・document ID・下請けID・完全月・現revisionを明示した自動計算の未確定draftだけ。旧snapshotはsource version 1、経費原額は正数、計算行/現在の承認済み費用配賦/claim revisionと原額が一致する必要がある。既存の給与/現金/支払済みの選択は費用負担の方向と別軸で、一切更新しない。

関数はprivateのsecurity invokerで、PUBLIC/anon/authenticatedの実行権限を取り消す。DB ownerによる限定運用向け候補であり、通常clientから呼べない。auth.uidの会社owner/admin/managerとaccount accessを再確認する。

会社の方向v2 gateに加えて`expense_direction_v2_client_rollout_verified(cid)`も既定falseとする。後者は「対応consumer版利用済み、旧版にv2 rowが誤配信されないことを実際に保証済み」という別条件であり、単なる利用者のboolean入力では解除できない。今回候補は常にfalseのまま。fixtureだけ両gateを検証会社限定trueへ置き換える。機能有効化承認や旧client制御を実装済みとは扱わない。

## 具体的な変更と原本保護

1. オペレーターが対象の全rowをJSONBとして取得・外部backupへ保存し、復元可能性を確認する。`expected_source`はその全row、`expected_hash`はPostgreSQLの`md5(expected_source::text)`。MD5は変更検知補助であり署名ではない。関数はhashだけでなく全rowのJSONB完全一致も必須とする。
2. 既scope lock→対象row FOR UPDATE→対象claim/settlement choice FOR SHAREを取得し、scope/revision/未確定/自動/未ブロック/原本一致を再確認する。対象帳票の消費履歴、対象claimのcost_recovery消費が1件でもあれば拒否する。申請者側の給与精算は別目的であり、この変換で作成・変更・破棄しない。
3. 現計算行と旧計算行が一致し、旧gross/net=作業額+経費、旧deductions=0であることを確認する。複雑な旧控除や未知の計算方式を推測して変換しない。
4. 同じIDでrevisionを1増やし、gross=既作業額、deductions=経費原額、net=作業額−経費原額へ変更する。原額は正数、netは負数を許容。旧snapshotの経費v1の3keyだけを除き、scope付きv2/basisを追加する。他のsnapshot値・社印・状態・精算選択は維持する。既v2 guardが保存値を検査する。
5. 同一transactionでprivate/RLS有効/公開権限なしの監査表に原本全row、結果全row、source hash、外部backup参照、対応版/旧client制御の確認証跡参照、actor、時刻を保存する。UPDATE/DELETE禁止triggerを置く。監査保存失敗を含めtransaction全体が失敗すれば対象rowもrollbackする。DB ownerによる任意DDLやbackupの実体内容までこの候補で強制できるとは主張しない。
6. 同一要求のretryは保存済み原本/参照/現在結果rowが完全一致した場合だけ同一結果を返し、revisionや消費を増やさない。変更後に確定・再編集された場合の古い要求は拒否する。確定は別操作として既finalizerがclaim/revisionを再確認し、初めて1回消費する。

ユーザー画像の作業0/経費1000は旧gross/net=+1000→新gross0/deductions1000/net=−1000。0丸め・繰越・自動送金・債権回収は行わない。請求書の+1000にも触れない。

## 隔離検証

既存`setupExpenseCostFixture`と実migration3本を再利用し、PGlite 0.3.14で実旧generatorから3択それぞれのv1 draftを作成した。方向v2 backend候補と今回候補を適用し、実変換→実reader→確定→消費履歴まで実行した。

- 会社/相手/月/revision/hash/backup・rollout参照/actor不一致、gate OFF、手動、消費済みを拒否し対象値を保持。
- 元の+1000が同じIDの−1000へ変わり、revisionは一度だけ増加。原本監査と結果rowが完全一致。
- 完全同一retryで追加変更なし、変更されたretry拒否、監査UPDATE/DELETE拒否。
- cash/payroll/paid全保存値・既ledger・既確定v1 row全値一致。変換で新消費ゼロ。
- 実readerが新revision/原額1000/v2 envelopeを返し、後の確定でcost_recoveryを1回だけ保存する。
- authenticatedに変換function実行権限がない。

単一接続・合成fixtureであり、実本番schema/関数同等性、native二接続競合、実JWT/RLS、旧client遮断を証明していない。適用前に既バックアップ/復元/承認条件を満たし、それらを検証する。

## 最短の利用開始手順と残る承認対象

PR #1244は安全なopt-in基盤で、現製品callerの`maybeCreate()`は全て既定false。そのPR単独や現在のbuildだけで経費差引は利用開始しない。次のclient buildで実callerを明示trueにする工程が別途必要。server capabilityが不存在/PostgrestException/厳密false/未知構造ならv1 row読取は従来を維持し、capability未許可でv2 rowを読んだ場合は拒否する。非Postgrestのネットワーク例外は読取を停止する。

対応buildを確認し旧clientへのv2誤配信防止を実証後、承認済みのbackend差分を適用し会社gateを有効にする。新draftはその時点でv2になる。既draftは引き続き自動変換されず、今回関数に対象ID/revision/原本/backup/rollout証跡を固定した具体的なレビュー要求を作成して承認後に限定実行する。原本・既消費履歴を保持し、結果のプレビュー/PDF/印刷/共有の−1000整合を対応buildで確認する。承認前に本番・既draftを変更しない。
