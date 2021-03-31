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

import 'model.dart';

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

Map<String,dynamic>? _cachedFlutterInformation;

Map<String, dynamic> getFlutterInformation(
    {Platform? platform,
    ProcessManager? processManager,
    FileSystem filesystem = const LocalFileSystem()}) {
  if (_cachedFlutterInformation != null) {
    return _cachedFlutterInformation!;
  }
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
  _cachedFlutterInformation = info;
  return info;
}

/// Injects the [injections] into the [template], and turning the
/// "description" injection into a comment. Only used for
/// [SampleType.sample] snippets.
String interpolateTemplate(
  List<TemplateInjection> injections,
  String template,
  Map<String, Object?> metadata, {
  bool addSectionMarkers = false,
}) {
  final RegExp moustacheRegExp = RegExp('{{([^}]+)}}');
  String sectionArrows(String name, {bool start = true}) {
    const int markerArrows = 8;
    final String arrows = (start ? '⯆' : '⯅') * markerArrows;
    final String marker = '//* $arrows $name $arrows (do not modify or remove section marker)';
    return '${start ? '\n//*${'*' * marker.length}\n' : '\n'}'
        '$marker'
        '${!start ? '\n//*${'*' * marker.length}\n' : '\n'}';
  }

  String wrapSectionMarker(Iterable<String> contents, {required String name}) {
    return <String>[
      if (addSectionMarkers) sectionArrows(name, start: true),
      ...contents,
      if (addSectionMarkers) sectionArrows(name, start: false),
    ].join('\n').trim();
  }

  return template.replaceAllMapped(moustacheRegExp, (Match match) {
    if (match[1] == 'description') {
      // Place the description into a comment.
      final List<String> description = injections
          .firstWhere((TemplateInjection tuple) => tuple.name == match[1])
          .contents
          .map<String>((SourceLine line) => '// ${line.text}')
          .toList();
      // Remove any leading/trailing empty comment lines.
      // We don't want to remove ALL empty comment lines, only the ones at the
      // beginning and the end.
      while (description.isNotEmpty && description.last == '// ') {
        description.removeLast();
      }
      while (description.isNotEmpty && description.first == '// ') {
        description.removeAt(0);
      }
      return wrapSectionMarker(description, name: 'description');
    } else {
      final int componentIndex =
          injections.indexWhere((TemplateInjection injection) => injection.name == match[1]);
      if (componentIndex == -1) {
      // If the match isn't found in the injections, then just remove the
      // mustache reference, since we want to allow the sections to be
      // "optional" in the input: users shouldn't be forced to add an empty
      // "```dart preamble" section if that section would be empty.
        return (metadata[match[1]] ?? '').toString();
      }
      return wrapSectionMarker(injections[componentIndex].stringContents, name: match[1]!);
    }
  }).trim();
}

void errorExit(String message) {
  io.stderr.writeln(message);
  io.exit(1);
}
