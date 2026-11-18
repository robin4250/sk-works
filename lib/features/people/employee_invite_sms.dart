import 'employee_invite_repository.dart';

const employeeInviteGuideUrl = 'https://skojapan.com/install/employee/start.html';

const employeeAppGuideSms =
    '【SKO 従業員登録のご案内】\n\n'
    '$employeeInviteGuideUrl\n\n'
    'SKOを利用中の方は、登録済みの方法でログインしてください。'
    '初回ログイン情報が届いていない場合は、会社の担当者にご確認ください。';

const employeeInviteWorkGuide =
    '出勤はメニューの「本日の出勤」から確認します。\n'
    '給与は「給与明細」で公開された自分の明細を確認します。\n'
    '請求書は、閲覧権限のある方が「請求書」から確認できます。';

String employeeInviteSms(EmployeeInviteResult invite) {
  return '【SKO 従業員登録のご案内】\n\n'
      '登録電話番号　${invite.phone}\n'
      '初回ログインパスワード　${invite.temporaryPassword}\n\n'
      '① 上の初回ログインパスワードだけをコピーします。\n'
      '② 以下の案内からSKOを開き、登録電話番号を入力します。\n'
      '$employeeInviteGuideUrl\n'
      '③ 「初回パスワードを貼り付け」を押します。\n'
      '④ 「ログイン」を押します。\n\n'
      'ログイン後、画面の案内に沿ってGoogle・Apple・メールのいずれかを登録してください。'
      '次回からは登録した方法でログインできます。\n\n'
      '【登録後に使う機能】\n$employeeInviteWorkGuide';
}
