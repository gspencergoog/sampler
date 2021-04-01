// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:file/file.dart';
import 'package:pub_semver/pub_semver.dart';

import 'data_types.dart';
import 'interval_tree.dart';

List<List<SourceLine>> getFileComments(File file) {
  final ParseStringResult parseResult = parseFile(
      featureSet: FeatureSet.fromEnableFlags2(
        // TODO(gspencergoog): Get the version string from the flutter --version
        sdkLanguageVersion: Version(2, 12, 1),
        flags: <String>[],
      ),
      path: file.absolute.path);
  final _CommentVisitor<CompilationUnit> visitor = _CommentVisitor<CompilationUnit>(file);
  visitor.visitCompilationUnit(parseResult.unit);
  visitor.assignLineNumbers();
  return visitor.results.values.toList();
}

class _LineNumber<T> extends Comparable<_LineNumber<T>> {
  _LineNumber(this.value, this.line);

  final int value;
  final T line;

  @override
  int compareTo(_LineNumber<T> other) => value.compareTo(other.value);

  @override
  String toString() {
    return '$value <$line>';
  }
}

class _LineNumberInterval extends Interval<_LineNumber<int>> {
  _LineNumberInterval(int start, int end, int line)
      : super(
          _LineNumber<int>(start, line),
          _LineNumber<int>(end, line),
        );
}

class _CommentVisitor<T> extends RecursiveAstVisitor<T> {
  _CommentVisitor(this.file) : results = <String, List<SourceLine>>{};

  final Map<String, List<SourceLine>> results;
  String enclosingClass = '';

  File file;

  void dumpResult() {
    for (final String key in results.keys) {
      print('$key: ${results[key]!.length} lines at line ${results[key]!.first.line}');
    }
  }

  void assignLineNumbers() {
    final String contents = file.readAsStringSync();
    int lineNumber = 0;
    int startRange = 0;
    final IntervalTree<_LineNumber<int>> itree = IntervalTree<_LineNumber<int>>();
    for (int i = 0; i < contents.length; ++i) {
      if (contents[i] == '\n') {
        itree.add(_LineNumberInterval(startRange, i, lineNumber + 1));
        lineNumber++;
        startRange = i + 1;
      }
    }
    for (final String key in results.keys) {
      final List<SourceLine> newLines = <SourceLine>[];
      for (final SourceLine line in results[key]!) {
        final IntervalTree<_LineNumber<int>> resultTree = IntervalTree<_LineNumber<int>>()
          ..add(_LineNumberInterval(line.startChar, line.endChar, -1));
        final IntervalTree<_LineNumber<int>> intersection = itree.intersection(resultTree);
        if (intersection.isNotEmpty) {
          final int intervalLine = intersection.single.start.line == -1
              ? intersection.single.end.line
              : intersection.single.start.line;
          newLines.add(line.copyWith(line: intervalLine));
        } else {
          newLines.add(line);
        }
      }
      results[key] = newLines;
    }
  }

  List<SourceLine> _processComment(String element, Comment comment) {
    final List<SourceLine> result = <SourceLine>[];
    if (comment.tokens.isNotEmpty) {
      for (final Token token in comment.tokens) {
        result.add(SourceLine(
          token.toString(),
          element: element,
          file: file,
          startChar: token.charOffset,
          endChar: token.charEnd,
        ));
      }
    }
    return result;
  }

  @override
  T? visitCompilationUnit(CompilationUnit node) {
    results.clear();
    return super.visitCompilationUnit(node);
  }

  @override
  T? visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    if (node.documentationComment != null && node.documentationComment!.tokens.isNotEmpty) {
      for (final VariableDeclaration declaration in node.variables.variables) {
        if (!declaration.name.name.startsWith('_')) {
          results['global ${declaration.name.name}'] =
              _processComment(declaration.name.name, node.documentationComment!);
        }
      }
    }
    return super.visitTopLevelVariableDeclaration(node);
  }

  @override
  T? visitGenericTypeAlias(GenericTypeAlias node) {
    if (node.documentationComment != null &&
        node.documentationComment!.tokens.isNotEmpty &&
        !node.name.name.startsWith('_')) {
      results['typedef ${node.name.name}'] =
          _processComment(node.name.name, node.documentationComment!);
    }
    return super.visitGenericTypeAlias(node);
  }

  @override
  T? visitFieldDeclaration(FieldDeclaration node) {
    if (node.documentationComment != null && node.documentationComment!.tokens.isNotEmpty) {
      for (final VariableDeclaration declaration in node.fields.variables) {
        if (!declaration.name.name.startsWith('_')) {
          final String element = '${enclosingClass.isNotEmpty ? '$enclosingClass.' : ''}${declaration.name.name}';
          results['field $element'] =
              _processComment(element, node.documentationComment!);
        }
      }
    }
    return super.visitFieldDeclaration(node);
  }

  @override
  T? visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.name != null &&
        node.documentationComment != null &&
        node.documentationComment!.tokens.isNotEmpty &&
        !node.name!.name.startsWith('_')) {
      final String element = '${enclosingClass.isNotEmpty ? '$enclosingClass.' : ''}${node.name!.name}';
      results['constructor $element'] =
          _processComment(element, node.documentationComment!);
    }
    return super.visitConstructorDeclaration(node);
  }

  @override
  T? visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.documentationComment != null &&
        node.documentationComment!.tokens.isNotEmpty &&
        !node.name.name.startsWith('_')) {
      results['function ${node.name.name}'] =
          _processComment(node.name.name, node.documentationComment!);
    }
    return super.visitFunctionDeclaration(node);
  }

  @override
  T? visitMethodDeclaration(MethodDeclaration node) {
    if (node.documentationComment != null &&
        node.documentationComment!.tokens.isNotEmpty &&
        !node.name.name.startsWith('_')) {
      final String element = '${enclosingClass.isNotEmpty ? '$enclosingClass.' : ''}${node.name.name}';
      results['method $element'] =
          _processComment(element, node.documentationComment!);
    }
    return super.visitMethodDeclaration(node);
  }

  @override
  T? visitClassDeclaration(ClassDeclaration node) {
    if (node.documentationComment != null &&
        node.documentationComment!.tokens.isNotEmpty &&
        !node.name.name.startsWith('_')) {
      enclosingClass = node.name.name;
      results['class ${node.name.name}'] =
          _processComment(node.name.name, node.documentationComment!);
    }
    final T? result = super.visitClassDeclaration(node);
    enclosingClass = '';
    return result;
  }
}
