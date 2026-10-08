class ManualSection {
  const ManualSection({
    required this.title,
    required this.summary,
    required this.buttonLabel,
    required this.steps,
    required this.support,
  });

  final String title;
  final String summary;
  final String buttonLabel;
  final List<String> steps;
  final String support;
}

enum ManualRole { general, subAdmin, admin }

class ManualContent {
  const ManualContent._();

  static ManualRole fromMembershipRole(String role) => switch (role) {
        'owner' || 'admin' => ManualRole.admin,
        'manager' => ManualRole.subAdmin,
        _ => ManualRole.general,
      };

  static String roleLabel(ManualRole role) => switch (role) {
        ManualRole.general => '一般ユーザー',
        ManualRole.subAdmin => 'サブ管理者',
        ManualRole.admin => '管理者',
      };

  static List<ManualSection> forRole(ManualRole role) => switch (role) {
        ManualRole.general => general,
        ManualRole.subAdmin => subAdmin,
        ManualRole.admin => admin,
      };

  static const general = <ManualSection>[
    ManualSection(
      title: '初期準備ガイド',
      summary: '利用権限に応じた登録項目と準備率を確認します。',
      buttonLabel: '初期準備ガイド',
      steps: ['必須項目を確認', '登録画面で保存', '準備率を確認', '利用方法を見る'],
      support: "準備率は保存済みの登録内容から計算します。通常の登録画面で保存しても更新されます。必須項目と推奨項目は別に表示し、対象外は計算に含めません。取得できない項目は未確定と表示します。初期準備の完了後はホームの準備カードを非表示にし、案内はメニューから開き直せます。案内を初めからにしても登録データは消えません。",
    ),
    ManualSection(
      title: '通知・要対応',
      summary: '通知と要対応を一つの一覧で確認します。',
      buttonLabel: 'お知らせ',
      steps: ['要対応を確認', '対象の画面を開く', '確認・承認を行う', '一覧で状態を再確認'],
      support: "ホームの要対応と通知ベルは同じ一覧を開きます。期限のある未対応を優先して表示します。通知の既読と業務の確認・承認完了は別に管理し、状態が確認できない項目を未対応件数へ加えません。通知から対象の申請・対象月を開き、処理後に状態を再確認します。",
    ),
    ManualSection(
      title: 'はじめに・SKOの基本',
      summary: '会社の決め事は会社データ、社員の情報は社員データで管理します。本人の情報はプロフィールから扱います。',
      buttonLabel: 'ホーム',
      steps: ['会社名と自分の名前を確認', '下の5つのタブを確認', '迷ったら「ヘルプ」を開く'],
      support: '2026-10-08改訂のベータ版です。公開前に実機の操作と照合して最終改訂します。',
    ),
    ManualSection(
      title: '初期パスワード・QRログイン',
      summary: '会社のSKO利用者から受け取った初期パスワード、またはQRコードで最初のログインを行います。',
      buttonLabel: '従業員登録QRでログイン',
      steps: ['電話番号と初期パスワードを入力', 'QRの場合はカメラで読み取る', 'ログイン後、本パスワードを2回設定'],
      support: 'QRが読めない時は初期パスワードを手入力できます。期限切れの場合は会社のSKO利用者へ再発行を依頼します。',
    ),
    ManualSection(
      title: '本人情報・本登録',
      summary: '住所、血液型、家族構成、緊急連絡先、本人写真、マイナンバーカード表裏を登録します。',
      buttonLabel: '本登録を申請',
      steps: ['必須項目を入力', '本人写真を撮影/選択', 'マイナンバー表裏を登録', '本登録申請を押す'],
      support: '送信後は承認待ち画面になります。管理者または承認担当者1人の承認で利用開始できます。',
    ),
    ManualSection(
      title: '出勤・退勤',
      summary: '一般ユーザー・サブ管理者・管理者の全員が、自分自身の出勤と退勤を登録できます。',
      buttonLabel: '本日の出勤 / 本日の退勤',
      steps: ['自分の現場を確認', '出勤または退勤を押す', '手動登録か本人が設定したGPS自動出勤を使う', '写真が必要な場合は撮影して登録'],
      support: '手動の打刻と日報の確定は別です。GPS自動出勤を本人が有効にした場合は、設定条件に応じて背景でも位置情報を使います。',
    ),
    ManualSection(
      title: '出勤表',
      summary: '自分の勤務日、現場、出退勤時刻、残業、早出、夜間、手当を確認します。',
      buttonLabel: '出勤表',
      steps: ['下部の「出勤表」を押す', '週または月を選ぶ', '必要ならA4プレビューを開く'],
      support: '打刻時刻と日報で確定した勤務内容を確認します。有給額・通常勤務の夜間割増が未設定の場合は、管理者へ会社規定の登録を依頼してください。',
    ),
    ManualSection(
      title: '日報・責任者サイン',
      summary: 'その日の作業内容を入力し、責任者の手書きサインで確定します。',
      buttonLabel: '日報',
      steps: ['日報を開く', '作業内容・時間・手当を入力', '責任者が指でサイン', '確定する'],
      support: '確定後の修正は、会社で設定された承認担当者への修正申請が必要です。',
    ),
    ManualSection(
      title: 'チャット・お知らせ',
      summary: '現場、個別、会社からの重要な連絡を確認します。',
      buttonLabel: 'チャット / ベル',
      steps: ['下部の「チャット」を押す', '現場/個別を選ぶ', '重要通知は右上のベルを確認'],
      support: '写真やファイルも送れます。個人情報や不要な機密情報は送らないでください。',
    ),
    ManualSection(
      title: '給与明細と第2パスワード',
      summary: '一般ユーザーとサブ管理者は、給与明細を開く時に第2パスワードを使います。',
      buttonLabel: '給与明細',
      steps: ['給与明細を押す', '初回だけ第2パスワードを2回設定', '以後は第2パスワードまたはFace IDで開く'],
      support: '会社の給料日と個別給与設定を使用します。確認印は実際に確認した担当者だけを表示し、プレビュー・印刷・共有は同じPDFです。',
    ),
    ManualSection(
      title: '必要書類・資格証',
      summary: '会社から指定された必要書類と、自分の免許・資格証を登録します。',
      buttonLabel: '必要書類 / 資格',
      steps: ['未提出の項目を確認', '写真またはファイルを登録', '有効期限がある場合は期限も確認'],
      support: '未提出などの対応事項はホームの「要対応」で確認します。登録を完了すると対応状態が更新されます。',
    ),
    ManualSection(
      title: 'プロフィール・ヘルプ・印刷',
      summary: '本人が扱う情報はプロフィールから登録します。社員番号・所属・職種・入社日は社員データで管理します。',
      buttonLabel: 'プロフィール / ヘルプ',
      steps: ['プロフィールを開く', '必要なら電話番号をSMS確認付きで変更', '「使い方・説明書」を開く', 'PDFプレビューから印刷'],
      support: '画面操作に迷った時は説明書の該当ページを開き、「ここを押す」表示を確認してください。',
    ),
  ];

