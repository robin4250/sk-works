import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// This terminal display flag is scoped to one user in one company.
/// It never serves as evidence that business data has been saved.
class TutorialPreferences {
  TutorialPreferences({Future<SharedPreferences> Function()? loader})
      : _loader = loader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _loader;

  String _key(String userId, String companyId) {
    if (userId.trim().isEmpty || companyId.trim().isEmpty) {
      throw ArgumentError('Tutorial preferences require user and company IDs.');
    }
    return 'sko.tutorial.initial_completed.v1.${jsonEncode([userId, companyId])}';
  }

  Future<bool> initialCompleted({required String userId, required String companyId}) async =>
      (await _loader()).getBool(_key(userId, companyId)) ?? false;

  /// Once completed, later task additions must use attention items instead.
  /// There is deliberately no reset API: restarting the guide is separate.
  Future<void> markInitialCompleted({required String userId, required String companyId}) async {
    final saved = await (await _loader()).setBool(_key(userId, companyId), true);
    if (!saved) {
      throw StateError('Could not persist tutorial completion.');
    }
  }
}
