// Native admission behavior remains in the repository's existing actor guard.
Future<T> withPersonalPendingAdmission<T>(String actor, Future<T> Function() body) => body();
