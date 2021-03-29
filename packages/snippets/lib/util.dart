// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'package:process/process.dart' show ProcessManager, LocalProcessManager;

class SnippetException implements Exception {
  SnippetException(this.message, {this.file, this.line});
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

Directory getFlutterRoot() {
  const ProcessManager manager = LocalProcessManager();
  late ProcessResult result;
  try {
    result = manager.runSync(<String>['flutter', '--version', '--machine'],
        stdoutEncoding: utf8);
  } on ProcessException catch (e) {
    throw SnippetException(
        'Unable to determine Flutter root. Either set FLUTTER_ROOT, or place flutter command in your path.\n$e');
  }
  if (result.exitCode != 0) {
    throw SnippetException(
        'Unable to determine Flutter root, because of abnormal exit to flutter command.');
  }
  final Map<String, dynamic> map =
  json.decode(result.stdout as String) as Map<String, dynamic>;
  if (map['flutterRoot'] == null) {
    throw SnippetException(
        'Flutter command output format has changed, unable to determine flutter root location.');
  }
  return Directory(map['flutterRoot']! as String);
}


void errorExit(String message) {
  stderr.writeln(message);
  exit(1);
}

