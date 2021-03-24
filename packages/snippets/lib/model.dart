// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:snippets/util.dart';

/// A class to represent a line of input code.
class Line {
  const Line(
    this.code, {
    this.file,
    this.element,
    this.line = -1,
    this.startChar = -1,
    this.endChar = -1,
    this.indent = 0,
  });
  final File? file;
  final String? element;
  final int line;
  final int startChar;
  final int endChar;
  final int indent;
  final String code;

  String toStringWithColumn(int column) {
    if (column != null && indent != null) {
      return '$file:$line:${column + indent}: $code';
    }
    return toString();
  }

  Line copyWith({
    String? element,
    String? code,
    File? file,
    int? line,
    int? startChar,
    int? endChar,
    int? indent,
  }) {
    return Line(
      code ?? this.code,
      element: element ?? this.element,
      file: file ?? this.file,
      line: line ?? this.line,
      startChar: startChar ?? this.startChar,
      endChar: endChar ?? this.endChar,
      indent: indent ?? this.indent,
    );
  }

  @override
  String toString() => '$file:${line == -1 ? '??' : line}: $code';
}

/// A class containing the name and contents associated with a code block inside if a
/// code sample, for named injection into a template.
class TemplateInjection {
  TemplateInjection(this.name, this.contents, {this.language = ''});
  final String name;
  final List<String> contents;
  final String language;
  String get mergedContent => contents.join('\n').trim();
}

/// A base class to represent a block of any kind of sample code, marked by
/// "{@tool (snippet|sample|dartdoc) ...}...{@end-tool}".
abstract class CodeSample {
  CodeSample(
    this.type,
    this.args,
    this.input,
  )   : assert(input.isNotEmpty),
        assert(args.isNotEmpty),
        id = _createNameFromSource(args.first, input.first);

  final SampleType type;
  final List<String> args;
  final String id;
  final List<Line> input;
  String description = '';
  String element = '';
  String output = '';
  List<TemplateInjection> parts = <TemplateInjection>[];
  Line get start => input.first;

  String get template {
    if (type != SampleType.sample && type != SampleType.dartpad) {
      return '';
    }
    final ArgParser parser = ArgParser();
    parser.addOption('template', defaultsTo: '');
    final ArgResults parsedArgs = parser.parse(args);
    return parsedArgs['template']! as String;
  }

  /// Creates a name for the snippets tool to use for the snippet ID from a
  /// filename and starting line number.
  static String _createNameFromSource(String prefix, Line start) {
    String sampleId = path.split(start.file?.path ?? '').join('.');
    sampleId = path.basenameWithoutExtension(sampleId);
    sampleId = '$prefix.$sampleId.${start.line}';
    return sampleId;
  }

  @override
  String toString() {
    final StringBuffer buf = StringBuffer('${args.join(' ')}:\n');
    for (final Line line in input) {
      buf.writeln(
        ' [${line.startChar == -1 ? '??' : line.startChar}] '
        '${(line.line == -1 ? '??' : line.line).toString().padLeft(4, ' ')}: ${line.code} '
        ' -- ${line.element}',
      );
    }
    return buf.toString();
  }
}

/// A class to represent a snippet of sample code, marked by "{@tool
/// snippet}...{@end-tool}".
///
/// This is code that is not meant to be run as a complete application, but
/// rather as a code usage example. One [Snippet] contains all of the "snippet"
/// blocks for an entire file, since they are evaluated in the analysis tool in
/// a single block.
class Snippet extends CodeSample {
  Snippet(List<Line> input)
      : super(SampleType.snippet, <String>['snippet'], input);

  factory Snippet.combine(List<Snippet> sections) {
    final List<Line> code =
        sections.expand((Snippet section) => section.input).toList();
    return Snippet(code);
  }

  factory Snippet.fromStrings(Line firstLine, List<String> code) {
    final List<Line> codeLines = <Line>[];
    int startPos = firstLine.startChar;
    for (int i = 0; i < code.length; ++i) {
      codeLines.add(
        firstLine.copyWith(
          code: code[i],
          line: firstLine.line + i,
          startChar: startPos,
        ),
      );
      startPos += code[i].length + 1;
    }
    return Snippet(codeLines);
  }

  factory Snippet.surround(
      Line firstLine, String prefix, List<String> code, String postfix) {
    assert(prefix != null);
    assert(postfix != null);
    final List<Line> codeLines = <Line>[];
    int startPos = firstLine.startChar;
    for (int i = 0; i < code.length; ++i) {
      codeLines.add(
        firstLine.copyWith(
          code: code[i],
          line: firstLine.line + i,
          startChar: startPos,
        ),
      );
      startPos += code[i].length + 1;
    }
    return Snippet(<Line>[
      Line(prefix),
      ...codeLines,
      Line(postfix),
    ]);
  }

  @override
  Line get start => input.firstWhere((Line line) => line.file != null);
}

/// A class to represent an application sample in the dartdoc comments, marked
/// by `{@tool (sample|dartdoc) ...}...{@end-tool}`.
///
/// Application samples are processed separately from non-application snippets,
/// because they must be injected into templates in order to be analyzed. Each
/// [ApplicationSample] represents one `{@tool (sample|dartdoc)
/// ...}...{@end-tool}` block in the source file.
class ApplicationSample extends CodeSample {
  ApplicationSample({
    Line start = const Line(''),
    List<String> input = const <String>[],
    List<String> args = const <String>[],
    SampleType type = SampleType.sample,
  })  : assert(args.isNotEmpty),
        super(type, args, _convertInput(input, start));

  static List<Line> _convertInput(List<String> input, Line start) {
    int lineNumber = start.line;
    int startChar = start.startChar;
    return input.map<Line>(
      (String line) {
        final Line result = start.copyWith(
          code: line,
          line: lineNumber,
          startChar: startChar,
        );
        lineNumber++;
        startChar += line.length + 1;
        return result;
      },
    ).toList();
  }
}
