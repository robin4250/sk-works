import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device-day preflight prevents stale main but allows detached fetched main', () {
    final source =
        File('tool/device_day_preflight.sh').readAsStringSync();

    expect(source, contains('git fetch --quiet origin main'));
    expect(source, contains(r'remote_full="$(git rev-parse FETCH_HEAD)"'));
    expect(source, isNot(contains('git rev-parse origin/main')));
    expect(
      source.indexOf('git fetch --quiet origin main'),
      lessThan(source.indexOf('git rev-parse FETCH_HEAD')),
    );
    expect(source, contains(r'if [[ "$local_full" == "$remote_full" ]]; then'));
    expect(
      source,
      contains(r'elif [[ -z "$branch_name" ]]; then'),
    );
    expect(
      source,
      contains(r'git merge-base --is-ancestor "$local_full" "$remote_full"'),
    );
    expect(
      source,
      contains('ローカルHEADと取得したmainが分岐しています'),
    );
    expect(
      source,
      contains('自動pullや強制更新は行いません'),
    );
    expect(
      source,
      isNot(contains('fail "現在のbranchは main ではありません')),
    );
  });

  test('narrow fetch detects new main even when origin/main remains stale', () {
    final temporary = Directory.systemTemp.createTempSync('sko-main-fetch-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final upstream = Directory('${temporary.path}/upstream');
    final clone = Directory('${temporary.path}/clone');

    String git(List<String> arguments, {Directory? directory}) {
      final result = Process.runSync(
        'git',
        arguments,
        workingDirectory: directory?.path,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return '${result.stdout}'.trim();
    }

    git(['init', '-b', 'main', upstream.path]);
    git(['config', 'user.name', 'Fixture'], directory: upstream);
    git(['config', 'user.email', 'fixture@example.invalid'], directory: upstream);
    File('${upstream.path}/version').writeAsStringSync('old');
    git(['add', 'version'], directory: upstream);
    git(['commit', '-m', 'old'], directory: upstream);
    git(['clone', upstream.path, clone.path]);
    final oldMain = git(['rev-parse', 'origin/main'], directory: clone);
    git([
      'config',
      'remote.origin.fetch',
      '+refs/heads/other:refs/remotes/origin/other',
    ], directory: clone);
    File('${upstream.path}/version').writeAsStringSync('new');
    git(['add', 'version'], directory: upstream);
    git(['commit', '-m', 'new'], directory: upstream);
    final newMain = git(['rev-parse', 'HEAD'], directory: upstream);

    git(['fetch', '--quiet', 'origin', 'main'], directory: clone);
    expect(git(['rev-parse', 'origin/main'], directory: clone), oldMain);
    expect(git(['rev-parse', 'HEAD'], directory: clone), oldMain);
    expect(git(['rev-parse', 'FETCH_HEAD'], directory: clone), newMain);
    expect(newMain, isNot(oldMain));

    // A detached checkout of the fetched commit is still a fresh source.
    git(['checkout', '--detach', 'FETCH_HEAD'], directory: clone);
    expect(git(['branch', '--show-current'], directory: clone), isEmpty);
    expect(
      git(['rev-parse', 'HEAD'], directory: clone),
      git(['rev-parse', 'FETCH_HEAD'], directory: clone),
    );
    expect(git(['rev-parse', 'origin/main'], directory: clone), oldMain);
  });

}
