// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:snippets/snippets.dart';

class Model extends ChangeNotifier {
  Model({
    File? workingFile,
    Directory? flutterRoot,
    this.filesystem = const LocalFileSystem(),
  })  : _workingFile = workingFile,
        flutterRoot = flutterRoot ?? _findFlutterRoot(filesystem),
        _dartdocParser = SnippetDartdocParser(),
        _snippetGenerator = SnippetGenerator();

  static Model? _instance;

  static Model get instance {
    _instance ??= Model();
    return _instance!;
  }

  static set instance(Model value) {
    _instance?.dispose();
    _instance = value;
  }

  final FileSystem filesystem;

  static Directory _findFlutterRoot(FileSystem filesystem) {
    return getFlutterRoot(filesystem: filesystem);
  }

  Future<void> listFiles(Directory directory, {String suffix = '.dart'}) async {
    final List<File> foundDartFiles = <File>[];
    await for (FileSystemEntity entity in directory.list(recursive: true)) {
      if (entity is Directory || !entity.basename.endsWith(suffix)) {
        continue;
      }
      if (entity is Link) {
        final String resolvedPath = entity.resolveSymbolicLinksSync();
        if (!(await filesystem.isFile(resolvedPath))) {
          continue;
        }
        entity = filesystem.file(resolvedPath);
      }
      final File relativePath =
          filesystem.file(path.relative(entity.absolute.path, from: directory.absolute.path));
      if (path.split(relativePath.path).contains('test')) {
        continue;
      }
      foundDartFiles.add(relativePath);
    }
    files = foundDartFiles;
  }

  File? _workingFile;

  File? get workingFile => _workingFile;

  Future<void> setWorkingFile(File? value) async {
    if (_workingFile == value) {
      return;
    }
    _workingFile = value;
    if (_workingFile == null) {
      _samples = null;
      return;
    }
    _samples = _dartdocParser
        .parse(filesystem.file(path.join(flutterPackageRoot.absolute.path, _workingFile!.path)));
    for (final CodeSample sample in samples!) {
      _snippetGenerator.generateCode(sample, addSectionMarkers: true);
    }
    print('Loaded ${samples!.length} samples from ${_workingFile!.path}');
    notifyListeners();
  }

  CodeSample? _workingSample;

  CodeSample? get workingSample => _workingSample;

  set workingSample(CodeSample? workingSample) {
    _workingSample = workingSample;
    notifyListeners();
  }

  List<CodeSample>? _samples;

  List<CodeSample>? get samples => _samples;

  Directory flutterRoot;
  Directory get flutterPackageRoot =>
      flutterRoot.childDirectory('packages').childDirectory('flutter');
  List<File>? files;

  final SnippetDartdocParser _dartdocParser;
  final SnippetGenerator _snippetGenerator;
}
