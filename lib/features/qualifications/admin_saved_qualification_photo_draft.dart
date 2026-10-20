/// A local selection only. Returning it neither submits nor approves a request.
class AdminSavedQualificationPhotoDraft {
  AdminSavedQualificationPhotoDraft({
    required this.companyId,
    required this.actorId,
    required this.targetId,
    required Iterable<String> savedPaths,
    required Iterable<String> selectedPaths,
  }) : savedPaths = List.unmodifiable(savedPaths),
       selectedPaths = List.unmodifiable(selectedPaths);

  final String companyId;
  final String actorId;
  final String targetId;
  final List<String> savedPaths;
  final List<String> selectedPaths;
}
