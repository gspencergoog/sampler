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
  static DartFormatter formatter = DartFormatter(pageWidth: 80, fixes: StyleFix.all);

  /// This returns the output file for a given snippet ID. Only used for
  /// [SampleType.sample] snippets.
  File getOutputFile(String id) => File(path.join(configuration.outputDirectory.path, '$id.dart'));

  /// Gets the path to the template file requested.
  File? getTemplatePath(String templateName, {Directory? templatesDir}) {
    final Directory templateDir = templatesDir ?? configuration.templatesDirectory;
    final File templateFile = File(path.join(templateDir.path, '$templateName.tmpl'));
    return templateFile.existsSync() ? templateFile : null;
  }

  /// Injects the [injections] into the [template], and turning the
  /// "description" injection into a comment. Only used for
  /// [SampleType.sample] snippets.
  String interpolateTemplate(
      List<TemplateInjection> injections, String template, Map<String, Object?> metadata) {
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
        final int componentIndex =
            injections.indexWhere((TemplateInjection injection) => injection.name == match[1]);
        if (componentIndex == -1) {
          return (metadata[match[1]] ?? '').toString();
        }
        return injections[componentIndex].mergedContent;
      }
    }).trim();
  }

  /// Interpolates the [injections] into an HTML skeleton file.
  ///
  /// Similar to interpolateTemplate, but we are only looking for `code-`
  /// components, and we care about the order of the injections.
  ///
  /// Takes into account the [type] and doesn't substitute in the id and the app
  /// if not a [SnippetType.sample] snippet.
  String interpolateSkeleton(
    String type,
    List<TemplateInjection> injections,
    String skeleton,
    Map<String, Object?> metadata,
  ) {
    final List<String> result = <String>[];
    const HtmlEscape htmlEscape = HtmlEscape();
    String? language;
    for (final TemplateInjection injection in injections) {
      if (!injection.name.startsWith('code')) {
        continue;
      }
      result.addAll(injection.contents);
      if (injection.language.isNotEmpty) {
        language = injection.language;
      }
      result.addAll(<String>['', '// ...', '']);
    }
    if (result.length > 3) {
      result.removeRange(result.length - 3, result.length);
    }
    // Only insert a div for the description if there actually is some text there.
    // This means that the {{description}} marker in the skeleton needs to
    // be inside of an {@inject-html} block.
    String description = injections
        .firstWhere((TemplateInjection tuple) => tuple.name == 'description')
        .mergedContent;
    description = description.trim().isNotEmpty
        ? '<div class="snippet-description">{@end-inject-html}$description{@inject-html}</div>'
        : '';

    // DartPad only supports stable or master as valid channels. Use master
    // if not on stable so that local runs will work (although they will
    // still take their sample code from the master docs server).
    final String channel = metadata['channel'] == 'stable' ? 'stable' : 'master';

    final Map<String, String> substitutions = <String, String>{
      'description': description,
      'code': htmlEscape.convert(result.join('\n')),
      'language': language ?? 'dart',
      'serial': '',
      'id': metadata['id']! as String,
      'channel': channel,
      'element': metadata['element'] as String? ?? '',
      'app': '',
    };
    if (type == 'sample') {
      substitutions
        ..['serial'] = metadata['serial']?.toString() ?? '0'
        ..['app'] = htmlEscape.convert(
            injections.firstWhere((TemplateInjection tuple) => tuple.name == 'app').mergedContent);
    }
    return skeleton.replaceAllMapped(RegExp('{{(${substitutions.keys.join('|')})}}'),
        (Match match) {
      return substitutions[match[1]]!;
    });
  }

  /// Consolidates all of the snippets and the preamble into one snippet, in
  /// order to create a compilable result.
  Iterable<String> consolidateSnippets(List<CodeSample> samples) {
    final List<CodeSample> preambles = samples.where((CodeSample sample) => sample.start.element == '#preamble').toList();
    assert(preambles.length < 2);
    final List<Line> snippetLines = <Line>[
      ...preambles.expand((CodeSample sample) => sample.input)
    ];
    final Iterable<SnippetSample> snippets = samples.whereType<SnippetSample>();
    for (SnippetSample snippet in snippets) {
      snippet = _processBlock(snippet);
    }
    final List<TemplateInjection> injections = parseInput(SnippetSample(snippetLines));
    return injections.expand<String>((TemplateInjection injection) => injection.contents);
  }

  /// A RegExp that matches a Dart constructor.
  static final RegExp _constructorRegExp = RegExp(r'(const\s+)?_*[A-Z][a-zA-Z0-9<>._]*\(');

  /// A serial number so that we can create unique expression names when we
  /// generate them.
  int _expressionId = 0;

  /// Process one block of sample code (the part inside of "```" markers).
  /// Splits any sections denoted by "// ..." into separate blocks to be
  /// processed separately. Uses a primitive heuristic to make sample blocks
  /// into valid Dart code.
  SnippetSample _processBlock(SnippetSample snippet) {
    final List<Line> block = snippet.input.toList();
    if (block.isEmpty) {
      throw SnippetException('${snippet.start}: Empty ```dart block in sample code.');
    }
    final String firstLine = block.first.code;
    if (firstLine.startsWith('new ') || firstLine.startsWith(_constructorRegExp)) {
      _expressionId += 1;
      return SnippetSample.surround('dynamic expression$_expressionId = ', block.toList(), ';');
    } else if (firstLine.startsWith('await ')) {
      _expressionId += 1;
      return SnippetSample.surround(
          'Future<void> expression$_expressionId() async { ', block.toList(), ' }');
    } else if (block.first.code.startsWith('class ') || block.first.code.startsWith('enum ')) {
      return SnippetSample(block);
    } else if ((block.first.code.startsWith('_') || block.first.code.startsWith('final ')) &&
        block.first.code.contains(' = ')) {
      _expressionId += 1;
      return SnippetSample.surround('void expression$_expressionId() { ', block.toList(), ' }');
    } else {
      final List<Line> buffer = <Line>[];
      int blocks = 0;
      Line? subLine;
      final List<SnippetSample> subsections = <SnippetSample>[];
      for (int index = 0; index < block.length; index += 1) {
        // Each section of the dart code that is either split by a blank line, or with
        // '// ...' is treated as a separate code block.
        if (block[index].code.trim().isEmpty || block[index].code == '// ...') {
          if (subLine == null)
            throw SnippetException(
                '${Line('', file: block.first.file, line: block.first.line + index, indent: block.first.indent)}: '
                    'Unexpected blank line or "// ..." line near start of block in sample code.');
          blocks += 1;
          subsections.add(_processBlock(SnippetSample(buffer)));
          buffer.clear();
          assert(buffer.isEmpty);
          subLine = null;
        } else if (block[index].code.startsWith('// ')) {
          if (buffer.length > 1) // don't include leading comments
            buffer.add(
                Line('/${block[index].code}')); // so that it doesn't start with "// " and get caught in this again
        } else {
          subLine ??= block[index];
          buffer.add(block[index]);
        }
      }
      if (blocks > 0) {
        if (subLine != null) {
          subsections.add(_processBlock(SnippetSample(buffer)));
        }
        // Combine all of the subsections into one section, now that they've been processed.
        return SnippetSample.combine(subsections);
      } else {
        return SnippetSample(block);
      }
    }
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
            components.add(TemplateInjection('code-${match.namedGroup('section')}', <String>[],
                language: language));
          } else {
            components.add(TemplateInjection('code', <String>[], language: language));
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

  String generateHtml(CodeSample sample) {
    final String skeleton =
    _loadFileAsUtf8(configuration.getHtmlSkeletonFile(sample.type));
    return interpolateSkeleton(sample.type, sample.parts, skeleton, sample.metadata);
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
  /// The optional [template] parameter can be used to override specifies the
  /// name of the template to use for interpolating the application code.
  /// Defaults to the template provided by the [CodeSample].
  ///
  /// The [id] is a string ID to use for the output file, and to tell the user
  /// about in the `flutter create` hint. It must not be null if the [type] is
  /// [SampleType.sample].
  String generateCode(
    CodeSample sample, {
    File? output,
  }) {
    configuration.createOutputDirectoryIfNeeded();

    final List<TemplateInjection> snippetData = parseInput(sample);
    switch (sample.runtimeType) {
      case DartpadSample:
      case ApplicationSample:
        final Directory templatesDir = configuration.templatesDirectory;
        if (templatesDir == null) {
          stderr.writeln('Unable to find the templates directory.');
          exit(1);
        }
        final String templateName = sample.template;
        final File? templateFile = getTemplatePath(templateName, templatesDir: templatesDir);
        if (templateFile == null) {
          stderr.writeln('The template $templateName was not found in the templates '
              'directory ${templatesDir.path}');
          exit(1);
        }
        final String templateContents = _loadFileAsUtf8(templateFile);
        String app = interpolateTemplate(snippetData, templateContents, sample.metadata);

        try {
          app = formatter.format(app);
        } on FormatterException catch (exception) {
          stderr.write('Code to format:\n${_addLineNumbers(app)}\n');
          errorExit('Unable to format snippet app template: $exception');
        }
        snippetData.add(TemplateInjection('app', app.split('\n')));
        sample.output = app;
        final int descriptionIndex =
            snippetData.indexWhere((TemplateInjection data) => data.name == 'description');
        final String descriptionString =
            descriptionIndex == -1 ? '' : snippetData[descriptionIndex].mergedContent;
        sample.description = descriptionString;
        break;
      case SnippetSample:
        const String templateContents = '{{code}}';
        final String app = interpolateTemplate(snippetData, templateContents, sample.metadata);
        snippetData.add(TemplateInjection('app', app.split('\n')));
        sample.output = app;
        final int descriptionIndex =
        snippetData.indexWhere((TemplateInjection data) => data.name == 'description');
        final String descriptionString =
        descriptionIndex == -1 ? '' : snippetData[descriptionIndex].mergedContent;
        sample.description = descriptionString;
        break;
    }
    sample.metadata['description'] = sample.description;
    if (output != null) {
      output.writeAsStringSync(sample.output);

      final File metadataFile = File(path.join(path.dirname(output.path),
          '${path.basenameWithoutExtension(output.path)}.json'));
      sample.metadata['file'] = path.basename(output.path);
      metadataFile.writeAsStringSync(jsonEncoder.convert(sample.metadata));
    }
    return sample.output;
  }
}
