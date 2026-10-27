/// A saved exemption is distinct from submission, verification or attachment.
Map<String, dynamic>? documentExemptionFor(Iterable<Map<String, dynamic>> rows,
    String? workerId, String? requirementId) {
  final matches = rows.where((row) => row['worker_id'] == workerId &&
      row['requirement_id'] == requirementId).toList();
  if (matches.length != 1) return null;
  final row = matches.single;
  if (row['active'] is! bool || row['version'] is! int ||
      (row['version'] as int) < 1 || row['reason'] is! String) { return null; }
  return row;
}
