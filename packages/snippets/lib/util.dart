// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:process/process.dart' show ProcessManager, LocalProcessManager;
import 'package:platform/platform.dart' show LocalPlatform, Platform;
import 'package:pub_semver/pub_semver.dart';

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
      return '$runtimeType: $fileStr$lineStr: $message';
    } else {
      return '$runtimeType: $message';
    }
  }
}

Directory getFlutterRoot(
    {Platform? platform,
    ProcessManager? processManager,
    FileSystem filesystem = const LocalFileSystem()}) {
  return getFlutterInformation(
      platform: platform,
      processManager: processManager,
      filesystem: filesystem)['flutterRoot'] as Directory;
}

Version getFlutterVersion(
    {Platform? platform,
    ProcessManager? processManager,
    FileSystem filesystem = const LocalFileSystem()}) {
  return getFlutterInformation(
      platform: platform,
      processManager: processManager,
      filesystem: filesystem)['frameworkVersion'] as Version;
}

Version getDartSdkVersion(
    {Platform? platform,
    ProcessManager? processManager,
    FileSystem filesystem = const LocalFileSystem()}) {
  return getFlutterInformation(
      platform: platform,
      processManager: processManager,
      filesystem: filesystem)['dartSdkVersion'] as Version;
}

Map<String, dynamic> getFlutterInformation(
    {Platform? platform,
    ProcessManager? processManager,
    FileSystem filesystem = const LocalFileSystem()}) {
  final ProcessManager manager = processManager ?? const LocalProcessManager();
  final Platform resolvedPlatform = platform ?? const LocalPlatform();
  String flutterCommand;
  if (resolvedPlatform.environment['FLUTTER_ROOT'] != null) {
    flutterCommand = filesystem
        .directory(resolvedPlatform.environment['FLUTTER_ROOT']!)
        .childDirectory('bin')
        .childFile('flutter')
        .absolute
        .path;
  } else {
    flutterCommand = 'flutter';
  }
  io.ProcessResult result;
  try {
    result =
        manager.runSync(<String>[flutterCommand, '--version', '--machine'], stdoutEncoding: utf8);
  } on io.ProcessException catch (e) {
    throw SnippetException(
        'Unable to determine Flutter information. Either set FLUTTER_ROOT, or place flutter command in your path.\n$e');
  }
  if (result.exitCode != 0) {
    throw SnippetException(
        'Unable to determine Flutter information, because of abnormal exit to flutter command.');
  }
  final Map<String, dynamic> map = json.decode(result.stdout as String) as Map<String, dynamic>;
  if (map['flutterRoot'] == null ||
      map['frameworkVersion'] == null ||
      map['dartSdkVersion'] == null) {
    throw SnippetException(
        'Flutter command output has unexpected format, unable to determine flutter root location.');
  }
  final Map<String, dynamic> info = <String, dynamic>{};
  info['flutterRoot'] = filesystem.directory(map['flutterRoot']! as String);
  info['frameworkVersion'] = Version.parse(map['frameworkVersion'] as String);
  final RegExpMatch? dartVersionRegex =
      RegExp(r'(?<base>[\d.]+)(?:\s+\(build (?<detail>[-.\w]+)\))?')
          .firstMatch(map['dartSdkVersion'] as String);
  if (dartVersionRegex == null) {
    throw SnippetException(
        'Flutter command output has unexpected format, unable to parse dart SDK version ${map['dartSdkVersion']}.');
  }
  info['dartSdkVersion'] =
      Version.parse(dartVersionRegex.namedGroup('detail') ?? dartVersionRegex.namedGroup('base')!);
  return info;
}

void errorExit(String message) {
  io.stderr.writeln(message);
  io.exit(1);
}