  static const subAdmin = <ManualSection>[
    ...general,
    ManualSection(
      title: 'サブ管理者の役割',
      summary: '付与された権限の範囲で、現場とメンバーの運用を支えます。',
      buttonLabel: 'メニュー',
      steps: ['自分の出退勤は一般ユーザーと同じ', '管理機能は付与権限だけ表示', '請求書・管理現場は会社から付与された権限を確認'],
      support: '会社の機能ON/OFFと本人の権限を両方満たす機能を利用します。機能をONにしても給与の閲覧権限は追加されません。',
    ),
    ManualSection(
      title: '勤怠状況の確認',
      summary: '権限がある場合、現場の出勤・退勤・未打刻を確認します。',
      buttonLabel: '出勤・社員管理',
      steps: ['管理用出勤画面を開く', '現場別人数を確認', '異常があれば本人へ確認'],
      support: '本人の打刻、日報確定、管理用の勤怠確認は別です。指定された給与確認者は、閲覧できる対象の明細を確認します。',
    ),
    ManualSection(
      title: '日報修正の承認',
      summary: '会社で承認担当者に設定された場合、確定済み日報の修正申請を承認できます。',
      buttonLabel: '承認待ち',
      steps: ['申請内容と理由を確認', '問題なければ承認', '却下する場合は内容を確認して処理'],
      support: '承認担当者は管理者が1〜3名で設定します。固定2名承認ではありません。',
    ),
    ManualSection(
      title: '従業員登録を手伝う',
      summary: 'サブ管理者も会社メンバーとして、名前と電話番号から従業員招待を作れます。',
      buttonLabel: '従業員登録',
      steps: ['名前と電話番号を入力', '初期パスワードを共有', 'またはQRを相手に見せる'],
      support: 'サブ管理者も招待できますが、役割・承認担当者の指定は管理者だけが行います。本登録の承認は管理者または承認担当者が行います。',
    ),
    ManualSection(
      title: '書類・資格のフォロー',
      summary: '権限がある場合、必要書類や資格の不足・期限を確認して本人を支援します。',
      buttonLabel: '必要書類 / 資格',
      steps: ['未提出や期限切れを確認', '本人へ案内', '個人情報は必要な範囲だけ扱う'],
      support: '一般ユーザー同士で他人の書類や資格証を直接見ることはできません。',
    ),
  ];

