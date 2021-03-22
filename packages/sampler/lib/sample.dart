// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:snippets/snippets.dart';

class Sample {
  Sample({
    required this.id,
    this.description = '',
    this.template = 'freeform',
    required this.codeBlocks,
    this.fs = const LocalFileSystem(),
  });

  String id;
  String description;
  String template;
  Map<String, String> codeBlocks;

  /// Creates a string with the contents of [codeBlocks] interpolated into [template].
  String interpolate(toolBlock) {
    final SnippetGenerator generator = SnippetGenerator(configuration: PackageSnippetConfiguration(
      packageRoot: fs.directory('..').childDirectory('snippets'),
      outputDirectory: fs.currentDirectory,
    ));

    return generator.parseInput(toolBlock);
  }

  FileSystem fs;
}

class SampleModel {
  SampleModel({required this.file, this.fs = const LocalFileSystem()}) {
    parseFile(file);
  }

  FileSystem fs;
  File file;
  List<Sample> snippets = <Sample>[];

  void parseFile(File file) {}
}
