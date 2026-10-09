# 会社共通税率設定UI（接続準備）

新ページは既存の請求用消費税率とは独立。会社管理者かつ会社ID取得済みの場合だけ設定画面から開く。

- 料率はpercentage pointの百万分の一整数。小数点以下6桁、0〜100%。double変換や雇用保険の÷2を使用しない。
- 全体／従業員／会社負担を別入力し、合計一致を検証。
- 標準5項目IDはkind固定、customはUUID v4。登録前の数値は未設定と表示し、初期料率を推測しない。
- read RPCの検証済み候補のみ表示。確認日時、情報元URL、保険適用・給与対象・支払年月、差異を表示。
- 確認ボタンは登録済み候補の再読み込み。公式サイトをクロール・取得するサービスは未接続。「最新であること」の断定をしない。
- 適用は選択候補ID／項目ID／取得時versionを送信。確認dialogのキャンセル時は書き込まない。
- 手動編集も率・期間・情報元を確認dialogに表示後、本人が確認して保存。
- 手動source.document_hashのadmin-manual-entryは資料hashではなく手動設定の識別値。正式資料の検証済みとは扱わない。
- 会社条件は会社共通の1箇所で保険者・都道府県・雇用保険事業区分を編集し、version付きRPCで保存。住所から県は推測しない。未登録nullと登録済みの未設定値を区別。料率編集で条件を重複入力せず保存時の会社条件をsource.applicabilityへsnapshot保存する。既存の未知証跡キーは保持、現会社条件がnullのknownキーは削除。
- 再読み込み失敗時は未取得を0や同率と見なさず、設定を非表示にして再試行を案内。保存失敗は成功通知しない。
- 読み込み世代とmountedを確認、編集中・確認中・保存中の重複操作を無効化。会社ID変更時は旧データを破棄。
- 候補scope_versionと現在の会社条件versionが一致しない場合は再確認案内と適用disable。会社条件の保存では既存料率を変更しない。
- 履歴の変更者ID・日時・旧新の3料率を表示。編集者名の解決は未接続。

## RPC契約と境界

read_company_payroll_rates(p_company_id)がitems/candidates/history/company_scope/scope_historyを返す。company_scopeは未登録null、登録済みversion/value/updated_by/updated_at。save_company_payroll_rate_scopeはexpected_versionと本人確認付きで保存し、返却version＋1とvalue一致を検証。
save_manual_company_payroll_rate、apply_company_payroll_rate_candidateを呼ぶ。DB導入前は取得エラーとなり、ローカル初期値で代替しない。RPC側の会社管理権限・検証候補・version検査は別laneで検証。

所得税のPDF/年度管理、介護保険生年月日判定、個別給与の適用フラグ、給与自動計算・確定snapshotは未接続。画面にも接続準備中と明示。住民税の固定率入力欄は設けない。

tests：会社条件の未登録・cancel・null保存、古い会社条件の候補apply禁止、返却item/version/origin/valueの不一致拒否、確認cancel書き込み無し、選択候補のみ適用、候補無し、保存失敗、取得失敗再試行、自由項目追加、6桁料率精度。ローカルFlutter SDKが無いためCI実行が必要。

Supabase Dart RPC公式docsを確認。changelog.mdは取得時unsupported content-typeで読めなかった。新しい依存追加、DB/Auth/RLS変更はこのlaneで行っていない。