  static const admin = <ManualSection>[
    ...general,
    ManualSection(
      title: '管理者の役割',
      summary: '自分自身の出勤・退勤・日報を使いながら、会社全体の現場・社員・請求・権限を管理します。',
      buttonLabel: 'メニュー',
      steps: ['自分の出退勤は一般ユーザーと同じ', '管理機能は管理者メニューから開く', '会社設定と権限を必要に応じて変更'],
      support: '本人の勤怠操作と会社全体の管理機能は分かれています。個人事業主・一人親方でも同じ管理者アカウントで両方使えます。',
    ),
    ManualSection(
      title: '管理者の初回設定',
      summary: '新しい会社では、個人情報・会社情報・提出書類・資格設定・従業員登録・初回登録の順で案内されます。',
      buttonLabel: '会社情報登録',
      steps: ['個人情報と会社情報を登録', '提出書類を登録し資格を設定', '従業員の名前と電話番号を登録', '初回登録から本人専用のログイン情報を案内'],
      support: '初回設定の6項目を確認します。給料日・締め日・確認者は会社データ、社員の給与単価は個別給与設定で管理します。会社データの会社角印で3帳票共通の表示ON／OFFを設定します。',
    ),
    ManualSection(
      title: '承認担当者1〜3名の設定',
      summary: '給与の確認者は会社データで管理者が1〜3名選びます。給与を閲覧できる管理者・サブ管理者・閲覧者が対象です。',
      buttonLabel: '会社データ / 給与の締め日・給料日・確認者',
      steps: ['会社データで給料日を確認', '確認者を1〜3名選ぶ', '月末から対象明細を確認', '全員の確認状態を確認'],
      support: '初期は管理者1名です。月末に通知し、未確認なら給料日の1週間前から当日まで毎日通知します。取消・再確認は履歴を残し、実際の確認日時を改変しません。',
    ),
    ManualSection(
      title: '従業員の本登録承認',
      summary: '本人情報の登録完了通知を受け取り、内容を確認して本登録します。',
      buttonLabel: '承認待ち',
      steps: ['氏名・連絡先を確認', '本人写真とマイナンバー表裏を確認', '問題なければ「本登録」'],
      support: '管理者または承認担当者のうち1人が承認すると利用開始できます。',
    ),
    ManualSection(
      title: '従業員・権限管理',
      summary: '社員番号は自動追加され、未使用の番号へ変更できます。所属・職種・入社日と役割を社員データで管理します。',
      buttonLabel: 'アプリ利用者の権限',
      steps: ['従業員登録時に必要なら「サブ管理者にする」をON', '必要なら「承認担当者にする」をON', '4人目なら現在の3名から外す人を選ぶ', '本登録後も権限設定から変更可能'],
      support: '役割・承認担当者の指定は管理者だけが行えます。同じ会社で使用中の社員番号は登録できません。給与など金銭情報の設定・変更と、閲覧者の確認は別の権限です。会社の機能ONだけで権限は増えません。',
    ),
    ManualSection(
      title: '現場・現場単価の管理',
      summary: '現場名、請求先会社、住所、最寄り駅、配置と管理者用の現場単価を管理します。',
      buttonLabel: '現場 / 管理現場',
      steps: ['現場を登録', '請求先・住所・最寄り駅を確認', '必要なメンバーを配置', '現場単価を管理'],
      support: '管理者用現場データは第2認証対象です。閲覧・変更できる範囲は会社から付与された現場データの権限に従います。',
    ),
    ManualSection(
      title: '請求書・第2認証',
      summary: '管理者は請求書を開く時に第2パスワードまたはFace IDで本人確認します。',
      buttonLabel: '請求書',
      steps: ['請求書を開く', '第2認証を行う', '内容を確認', 'PDF印刷・共有'],
      support: '請求書・給与明細・支払証明書は同じPDFをプレビュー・印刷・共有します。下請け会社登録後は出勤なしでも支払証明書をプレビューできます。',
    ),
    ManualSection(
      title: '会社単価・手当設定',
      summary: '会社共通の税率・福利厚生費率・手当を設定します。社員の給与単価は個別給与設定、現場の請求単価は管理者用現場データで扱います。',
      buttonLabel: '会社単価・手当設定',
      steps: ['会社データを開く', '税率・福利厚生費率を確認', '手当の名称・金額・単位を設定', '保存'],
      support: '旧単価は登録済み設定の折りたたみ欄に保持します。有給支給額・通常勤務の夜間割増が未登録なら設定を確認し、計算完了と判断しないでください。',
    ),
    ManualSection(
      title: '勤怠・日報の管理',
      summary: '自分の勤怠とは別に、権限のある管理画面から会社全体の出勤状況と日報承認を確認します。',
      buttonLabel: '出勤・社員管理 / 承認待ち',
      steps: ['現場別の出勤状況を確認', '未打刻を確認', '日報修正申請を確認', '承認または却下'],
      support: '日報修正は会社で設定した承認担当者（1〜3名）のうち1人が承認します。通知から対象申請を直接開き、日付・現場・承認状態を確認できます。既読と承認完了は別に管理します。',
    ),
    ManualSection(
      title: '運用準備・説明書更新',
      summary: '運用準備チェックと役割別説明書を使い、設定漏れがないか確認します。',
      buttonLabel: '運用準備チェック / 使い方・説明書',
      steps: ['運用準備チェックを開く', '未完了項目を確認', '役割別説明書を確認', '必要ならA4印刷'],
      support: '2026-10-08改訂のベータ版です。社内試験の結果を反映し、公開前に全役割の説明書とパンフレットを最終改訂します。',
    ),
  ];

