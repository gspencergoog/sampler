// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:pub_semver/pub_semver.dart';
import 'model.dart';

String getNextSymbolForLine(Line line) {
  final ParseStringResult result = parseFile(
      featureSet: FeatureSet.fromEnableFlags2(
        sdkLanguageVersion: Version(2, 12, 1),
        flags: <String>[],
      ),
      path: line.file!.absolute.path);
  final _SourceVisitor<CompilationUnit> visitor =
      _SourceVisitor<CompilationUnit>(line);
  visitor.visitCompilationUnit(result.unit);
  return visitor.name;
}

class _SourceVisitor<T> extends RecursiveAstVisitor<T> {
  _SourceVisitor(this.line);

  String name = '';
  Line line;

  @override
  T? visitClassDeclaration(ClassDeclaration node) {
    final List<Token> tokens = node.documentationComment?.tokens ?? <Token>[];
    if (tokens.isNotEmpty) {
      if (tokens.first.charOffset < line.startChar &&
          tokens.last.charEnd > line.startChar) {
        print('Class for $line is ${node.name.name}');
        name = node.name.name;
      }
    }
    //  final String commentText = tokens.map<String>((Token token) => token.toString()).join('\n');
//    print('Class Declaration ${node.name.name}:\n$commentText');
    return super.visitClassDeclaration(node);
  }
}

Map<String, List<Line>> getFileComments(File file) {
  final ParseStringResult parseResult = parseFile(
      featureSet: FeatureSet.fromEnableFlags2(
        // TODO(gspencergoog): Get the version string from the flutter --version
        sdkLanguageVersion: Version(2, 12, 1),
        flags: <String>[],
      ),
      path: file.absolute.path);
  final _CommentVisitor<CompilationUnit> visitor =
      _CommentVisitor<CompilationUnit>(file);
  visitor.visitCompilationUnit(parseResult.unit);
  visitor.assignLineNumbers();
  visitor.dumpResult();
  return visitor.results;
}

class _CommentVisitor<T> extends RecursiveAstVisitor<T> {
  _CommentVisitor(this.file) : results = <String, List<Line>>{};

  Map<String, List<Line>> results;

  File file;

  void dumpResult() {
    for (final String key in results.keys) {
      print(
          '$key: ${results[key]!.length} lines at line ${results[key]!.first.line}');
    }
  }

  void assignLineNumbers() {
    final String contents = file.readAsStringSync();
    int lineNumber = 0;
    int startRange = 0;
    final List<Line> lineRanges = <Line>[];
    for (int i = 0; i < contents.length; ++i) {
      if (contents[i] == '\n') {
        lineRanges.add(
            Line('', line: lineNumber, startChar: startRange, endChar: i + 1));
        lineNumber++;
        startRange = i + 1;
      }
    }
    for (final String key in results.keys) {
      final List<Line> newLines = <Line>[];
      for (final Line line in results[key]!) {
        bool found = false;
        for (final Line lineRange in lineRanges) {
          if (line.startChar >= lineRange.startChar &&
              line.endChar < lineRange.endChar) {
            newLines.add(line.copyWith(line: lineRange.line));
            found = true;
            break;
          }
        }
        if (!found) {
          newLines.add(line);
        }
      }
      results[key] = newLines;
    }
  }

  List<Line> _processComment(Comment comment) {
    final List<Line> result = <Line>[];
    if (comment.tokens.isNotEmpty) {
      for (final Token token in comment.tokens) {
        result.add(Line(
          token.toString(),
          file: file,
          startChar: token.charOffset,
          endChar: token.charEnd,
        ));
      }
    }
    return result;
  }

  @override
  T? visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    if (node.documentationComment != null &&
        node.documentationComment!.tokens.isNotEmpty) {
      for (final VariableDeclaration declaration in node.variables.variables) {
        if (!declaration.name.name.startsWith('_')) {
          results['global ${declaration.name.name}'] =
              _processComment(node.documentationComment!);
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
          _processComment(node.documentationComment!);
    }
    return super.visitGenericTypeAlias(node);
  }

  @override
  T? visitFieldDeclaration(FieldDeclaration node) {
    if (node.documentationComment != null &&
        node.documentationComment!.tokens.isNotEmpty) {
      for (final VariableDeclaration declaration in node.fields.variables) {
        if (!declaration.name.name.startsWith('_')) {
          results['field ${declaration.name.name}'] =
              _processComment(node.documentationComment!);
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
      results['constructor ${node.name!.name}'] =
          _processComment(node.documentationComment!);
    }
    return super.visitConstructorDeclaration(node);
  }

  @override
  T? visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.documentationComment != null &&
        node.documentationComment!.tokens.isNotEmpty &&
        !node.name.name.startsWith('_')) {
      results['function ${node.name.name}'] =
          _processComment(node.documentationComment!);
    }
    return super.visitFunctionDeclaration(node);
  }

  @override
  T? visitMethodDeclaration(MethodDeclaration node) {
    if (node.documentationComment != null &&
        node.documentationComment!.tokens.isNotEmpty &&
        !node.name.name.startsWith('_')) {
      results['method ${node.name.name}'] =
          _processComment(node.documentationComment!);
    }
    return super.visitMethodDeclaration(node);
  }

  @override
  T? visitClassDeclaration(ClassDeclaration node) {
    if (node.documentationComment != null &&
        node.documentationComment!.tokens.isNotEmpty &&
        !node.name.name.startsWith('_')) {
      results['class ${node.name.name}'] =
          _processComment(node.documentationComment!);
    }
    return super.visitClassDeclaration(node);
  }
}
