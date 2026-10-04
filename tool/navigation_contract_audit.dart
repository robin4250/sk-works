import 'dart:io';

void main() {
  final source = File('lib/app_v2.dart').readAsStringSync();
  final menuStart = source.indexOf('List<_MenuAction> get _menuItems');
  final homeStart = source.indexOf('Widget _homeDashboard');
  final routeStart = source.indexOf('Future<void> _openHomeAction');

  if (menuStart < 0 || homeStart < 0 || routeStart < 0) {
    stderr.writeln('Could not find app navigation sections.');
    exitCode = 1;
    return;
  }

  final menu = source.substring(menuStart, homeStart);
  final routes = source.substring(routeStart, menuStart);

  final menuKeys = RegExp(r"key:\s*'([^']+)'")
      .allMatches(menu)
      .map((match) => match.group(1)!)
      .toSet();
  final explicitRoutes = <String>{
    ...RegExp(r"case\s+'([^']+)'")
        .allMatches(routes)
        .map((match) => match.group(1)!),
    ...RegExp(r"key\s*==\s*'([^']+)'")
        .allMatches(routes)
        .map((match) => match.group(1)!),
  };

  final fallbackModules = <String>{};
  final modulesFile = File('lib/app.dart');
  if (modulesFile.existsSync()) {
    final modules = modulesFile.readAsStringSync();
    fallbackModules.addAll(
      RegExp(r"storageKey:\s*'([^']+)'")
          .allMatches(modules)
          .map((match) => match.group(1)!),
    );
  }

  final unresolved = menuKeys
      .where((key) => !explicitRoutes.contains(key) && !fallbackModules.contains(key))
      .toList()
    ..sort();

  stdout.writeln('SKO navigation audit');
  stdout.writeln('menu_keys=' + menuKeys.length.toString());
  stdout.writeln('explicit_routes=' + explicitRoutes.length.toString());
  stdout.writeln('fallback_modules=' + fallbackModules.length.toString());

  if (unresolved.isEmpty) {
    stdout.writeln('OK: all menu keys resolve to a route or module fallback.');
  } else {
    stdout.writeln('UNRESOLVED: ' + unresolved.join(', '));
    exitCode = 1;
  }
}
