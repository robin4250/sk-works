import 'package:supabase_flutter/supabase_flutter.dart';

List<String> removedAttendanceAllowanceNames(Map<String, dynamic> original,
    Map<String, dynamic> proposed) {
  final before = original['allowanceNames'];
  final after = proposed['allowanceNames'];
  if (before is! List || after is! List) return const [];
  return before.whereType<String>().where((name) => !after.contains(name))
      .toSet().toList(growable: false);
}

String? protectedAttendanceAllowanceMessage(Object error) {
  if (error is! PostgrestException || error.code != '22023' ||
      !error.message.startsWith('署名済みの会社共通手当は、この勤怠修正では削除できません。')) {
    return null;
  }
  return '署名済みの会社共通手当を削除する変更が含まれているため、承認できません。\n\n'
      'この申請は承認せず、却下してください。\n\n'
      '手当を変えない場合は、元の手当を残して勤務修正を申請し直してください。\n\n'
      '手当を変更する場合は、対象日報の修正申請・承認を行い、日報で手当を変更して再署名してください。'
      'その後、勤怠を再読み込みし、ほかに必要な修正があれば新しく申請してください。以前の申請を再承認しないでください。';
}
