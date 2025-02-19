// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

late PackageServer server;

void main() {
  setUp(() async {
    server = await servePackages();

    server.serve('foo', '1.0.0');
    server.serve('foo', '2.0.0');

    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('web', []),
      d.dir('bin', [d.file('script.dart', "main() => print('hello!');")])
    ]).create();

    await pubGet();
  });

  test(
      'does not require a pub get if a `flutter_gen` package is injected into package_config.json',
      () async {
    await d.dir('bar', [
      d.pubspec({'name': 'bar'})
    ]).create();
    await d.dir(appPath, [
      d.appPubspec(
        dependencies: {
          'bar': {'path': '../bar'}
        },
      )
    ]).create();

    await pubGet();

    final packageConfig =
        p.join(d.sandbox, 'myapp', '.dart_tool', 'package_config.json');
    final contents = json.decode(readTextFile(packageConfig));
    contents['packages'].add({
      'name': 'flutter_gen',
      'rootUri': '.dart_tool/flutter_gen',
      'languageVersion': '2.8',
    });
    writeTextFile(packageConfig, json.encode(contents));

    await runPub(args: ['run', 'bin/script.dart'], output: endsWith('hello!'));
  });
  group('requires the user to run pub get first if', () {
    group("there's no lockfile", () {
      setUp(() {
        deleteEntry(p.join(d.sandbox, 'myapp/pubspec.lock'));
      });

      _requiresPubGet(
        'No pubspec.lock file found, please run "dart pub get" first.',
      );
    });

    group("there's no package_config.json", () {
      setUp(() {
        deleteEntry(p.join(d.sandbox, 'myapp/.dart_tool/package_config.json'));
      });

      _requiresPubGet(
        'No .dart_tool${p.separator}package_config.json file found, please run "dart pub get".',
      );
    });

    group('the pubspec has a new dependency', () {
      setUp(() async {
        await d.dir('foo', [d.libPubspec('foo', '1.0.0')]).create();

        await d.dir(appPath, [
          d.appPubspec(
            dependencies: {
              'foo': {'path': '../foo'}
            },
          )
        ]).create();

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.yaml');
      });

      _requiresPubGet('The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated, please run "dart pub get" again.');
    });

    group('the lockfile has a dependency from the wrong source', () {
      setUp(() async {
        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.0.0'})
        ]).create();

        await pubGet();

        await createLockFile(appPath, dependenciesInSandBox: ['foo']);

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.yaml');
      });

      _requiresPubGet('The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated, please run "dart pub get" again.');
    });

    group('the lockfile has a dependency from an unknown source', () {
      setUp(() async {
        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.0.0'})
        ]).create();

        await pubGet();

        await d.dir(appPath, [
          d.file(
            'pubspec.lock',
            yaml({
              'packages': {
                'foo': {
                  'description': 'foo',
                  'version': '1.0.0',
                  'source': 'sdk'
                }
              }
            }),
          )
        ]).create();

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.yaml');
      });

      _requiresPubGet('The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated, please run "dart pub get" again.');
    });

    group('the lockfile has a dependency with the wrong description', () {
      setUp(() async {
        await d.dir('bar', [d.libPubspec('foo', '1.0.0')]).create();

        await d.dir(appPath, [
          d.appPubspec(
            dependencies: {
              'foo': {'path': '../bar'}
            },
          )
        ]).create();

        await pubGet();

        await createLockFile(appPath, dependenciesInSandBox: ['foo']);

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.yaml');
      });

      _requiresPubGet('The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated, please run "dart pub get" again.');
    });

    group('the pubspec has an incompatible version of a dependency', () {
      setUp(() async {
        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.0.0'})
        ]).create();

        await pubGet();

        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '2.0.0'})
        ]).create();

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.yaml');
      });

      _requiresPubGet('The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated, please run "dart pub get" again.');
    });

    group(
        'the lockfile is pointing to an unavailable package with a newer '
        'pubspec', () {
      setUp(() async {
        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.0.0'})
        ]).create();

        await pubGet();

        deleteEntry(p.join(d.sandbox, cachePath));

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.yaml');
      });

      _requiresPubGet('The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated, please run "dart pub get" again.');
    });

    group('the package_config.json file points to the wrong place', () {
      setUp(() async {
        await d.dir('bar', [d.libPubspec('foo', '1.0.0')]).create();

        await d.dir(appPath, [
          d.appPubspec(
            dependencies: {
              'foo': {'path': '../bar'}
            },
          )
        ]).create();

        await pubGet();

        await d.dir(appPath, [
          d.packageConfigFile([
            d.packageConfigEntry(
              name: 'foo',
              path: '../foo', // this is the wrong path
            ),
            d.packageConfigEntry(
              name: 'myapp',
              path: '.',
            ),
          ]),
        ]).create();

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.lock');
      });

      _requiresPubGet('The pubspec.lock file has changed since the '
          '.dart_tool${p.separator}package_config.json file was generated, '
          'please run "dart pub get" again.');
    });

    group("the lock file's SDK constraint doesn't match the current SDK", () {
      setUp(() async {
        // Avoid using a path dependency because it triggers the full validation
        // logic. We want to be sure SDK-validation works without that logic.
        server.serve(
          'foo',
          '3.0.0',
          pubspec: {
            'environment': {'sdk': '>=1.0.0 <2.0.0'}
          },
        );

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {'foo': '3.0.0'},
            'environment': {
              'sdk': '>=1.0.0 <2.0.0',
            },
          }),
        ]).create();

        await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '1.2.3+4'});
      });

      _requiresPubGet("Dart 3.1.2+3 is incompatible with your dependencies' "
          'SDK constraints. Please run "dart pub get" again.');
    });

    test(
        "the lock file's Flutter SDK constraint doesn't match the "
        'current Flutter SDK', () async {
      // Avoid using a path dependency because it triggers the full validation
      // logic. We want to be sure SDK-validation works without that logic.
      server.serve(
        'foo',
        '3.0.0',
        pubspec: {
          'environment': {
            'flutter': '>=1.0.0 <2.0.0',
            'sdk': defaultSdkConstraint
          }
        },
      );

      await d.dir('flutter', [d.file('version', '1.2.3')]).create();

      await d.dir(appPath, [
        d.appPubspec(dependencies: {'foo': '3.0.0'})
      ]).create();

      await pubGet(environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});

      await d.dir('flutter', [d.file('version', '0.9.0')]).create();

      // Run pub manually here because otherwise we don't have access to
      // d.sandbox.
      await runPub(
        args: ['run', 'script'],
        environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
        error: "Flutter 0.9.0 is incompatible with your dependencies' SDK "
            'constraints. Please run "dart pub get" again.',
        exitCode: exit_codes.DATA,
      );
    });

    group("a path dependency's dependency doesn't match the lockfile", () {
      setUp(() async {
        await d.dir('bar', [
          d.libPubspec('bar', '1.0.0', deps: {'foo': '1.0.0'})
        ]).create();

        await d.dir(appPath, [
          d.appPubspec(
            dependencies: {
              'bar': {'path': '../bar'}
            },
          )
        ]).create();

        await pubGet();

        // Update bar's pubspec without touching the app's.
        await d.dir('bar', [
          d.libPubspec('bar', '1.0.0', deps: {'foo': '2.0.0'})
        ]).create();
      });

      _requiresPubGet('${p.join('..', 'bar', 'pubspec.yaml')} has changed '
          'since the pubspec.lock file was generated, please run "dart pub get" '
          'again.');
    });

    group(
        "a path dependency's language version doesn't match the package_config.json",
        () {
      setUp(() async {
        await d.dir('bar', [
          d.libPubspec(
            'bar',
            '1.0.0',
            deps: {'foo': '1.0.0'},
            // Creates language version requirement 2.99
            sdk: '>= 2.99.0 <=4.0.0', // tests runs with '3.1.2+3'
          ),
        ]).create();

        await d.dir(appPath, [
          d.appPubspec(
            dependencies: {
              'bar': {'path': '../bar'}
            },
          )
        ]).create();

        await pubGet();

        // Update bar's pubspec without touching the app's.
        await d.dir('bar', [
          d.libPubspec(
            'bar',
            '1.0.0',
            deps: {'foo': '1.0.0'},
            // Creates language version requirement 2.100
            sdk: '>= 2.100.0 <=4.0.0', // tests runs with '3.1.2+3'
          ),
        ]).create();
      });

      _requiresPubGet('${p.join('..', 'bar', 'pubspec.yaml')} has changed '
          'since the pubspec.lock file was generated, please run "dart pub get" '
          'again.');
    });
  });

  group("doesn't require the user to run pub get first if", () {
    group(
        'the pubspec is older than the lockfile which is older than the '
        'package-config, even if the contents are wrong', () {
      setUp(() async {
        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.0.0'})
        ]).create();
        // Ensure we get a new mtime (mtime is only reported with 1s precision)
        await _touch('pubspec.yaml');

        await _touch('pubspec.lock');
        await _touch('.dart_tool/package_config.json');
      });

      _runsSuccessfully(runDeps: false);
    });

    group("the pubspec is newer than the lockfile, but they're up-to-date", () {
      setUp(() async {
        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.0.0'})
        ]).create();

        await pubGet();

        await _touch('pubspec.yaml');
      });

      _runsSuccessfully();
    });

    // Regression test for #1416
    group('a path dependency has a dependency on the root package', () {
      setUp(() async {
        await d.dir('foo', [
          d.libPubspec('foo', '1.0.0', deps: {'myapp': 'any'})
        ]).create();

        await d.dir(appPath, [
          d.appPubspec(
            dependencies: {
              'foo': {'path': '../foo'}
            },
          )
        ]).create();

        await pubGet();

        await _touch('pubspec.lock');
      });

      _runsSuccessfully();
    });

    group("the lockfile is newer than package_config.json, but it's up-to-date",
        () {
      setUp(() async {
        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.0.0'})
        ]).create();

        await pubGet();

        await _touch('pubspec.lock');
      });

      _runsSuccessfully();
    });

    group("an overridden dependency's SDK constraint is unmatched", () {
      setUp(() async {
        server.serve(
          'bar',
          '1.0.0',
          pubspec: {
            'environment': {'sdk': '0.0.0-fake'}
          },
        );

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependency_overrides': {'bar': '1.0.0'}
          })
        ]).create();

        await pubGet();

        await _touch('pubspec.lock');
      });

      _runsSuccessfully();
    });

    test('the lock file has a Flutter SDK but Flutter is unavailable',
        () async {
      // Avoid using a path dependency because it triggers the full validation
      // logic. We want to be sure SDK-validation works without that logic.
      server.serve(
        'foo',
        '3.0.0',
        pubspec: {
          'environment': {
            'flutter': '>=1.0.0 <2.0.0',
            'sdk': defaultSdkConstraint
          }
        },
      );

      await d.dir('flutter', [d.file('version', '1.2.3')]).create();

      await d.dir(appPath, [
        d.appPubspec(dependencies: {'foo': '3.0.0'})
      ]).create();

      await pubGet(environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});

      await d.dir('flutter', [d.file('version', '2.4.6')]).create();

      // Run pub manually here because otherwise we don't have access to
      // d.sandbox.
      await runPub(args: ['run', 'bin/script.dart']);
    });
  });
}

