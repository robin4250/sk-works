# 出勤3日・請求2日の切り分け（担当B）

基準: main d70b90b9f19f854e8f13c00c4a1e66fbfeb4235e、作業基準075b4004。実機対象の個人・会社・日付・金額は含めない。本番照会・修復・再計算なし。

## 既存調査との関係

`attendance_clock_only_work_completion_20261019.md`は、過去の限定照合で3日打刻に対し勤務記録が2日だった点と、打刻のみの日を未確定として既存勤怠管理へ表示する対応を記録している。これは今回の実機対象の再照合ではなく、不足日の実勤務確定や請求書3日反映の証明でもない。

現在の通常請求一覧は、管理権限・署名退勤契約が準備済みの場合に`refreshSignedCheckoutInvoices`から会社範囲の既存RPCを呼ぶ。更新失敗は保存済み表示へ切り替える旨を表示する。通知専用入口は読み取り専用を維持。ここに日数を3へ書き換える処理を追加しない。

## 今回追加した独立回帰

`tool/verify_invoice_three_day_evidence.mjs`は既存`verify_route_signed_checkout_billing.mjs`のsynthetic PGlite fixtureと実SQL generatorを再利用する。新しい金融ロジックやfixture schemaを複製しない。ネットワークDB指定を明示拒否し、既存fixtureの中の独立トランザクションをrollbackして既存検証も維持する。

検証成功:

- 同一worker・customerで、複数現場を回っても署名根拠のある2日分は2人工。
- 3日目に出退勤打刻だけを追加しても2人工。日報・署名・勤務を自動捏造しない。
- syntheticな3日目に正しい日報・署名・参加者・現場訪問・勤務の根拠を順に構成し、最後の既attendance INSERT triggerで未確定請求が3人工へ更新。
- 会社範囲refreshの再実行でも3人工のままで重複なし。
- 登録単価のある残業を既存勤務へ追加すると、人工3を保ち金額だけを再計算。
- 確定後の勤務変更・refreshでも既確定snapshotと総額を保持。

初回の追加fixtureは未登録の手当名を使って「編集」を表現したため、その日が単価未確認としてblockedになり人工表示が2へ減る既存guardを踏んだ。実装を緩めず、登録済み残業単価と残業時間の編集へfixtureを修正して成功。人工の集計は残業時間・福利費の行を含めず、`quantity_contract=one_per_worker_day_customer`の基礎行だけを用いる。

実行:

`node tool/verify_invoice_three_day_evidence.mjs /tmp/sko-validation/node_modules/@electric-sql/pglite/dist/index.js`

既存4群の結果に加え、新しい3日根拠回帰PASS。Node構文・git diff --check成功。Flutter起動は親からの拒否境界に従い行っていない。

## 残条件と非保証

この検査は20261013署名退勤契約と既存generator fixtureの経路。後続のcheckout起源receipt候補、全本番schema/RLS/trigger、単一現場の全経路、実機対象の補完承認、PDFの表示を証明しない。新たに確認できたinvoice固有コードの欠落がないため製品コード・共有勤怠DBを変更しない。

本番の該当worker/月を限定し、不足日の日報・署名・勤務・現場・取引先・単価と稼働関数を照合する工程が残る。正規の原本補完または承認済み修正後、対象未確定請求を更新して保存値・画面・PDFで3日分を確認する。原本保護と復元準備を先に整え、確定済みは保持する。
