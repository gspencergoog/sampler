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

  void clearWorkingFile() {
    if (_workingFile == null) {
      return;
    }
    _workingFile = null;
    _currentSample = null;
    _currentElement = null;
    notifyListeners();
  }

  Future<void> setWorkingFile(File value) async {
    if (_workingFile == value) {
      return;
    }
    _workingFile = value;

    // Clear existing selections if the file has changed.
    _currentSample = null;
    _currentElement = null;

    if (_workingFile == null) {
      return;
    }
 
    final File file = filesystem.file(path.join(flutterPackageRoot.absolute.path, _workingFile!.path));
    _elements = getFileElements(file);
    _dartdocParser.parseFromComments(_elements!);
    _dartdocParser.parseAndAddAssumptions(_elements!, file, silent: true);
    for (final CodeSample sample in samples) {
      _snippetGenerator.generateCode(sample, addSectionMarkers: true, includeAssumptions: true);
    }
    print('Loaded ${samples.length} samples from ${_workingFile!.path}');
    notifyListeners();
  }

  CodeSample? _currentSample;

  CodeSample? get currentSample => _currentSample;

  set currentSample(CodeSample? value) {
    if (value != _currentSample) {
      _currentSample = value;
      notifyListeners();
    }
  }

  SourceElement? _currentElement;

  SourceElement? get currentElement => _currentElement;

  set currentElement(SourceElement? value) {
    if (value != _currentElement) {
      _currentElement = value;
      notifyListeners();
    }
  }

  Iterable<CodeSample> get samples {
    return _elements?.expand<CodeSample>((SourceElement element) => element.samples) ?? const <CodeSample>[];
  } 

  Iterable<SourceElement>? _elements;

  Iterable<SourceElement>? get elements => _elements;

  Directory flutterRoot;
  Directory get flutterPackageRoot =>
      flutterRoot.childDirectory('packages').childDirectory('flutter');
  List<File>? files;

  final SnippetDartdocParser _dartdocParser;
  final SnippetGenerator _snippetGenerator;
}
