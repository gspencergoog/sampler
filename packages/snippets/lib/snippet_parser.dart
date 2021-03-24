// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'analysis.dart';
import 'model.dart';
import 'util.dart';

/// Parses [CodeSample]s from the source file given to [parse].
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
  static final RegExp _constructorRegExp =
      RegExp(r'(const\s+)?_*[A-Z][a-zA-Z0-9<>._]*\(');
  //
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

  List<Line> parsePreamble(File file) {
    bool inPreamble = false;
    final List<Line> preamble = <Line>[];
    int lineNumber = 0;
    int charPosition = 0;
    for (final String line in file.readAsLinesSync()) {
      if (inPreamble && line.trim().isEmpty) {
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
          element: '#preamble',
          line: lineNumber,
          endChar: charPosition + line.length + 1,
        ));
      }
      lineNumber++;
      charPosition += line.length + 1;
    }
    print('found Preamble:\n${preamble.map<String>((Line line) => line.code).join('\n')}');
    return preamble;
  }

  List<CodeSample> parseFromComments(
    Map<String, List<Line>> comments, {
    bool silent = false,
    List<Line> preamble = const <Line>[],
  }) {
    int dartpadCount = 0;
    int sampleCount = 0;
    int snippetCount = 0;

    final List<CodeSample> samples = <CodeSample>[];
    for (final String commentKey in comments.keys) {
      final List<CodeSample> newSamples = parseComment(comments[commentKey]!);
      for (final CodeSample sample in newSamples) {
        switch (sample.type) {
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
      print('Found $snippetCount snippet code blocks, $sampleCount '
          'sample code sections, and $dartpadCount dartpad sections.');
    }
    return samples;
  }

  List<CodeSample> parseComment(List<Line> comments) {
    // Whether or not we're in the file-wide preamble section ("Examples can assume").
    bool inPreamble = false;
    // Whether or not we're in a code sample
    bool inSampleSection = false;
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
            case 'sample':
              snippetType = SampleType.sample;
              break;
            case 'dartpad':
              snippetType = SampleType.dartpad;
              break;
            default:
              throw SnippetException(
                  'Unknown snippet type ${snippetArgs.first}');
          }
          samples.add(
            ApplicationSample(
              start: startLine,
              input: block,
              args: snippetArgs,
              type: snippetType,
            ),
          );
          snippetArgs = <String>[];
          block.clear();
          inSnippet = false;
          inSampleSection = false;
        } else {
          block.add(line.code.replaceFirst(RegExp(r'\s*/// ?'), ''));
        }
      } else if (inPreamble) {
        if (line.code.isEmpty) {
          inPreamble = false;
          block.clear();
        } else if (!line.code.startsWith('// ')) {
          throw SnippetException('Unexpected content in sample code preamble.',
              file: line.file?.path, line: line.line);
        } else {
          block.add(line.code.substring(3));
        }
      } else if (inSampleSection) {
        if (_dartDocSampleEndRegex.hasMatch(trimmedLine)) {
          if (inDart) {
            throw SnippetException(
                "Dart section didn't terminate before end of sample",
                file: line.file?.path,
                line: line.line);
          }
          inSampleSection = false;
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
              indent: line.code.indexOf(_dartDocPrefixWithSpace) +
                  _dartDocPrefixWithSpace.length);
          inDart = true;
        }
      }
      if (!inSampleSection) {
        final RegExpMatch? sampleMatch =
            _dartDocSampleBeginRegex.firstMatch(trimmedLine);
        if (line.code == '// Examples can assume:') {
          assert(block.isEmpty);
          startLine = line.copyWith(indent: 3);
          inPreamble = true;
        } else if (sampleMatch != null) {
          inSnippet = sampleMatch != null &&
              (sampleMatch.namedGroup('type') == 'sample' ||
                  sampleMatch.namedGroup('type') == 'dartpad');
          if (inSnippet) {
            startLine = line.copyWith(
              indent: line.code.indexOf(_dartDocPrefixWithSpace) +
                  _dartDocPrefixWithSpace.length,
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
          inSampleSection = !inSnippet;
        } else if (RegExp(r'///\s*#+\s+[Ss]ample\s+[Cc]ode:?$')
            .hasMatch(trimmedLine)) {
          throw SnippetException(
            "Found deprecated '## Sample code' section: use {@tool snippet}...{@end-tool} instead.",
            file: line.file?.path,
            line: line.line,
          );
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

  /// Process one block of sample code (the part inside of "```" markers).
  /// Splits any sections denoted by "// ..." into separate blocks to be
  /// processed separately. Uses a primitive heuristic to make sample blocks
  /// into valid Dart code.
  Snippet _processBlock(Line line, List<String> block) {
    if (block.isEmpty) {
      throw SnippetException('$line: Empty ```dart block in sample code.');
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
      int blocks = 0;
      Line? subLine;
      final List<Snippet> subsections = <Snippet>[];
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
        return Snippet.combine(subsections);
      } else {
        return Snippet.fromStrings(line, block.toList());
      }
    }
  }
}
