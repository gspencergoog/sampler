// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:args/args.dart';
import 'package:snippets/snippets.dart';

void main(List<String> argList) {
  final ArgParser parser = ArgParser();
  parser.addOption('templates', help: 'Where to find the templates');
  parser.addOption(
    'file',
    help: 'Which source file to edit samples in',
  );
  final ArgResults args = parser.parse(argList);
  if (!args.wasParsed('file')) {
    print(
        'File containing samples to edit must be specified with the --file option.');
    print(parser.usage);
    exit(-1);
  }

  final SnippetDartdocParser snippetParser = SnippetDartdocParser();
  final SnippetGenerator generator = SnippetGenerator();
  final Map<String, CodeSample> snippets =
      snippetParser.parse(File(args['file']! as String));
  for (final String key in snippets.keys) {
    print('$key: ${snippets[key]}');
    print('Generated:\n${generator.generate(snippets[key]!)}');
  }
  getFileComments(File(args['file']! as String));
}
