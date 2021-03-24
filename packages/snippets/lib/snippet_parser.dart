// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'analysis.dart';
import 'model.dart';
import 'util.dart';

/// Parses [CodeSample]s from the source file given to [parse], or from
class SnippetDartdocParser {
  SnippetDartdocParser();

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
  static final RegExp _constructorRegExp = RegExp(r'(const\s+)?_*[A-Z][a-zA-Z0-9<>._]*\(');

  // /// A RegExp that matches a dart version specification in an example preamble.
  // static final RegExp _dartVersionOverrideRegExp =
  //     RegExp(r'\/\/ (?<override>\/\/ @dart = (?<version>[0-9]+\.[0-9]+))');

  /// A serial number so that we can create unique expression names when we
  /// generate them.
  int _expressionId = 0;

  /// Extracts the samples from the Dart files in [files], writes them
  /// to disk, and adds them to the appropriate [sectionMap] or [sampleMap].
  List<CodeSample> parse(
    File file, {
    bool silent = false,
  }) {
    return parseFromComments(getFileComments(file), silent: silent, preamble: parsePreamble(file));
  }

  List<CodeSample> parseFromDartdocToolFile(
    File input, {
    int? startLine,
    String? element,
    required File sourceFile,
    required SampleType type,
    String template = '',
  }) {
    final List<Line> lines = <Line>[];
    int lineNumber = startLine ?? 0;
    final List<String> inputStrings = <String>[
      // The parser wants to read the arguments from the input, so we create a new
      // tool line to match the given arguments, so that we can use the same parser for
      // editing and docs generation.
      if (type != SampleType.bare) '/// {@tool ${getEnumName(type)}${template.isNotEmpty ? ' --template=$template}' : ''}}',
      // Snippet input comes in with the comment markers stripped, so we add them
      // back to make it conform to the source format, so we can use the same
      // parser for editing samples as we do for processing docs.
      ...input.readAsLinesSync().map<String>((String line) => '/// $line'),
      if (type != SampleType.bare) '/// {@end-tool}',
    ];
    for (final String line in inputStrings) {
      lines.add(
        Line(line, element: element ?? '', line: lineNumber, file: sourceFile),
      );
      lineNumber++;
    }
    final List<CodeSample> samples = parseFromComments(<List<Line>>[lines]);
    for (final CodeSample sample in samples) {
      sample.metadata.addAll(<String, Object?>{
        'id': sample.id,
        'element': sample.start.element,
        'sourcePath': sourceFile.path,
        'sourceLine': sample.start.line,
      });
    }
    return samples;
  }

  List<Line> parsePreamble(File file) {
    // Whether or not we're in the file-wide preamble section ("Examples can assume").
    bool inPreamble = false;
    final List<Line> preamble = <Line>[];
    int lineNumber = 0;
    int charPosition = 0;
    for (final String line in file.readAsLinesSync()) {
      if (inPreamble && line.trim().isEmpty) {
        // Reached the end of the preamble.
        break;
      }
      if (!line.startsWith('// ')) {
        lineNumber++;
        charPosition += line.length + 1;
        continue;
      }
      if (line == '// Examples can assume:') {
        inPreamble = true;
        lineNumber++;
        charPosition += line.length + 1;
        continue;
      }
      if (inPreamble) {
        preamble.add(Line(
          line.substring(3),
          startChar: charPosition,
          endChar: charPosition + line.length + 1,
          element: '#preamble',
          line: lineNumber,
        ));
      }
      lineNumber++;
      charPosition += line.length + 1;
    }
    return preamble;
  }

  List<CodeSample> parseFromComments(
    List<List<Line>> comments, {
    bool silent = false,
    List<Line> preamble = const <Line>[],
  }) {
    int dartpadCount = 0;
    int sampleCount = 0;
    int snippetCount = 0;
    int bareCount = 0;

    final List<CodeSample> samples = <CodeSample>[];
    for (final List<Line> commentLines in comments) {
      final List<CodeSample> newSamples = parseComment(commentLines);
      for (final CodeSample sample in newSamples) {
        switch (sample.type) {
          case SampleType.bare:
            bareCount++;
            break;
          case SampleType.sample:
            sampleCount++;
            break;
          case SampleType.dartpad:
            dartpadCount++;
            break;
          case SampleType.snippet:
            snippetCount++;
            break;
        }
        samples.addAll(newSamples);
      }
    }
    if (!silent) {
      print('Found:\n  $bareCount bare Dart blocks,\n'
          '  $snippetCount snippet code blocks,\n'
          '  $sampleCount non-dartpad sample code sections, and\n'
          '  $dartpadCount dartpad sections.');
    }
    return samples;
  }

  List<CodeSample> parseComment(List<Line> comments) {
    // Whether or not we're in a snippet code sample (with template) specifically.
    bool inSnippet = false;
    // Whether or not we're in a '```dart' segment.
    bool inDart = false;
    final List<String> block = <String>[];
    List<String> snippetArgs = <String>[];
    Line startLine = const Line('');
    final List<CodeSample> samples = <CodeSample>[];

    for (final Line line in comments) {
      final String trimmedLine = line.code.trim();
      if (inSnippet) {
        if (!trimmedLine.startsWith(_dartDocPrefix)) {
          throw SnippetException('Snippet section unterminated.',
              file: line.file?.path, line: line.line);
        }
        if (_dartDocSampleEndRegex.hasMatch(trimmedLine)) {
          late SampleType snippetType;
          switch (snippetArgs.first) {
            case 'snippet':
              snippetType = SampleType.snippet;
              samples.add(
                Snippet.fromStrings(startLine, block),
              );
              break;
            case 'sample':
              snippetType = SampleType.sample;
              samples.add(
                ApplicationSample(
                  start: startLine,
                  input: block,
                  args: snippetArgs,
                  type: snippetType,
                ),
              );
              break;
            case 'dartpad':
              snippetType = SampleType.dartpad;
              samples.add(
                ApplicationSample(
                  start: startLine,
                  input: block,
                  args: snippetArgs,
                  type: snippetType,
                ),
              );
              break;
            default:
              throw SnippetException('Unknown snippet type ${snippetArgs.first}');
          }
          snippetArgs = <String>[];
          block.clear();
          inSnippet = false;
        } else {
          block.add(line.code.replaceFirst(RegExp(r'\s*/// ?'), ''));
        }
      } else {
        if (_dartDocSampleEndRegex.hasMatch(trimmedLine)) {
          if (inDart) {
            throw SnippetException("Dart section didn't terminate before end of sample",
                file: line.file?.path, line: line.line);
          }
        }
        if (inDart) {
          if (_codeBlockEndRegex.hasMatch(trimmedLine)) {
            inDart = false;
            samples.add(_processBlock(startLine, block));
            block.clear();
          } else if (trimmedLine == _dartDocPrefix) {
            block.add('');
          } else {
            final int index = line.code.indexOf(_dartDocPrefixWithSpace);
            if (index < 0) {
              throw SnippetException(
                'Dart section inexplicably did not contain "$_dartDocPrefixWithSpace" prefix.',
                file: line.file?.path,
                line: line.line,
              );
            }
            block.add(line.code.substring(index + 4));
          }
        } else if (_codeBlockStartRegex.hasMatch(trimmedLine)) {
          assert(block.isEmpty);
          startLine = line.copyWith(
              indent: line.code.indexOf(_dartDocPrefixWithSpace) + _dartDocPrefixWithSpace.length);
          inDart = true;
        }
      }
      if (!inSnippet && !inDart) {
        final RegExpMatch? sampleMatch = _dartDocSampleBeginRegex.firstMatch(trimmedLine);
        if (sampleMatch != null) {
          inSnippet = sampleMatch != null &&
              (sampleMatch.namedGroup('type') == 'snippet' ||
               sampleMatch.namedGroup('type') == 'sample' ||
               sampleMatch.namedGroup('type') == 'dartpad');
          if (inSnippet) {
            startLine = line.copyWith(
              indent: line.code.indexOf(_dartDocPrefixWithSpace) + _dartDocPrefixWithSpace.length,
            );
            if (sampleMatch.namedGroup('args') != null) {
              // There are arguments to the snippet tool to keep track of.
              snippetArgs = <String>[
                sampleMatch.namedGroup('type')!,
                ..._splitUpQuotedArgs(sampleMatch.namedGroup('args')!).toList()
              ];
            } else {
              snippetArgs = <String>[
                sampleMatch.namedGroup('type')!,
              ];
            }
          }
        }
      }
    }
    return samples;
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
    // This function is used because the arg parser package doesn't handle
    // quoted args.

    // Regexp to take care of splitting arguments, and handling the quotes
    // around arguments, if any.
    //
    // Match group 1 (option) is the "foo=" (or "--foo=") part of the option, if any.
    // Match group 2 (quote) contains the quote character used (which is discarded).
    // Match group 3 (value) is a quoted arg, if any, without the quotes.
    // Match group 4 (unquoted) is the unquoted arg, if any.
    final RegExp argMatcher = RegExp(r'(?<option>[a-zA-Z\-_0-9]+=)?' // option name
        r'(?:' // Start a new non-capture group for the two possibilities.
        r'''(?<quote>["'])(?<value>(?:\\{2})*|(?:.*?[^\\](?:\\{2})*))\2|''' // with quotes.
        r'(?<unquoted>[^ ]+))'); // without quotes.
    final Iterable<RegExpMatch> matches = argMatcher.allMatches(argsAsString);

    // Remove quotes around args, and if convertToArgs is true, then for any
    // args that look like assignments (start with valid option names followed
    // by an equals sign), add a "--" in front so that they parse as options.
    return matches.map<String>((RegExpMatch match) {
      String option = '';
      if (match.namedGroup('option') != null && !match.namedGroup('option')!.startsWith('-')) {
        option = '--';
      }
      if (match.namedGroup('quote') != null) {
        // This arg has quotes, so strip them.
        return '$option${match.namedGroup('quote') ?? ''}'
            '${match.namedGroup('value') ?? ''}'
            '${match.namedGroup('unquoted') ?? ''}';
      }
      return '$option${match[0]}';
    });
  }

  /// Process one block of sample code (the part inside of "```" markers).
  /// Splits any sections denoted by "// ..." into separate blocks to be
  /// processed separately. Uses a primitive heuristic to make sample blocks
  /// into valid Dart code.
  BareDartSample _processBlock(Line line, List<String> block) {
    if (block.isEmpty) {
      throw SnippetException('$line: Empty ```dart block in sample code.');
    }
    if (block.first.startsWith('new ') || block.first.startsWith(_constructorRegExp)) {
      _expressionId += 1;
      return BareDartSample.surround(line, 'dynamic expression$_expressionId = ', block.toList(), ';');
    } else if (block.first.startsWith('await ')) {
      _expressionId += 1;
      return BareDartSample.surround(
          line, 'Future<void> expression$_expressionId() async { ', block.toList(), ' }');
    } else if (block.first.startsWith('class ') || block.first.startsWith('enum ')) {
      return BareDartSample.fromStrings(line, block.toList());
    } else if ((block.first.startsWith('_') || block.first.startsWith('final ')) &&
        block.first.contains(' = ')) {
      _expressionId += 1;
      return BareDartSample.surround(line, 'void expression$_expressionId() { ', block.toList(), ' }');
    } else {
      final List<String> buffer = <String>[];
      int blocks = 0;
      Line? subLine;
      final List<BareDartSample> subsections = <BareDartSample>[];
      int startPos = line.startChar;
      for (int index = 0; index < block.length; index += 1) {
        // Each section of the dart code that is either split by a blank line, or with
        // '// ...' is treated as a separate code block.
        if (block[index] == '' || block[index] == '// ...') {
          if (subLine == null)
            throw SnippetException(
                '${Line('', file: line.file, line: line.line + index, indent: line.indent)}: '
                'Unexpected blank line or "// ..." line near start of block in sample code.');
          blocks += 1;
          subsections.add(_processBlock(subLine, buffer));
          buffer.clear();
          assert(buffer.isEmpty);
          subLine = null;
        } else if (block[index].startsWith('// ')) {
          if (buffer.length > 1) // don't include leading comments
            buffer.add(
                '/${block[index]}'); // so that it doesn't start with "// " and get caught in this again
        } else {
          subLine ??= line.copyWith(
            code: block[index],
            line: line.line + index,
            startChar: startPos,
          );
          buffer.add(block[index]);
          startPos += block[index].length + 1;
        }
      }
      if (blocks > 0) {
        if (subLine != null) {
          subsections.add(_processBlock(subLine, buffer));
        }
        // Combine all of the subsections into one section, now that they've been processed.
        return BareDartSample.combine(subsections);
      } else {
        return BareDartSample.fromStrings(line, block.toList());
      }
    }
  }
}
