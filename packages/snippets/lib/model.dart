// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;

/// A class to represent a line of input code.
class Line {
  const Line(
    this.text, {
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
  final String text;

  String toStringWithColumn(int column) {
    if (column != null && indent != null) {
      return '$file:$line:${column + indent}: $text';
    }
    return toString();
  }

  Line copyWith({
    String? element,
    String? text,
    File? file,
    int? line,
    int? startChar,
    int? endChar,
    int? indent,
  }) {
    return Line(
      text ?? this.text,
      element: element ?? this.element,
      file: file ?? this.file,
      line: line ?? this.line,
      startChar: startChar ?? this.startChar,
      endChar: endChar ?? this.endChar,
      indent: indent ?? this.indent,
    );
  }

  bool get hasFile => file != null;

  @override
  String toString() => '$file:${line == -1 ? '??' : line}: $text';
}

/// A class containing the name and contents associated with a code block inside if a
/// code sample, for named injection into a template.
class TemplateInjection {
  TemplateInjection(this.name, this.contents, {this.language = ''});
  final String name;
  final List<Line> contents;
  final String language;
  Iterable<String> get stringContents => contents.map<String>((Line line) => line.text);
  String get mergedContent => stringContents.join('\n').trim();
}

/// A base class to represent a block of any kind of sample code, marked by
/// "{@tool (snippet|sample|dartdoc) ...}...{@end-tool}".
abstract class CodeSample {
  CodeSample(
    this.args,
    this.input,
  )   : assert(input.isNotEmpty),
        assert(args.isNotEmpty),
        id = _createNameFromSource(args.first, input.first);

  final List<String> args;
  final String id;
  final List<Line> input;
  String description = '';
  String get element => input.isEmpty ? '' : input.first.element ?? '';
  String output = '';
  Map<String, Object?> metadata = <String, Object?>{};
  List<TemplateInjection> parts = <TemplateInjection>[];
  Line get start => input.first;

  String get template {
    final ArgParser parser = ArgParser();
    parser.addOption('template', defaultsTo: '');
    final ArgResults parsedArgs = parser.parse(args);
    return parsedArgs['template']! as String;
  }

  /// Creates a name for the snippets tool to use for the snippet ID from a
  /// filename and starting line number.
  static String _createNameFromSource(String prefix, Line start) {
    final List<String> components = path.split(start.file?.absolute.path ?? '');
    assert(components.contains('lib'));
    components.removeRange(0, components.lastIndexOf('lib') + 1);
    String sampleId = components.join('.');
    sampleId = path.basenameWithoutExtension(sampleId);
    sampleId = '$prefix.$sampleId.${start.line}';
    return sampleId;
  }

  @override
  String toString() {
    final StringBuffer buf = StringBuffer('${args.join(' ')}:\n');
    for (final Line line in input) {
      buf.writeln(
        '${(line.line == -1 ? '??' : line.line).toString().padLeft(4, ' ')}: ${line.text} ',
      );
    }
    return buf.toString();
  }

  String get type;
}

/// A class to represent a snippet of sample code, marked by "{@tool
/// snippet}...{@end-tool}".
///
/// This is code that is not meant to be run as a complete application, but
/// rather as a code usage example. One [SnippetSample] contains all of the "snippet"
/// blocks for an entire file, since they are evaluated in the analysis tool in
/// a single block.
class SnippetSample extends CodeSample {
  SnippetSample(List<Line> input)
      : super(<String>['snippet'], input);

  factory SnippetSample.combine(List<SnippetSample> sections) {
    final List<Line> code =
    sections.expand((SnippetSample section) => section.input).toList();
    return SnippetSample(code);
  }


  factory SnippetSample.fromStrings(Line firstLine, List<String> code) {
    final List<Line> codeLines = <Line>[];
    int startPos = firstLine.startChar;
    for (int i = 0; i < code.length; ++i) {
      codeLines.add(
        firstLine.copyWith(
          text: code[i],
          line: firstLine.line + i,
          startChar: startPos,
        ),
      );
      startPos += code[i].length + 1;
    }
    return SnippetSample(codeLines);
  }

  factory SnippetSample.surround(String prefix, List<Line> code, String postfix) {
    return SnippetSample(<Line>[
      if (prefix.isNotEmpty) Line(prefix),
      ...code,
      if (postfix.isNotEmpty) Line(postfix),
    ]);
  }

  @override
  String get template => '';

  @override
  Line get start => input.firstWhere((Line line) => line.file != null);

  @override
  String get type => 'snippet';
}

/// A class to represent a plain application sample in the dartdoc comments,
/// marked by `{@tool sample ...}...{@end-tool}`.
///
/// Application samples are processed separately from non-application snippets,
/// because they must be injected into templates in order to be analyzed. Each
/// [ApplicationSample] represents one `{@tool sample ...}...{@end-tool}` block
/// in the source file.
class ApplicationSample extends CodeSample {
  ApplicationSample({
    Line start = const Line(''),
    List<String> input = const <String>[],
    required List<String> args,
  })  : assert(args.isNotEmpty),
        super(args, _convertInput(input, start));

  static List<Line> _convertInput(List<String> input, Line start) {
    int lineNumber = start.line;
    int startChar = start.startChar;
    return input.map<Line>(
      (String line) {
        final Line result = start.copyWith(
          text: line,
          line: lineNumber,
          startChar: startChar,
        );
        lineNumber++;
        startChar += line.length + 1;
        return result;
      },
    ).toList();
  }

  @override
  String get type => 'sample';
}

/// A class to represent a Dartpad application sample in the dartdoc comments,
/// marked by `{@tool dartpad ...}...{@end-tool}`.
///
/// Dartpad samples are processed separately from non-application snippets,
/// because they must be injected into templates in order to be analyzed. Each
/// [DartpadSample] represents one `{@tool dartpad ...}...{@end-tool}` block in
/// the source file.
class DartpadSample extends ApplicationSample {
  DartpadSample({
    Line start = const Line(''),
    List<String> input = const <String>[],
    required List<String> args,
  })  : assert(args.isNotEmpty),
        super(start: start, input: input, args: args);


  @override
  String get type => 'dartpad';
}