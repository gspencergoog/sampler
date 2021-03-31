// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:file/local.dart';
import 'package:file/file.dart';
import 'package:process/process.dart';
import 'package:snippets/snippets.dart';
import 'package:recase/recase.dart';
import 'package:pub_semver/pub_semver.dart';

import 'model.dart';

class FlutterProject {
  const FlutterProject(
    this.sample, {
    required this.location,
    String? name,
    this.filesystem = const LocalFileSystem(),
    this.processManager = const LocalProcessManager(),
    this.flutterRoot,
  }) : _name = name;

  final FileSystem filesystem;
  final ProcessManager processManager;
  final CodeSample sample;
  final Directory location;
  final String? _name;
  final Directory? flutterRoot;

  String get name => _name ?? '${sample.type}_${sample.element.snakeCase.replaceAll('.', '_')}_${sample.index}';
  File get mainDart => location.childDirectory('lib').childFile('main.dart');

  Future<bool> restore() async {
    // 1) Load up the modified main.dart, parse out the components.
    // final String mainDartContents = await mainDart.readAsString();
    // 2) Re-parse the original file to find the current char range for the
    // original example.
    // 3) Create a substitute example, and replace the char range with the new example.
    // 4) Rewrite the original framework file.
    return true;
  }

  Future<bool> export({bool overwrite = false}) async {
    if (await location.exists() && !overwrite) {
      throw SnippetException(
          'Project output location ${location.absolute.path} exists, refusing to overwrite.');
    }

    final Directory flutterRoot =
        this.flutterRoot ?? getFlutterRoot(processManager: processManager, filesystem: filesystem);
    final File flutter = flutterRoot.childDirectory('bin').childFile('flutter');
    if (!processManager.canRun(flutter.absolute.path)) {
      throw SnippetException('Unable to run flutter command');
    }

    final String description = 'A temporary code sample for ${sample.element}';
    ProcessResult result = await processManager.run(<String>[
      flutter.absolute.path,
      'create',
      if (overwrite) '--overwrite',
      '--org=dev.flutter',
      '--no-pub',
      '--description',
      description,
      '--project-name',
      name,
      '--template=app',
      '--platforms=linux,windows,macos,web',
      location.absolute.path,
    ]);

    if (result.exitCode != 0) {
      return false;
    }

    // Now, get rid of stuff we don't care about and write out main.dart.
    await location.childDirectory('test').delete(recursive: true);
    await location.childDirectory('lib').delete(recursive: true);
    await location.childDirectory('lib').create();

    final File mainDart = location.childDirectory('lib').childFile('main.dart');
    await mainDart.writeAsString(sample.output);

    // Rewrite the pubspec to include the right contstraints and point to the flutter root.

    final File pubspec = location.childFile('pubspec.yaml');
    final Version flutterVersion = getFlutterVersion();
    final Version dartVersion = getDartSdkVersion();
    await pubspec.writeAsString('''
name: $name
description: $description
publish_to: 'none'

version: 1.0.0+1

environment: 
  sdk: ">=$dartVersion <3.0.0"
  flutter: ">=$flutterVersion <3.0.0"

dependencies:
  cupertino_icons: 1.0.2
  flutter:
    sdk: flutter
    
flutter:
  uses-material-design: true
''');

    // Overwrite the analysis_options.yaml so that it matches the Flutter repo.

    final File analysisOptions = location.childFile('analysis_options.yaml');
    await analysisOptions.writeAsString('''
include: ${flutterRoot.absolute.path}/analysis_options.yaml
''');

    // Run 'flutter pub get' to update the dependencies.
    result = await processManager.run(<String>[flutter.absolute.path, 'pub', 'get'],
        workingDirectory: location.absolute.path);

    return result.exitCode == 0;
  }
}
