# 現場契約：押印前の操作確認（準備中）

既存の契約候補確認画面の右上メニューから「送信内容を確認」「承認内容を確認」を開きます。既存の最新候補の条件を再利用し、金額を推測・再計算しません。送信時の適用開始日が未登録の場合だけ、人が対象期間内の日付を入力します。

## 人の確認と既存API

- 既存の比較表示を使い、版・期間・内訳・税条件・最終額を確認します。
- `preview_site_contract_seal(p_item,p_company,p_proposal)` の公式 `seal_snapshot` を既存CompanySealPdf rendererで角印だけ画像化します。仮の会社印、氏名、押印済み画像を生成しません。画像化失敗時は操作できません。
- 人が角印を拡大して確認し、条件と印のチェックを明示した場合だけ実行候補になります。
- `seal_hash` はserverが返すSHA256の不透明tokenをそのまま保持し、clientで再計算しません。
- 送信は `send_sealed_site_contract(p_item,p_company,p_expected_revision,p_terms,p_expected_seal_hash)`、承認は `approve_sealed_site_contract(p_proposal,p_company,p_expected_revision,p_expected_seal_hash)` を使う契約です。旧hash無しAPIへfallbackしません。
- 実行直前にactor・最新版・条件・印snapshot/hashを再照合し、保存後の同proposal・版・terms・actor・印との一致を取得できた場合だけ成功表示します。応答不明は自動再送せず、再読み込みで確認します。

従来の金額調整画面は、`site_contract_workspace`で保存済みsealの存在を確認した時だけ押印承認確認へ誘導します。sealed APIが明示的に未配備（42883/PGRST202）の時は既存legacy確認を維持します。その他の取得失敗や不正応答でlegacy承認へ戻すことはありません。既存金額提案・合意・PDFを削除しません。

## 現在の制限・未完了

runtime repositoryは `atomic_seal_version:1`、`rollout_enabled:true`、検証済み送受信会社ID、操作別can_send/can_approveをpreviewで確認した場合だけ有効化します。旧backend・能力不足・OFF・権限不足は無効のままです。配備済みと推測して本番操作を有効化した完成版とは扱いません。SQL/本番DB/共有認証/給与/既存金額計算は今回変更せず、ツールから実変異・通知・押印を実行していません。検証はfakeのみです。

別担当の原子的expected-hash staged backend（PR #1062）と実PostgreSQL競合検査・runtime能力応答が揃った後に統合検証し、本番への配備と会社別rolloutを別工程として確認します。初期OFF・OFF時拒否は維持します。ソース定数を変更しないとONにできないgateは残さず、サーバーの能力と権限・利用状態で判断します。設定ONだけで本番配備や製品完成を意味するものではありません。

実会社印の一致を保証できない場合は準備中のままです。相手の承認を自動作成せず、双方承認と適用日まで現行条件を維持します。契約書PDF/署名capture・請求/支払の適用日別計算との接続、実機確認、本番配備は別工程です。
