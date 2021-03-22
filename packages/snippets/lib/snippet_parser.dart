// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:path/path.dart' as path;

class SnippetParserException implements Exception {
  SnippetParserException(this.message, {this.file, this.line});
  final String message;
  final String? file;
  final int? line;

  @override
  String toString() {
    if (file != null || line != null) {
      final String fileStr = file == null ? '' : '$file:';
      final String lineStr = line == null ? '' : '$line:';
      return '$fileStr$lineStr Error: $message';
    } else {
      return 'Error: $message';
    }
  }
}

/// A class to represent a line of input code.
class Line {
  const Line(this.code, {this.filename = '', this.line = -1, this.indent = 0});
  final String filename;
  final int line;
  final int indent;
  final String code;

  String toStringWithColumn(int column) {
    if (column != null && indent != null) {
      return '$filename:$line:${column + indent}: $code';
    }
    return toString();
  }

  @override
  String toString() => '$filename:${line == -1 ? '??' : line}: $code';
}

/// A class to represent a section of sample code, marked by "{@tool
/// (snippet|sample|dartdoc) ...}...{@end-tool}".
abstract class Section {
  Section(
    this.args,
    this.input,
  )   : assert(input.isNotEmpty),
        assert(args.isNotEmpty),
        id = _createNameFromSource(args.first, input.first);

  final List<String> args;
  final String id;
  final List<Line> input;
  Line get start => input.first;

  /// Creates a name for the snippets tool to use for the snippet ID from a
  /// filename and starting line number.
  static String _createNameFromSource(String prefix, Line start) {
    String sampleId = path.split(start.filename).join('.');
    sampleId = path.basenameWithoutExtension(sampleId);
    sampleId = '$prefix.$sampleId.${start.line}';
    return sampleId;
  }

  @override
  String toString() {
    final StringBuffer buf = StringBuffer('${args.join(' ')}:\n');
    for (final Line line in input) {
      buf.writeln(' ${(line.line == -1 ? '??' : line.line).toString().padLeft(4, ' ')}: ${line.code}');
    }
    return buf.toString();
  }
}

/// A class to represent a snippet of sample code, marked by "{@tool
/// snippet}...{@end-tool}".
///
/// This is code that is not meant to be run as a complete application, but
/// rather as a code usage example.
class Snippet extends Section {
  Snippet(List<Line> input, {this.dartVersionOverride = ''}) : super(<String>['snippet'], input);

  factory Snippet.combine(List<Snippet> sections) {
    final List<Line> code =
        sections.expand((Snippet section) => section.input).toList();
    return Snippet(code);
  }

  factory Snippet.fromStrings(Line firstLine, List<String> code) {
    final List<Line> codeLines = <Line>[];
    for (int i = 0; i < code.length; ++i) {
      codeLines.add(
        Line(
          code[i],
          filename: firstLine.filename,
          line: firstLine.line + i,
          indent: firstLine.indent,
        ),
      );
    }
    return Snippet(codeLines);
  }

  factory Snippet.surround(
      Line firstLine, String prefix, List<String> code, String postfix) {
    assert(prefix != null);
    assert(postfix != null);
    final List<Line> codeLines = <Line>[];
    for (int i = 0; i < code.length; ++i) {
      codeLines.add(
        Line(
          code[i],
          filename: firstLine.filename,
          line: firstLine.line + i,
          indent: firstLine.indent,
        ),
      );
    }
    return Snippet(<Line>[
      Line(prefix),
      ...codeLines,
      Line(postfix),
    ]);
  }

  @override
  Line get start => input.firstWhere((Line line) => line.filename != null);

  final String dartVersionOverride;

  Snippet copyWith({String? dartVersionOverride = ''}) {
    if (dartVersionOverride == null) {
      return Snippet(input);
    }
    return Snippet(input, dartVersionOverride: dartVersionOverride);
  }
}

/// A class to represent a sample in the dartdoc comments, marked by
/// "{@tool sample ...}...{@end-tool}". Samples are processed separately from
/// regular snippets, because they must be injected into templates in order to be
/// analyzed.
class Sample extends Section {
  Sample({
    Line start = const Line(''),
    List<String> input = const <String>[],
    List<String> args = const <String>[],
    this.serial = -1,
  }) : super(args, _convertInput(input, start));

  static List<Line> _convertInput(List<String> input, Line start) {
    int lineNumber = start.line;
    return input
        .map<Line>((String line) => Line(line,
            line: lineNumber++, filename: start.filename, indent: start.indent))
        .toList();
  }