/// Runs every command that care about the world being up-to-date, and asserts
/// that it prints [message] as part of its error.
void _requiresPubGet(String message) {
  for (var command in ['run', 'deps']) {
    test('for pub $command', () {
      var args = [command];
      if (command == 'run') args.add('script');

      return runPub(
        args: args,
        error: contains(message),
        exitCode: exit_codes.DATA,
      );
    });
  }
}

/// Ensures that pub doesn't require "dart pub get" for the current package.
///
/// If [runDeps] is false, `pub deps` isn't included in the test. This is
/// sometimes not desirable, since it uses slightly stronger checks for pubspec
/// and lockfile consistency.
void _runsSuccessfully({bool runDeps = true}) {
  var commands = ['run'];
  if (runDeps) commands.add('deps');

  for (var command in commands) {
    test('for pub $command', () async {
      var args = [command];
      if (command == 'run') args.add('bin/script.dart');

      await runPub(args: args);

      // If pub determines that everything is up-to-date, it should set the
      // mtimes to indicate that.
      var pubspecModified =
          File(p.join(d.sandbox, 'myapp/pubspec.yaml')).lastModifiedSync();
      var lockFileModified =
          File(p.join(d.sandbox, 'myapp/pubspec.lock')).lastModifiedSync();
      var packageConfigModified =
          File(p.join(d.sandbox, 'myapp/.dart_tool/package_config.json'))
              .lastModifiedSync();

      expect(!pubspecModified.isAfter(lockFileModified), isTrue);
      expect(!lockFileModified.isAfter(packageConfigModified), isTrue);
    });
  }
}

/// Schedules a non-semantic modification to [path].
Future _touch(String path) async {
  // Delay a bit to make sure the modification times are noticeably different.
  // 1s seems to be the finest granularity that dart:io reports.
  await Future.delayed(Duration(seconds: 1));

  path = p.join(d.sandbox, 'myapp', path);
  touch(path);
}
