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
      title: 'はじめに・SKOの基本',
      summary: '毎日の出勤、日報、チャット、給与明細、必要書類をひとつのアプリで使います。',
      buttonLabel: 'ホーム',
      steps: ['会社名と自分の名前を確認', '下の5つのタブを確認', '迷ったら「ヘルプ」を開く'],
      support: '最初の利用時や、どこから操作するか分からない時にこのページを見ます。',
    ),
    ManualSection(
      title: '初期パスワード・QRログイン',
      summary: '会社のSKO利用者から受け取った初期パスワード、またはQRコードで最初のログインを行います。',
      buttonLabel: '従業員登録QRコードからログイン',
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
      steps: ['自分の現場を確認', '出勤または退勤を押す', 'GPSは操作時だけ取得', '写真が必要な場合は撮影して登録'],
      support: '写真撮影をキャンセルした場合は勤怠登録されません。位置情報は常時追跡しません。',
    ),
    ManualSection(
      title: '出勤表',
      summary: '自分の勤務日、現場、出退勤時刻、残業、早出、夜間、手当を確認します。',
      buttonLabel: '出勤表',
      steps: ['下部の「出勤表」を押す', '週または月を選ぶ', '必要ならA4プレビューを開く'],
      support: '表示に違いがある時は、まず日報の確定状況と出退勤記録を確認してください。',
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
      support: 'アプリをバックグラウンドへ送ると再ロックされます。5回失敗すると一時ロックされます。',
    ),
    ManualSection(
      title: '必要書類・資格証',
      summary: '会社から指定された必要書類と、自分の免許・資格証を登録します。',
      buttonLabel: '必要書類 / 資格',
      steps: ['未提出の項目を確認', '写真またはファイルを登録', '有効期限がある場合は期限も確認'],
      support: '未提出がある間はホーム最上部に「大事なお知らせ」が表示され、全て登録すると自動で消えます。',
    ),
    ManualSection(
      title: 'プロフィール・ヘルプ・印刷',
      summary: '氏名、電話番号、写真の変更と、説明書・パンフレットの閲覧・印刷を行います。',
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
      steps: ['自分の出退勤は一般ユーザーと同じ', '管理機能は付与権限だけ表示', '請求書・現場単価は対象外'],
      support: '権限OFFの機能は画面から消え、別経路から開いてもDB側で拒否されます。',
    ),
    ManualSection(
      title: '勤怠状況の確認',
      summary: '権限がある場合、現場の出勤・退勤・未打刻を確認します。',
      buttonLabel: '出勤・人区管理',
      steps: ['管理用出勤画面を開く', '現場別人数を確認', '異常があれば本人へ確認'],
      support: '本人の出退勤ボタンと管理用勤怠確認は別機能です。',
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
      support: '本登録の承認は、管理者または承認担当者に設定されている人が行います。',
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
    ...subAdmin,
    ManualSection(
      title: '管理者の初回設定',
      summary: '新しい会社では、会社・本人→必要書類→初回現場→単価設定の順で案内されます。',
      buttonLabel: '次へ',
      steps: ['会社・本人情報を登録', '必要書類を決める', '初回現場を登録', '税率・各単価を設定'],
      support: '4段階が完了すると通常のSKOホームを利用できます。既存会社はこのウィザードへ戻りません。',
    ),
    ManualSection(
      title: '承認担当者1〜3名の設定',
      summary: '管理者またはサブ管理者から、承認担当者を1〜3名選びます。',
      buttonLabel: '承認担当者（1〜3名）',
      steps: ['権限設定を開く', '承認担当者を選ぶ', '4人目を選ぶ場合は現在の3名から外す人を選択'],
      support: '個人事業主・一人親方は管理者本人1名を承認担当者にできます。',
    ),
    ManualSection(
      title: '従業員の本登録承認',
      summary: '本人情報の登録完了通知を受け取り、内容を確認して本登録します。',
      buttonLabel: '本登録承認',
      steps: ['氏名・連絡先を確認', '本人写真とマイナンバー表裏を確認', '問題なければ「本登録」'],
      support: '管理者または承認担当者のうち1人が承認すると利用開始できます。',
    ),
    ManualSection(
      title: '請求書・管理者用現場データ',
      summary: '管理者は請求書と管理者用現場データを開く時に第2パスワードを使います。',
      buttonLabel: '請求書 / 管理者用現場データ',
      steps: ['対象機能を押す', '初回のみ第2パスワードを設定', 'Face ID利用も設定可能'],
      support: '必要書類・資格証には第2パスワードを要求しません。',
    ),
    ManualSection(
      title: '請求・単価の会社設定',
      summary: '税率、福利厚生費率、残業・早出・夜勤・休日出勤単価、任意手当3種類を管理します。',
      buttonLabel: '設定 / 請求書',
      steps: ['会社設定を確認', '単価を変更', '請求書A4プレビューで結果を確認'],
      support: '単価や請求情報は権限のある管理者だけが扱います。',
    ),
  ];

  static const pamphlet = <ManualSection>[
    ManualSection(title: 'SKOとは', summary: '現場と会社をつなぐ業務アプリです。', buttonLabel: 'SKO', steps: ['出勤', '日報', 'チャット', '書類・請求を一元化'], support: 'ベータ版として実機検証を続けます。'),
    ManualSection(title: '3つの利用者区分', summary: '一般ユーザー、サブ管理者、管理者で必要な機能だけを表示します。', buttonLabel: '役割', steps: ['一般ユーザー', 'サブ管理者', '管理者'], support: '本人の出退勤は全役割で利用できます。'),
    ManualSection(title: '電話番号ID', summary: 'ログインIDは携帯電話番号です。', buttonLabel: 'ログイン', steps: ['電話番号', '本パスワード', '必要時SMS'], support: '旧メールログインは使用しません。'),
    ManualSection(title: '従業員招待', summary: '名前と電話番号だけで初期登録を開始できます。', buttonLabel: '従業員登録', steps: ['初期パスワード', '共有', 'QR'], support: '会社メンバーなら従業員登録を作れます。'),
    ManualSection(title: '本登録', summary: '本人情報を登録し、管理者/承認担当者1人の承認で利用開始します。', buttonLabel: '本登録', steps: ['本人情報', '本人写真', 'マイナンバー表裏'], support: '承認完了後に通常ホームへ進みます。'),
    ManualSection(title: '出勤・退勤', summary: '操作時だけGPSを取得します。', buttonLabel: '本日の出勤', steps: ['現場確認', 'GPS', '必要なら写真'], support: '常時位置追跡は行いません。'),
    ManualSection(title: '日報', summary: '作業内容と責任者サインを記録します。', buttonLabel: '日報', steps: ['入力', 'サイン', '確定'], support: '確定後の修正は承認フローです。'),
    ManualSection(title: '出勤表', summary: '勤務実績を週・月で確認できます。', buttonLabel: '出勤表', steps: ['現場', '時刻', '残業等'], support: 'A4印刷にも対応します。'),
    ManualSection(title: 'チャット', summary: '現場・個別の連絡をまとめます。', buttonLabel: 'チャット', steps: ['テキスト', '写真', 'ファイル'], support: '重要通知はベルから確認できます。'),
    ManualSection(title: '給与明細', summary: '一般・サブ管理者は給与明細を第2認証で保護します。', buttonLabel: '給与明細', steps: ['第2パスワード', 'Face ID', '印刷'], support: 'バックグラウンド復帰時は再ロックします。'),
    ManualSection(title: '必要書類', summary: '会社指定書類を一覧で管理します。', buttonLabel: '必要書類', steps: ['不足確認', '提出', '期限確認'], support: '不足中はホームへ大事な通知を表示します。'),
    ManualSection(title: '資格証', summary: '資格と期限を管理します。', buttonLabel: '資格', steps: ['資格名', '写真', '期限'], support: '他人の資格証は一般ユーザーから見えません。'),
    ManualSection(title: '管理者初期設定', summary: '新しい会社を順番にセットアップします。', buttonLabel: '次へ', steps: ['会社・本人', '必要書類', '現場', '単価'], support: '初めてでも順番に進めれば利用開始できます。'),
    ManualSection(title: '現場管理', summary: '現場、請求先、住所、最寄駅、メンバーを管理します。', buttonLabel: '現場', steps: ['現場登録', '配置', '進捗'], support: '管理者は現場単価も設定します。'),
    ManualSection(title: '承認担当者', summary: '1〜3名の承認担当者を柔軟に設定できます。', buttonLabel: '承認担当者', steps: ['1名', '2名', '3名まで'], support: '4人目は既存3名から入れ替えます。'),
    ManualSection(title: '請求書', summary: '月・年・会社別で請求を管理します。', buttonLabel: '請求書', steps: ['作成', 'PDF', 'メール/印刷'], support: '管理者の第2認証対象です。'),
    ManualSection(title: '権限・プライバシー', summary: '必要な人だけが必要な情報へアクセスします。', buttonLabel: '権限', steps: ['RLS', 'private Storage', '役割別権限'], support: '権限OFFはUIとDBの両方で拒否します。'),
    ManualSection(title: 'LINE・通知', summary: 'LINE連携とアプリ通知を安全に扱います。', buttonLabel: 'ベル', steps: ['通知', '承認待ち', '重要連絡'], support: 'Webhook署名検証を行います。'),
    ManualSection(title: '説明書・ヘルプ', summary: 'アプリ内で役割別説明書とパンフレットを確認できます。', buttonLabel: '使い方・説明書', steps: ['プレビュー', '印刷', 'いつでも見直す'], support: '大幅更新時はアプリと説明書をセットで更新します。'),
    ManualSection(title: 'ベータ版と実機確認', summary: 'Mac/iPhone実機でSMS、Face ID、GPS、カメラ、AirPrintを最終確認します。', buttonLabel: '運用準備チェック', steps: ['実SMS', 'Face ID', 'GPS/カメラ', 'AirPrint'], support: '実機結果を次の更新へ反映します。'),
  ];
}
