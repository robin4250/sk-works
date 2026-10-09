# 会社共通税率設定UI（接続準備）

新ページは既存の請求用消費税率とは独立。同社の管理者・閲覧者で会社ID取得済みの場合だけ設定画面から開く。

- 料率はpercentage pointの百万分の一整数。小数点以下6桁、0〜100%。double変換や雇用保険の÷2を使用しない。
- 全体／従業員／会社負担を別入力し、合計一致を検証。
- 標準5項目IDはkind固定、customはUUID v4。登録前は未設定と表示。未設定の手動編集だけ利用者指定の初期入力値を示し、適用月・情報元・確認後保存を必須とする。既存0を含む保存値は上書きしない。支援金負担の標準折半は新規編集の明示ボタンのみ。
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

## コンパクト表示

通常表示は現在率・従業員／会社負担・保険適用月・情報元名称を中心に、確認値と比較できる構成。給与対象月／支払月、正式URL・条件証跡は項目ごとの「適用月・資料の詳細」、監査情報は「変更履歴」で開く。確認popupは折り畳まず全率・3年月・情報元・必須確認文を表示する。未接続の説明は短い表示とヘルプに集約し、自動取得や給与反映済みとは表示しない。折り畳み前の重要値と展開後の資料・月区分・履歴をwidgettestで検証する。

## 通信断後の変更停止

送信前に会社・項目ID（自由項目UUIDを含む）・取得版・値・保存originを保持する。保存／候補適用／会社条件保存の応答不明時は全変更操作を停止し、自動再送しない。明示再読込で同じIDの期待版+1、originと全値（会社条件は版と全値）が一致した場合だけ回復する。未存在・旧版・競合版・取得失敗は未保存の証明ではなく停止を保持する。自由項目は結果不明のまま別UUIDで作り直せない。送信前に既存path_providerのApplication Support下でflush済みファイルへ利用者ID＋会社IDで永続記録し、記録失敗時はRPCを送信しない。画面再入場とアプリ再起動でgateを復元する。ログアウト/利用者変更/他社は別キーとなり、前利用者の記録を表示・削除しない。API取得権限の確認前に記録だけで保存成功へ昇格しない。確認済み応答又は実API照合後だけ削除し、削除失敗もgateを保持する。

read RPCのPGRST202/42883かつ対象関数名一致だけを「準備中：この会社では料率設定をまだ利用できません」と表示する。権限・通信エラーを未導入へ読み替えず、取得済み設定も隠す。再取得で閲覧者となった場合は保存成立を確認しても変更操作を出さない。閲覧者は同社の料率・適用月・情報元・年度PDFを読み取り、保存・適用・条件編集・新規登録を行わない。

同一actor/companyの複数store instanceは同じキーのmutexで既存記録確認・保存・読込・削除を直列化する。後発の別操作でpendingを上書きせず、確認済み操作のpayload一致を削除前にも照合する。同時2instance保存fixtureで1操作だけ記録成功し、違うUUIDのcleanupで削除できないことを確認する。複数端末間のDB idempotencyを追加するものではない。

## 確定拒否と不明応答の区別

完全受信したPostgrestExceptionのSQLSTATE `22023`（原典validate_value/scope等の入力拒否）、`40001`（原典設定/会社条件版競合）、`23505`（原典payroll_rate_label/standard_kindのunique制約）、`42501`（原典assert_adminの権限拒否）だけをtransaction拒否として分類する。原典は20261009151946_company_payroll_rate_registry.sql、HTTP error mapping根拠はhttps://docs.postgrest.org/en/stable/references/errors.html と https://supabase.com/docs/guides/api/rest/postgrest-error-codes。これらは同一scope・世代・期待操作が維持された場合にpendingをCAS削除し、古い表示とcan_editを破棄してfresh readする。新しいcan_edit取得前に変更操作を復活させない。重複名称拒否→再取得→名称修正保存fixtureを含む。

network/TimeoutException/FormatException、PGRST003等の汎用APIエラー、未知SQL/500は不明応答のまま保持する。旧read・未存在ではtimeout操作を解除しない。確定拒否のローカル記録削除に失敗した場合も変更停止を維持する。

SharedPreferences公式READMEは戻り後のdisk永続化を保証しないため採用せず、既存path_provider2.1.6＋crypto3.0.7＋dart:ioでactor/companyのSHA256キーを用いた専用JSONをApplication Supportに保存する。File.writeAsString(flush:true)完了後にだけRPCを送信する（https://api.dart.dev/dart-io/File/writeAsString.html）。途中で書込に失敗したfileは成功扱いせず、読込不正は変更操作を閉じる。電源断・複数process・別端末のDB idempotencyまで保証するものではない。

専用JSONの同一directory一時fileをflush完了後にrenameしてからRPCを送信する。キーごとのDart mutexに加えて専用lock fileをnative exclusive lockし、lock取得失敗は未送信で閉じる。正常な途中一時fileは再open時に同scope記録として復元し、破損一時fileやmain/temp競合は失敗のまま残して変更操作を止める。原典https://api.dart.dev/dart-io/RandomAccessFile/lock.html に従い、Linux/macOSのlockはadvisory・process単位であるため複数isolateの絶対直列化は称しない。途中temp復元・破損閉鎖・filesystem準備失敗の実file fixtureを追加。
