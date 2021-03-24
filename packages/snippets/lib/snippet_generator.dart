// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as path;

import 'configuration.dart';
import 'model.dart';
import 'util.dart';

/// Generates the snippet HTML, as well as saving the output snippet main to
/// the output directory.
class SnippetGenerator {
  SnippetGenerator({SnippetConfiguration? configuration})
      : configuration = configuration ??
      FlutterRepoSnippetConfiguration(
        flutterRoot: Platform.environment['FLUTTER_ROOT'] == null
            ? getFlutterRoot()
            : Directory(Platform.environment['FLUTTER_ROOT']!),
      );

  /// The configuration used to determine where to get/save data for the
  /// snippet.
  final SnippetConfiguration configuration;

  static const JsonEncoder jsonEncoder = JsonEncoder.withIndent('    ');

  /// A Dart formatted used to format the snippet code and finished application
  /// code.
  static DartFormatter formatter =
  DartFormatter(pageWidth: 80, fixes: StyleFix.all);

  /// This returns the output file for a given snippet ID. Only used for
  /// [SampleType.sample] snippets.
  File getOutputFile(String id) =>
      File(path.join(configuration.outputDirectory.path, '$id.dart'));

  /// Gets the path to the template file requested.
  File? getTemplatePath(String templateName, {Directory? templatesDir}) {
    final Directory templateDir =
        templatesDir ?? configuration.templatesDirectory;
    final File templateFile =
    File(path.join(templateDir.path, '$templateName.tmpl'));
    return templateFile.existsSync() ? templateFile : null;
  }

  /// Injects the [injections] into the [template], and turning the
  /// "description" injection into a comment. Only used for
  /// [SampleType.sample] snippets.
  String interpolateTemplate(List<TemplateInjection> injections, String template,
      Map<String, Object?> metadata) {
    final RegExp moustacheRegExp = RegExp('{{([^}]+)}}');
    return template.replaceAllMapped(moustacheRegExp, (Match match) {
      if (match[1] == 'description') {
        // Place the description into a comment.
        final List<String> description = injections
            .firstWhere((TemplateInjection tuple) => tuple.name == match[1])
            .contents
            .map<String>((String line) => '// $line')
            .toList();
        // Remove any leading/trailing empty comment lines.
        // We don't want to remove ALL empty comment lines, only the ones at the
        // beginning and the end.
        while (description.isNotEmpty && description.last == '// ') {
          description.removeLast();
        }
        while (description.isNotEmpty && description.first == '// ') {
          description.removeAt(0);
        }
        return description.join('\n').trim();
      } else {
        // If the match isn't found in the injections, then just remove the
        // mustache reference, since we want to allow the sections to be
        // "optional" in the input: users shouldn't be forced to add an empty
        // "```dart preamble" section if that section would be empty.
        final int componentIndex = injections.indexWhere(
                (TemplateInjection injection) => injection.name == match[1]);
        if (componentIndex == -1) {
          return (metadata[match[1]] ?? '').toString();
        }
        return injections[componentIndex].mergedContent;
      }
    }).trim();
  }

  /// Parses the input for the various code and description segments, and
  /// returns them in the order found.
  List<TemplateInjection> parseInput(CodeSample sample) {
    bool inCodeBlock = false;
    final List<String> description = <String>[];
    final List<TemplateInjection> components = <TemplateInjection>[];
    String? language;
    final RegExp codeStartEnd =
    RegExp(r'^\s*```(?<language>[-\w]+|[-\w]+ (?<section>[-\w]+))?\s*$');
    for (final String line in sample.input.map<String>((Line line) => line.code)) {
      final RegExpMatch? match = codeStartEnd.firstMatch(line);
      if (match != null) {
        // If we saw the start or end of a code block
        inCodeBlock = !inCodeBlock;
        if (match.namedGroup('language') != null) {
          language = match[1]!;
          if (match.namedGroup('section') != null) {
            components.add(TemplateInjection(
                'code-${match.namedGroup('section')}', <String>[],
                language: language));
          } else {
            components
                .add(TemplateInjection('code', <String>[], language: language));
          }
        } else {
          language = null;
        }
        continue;
      }
      if (!inCodeBlock) {
        description.add(line);
      } else {
        assert(language != null);
        components.last.contents.add(line);
      }
    }
    sample.parts = <TemplateInjection>[
      TemplateInjection('description', description),
      ...components,
    ];
    return sample.parts;
  }

  String _loadFileAsUtf8(File file) {
    return file.readAsStringSync(encoding: utf8);
  }

  String _addLineNumbers(String app) {
    final StringBuffer buffer = StringBuffer();
    int count = 0;
    for (final String line in app.split('\n')) {
      count++;
      buffer.writeln('${count.toString().padLeft(5, ' ')}: $line');
    }
    return buffer.toString();
  }

  /// The main routine for generating snippets.
  ///
  /// The [sample] is the file containing the dartdoc comments (minus the leading
  /// comment markers).
  ///
  /// The [type] is the type of snippet to create: either a
  /// [SampleType.sample] or a [SampleType.snippet].
  ///
  /// [showDartPad] indicates whether DartPad should be shown where possible.
  /// Currently, this value only has an effect if [type] is
  /// [SampleType.sample], in which case an alternate skeleton file is
  /// used to create the final HTML output.
  ///
  /// The [template] must not be null if the [type] is
  /// [SampleType.sample], and specifies the name of the template to use
  /// for the application code.
  ///
  /// The [id] is a string ID to use for the output file, and to tell the user
  /// about in the `flutter create` hint. It must not be null if the [type] is
  /// [SampleType.sample].
  String generate(
      CodeSample sample, {
        Map<String, Object?>? metadata,
      }) {
    metadata ??= <String, Object>{};
    metadata['id'] ??= sample.id;
    metadata['element'] ??= sample.start.element;

    configuration.createOutputDirectoryIfNeeded();

    final List<TemplateInjection> snippetData = parseInput(sample);
    switch (sample.type) {
      case SampleType.dartpad:
      case SampleType.sample:
        final String template = sample.template;
        final Directory templatesDir = configuration.templatesDirectory;
        if (templatesDir == null) {
          stderr.writeln('Unable to find the templates directory.');
          exit(1);
        }
        final File? templateFile =
        getTemplatePath(template, templatesDir: templatesDir);
        if (templateFile == null) {
          stderr.writeln(
              'The template $template was not found in the templates directory ${templatesDir.path}');
          exit(1);
        }
        final String templateContents = _loadFileAsUtf8(templateFile);
        String app =
        interpolateTemplate(snippetData, templateContents, metadata);

        try {
          app = formatter.format(app);
        } on FormatterException catch (exception) {
          stderr.write('Code to format:\n${_addLineNumbers(app)}\n');
          errorExit('Unable to format snippet app template: $exception');
        }
        snippetData.add(TemplateInjection('app', app.split('\n')));
        sample.output = app;
        final int descriptionIndex = snippetData
            .indexWhere((TemplateInjection data) => data.name == 'description');
        final String descriptionString = descriptionIndex == -1
            ? ''
            : snippetData[descriptionIndex].mergedContent;
        sample.description = descriptionString;
        break;
      case SampleType.snippet:
        break;
    }
    return sample.output;
  }
}