  final int serial;
}

/// Parses Snippets, samples, and dartdoc samples from the source file given to
/// [parse].
class SnippetParser {
  SnippetParser();

  /// The prefix of each comment line
  static const String _dartDocPrefix = '///';

  /// The prefix of each comment line with a space appended.
  static const String _dartDocPrefixWithSpace = '$_dartDocPrefix ';

  /// A RegExp that matches the beginning of a dartdoc snippet or sample.
  static final RegExp _dartDocSampleBeginRegex =
      RegExp(r'{@tool (?<type>sample|snippet|dartpad)(?:| (?<args>[^}]*))}');

  /// A RegExp that matches the end of a dartdoc snippet or sample.
  static final RegExp _dartDocSampleEndRegex = RegExp(r'{@end-tool}');

  /// A RegExp that matches the start of a code block within dartdoc.
  static final RegExp _codeBlockStartRegex = RegExp(r'///\s+```dart.*$');

  /// A RegExp that matches the end of a code block within dartdoc.
  static final RegExp _codeBlockEndRegex = RegExp(r'///\s+```\s*$');

  /// A RegExp that matches a Dart constructor.
  static final RegExp _constructorRegExp =
      RegExp(r'(const\s+)?_*[A-Z][a-zA-Z0-9<>._]*\(');

  /// A RegExp that matches a dart version specification in an example preamble.
  static final RegExp _dartVersionOverrideRegExp =
      RegExp(r'\/\/ (?<override>\/\/ @dart = (?<version>[0-9]+\.[0-9]+))');

  /// A serial number so that we can create unique expression names when we
  /// generate them.
  int _expressionId = 0;

