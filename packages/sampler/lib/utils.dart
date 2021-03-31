// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:platform/platform.dart';
import 'package:process/process.dart';
import 'package:process_runner/process_runner.dart';

void openFileBrowser(FileSystemEntity location,
    {Platform platform = const LocalPlatform(),
    ProcessManager processManager = const LocalProcessManager()}) {
  switch (platform.operatingSystem) {
    case 'linux':
      // Tries to open the system file manager using DBus and select the file.
      // Some file managers don't support selecting the file, but it will at
      // least open the directory that the file exists in.
      final ProcessRunner runner = ProcessRunner(processManager: processManager);
      runner.runProcess(<String>[
        'dbus-send',
        '--session',
        '--print-reply',
        '--dest=org.freedesktop.FileManager1',
        '/org/freedesktop/FileManager1',
        'org.freedesktop.FileManager1.ShowItems',
        'array:string:${location.absolute.path}',
        'string:""',
      ]).then((ProcessRunnerResult result) {
        if (result.exitCode != 0) {
          print('Failed to open file ${location.absolute.path}: ${result.output}');
        }
      });
      break;
    case 'macOS':
      processManager.run(<String>['open', '-R', location.absolute.path], runInShell: true);
      break;
    case 'windows':
      processManager.run(<String>['start', '/select', location.absolute.path], runInShell: true);
      break;
    default:
      throw Exception('Opening files on platform ${platform.operatingSystem} is not supported.');
  }
}

enum IdeType {
  idea,
  vscode,
}

String getIdeName(IdeType type) {
  switch (type) {
    case IdeType.idea:
      return 'IntelliJ';
    case IdeType.vscode:
      return 'VS Code';
  }
}

void openInIde(IdeType type, FileSystemEntity location,
    {ProcessManager processManager = const LocalProcessManager(), int startLine = 0}) {
  switch (type) {
    case IdeType.idea:
      processManager.run(<String>[
        'idea',
        if (startLine != 0) '${location.absolute.path}:$startLine',
        if (startLine == 0) location.absolute.path,
      ], runInShell: true);
      break;
    case IdeType.vscode:
      processManager.run(<String>[
        'code',
        '--goto',
        '${location.absolute.path}:$startLine',
      ], runInShell: true);
      break;
  }
}