  static const pamphlet = <ManualSection>[
    ManualSection(title: 'SKOとは', summary: '現場と会社をつなぐ業務アプリです。', buttonLabel: 'SKO', steps: ['出勤', '日報', 'チャット', '書類・請求を一元化'], support: 'ベータ版として実機検証を続けます。'),
    ManualSection(title: '3つの利用者区分', summary: '一般ユーザー、サブ管理者、管理者で必要な機能だけを表示します。', buttonLabel: '役割', steps: ['一般ユーザー', 'サブ管理者', '管理者'], support: '本人の出退勤は全役割で利用できます。'),
    ManualSection(title: '電話番号ID', summary: 'ログインIDは携帯電話番号です。', buttonLabel: 'ログイン', steps: ['電話番号', '本パスワード', '必要時SMS'], support: '旧メールログインは使用しません。'),
    ManualSection(title: '従業員招待', summary: '名前と電話番号だけで初期登録を開始できます。', buttonLabel: '従業員登録', steps: ['初期パスワード', '共有', 'QR'], support: '会社メンバーなら従業員登録を作れます。'),
    ManualSection(title: '本登録', summary: '本人情報を登録し、管理者/承認担当者1人の承認で利用開始します。', buttonLabel: '本登録', steps: ['本人情報', '本人写真', 'マイナンバー表裏'], support: '承認完了後に通常ホームへ進みます。'),
    ManualSection(title: '出勤・退勤', summary: '手動の打刻と本人が有効にするGPS自動出勤を使い分けます。', buttonLabel: '本日の出勤', steps: ['現場確認', 'GPS', '必要なら写真'], support: 'GPS自動出勤を有効にした場合は設定条件で背景でも位置情報を使います。本人が停止できます。'),
    ManualSection(title: '日報', summary: '作業内容と責任者サインを記録します。', buttonLabel: '日報', steps: ['入力', 'サイン', '確定'], support: '打刻と日報の確定は別です。確定後の修正は申請内容を確認して承認します。'),
    ManualSection(title: '出勤表', summary: '勤務実績を週・月で確認できます。', buttonLabel: '出勤表', steps: ['現場', '時刻', '残業等'], support: 'A4印刷にも対応します。'),
    ManualSection(title: 'チャット', summary: '現場・個別の連絡をまとめます。', buttonLabel: 'チャット', steps: ['テキスト', '写真', 'ファイル'], support: '重要通知はベルから確認できます。'),
    ManualSection(title: '給与明細', summary: '会社の給料日と社員ごとの給与設定を使い、明細を第2認証で保護します。', buttonLabel: '給与明細', steps: ['第2認証', '設定と明細の確認', '同じPDFで印刷・共有'], support: '有給支給額・通常勤務の夜間割増が未登録なら会社規定を確認します。'),
    ManualSection(title: '必要書類', summary: '会社指定書類を一覧で管理します。', buttonLabel: '必要書類', steps: ['不足確認', '提出', '期限確認'], support: '不足中はホームへ大事な通知を表示します。'),
    ManualSection(title: '資格証', summary: '資格と期限を管理します。', buttonLabel: '資格', steps: ['資格名', '写真', '期限'], support: '他人の資格証は一般ユーザーから見えません。'),
    ManualSection(title: '管理者初期設定', summary: '会社と管理者の初回登録を順番に進めます。', buttonLabel: '会社情報登録', steps: ['個人情報・会社情報', '提出書類・資格設定', '従業員登録', '初回登録'], support: '初めてでも順番に進めれば利用開始できます。'),
    ManualSection(title: '現場管理', summary: '現場、請求先、住所、最寄駅、メンバーを管理します。', buttonLabel: '現場', steps: ['現場登録', '配置', '進捗'], support: '管理者は現場単価も設定します。'),
    ManualSection(title: '承認担当者', summary: '給与の確認者は会社データで1〜3名を選びます。初期は管理者1名です。', buttonLabel: '承認担当者', steps: ['1名', '2名', '3名まで'], support: '月末から確認でき、未確認は給料日1週間前から毎日通知します。取消・再確認でも実際の日時を保持します。'),
    ManualSection(title: '請求書', summary: '請求書・給与明細・支払証明書を登録データから作成します。', buttonLabel: '請求書', steps: ['作成', 'PDF', 'メール/印刷'], support: '同じPDFを印刷・共有します。登録した下請け会社は出勤なしでも支払証明書をプレビューできます。会社角印のON／OFFは会社データで設定し、3帳票へ共通反映します。確認印・承認印と履歴は保持します。'),
    ManualSection(title: '権限・プライバシー', summary: '必要な人だけが必要な情報へアクセスします。', buttonLabel: '権限', steps: ['会社の機能ON/OFF', '本人の役割', '金銭情報の閲覧・変更を区別'], support: '機能ONは給与の閲覧権限を追加する操作ではありません。本人と会社の登録情報を権限に応じて扱います。'),
    ManualSection(title: 'LINE・通知', summary: 'LINE連携とアプリ通知を安全に扱います。', buttonLabel: 'ベル', steps: ['通知', '承認待ち', '重要連絡'], support: 'Webhook署名検証を行います。'),
    ManualSection(title: '説明書・ヘルプ', summary: 'アプリ内で役割別説明書とパンフレットを確認できます。', buttonLabel: '使い方・説明書', steps: ['プレビュー', '印刷', 'いつでも見直す'], support: '2026-10-08改訂のベータ版です。公開前に実機操作と照合して最終改訂します。'),
    ManualSection(title: 'ベータ版と実機確認', summary: 'Mac/iPhone実機でSMS、Face ID、GPS、カメラ、AirPrintを最終確認します。', buttonLabel: '運用準備チェック', steps: ['実SMS', 'Face ID', 'GPS/カメラ', 'AirPrint'], support: '実機結果を次の更新へ反映します。'),
  ];
}
