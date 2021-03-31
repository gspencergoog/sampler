// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:file/local.dart';
import 'package:file/file.dart';
import 'package:process/process.dart';
import 'package:recase/recase.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:snippets/snippet_generator.dart';

import 'analysis.dart';
import 'model.dart';
import 'snippet_parser.dart';
import 'util.dart';

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

  Map<String, int> _findReplacementRangeAndIndents() {
    final File frameworkFile = sample.start.file!;
    final List<List<SourceLine>> frameworkComments = getFileComments(frameworkFile).where((List<SourceLine> lines) {
      return lines.first.element == sample.element;
    }).toList();
    if (frameworkComments.length != 1) {
      throw SnippetException('Unable to find original comment block for sample ${sample.id}');
    }
    final SnippetDartdocParser parser = SnippetDartdocParser();
    final List<CodeSample> foundBlocks = parser.parseComment(frameworkComments.first).where((CodeSample foundSample) {
      return foundSample.id == sample.id;
    }).toList();
    if (foundBlocks.length != 1) {
      throw SnippetException('Unable to find original location for sample ${sample.id}');
    }
    final CodeSample foundBlock = foundBlocks.first;
    final int startRange = foundBlock.input.first.startChar;
    final int endRange = foundBlock.input.last.endChar;
    // find out much the first line in the comment was indented.
    final RegExp indentRegexp = RegExp(r'^([ ]*).*$');
    final RegExpMatch? indentMatch = indentRegexp.firstMatch(frameworkComments.first.first.text);
    final int commentIndent = indentMatch?[1]?.length ?? 0;
    return <String, int>{'startRange': startRange, 'endRange': endRange, 'commentIndent': commentIndent};
  }

  String _buildSampleReplacement(Map<String, List<String>> sections, List<String> sectionOrder, Map<String, int> indents) {
    final String commentMarker = '${' ' * indents['commentIndent']!}///';
    final List<String> result = <String>[commentMarker]; // add a blank line at the beginning.
    for (final String section in sectionOrder) {
      final String dartdocSection = section.replaceFirst(RegExp(r'code-?'), ' ').trimRight();
      final List<String> sectionContents = sections[section]!;
      final int sectionIndent = sectionContents.first.length - sectionContents.first.trimLeft().length;
      if (section != 'description') {
        result.add('$commentMarker ```dart$dartdocSection');
      }
      result.addAll(sections[section]!.map<String>((String line) {
        assert(line.substring(0, sectionIndent).trim().isEmpty);
        line = line.substring(sectionIndent);
        return '$commentMarker $line';
      }));
      if (section != 'description') {
        result.add('$commentMarker ```');
      }
      if (section != sectionOrder.last) {
        result.add(commentMarker); // add a blank line between sections.
      }
    }
    return result.join('\n');
  }

  Future<void> _parseMainDart({required Map<String, List<String>> sections, required List<String> sectionOrder}) async {
    final List<String> mainDartLines = await mainDart.readAsLines();
    final RegExp sectionMarkerRe = RegExp(
        r'^([/]{2}\*) ((?<direction>\S)\3{7}) (?<name>[-a-zA-Z0-9]+).*$');
    String? currentSection;
    int firstTrailingEmpty = -1;
    sections.clear();
    sectionOrder.clear();
    for (String line in mainDartLines) {
      final RegExpMatch? match = sectionMarkerRe.firstMatch(line);
      if (match != null) {
        if (match.namedGroup('direction')! == '⯆') {
          // Start of section, initialize it.
          currentSection = match.namedGroup('name')!;
          sections[currentSection] ??= <String>[];
          sectionOrder.add(currentSection);
        } else {
          // End of a section
          // Remove any blank lines at the end
          if (firstTrailingEmpty >= 0 && firstTrailingEmpty < sections[currentSection]!.length) {
            sections[currentSection]!.removeRange(firstTrailingEmpty, sections[currentSection]!.length);
          }
          currentSection = null;
          firstTrailingEmpty = -1;
        }
      } else {
        if (currentSection != null) {
          final bool isEmpty = line
              .trim()
              .isEmpty;
          if (sections[currentSection]!.isEmpty && isEmpty) {
            continue;
          }
          if (currentSection == 'description') {
            // Strip comment markers off of description lines.
            line = line.replaceFirst(RegExp(r'^\s*///? ?'), '');
          }
          sections[currentSection]!.add(line);
          if (!isEmpty) {
            // If we find a non-empty line, reset the trailing empty index.
            firstTrailingEmpty = sections[currentSection]!.length;
          }
        }
      }
    }
  }

  Future<String> restore() async {
    try {
      // Load up the modified main.dart and parse out the components, keeping them
      // in order.
      final Map<String, List<String>> sections = <String, List<String>>{};
      final List<String> sectionOrder = <String>[];
      await _parseMainDart(sections:sections, sectionOrder: sectionOrder);

      // Re-parse the original file to find the current char range for the
      // original example.
      final Map<String, int> rangesAndIndents = _findReplacementRangeAndIndents();

      // 3) Create a substitute example, and replace the char range with the new example.
      final String replacement = _buildSampleReplacement(sections, sectionOrder, rangesAndIndents);
      // 4) Rewrite the original framework file.
      final File frameworkFile = sample.start.file!;
      String frameworkContents = await frameworkFile.readAsString();
      frameworkContents = frameworkContents.replaceRange(rangesAndIndents['startRange']!, rangesAndIndents['endRange']!, replacement);
      await frameworkFile.writeAsString(frameworkContents);
    } on SnippetException catch (e) {
      return e.message;
    }
    return '';
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
