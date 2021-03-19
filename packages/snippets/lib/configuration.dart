// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' hide Platform;

import 'package:path/path.dart' as path;

/// What type of snippet to produce.
enum SnippetType {
  /// Produces a snippet that includes the code interpolated into an application
  /// template.
  sample,

  /// Produces a nicely formatted sample code, but no application.
  snippet,
}

/// Return the name of an enum item.
String getEnumName(dynamic enumItem) {
  final String name = '$enumItem';
  final int index = name.indexOf('.');
  return index == -1 ? name : name.substring(index + 1);
}

abstract class SnippetConfiguration {
  const SnippetConfiguration({
    required this.configDirectory,
    required this.outputDirectory,
    required this.skeletonsDirectory,
    required this.templatesDirectory,
  });

  /// This is the configuration directory for the snippets system, containing
  /// the skeletons and templates.
  final Directory configDirectory;

  /// This is where the snippets themselves will be written, in order to be
  /// uploaded to the docs site.
  final Directory outputDirectory;

  /// The directory containing the HTML skeletons to be filled out with metadata
  /// and returned to dartdoc for insertion in the output.
  final Directory skeletonsDirectory;

  /// The directory containing the code templates that can be referenced by the
  /// dartdoc.
  final Directory templatesDirectory;

  /// This makes sure that the output directory exists, and creates it if it
  /// doesn't.
  void createOutputDirectory() {
    if (!outputDirectory.existsSync()) {
      outputDirectory.createSync(recursive: true);
    }
  }

  /// Gets the skeleton file to use for the given [SnippetType] and DartPad
  /// preference.
  File getHtmlSkeletonFile(SnippetType type, {bool showDartPad = false}) {
    assert(!showDartPad || type == SnippetType.sample,
        'Only application snippets work with dartpad.');
    final String filename =
        '${showDartPad ? 'dartpad-' : ''}${getEnumName(type)}.html';
    return File(path.join(skeletonsDirectory.path, filename));
  }
}

/// A class to compute the configuration of the snippets input and output
/// locations based in the current location of the snippets main.dart.
class FlutterRepoSnippetConfiguration extends SnippetConfiguration {
  FlutterRepoSnippetConfiguration({required Directory flutterRoot})
      : super(
            configDirectory: _underRoot(
                flutterRoot, const <String>['dev', 'snippets', 'config']),
            outputDirectory: _underRoot(
                flutterRoot, const <String>['dev', 'docs', 'doc', 'snippets']),
            skeletonsDirectory: _underRoot(flutterRoot,
                const <String>['dev', 'snippets', 'config', 'skeletons']),
            templatesDirectory: _underRoot(
              flutterRoot,
              const <String>['dev', 'snippets', 'config', 'templates'],
            ));

  static Directory _underRoot(Directory flutterRoot, List<String> dirs) =>
      Directory(path.canonicalize(
          path.joinAll(<String>[flutterRoot.absolute.path, ...dirs])));
}