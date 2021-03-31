// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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

Future<void> _doExport(FlutterProject project) async {
  await project.export(overwrite: true);
}

class _DetailViewState extends State<DetailView> {
  FlutterProject? project;
  bool exporting = false;

  void _exportSample() {
    setState(() {
      exporting = true;
      if (project == null) {
        final Directory outputLocation =
            Model.instance.filesystem.systemTempDirectory.createTempSync('flutter_sample.');
        project = FlutterProject(Model.instance.workingSample!,
            location: outputLocation, flutterRoot: Model.instance.flutterRoot);
      }
      compute(_doExport, project!).whenComplete(() {
        setState(() {
          exporting = false;
        });
      });
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
        child: Column(
          children: <Widget>[
            DataLabel(label: 'Type of sample:', data: sample.type),
            DataLabel(
                label: 'Sample is attached to:',
                data: '${sample.element} starting at line ${sample.start.line}'),
            Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Container(
                  height: 100,
                  margin: const EdgeInsets.all(8.0),
                  padding: const EdgeInsets.all(8.0),
                  decoration: const ShapeDecoration(
                      color: Colors.black12,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10.0)))),
                  child: Row(
                    mainAxisAlignment:
                        project == null ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      TextButton(
                          child: Text(project == null ? 'EXPORT SAMPLE' : 'RE-EXPORT SAMPLE'),
                          onPressed: _exportSample),
                      if (project != null && !exporting)
                        OutputLocation(location: project!.location),
                    ],
                  ),
                ),
                if (exporting) const CircularProgressIndicator.adaptive(value: null),
              ],
            ),
            Container(
              height: 100,
              margin: const EdgeInsets.all(8.0),
              padding: const EdgeInsets.all(8.0),
              decoration: const ShapeDecoration(
                  color: Colors.black12,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10.0)))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  TextButton(
                      child: const Text('SAVE TO FRAMEWORK FILE'), onPressed: _saveToFrameworkFile),
                  const Spacer(),
                  if (sample.start.file != null)
                    OutputLocation(
                      location: sample.start.file!.parent,
                      file: sample.start.file!,
                      startLine: sample.start.line,
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  ListTile(
                    title: HighlightView(
                      // The original code to be highlighted
                      sample.output,
                      language: 'dart',
                      tabSize: 2,
                      theme: githubTheme,
                      padding: const EdgeInsets.all(12),
                      textStyle: const TextStyle(
                        fontFamily: 'Fira Code',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