  /// Extracts the samples from the Dart files in [files], writes them
  /// to disk, and adds them to the appropriate [sectionMap] or [sampleMap].
  Map<String, Section> parse(
    File file, {
    bool silent = false,
  }) {
    final List<Snippet> snippets = <Snippet>[];
    final List<Sample> samples = <Sample>[];
    int dartpadCount = 0;
    int sampleCount = 0;

    final List<String> sampleLines = file.readAsLinesSync();
    final List<Snippet> preambleSections = <Snippet>[];
    // Whether or not we're in the file-wide preamble section ("Examples can assume").
    bool inPreamble = false;
    // Whether or not we're in a code sample
    bool inSampleSection = false;
    // Whether or not we're in a snippet code sample (with template) specifically.
    bool inSnippet = false;
    // Whether or not we're in a '```dart' segment.
    bool inDart = false;
    String? dartVersionOverride;
    int lineNumber = 0;
    final List<String> block = <String>[];
    List<String> snippetArgs = <String>[];
    Line startLine = const Line('');
    for (final String line in sampleLines) {
      lineNumber += 1;
      final String trimmedLine = line.trim();
      if (inSnippet) {
        if (!trimmedLine.startsWith(_dartDocPrefix)) {
          throw SnippetParserException('Snippet section unterminated.',
              file: file.path, line: lineNumber);
        }
        if (_dartDocSampleEndRegex.hasMatch(trimmedLine)) {
          samples.add(
            Sample(
              start: startLine,
              input: block,
              args: snippetArgs,
              serial: samples.length,
            ),
          );
          snippetArgs = <String>[];
          block.clear();
          inSnippet = false;
          inSampleSection = false;
        } else {
          block.add(line.replaceFirst(RegExp(r'\s*/// ?'), ''));
        }
      } else if (inPreamble) {
        if (line.isEmpty) {
          inPreamble = false;
          // If there's only a dartVersionOverride in the preamble, don't add
          // it as a section. The dartVersionOverride was processed below.
          if (dartVersionOverride == null || block.isNotEmpty) {
            preambleSections.add(_processBlock(startLine, block));
          }
          block.clear();
        } else if (!line.startsWith('// ')) {
          throw SnippetParserException(
              'Unexpected content in sample code preamble.',
              file: file.path,
              line: lineNumber);
        } else {
          final RegExpMatch? override =
              _dartVersionOverrideRegExp.firstMatch(line);
          if (override != null) {
            dartVersionOverride = override.namedGroup('override');
          } else {
            block.add(line.substring(3));
          }
        }
      } else if (inSampleSection) {
        if (_dartDocSampleEndRegex.hasMatch(trimmedLine)) {
          if (inDart) {
            throw SnippetParserException(
                "Dart section didn't terminate before end of sample",
                file: file.path,
                line: lineNumber);
          }
          inSampleSection = false;
        }
        if (inDart) {
          if (_codeBlockEndRegex.hasMatch(trimmedLine)) {
            inDart = false;
            final Snippet processed = _processBlock(startLine, block);
            final Snippet combinedSection = preambleSections.isEmpty
                ? processed
                : Snippet.combine(preambleSections..add(processed));
            snippets.add(combinedSection.copyWith(
                dartVersionOverride: dartVersionOverride));
            block.clear();
          } else if (trimmedLine == _dartDocPrefix) {
            block.add('');
          } else {
            final int index = line.indexOf(_dartDocPrefixWithSpace);
            if (index < 0) {
              throw SnippetParserException(
                'Dart section inexplicably did not contain "$_dartDocPrefixWithSpace" prefix.',
                file: file.path,
                line: lineNumber,
              );
            }
            block.add(line.substring(index + 4));
          }
        } else if (_codeBlockStartRegex.hasMatch(trimmedLine)) {
          assert(block.isEmpty);
          startLine = Line(
            '',
            filename: file.path,
            line: lineNumber + 1,
            indent: line.indexOf(_dartDocPrefixWithSpace) +
                _dartDocPrefixWithSpace.length,
          );
          inDart = true;
        }
      }
      if (!inSampleSection) {
        final RegExpMatch? sampleMatch =
            _dartDocSampleBeginRegex.firstMatch(trimmedLine);
        if (line == '// Examples can assume:') {
          assert(block.isEmpty);
          startLine =
              Line('', filename: file.path, line: lineNumber + 1, indent: 3);
          inPreamble = true;
        } else if (sampleMatch != null) {
          inSnippet = sampleMatch != null &&
              (sampleMatch.namedGroup('type') == 'sample' ||
                  sampleMatch.namedGroup('type') == 'dartpad');
          if (inSnippet) {
            if (sampleMatch.namedGroup('type') == 'sample') {
              sampleCount++;
            }
            if (sampleMatch.namedGroup('type') == 'dartpad') {
              dartpadCount++;
            }
            startLine = Line(
              '',
              filename: file.path,
              line: lineNumber + 1,
              indent: line.indexOf(_dartDocPrefixWithSpace) +
                  _dartDocPrefixWithSpace.length,
            );
            if (sampleMatch.namedGroup('args') != null) {
              // There are arguments to the snippet tool to keep track of.
              snippetArgs = <String>[
                sampleMatch.namedGroup('type')!,
                ... _splitUpQuotedArgs(sampleMatch.namedGroup('args')!).toList()
              ];
            } else {
              snippetArgs = <String>[
                sampleMatch.namedGroup('type')!,
              ];
            }
          }
          inSampleSection = !inSnippet;
        } else if (RegExp(r'///\s*#+\s+[Ss]ample\s+[Cc]ode:?$')
            .hasMatch(trimmedLine)) {
          throw SnippetParserException(
            "Found deprecated '## Sample code' section: use {@tool snippet}...{@end-tool} instead.",
            file: file.path,
            line: lineNumber,
          );
        }
      }
    }
    if (!silent)
      print('Found ${snippets.length} snippet code blocks, $sampleCount '
          'sample code sections, and $dartpadCount dartpad sections.');
    final Map<String, Section> sectionMap = <String, Section>{};
    for (final Snippet snippet in snippets) {
      sectionMap[snippet.id] = snippet;
    }
    for (final Sample sample in samples) {
      sectionMap[sample.id] = sample;
    }
    return sectionMap;
  }

