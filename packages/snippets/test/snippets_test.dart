// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' hide Platform;
import 'package:path/path.dart' as path;

import 'package:test/test.dart' hide TypeMatcher, isInstanceOf;

import 'package:snippets/snippets.dart';

void main() {
  group('Generator', () {
    late SnippetConfiguration configuration;
    late SnippetGenerator generator;
    late Directory tmpDir;
    late File template;

    void _writeSkeleton(String type) {
      switch(type) {
        case 'dartpad':
          configuration.getHtmlSkeletonFile('dartpad').writeAsStringSync('''
<div>HTML Bits (DartPad-style)</div>
<iframe class="snippet-dartpad" src="https://dartpad.dev/embed-flutter.html?split=60&run=true&sample_id={{id}}&sample_channel={{channel}}"></iframe>
<div>More HTML Bits</div>
''');
          break;
        case 'sample':
        case 'snippet':
          configuration.getHtmlSkeletonFile(type).writeAsStringSync('''
<div>HTML Bits</div>
{{description}}
<pre>{{code}}</pre>
<pre>{{app}}</pre>
<div>More HTML Bits</div>
''');
          break;
      }
    }

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('flutter_snippets_test.');
      configuration = FlutterRepoSnippetConfiguration(flutterRoot: Directory(path.join(
          tmpDir.absolute.path, 'flutter')));
      configuration.createOutputDirectoryIfNeeded();
      configuration.templatesDirectory.createSync(recursive: true);
      configuration.skeletonsDirectory.createSync(recursive: true);
      template = File(path.join(configuration.templatesDirectory.path, 'template.tmpl'));
      template.writeAsStringSync('''
// Flutter code sample for {{element}}

{{description}}

{{code-my-preamble}}

main() {
  {{code}}
}
''');
      <String>['dartpad', 'sample', 'snippet'].forEach(_writeSkeleton);
      generator = SnippetGenerator(configuration: configuration);
    });
    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('generates samples', () async {
      final File inputFile = File(path.join(tmpDir.absolute.path, 'snippet_in.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync(r'''
A description of the snippet.

On several lines.

```my-dart_language my-preamble
const String name = 'snippet';
```

```dart
void main() {
  print('The actual $name.');
}
```
''');
      final File outputFile = File(path.join(tmpDir.absolute.path, 'snippet_out.txt'));
      final SnippetDartdocParser sampleParser = SnippetDartdocParser();
      const String sourcePath = 'packages/flutter/lib/src/widgets/foo.dart';
      const int sourceLine = 222;
      final List<CodeSample> samples = sampleParser.parseFromDartdocToolFile(
        inputFile,
        element: 'MyElement',
        template: 'template',
        startLine: sourceLine,
        sourceFile: File(sourcePath),
        type: 'sample',
      );
      expect(samples, isNotEmpty);
      samples.first.metadata.addAll(<String, Object?>{
        'channel': 'stable',
      });
      final String code = generator.generateCode(
        samples.first,
        output: outputFile,
      );
      expect(code, contains('// Flutter code sample for MyElement'));
      final String html = generator.generateHtml(
        samples.first,
      );
      expect(html, contains('<div>HTML Bits</div>'));
      expect(html, contains('<div>More HTML Bits</div>'));
      expect(html, contains(r'print(&#39;The actual $name.&#39;);'));
      expect(html, contains('A description of the snippet.\n'));
      expect(html, isNot(contains('sample_channel=stable')));
      expect(
          html,
          contains('&#47;&#47; A description of the snippet.\n'
              '&#47;&#47;\n'
              '&#47;&#47; On several lines.\n'));
      expect(html, contains('void main() {'));

      final String outputContents = outputFile.readAsStringSync();
      expect(outputContents, contains('// Flutter code sample for MyElement'));
      expect(outputContents, contains('A description of the snippet.'));
      expect(outputContents, contains('void main() {'));
      expect(outputContents, contains("const String name = 'snippet';"));
    });

    test('generates snippets', () async {
      final File inputFile = File(path.join(tmpDir.absolute.path, 'snippet_in.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync(r'''
A description of the snippet.

On several lines.

```code
void main() {
  print('The actual $name.');
}
```
''');

      final SnippetDartdocParser sampleParser = SnippetDartdocParser();
      const String sourcePath = 'packages/flutter/lib/src/widgets/foo.dart';
      const int sourceLine = 222;
      final List<CodeSample> samples = sampleParser.parseFromDartdocToolFile(
        inputFile,
        element: 'MyElement',
        startLine: sourceLine,
        sourceFile: File(sourcePath),
        type: 'snippet',
      );
      expect(samples, isNotEmpty);
      samples.first.metadata.addAll(<String, Object>{
        'channel': 'stable',
      });
      final String code = generator.generateCode(samples.first);
      expect(code, contains('// A description of the snippet.'));
      final String html = generator.generateHtml(samples.first);
      expect(html, contains('<div>HTML Bits</div>'));
      expect(html, contains('<div>More HTML Bits</div>'));
      expect(html, contains(r'  print(&#39;The actual $name.&#39;);'));
      expect(html, contains('<div class="snippet-description">{@end-inject-html}A description of the snippet.\n\n'
          'On several lines.{@inject-html}</div>\n'));
      expect(html, contains('main() {'));
    });

    test('generates dartpad samples', () async {
      final File inputFile = File(path.join(tmpDir.absolute.path, 'snippet_in.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync(r'''
A description of the snippet.

On several lines.

```code
void main() {
  print('The actual $name.');
}
```
''');

      final SnippetDartdocParser sampleParser = SnippetDartdocParser();
      const String sourcePath = 'packages/flutter/lib/src/widgets/foo.dart';
      const int sourceLine = 222;
      final List<CodeSample> samples = sampleParser.parseFromDartdocToolFile(
        inputFile,
        element: 'MyElement',
        template: 'template',
        startLine: sourceLine,
        sourceFile: File(sourcePath),
        type: 'dartpad',
      );
      expect(samples, isNotEmpty);
      samples.first.metadata.addAll(<String, Object>{
        'channel': 'stable',
      });
      final String code = generator.generateCode(samples.first);
      expect(code, contains('// Flutter code sample for MyElement'));
      final String html = generator.generateHtml(samples.first);
      expect(html, contains('<div>HTML Bits (DartPad-style)</div>'));
      expect(html, contains('<div>More HTML Bits</div>'));
      expect(html, contains('<iframe class="snippet-dartpad" src="https://dartpad.dev/embed-flutter.html?split=60&run=true&sample_id=dartpad.packages.flutter.lib.src.widgets.foo.222&sample_channel=stable"></iframe>\n'));
    });

    test('generates sample metadata', () async {
      final File inputFile = File(path.join(tmpDir.absolute.path, 'snippet_in.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync(r'''
A description of the snippet.

On several lines.

```dart
void main() {
  print('The actual $name.');
}
```
''');

      final File outputFile = File(path.join(tmpDir.absolute.path, 'snippet_out.dart'));
      final File expectedMetadataFile = File(path.join(tmpDir.absolute.path, 'snippet_out.json'));

      final SnippetDartdocParser sampleParser = SnippetDartdocParser();
      const String sourcePath = 'packages/flutter/lib/src/widgets/foo.dart';
      const int sourceLine = 222;
      final List<CodeSample> samples = sampleParser.parseFromDartdocToolFile(
        inputFile,
        element: 'MyElement',
        template: 'template',
        startLine: sourceLine,
        sourceFile: File(sourcePath),
        type: 'sample',
      );
      expect(samples, isNotEmpty);
      samples.first.metadata.addAll(<String, Object>{'channel': 'stable'});
      generator.generateCode(samples.first, output: outputFile);
      expect(expectedMetadataFile.existsSync(), isTrue);
      final Map<String, dynamic> json = jsonDecode(expectedMetadataFile.readAsStringSync()) as Map<String, dynamic>;
      expect(json['id'], equals('sample.packages.flutter.lib.src.widgets.foo.222'));
      expect(json['channel'], equals('stable'));
      expect(json['file'], equals('snippet_out.dart'));
      expect(json['description'], equals('A description of the snippet.\n\nOn several lines.'));
      expect(json['sourcePath'], equals('packages/flutter/lib/src/widgets/foo.dart'));
    });
  });
}
