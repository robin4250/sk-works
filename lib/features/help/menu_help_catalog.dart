import 'manual_content.dart';

class MenuHelpItem {
  const MenuHelpItem({
    required this.key,
    required this.label,
    required this.purpose,
    required this.destination,
    required this.access,
    this.details = '',
    this.roles = const <ManualRole>{
      ManualRole.general,
      ManualRole.subAdmin,
      ManualRole.admin,
    },
  });

  final String key;
  final String label;
  final String purpose;
  final String destination;
  final String access;
  final String details;
  final Set<ManualRole> roles;
}

class MenuHelpCatalog {
  const MenuHelpCatalog._();

  static const items = <MenuHelpItem>[
    MenuHelpItem(key: 'attendance', label: '出勤表', purpose: '週間・月間の勤務実績、残業、早出、夜間、手当を確認します。', destination: '出勤表の週間画面へ移動します。月間・A4プレビューも開けます。', access: '管理者・サブ管理者・一般・閲覧権限', details: '週間表示は開いた時に本日を含む週を表示し、今日の勤務日は枠で確認できます。週/月を切り替え、月間集計では出勤日数・残業・早出・夜間・回数制手当を確認できます。日付・勤務修正・有給画面から戻った後も下部ナビを再表示します。勤務修正が承認された日は有給との重複を解消し、給与明細・請求書の自動計算にも反映します。'),
    MenuHelpItem(key: 'daily_report', label: '日報', purpose: '作業内容、勤務時間、手当、責任者サインを記録します。', destination: '日報入力・確認画面へ移動します。', access: '管理者・サブ管理者・一般・閲覧権限'),
    MenuHelpItem(key: 'chat', label: 'チャット', purpose: '現場・友達・グループ・協力会社との連絡、写真、ファイルを扱います。', destination: '「すべて / 友達 / 現場 / グループ / 協力会社」のタブがあるチャット一覧へ移動します。', access: '管理者・サブ管理者・一般・閲覧権限', details: '友達の氏名をタップすると個別トークを開始できます。グループでは友達招待、承認/拒否、メンバー確認、脱退、メンバー追放ができます。グループを右スワイプするとピン留め・通知音、左スワイプすると非表示・削除を選べます。現場タブには利用権限のある現場チャットが表示されます。個別トークやグループトークを開いた後でも、上部のタブを押すとそのタブの一覧へ戻れます。'),
    MenuHelpItem(key: 'site_register', label: '現場登録', purpose: '新しい現場の基本情報、住所、最寄駅、責任者等を登録します。', destination: '現場登録画面へ移動します。', access: '現場登録を許可された利用者'),
    MenuHelpItem(key: 'people', label: '社員', purpose: '自社社員の基本情報、資格、必要書類を確認・管理します。', destination: '社員一覧へ移動します。', access: '管理者・サブ管理者・社員閲覧権限', roles: {ManualRole.subAdmin, ManualRole.admin}),
    MenuHelpItem(key: 'initial_registration', label: '初回登録', purpose: '従業員登録済みの人へ、TestFlightと本人専用の初回ログイン情報を送ります。', destination: 'TOPページの「初回登録」から、未送信の従業員一覧へ移動します。', access: '管理者', details: '先に「従業員登録」で名前と携帯電話番号を登録します。その後「初回登録」で未送信の従業員を選び、TestFlight URLと本人専用の初回ログインQR/初期ログイン情報を送ります。送信済みの人は一覧で判別できます。', roles: {ManualRole.admin}),
    MenuHelpItem(key: 'employee_register', label: '従業員登録', purpose: '従業員の名前と携帯電話番号を先に登録します。', destination: '従業員登録画面へ移動します。', access: '管理者・サブ管理者', details: 'ここでは名前と電話番号だけを登録します。TestFlightや初回ログイン情報の送信は、管理者がTOPページの「初回登録」から別に行います。', roles: {ManualRole.subAdmin, ManualRole.admin}),
    MenuHelpItem(key: 'employee_onboarding_approvals', label: '本登録承認', purpose: '従業員の本人情報登録を確認して本登録を承認・拒否します。', destination: '本登録承認待ち一覧へ移動します。', access: '管理者・承認担当者', roles: {ManualRole.subAdmin, ManualRole.admin}),
    MenuHelpItem(key: 'payroll', label: '給与明細', purpose: '自分の給与明細を月別に確認し、預け済み帳票と同じA4横プレビュー・印刷・共有を行います。', destination: '第2認証後、給与明細一覧へ移動します。', access: '本人・給与明細閲覧権限', details: '給与明細は預け済み「給与明細書」の横長帳票を基準に、所属・社員番号・氏名・対象年月・支払日・勤怠・支給・控除・総支給額・総控除額・差引支給額・日給単価・減税項目を同じ表配置で表示します。原本の「休出日数」「法定休出時間」を含む見出しを使い、出勤日数・有給日数・残業時間・早出時間・夜間時間を勤怠修正後の最新データから表示します。各行に十分な高さを確保して文字と数字が罫線に重ならないよう表示します。プレビューは2本指のピンチで拡大縮小し、拡大後はドラッグ移動、右上ボタンで全体表示へ戻せます。金額はSKOの給与データと計算結果を使います。'),
    MenuHelpItem(key: 'payment_certificates', label: '支払証明書', purpose: '協力会社への工事代金を、工事代金支払明細書の帳票で確認・印刷・共有します。', destination: '支払証明書一覧から会社・月を選ぶとA4縦の帳票プレビューを開きます。', access: '管理者・サブ管理者・支払証明書閲覧権限', details: '預け済み「工事代金支払明細書」を基準に、作業所名・工事内容・数量・単価・支払金額をSKOの出勤実績と支払設定から計算して表示します。合計・控除・差引残高も自動計算します。', roles: {ManualRole.subAdmin, ManualRole.admin}),
    MenuHelpItem(key: 'payroll_settings', label: '個別給与設定', purpose: '社員ごとの日勤・夜勤・休日・残業・早出・手当・控除単価を設定します。', destination: '個別給与設定画面へ移動します。', access: '管理者・給与編集権限', roles: {ManualRole.admin}),
    MenuHelpItem(key: 'payroll_adjustments', label: '給与調整', purpose: '給与の加算・控除項目を社員別・期間別に登録、修正、取消します。', destination: '給与調整一覧へ移動します。', access: '管理者・給与閲覧/編集権限', roles: {ManualRole.admin}),
    MenuHelpItem(key: 'qualifications', label: '資格', purpose: '資格情報、資格証表裏、有効期限を確認・登録します。', destination: '資格一覧へ移動します。', access: '本人・管理者・サブ管理者・資格閲覧権限'),
    MenuHelpItem(key: 'documents', label: '必要書類', purpose: '会社指定の必要書類を確認し、写真/PDFを登録します。', destination: '必要書類一覧へ移動します。', access: '本人・管理者・サブ管理者・書類閲覧権限'),
    MenuHelpItem(key: 'company_documents', label: '会社提出書類', purpose: '会社単位で提出するPDF・画像を登録し、接続会社へ送信します。', destination: '会社提出書類一覧へ移動します。', access: '管理者', roles: {ManualRole.admin}),
    MenuHelpItem(key: 'signatures', label: 'サイン一覧', purpose: '日報に保存済みの責任者・代表者・監督者サインを確認し、接続済み親会社へ送信します。', destination: 'サイン一覧へ移動します。', access: '管理者', roles: {ManualRole.admin}),
    MenuHelpItem(key: 'company_deliveries', label: '協力会社情報', purpose: '協力会社から受信した社員・資格・必要書類・会社提出書類を会社別に確認します。', destination: '協力会社一覧・受信データ画面へ移動します。', access: '管理者', roles: {ManualRole.admin}),
    MenuHelpItem(key: 'trade_companies', label: '取引会社登録', purpose: 'SKO連携あり・なしを問わず取引会社を登録し、会社情報の確認・編集・削除と、1日・月・平米・請負の契約金額設定を行います。', destination: '取引会社一覧へ移動し、会社名タップで詳細を確認できます。詳細画面から会社情報の編集、削除、契約設定、SKO連携候補の統合確認を行えます。', access: '管理者・サブ管理者', details: '会社名・電話番号・郵便番号・住所・メール・法人番号・備考を確認/編集できます。削除時は確認画面を表示し、関連する契約設定も削除されます。SKOを使っていない会社も登録可能です。既存SKO会社と候補一致した場合は、確認してから統合します。管理現場側にも金額設定がある場合は、どちらを計算元にするか選択します。', roles: {ManualRole.subAdmin, ManualRole.admin}),
    MenuHelpItem(key: 'subcontractors', label: '協力会社登録', purpose: 'SKO連携なしの協力会社も登録し、会社情報の確認・編集・削除と、支払証明書に使う契約金額設定を行います。', destination: '協力会社一覧へ移動し、会社名タップで詳細を確認できます。詳細画面から会社情報の編集、削除、契約設定、SKO連携候補の統合確認を行えます。', access: '管理者・サブ管理者', details: '会社名・電話番号・郵便番号・住所・メール・法人番号・備考を確認/編集できます。1日単価・月単価・平米単価・請負金額を設定できます。削除時は確認画面を表示し、関連契約設定も削除されます。SKO未連携の協力会社でも支払証明書の計算対象にできます。後からSKO連携する場合は同一会社であることを確認して統合します。', roles: {ManualRole.subAdmin, ManualRole.admin}),
    MenuHelpItem(key: 'invoices', label: '請求書', purpose: '請求内容を確認・作成し、拡大縮小できるPDFプレビュー、印刷、共有、承認を行います。', destination: '第2認証後、請求書画面へ移動します。月末の承認通知から対象請求書を直接開けます。', access: '管理者・請求書閲覧権限・設定済み承認者', details: '請求書は預け済みの「御請求書」テンプレートを基準にA4縦で表示します。明細は「作業所名 / 工事内容 / 数量 / 単価 / 請求金額」で、出勤実績がある現場ごとに正式名称を表示します。請求書用の残業単価・早出単価は管理現場で個別に登録し、給与計算用単価とは分けて管理します。手当は出勤データに登録された実際の手当名を「（手当名）」として表示し、管理現場の同名手当単価を使います。確認印は印中文字を見やすくし、会社角印は角印案B（太い外角枠＋細い内角枠）を使います。請求金額枠と確認印枠は隣り合う独立した枠とし、請求金額枠は請求先名の直下へ配置します。下部の「お支払約定日」と「金額」は同じ横幅で表示します。プレビュー・PDF・印刷・共有は同じ帳票生成を使います。プレビューは2本指で拡大縮小、拡大後はドラッグ移動できます。', roles: {ManualRole.admin}),
    MenuHelpItem(key: 'site_map', label: '現場マップ', purpose: '現場・取引会社・下請け会社・社員の最新打刻位置をGoogleマップで確認します。', destination: 'Googleマップ一覧へ移動します。', access: '管理者・サブ管理者', roles: {ManualRole.subAdmin, ManualRole.admin}),
    MenuHelpItem(key: 'admin_sites', label: '管理現場', purpose: '給与計算用単価と請求書用単価・手当を現場ごとに登録します。', destination: '第2認証後、管理現場画面へ移動します。請求書用には1日/月/平米/請負に加えて残業1時間単価・早出1時間単価と手当名/単価を登録できます。', access: '管理者・現場データ閲覧権限', details: '給与計算用の残業・早出単価と、請求書用の残業・早出単価は別項目です。既存設定は移行時に請求書用へ引き継ぎ、以後はそれぞれ個別に変更できます。', roles: {ManualRole.admin}),
    MenuHelpItem(key: 'vehicle_routes', label: '車両・ルート', purpose: '車両番号・走行距離・車両書類と、複数地点の業務ルートを確認します。当日の勤務報告では車両とルートを選択できます。', destination: '車両・ルート一覧へ移動します。', access: '全社員が閲覧・当日選択、管理者/サブ管理者が登録・編集'),
    MenuHelpItem(key: 'profile', label: 'プロフィール', purpose: '自分の氏名、電話番号、写真、会社SKO ID等を確認します。', destination: 'プロフィール画面へ移動します。', access: '管理者・サブ管理者・一般・閲覧権限'),
    MenuHelpItem(key: 'notes', label: 'ノート', purpose: '業務メモと添付ファイルをチャット単位で管理します。', destination: 'ノート一覧へ移動します。', access: '会社設定と参加チャットの権限に従います'),
    MenuHelpItem(key: 'albums', label: 'アルバム', purpose: '業務写真をアルバムとしてまとめて確認します。', destination: 'アルバム一覧へ移動します。', access: '会社設定と参加チャットの権限に従います'),
    MenuHelpItem(key: 'approvals', label: '承認待ち', purpose: '日報修正等の承認申請を確認して承認・却下します。', destination: '承認待ち一覧へ移動します。', access: '管理者・承認担当者', roles: {ManualRole.subAdmin, ManualRole.admin}),
    MenuHelpItem(key: 'today_line', label: '本日のLINE出勤候補', purpose: 'LINE連携から取り込んだ出勤候補を確認します。', destination: '本日のLINE出勤候補画面へ移動します。', access: '管理者・勤怠管理権限', roles: {ManualRole.subAdmin, ManualRole.admin}),
    MenuHelpItem(key: 'appearance', label: '背景・ヘッダー・フッター設定', purpose: '自分のホーム壁紙と、ボタン・カード・ヘッダー・フッターの透明度を調整します。', destination: '個人用のホーム外観設定画面へ移動します。', access: '本人のみ。ほかの利用者には影響しません'),
    MenuHelpItem(key: 'settings', label: '設定', purpose: '会社機能、表示、権限、単価、通知音、フローティングヘルプ等の設定を確認します。', destination: '設定画面へ移動します。', access: '表示項目は役割と付与権限で変わります', details: '利用できる設定だけが表示されます。フローティングヘルプをONにすると、画面上の「？」からいつでも使い方を確認できます。通知音はアプリ全体とグループ単位で分けて設定できます。'),
    MenuHelpItem(key: 'help', label: 'ヘルプ', purpose: '現在利用できる各ボタンの説明と役割別説明書を確認します。', destination: 'このヘルプ画面です。', access: '管理者・サブ管理者・一般・閲覧権限', details: '画面右側の「？」は長押しして好きな位置へ移動できます。タップすると現在画面の説明が最初に出ます。検索欄には「出勤」「日報」「チャット」「給与」「現場」などの機能名を入力して使い方を探せます。'),
  ];

  static List<MenuHelpItem> visibleFor({
    required ManualRole role,
    Set<String>? visibleKeys,
  }) {
    return [
      for (final item in items)
        if (item.roles.contains(role) &&
            (visibleKeys == null || visibleKeys.contains(item.key)))
          item,
    ];
  }
}