  /// Helper to process arguments given as a (possibly quoted) string.
  ///
  /// First, this will split the given [argsAsString] into separate arguments,
  /// taking any quoting (either ' or " are accepted) into account, including
  /// handling backslash-escaped quotes.
  ///
  /// Then, it will prepend "--" to any args that start with an identifier
  /// followed by an equals sign, allowing the argument parser to treat any
  /// "foo=bar" argument as "--foo=bar" (which is a dartdoc-ism).
  Iterable<String> _splitUpQuotedArgs(String argsAsString) {
    // Regexp to take care of splitting arguments, and handling the quotes
    // around arguments, if any.
    //
    // Match group 1 is the "foo=" (or "--foo=") part of the option, if any.
    // Match group 2 contains the quote character used (which is discarded).
    // Match group 3 is a quoted arg, if any, without the quotes.
    // Match group 4 is the unquoted arg, if any.
    final RegExp argMatcher = RegExp(r'([a-zA-Z\-_0-9]+=)?' // option name
        r'(?:' // Start a new non-capture group for the two possibilities.
        r'''(["'])((?:\\{2})*|(?:.*?[^\\](?:\\{2})*))\2|''' // with quotes.
        r'([^ ]+))'); // without quotes.
    final Iterable<Match> matches = argMatcher.allMatches(argsAsString);

    // Remove quotes around args, and if convertToArgs is true, then for any
    // args that look like assignments (start with valid option names followed
    // by an equals sign), add a "--" in front so that they parse as options.
    return matches.map<String>((Match match) {
      String option = '';
      if (match[1] != null && !match[1]!.startsWith('-')) {
        option = '--';
      }
      if (match[2] != null) {
        // This arg has quotes, so strip them.
        return '$option${match[1] ?? ''}${match[3] ?? ''}${match[4] ?? ''}';
      }
      return '$option${match[0]}';
    });
  }

//   /// Creates the configuration files necessary for the analyzer to consider
//   /// the temporary directory a package, and sets which lint rules to enforce.
//   void _createConfigurationFiles(Directory directory) {
//     final File pubSpec = File(path.join(directory.path, 'pubspec.yaml'))
//       ..createSync(recursive: true);
//
//     pubSpec.writeAsStringSync('''
// name: analyze_sample_code
// environment:
//   sdk: ">=2.12.0-0 <3.0.0"
// dependencies:
//   flutter:
//     sdk: flutter
//   flutter_test:
//     sdk: flutter
// ''');
//
//     // Copy in the analysis options from the Flutter root.
//     File(path.join(_flutterPackage.path, 'analysis_options_user.yaml'))
//         .copySync(path.join(directory.path, 'analysis_options.yaml'));
//   }

  /// Process one block of sample code (the part inside of "```" markers).
  /// Splits any sections denoted by "// ..." into separate blocks to be
  /// processed separately. Uses a primitive heuristic to make sample blocks
  /// into valid Dart code.
  Snippet _processBlock(Line line, List<String> block) {
    if (block.isEmpty) {
      throw SnippetParserException(
          '$line: Empty ```dart block in sample code.');
    }
    if (block.first.startsWith('new ') ||
        block.first.startsWith(_constructorRegExp)) {
      _expressionId += 1;
      return Snippet.surround(
          line, 'dynamic expression$_expressionId = ', block.toList(), ';');
    } else if (block.first.startsWith('await ')) {
      _expressionId += 1;
      return Snippet.surround(
          line,
          'Future<void> expression$_expressionId() async { ',
          block.toList(),
          ' }');
    } else if (block.first.startsWith('class ') ||
        block.first.startsWith('enum ')) {
      return Snippet.fromStrings(line, block.toList());
    } else if ((block.first.startsWith('_') ||
            block.first.startsWith('final ')) &&
        block.first.contains(' = ')) {
      _expressionId += 1;
      return Snippet.surround(
          line, 'void expression$_expressionId() { ', block.toList(), ' }');
    } else {
      final List<String> buffer = <String>[];
      int subblocks = 0;
      Line? subline;
      final List<Snippet> subsections = <Snippet>[];
      for (int index = 0; index < block.length; index += 1) {
        // Each section of the dart code that is either split by a blank line, or with '// ...' is
        // treated as a separate code block.
        if (block[index] == '' || block[index] == '// ...') {
          if (subline == null)
            throw SnippetParserException(
                '${Line('', filename: line.filename, line: line.line + index, indent: line.indent)}: '
                'Unexpected blank line or "// ..." line near start of subblock in sample code.');
          subblocks += 1;
          subsections.add(_processBlock(subline, buffer));
          buffer.clear();
          assert(buffer.isEmpty);
          subline = null;
        } else if (block[index].startsWith('// ')) {
          if (buffer.length > 1) // don't include leading comments
            buffer.add(
                '/${block[index]}'); // so that it doesn't start with "// " and get caught in this again
        } else {
          subline ??= Line(
            block[index],
            filename: line.filename,
            line: line.line + index,
            indent: line.indent,
          );
          buffer.add(block[index]);
        }
      }
      if (subblocks > 0) {
        if (subline != null) {
          subsections.add(_processBlock(subline, buffer));
        }
        // Combine all of the subsections into one section, now that they've been processed.
        return Snippet.combine(subsections);
      } else {
        return Snippet.fromStrings(line, block.toList());
      }
    }
  }
}
