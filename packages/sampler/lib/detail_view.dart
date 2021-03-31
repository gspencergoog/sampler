// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:path/path.dart' as path;
import 'package:snippets/snippets.dart';

import 'helper_widgets.dart';
import 'model.dart';

class DetailView extends StatefulWidget {
  const DetailView({Key? key}) : super(key: key);

  @override
  _DetailViewState createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView> {
  FlutterProject? project;

  void _exportSample() {
    setState(() {
      final Directory outputLocation =
          Model.instance.filesystem.systemTempDirectory.createTempSync('flutter_sample.');
      project = FlutterProject(Model.instance.workingSample!,
          location: outputLocation, flutterRoot: Model.instance.flutterRoot);
      project!.create(overwrite: true);
    });
  }

  void _saveToFrameworkFile() {
    setState(() {
      project = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (Model.instance.workingSample == null) {
      return const Scaffold(body: Center(child: Text('Working sample not set.')));
    }
    final CodeSample sample = Model.instance.workingSample!;
    final String filename = sample.start.file != null
        ? path.relative(sample.start.file!.path, from: Model.instance.flutterPackageRoot.path)
        : '<generated>';
    return Scaffold(
      appBar: AppBar(
        title: Text('${sample.element} - $filename:${sample.start.line}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            DataLabel(label: 'Type of sample:', data: sample.type),
            DataLabel(label: 'Element sample is attached to:', data: sample.element),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                TextButton(child: const Text('EXPORT SAMPLE'), onPressed: _exportSample),
                const Spacer(),
                if (project?.location != null) OutputLocation(location: project!.location),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                TextButton(
                    child: const Text('SAVE TO FRAMEWORK FILE'), onPressed: _saveToFrameworkFile),
                const Spacer(),
                if (sample.start.file != null)
                  OutputLocation(location: sample.start.file!.parent, file: sample.start.file!),
              ],
            ),
            ListTile(
              title: HighlightView(
                // The original code to be highlighted
                sample.output,

                // Specify language
                // It is recommended to give it a value for performance
                language: 'dart',

                // Specify highlight theme
                // All available themes are listed in `themes` folder
                theme: githubTheme,

                // Specify padding
                padding: const EdgeInsets.all(12),

                // Specify text style
                textStyle: const TextStyle(
                  fontFamily: 'Fira Code',
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
