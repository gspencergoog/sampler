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
  final List<CodeSample> samples =
      snippetParser.parse(File(args['file']! as String));
  for (final CodeSample sample in samples) {
    print('${sample.id}: $sample');
    print('Generated:\n${generator.generate(sample)}');
  }
}
