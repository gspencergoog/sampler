// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:snippets/snippets.dart';

import 'helper_widgets.dart';
import 'main.dart';
import 'model.dart';

class NewSampleSelect extends StatefulWidget {
  const NewSampleSelect({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  _NewSampleSelectState createState() => _NewSampleSelectState();
}

class _NewSampleSelectState extends State<NewSampleSelect> {
  bool get filesLoading => Model.instance.files == null;
  int expandedIndex = -1;
  TextEditingController editingController = TextEditingController();

  ExpansionPanel _createExpansionPanel(SourceElement element, {bool isExpanded = false}) {
    return ExpansionPanel(
      headerBuilder: (BuildContext context, bool isExpanded) {
        return ListTile(
          title:
          Text('${element.elementName} at line ${element.startLine} (${element.typeAsString})'),
          trailing: TextButton(
            child: const Text('ADD SAMPLE'),
            onPressed: () {
              Model.instance.currentElement = element;
              Navigator.of(context).pushNamed(kNewSampleView).then((Object? result) {
                Model.instance.currentElement = null;
              });
            },
          ),
        );
      },
      body: element.comment.isNotEmpty
          ? ListTile(
        title: CodePanel(
          code: element.comment.map<String>((SourceLine line) => line.text).join('\n'),
        ),
      )
          : const SizedBox(),
      isExpanded: isExpanded,
    );
  }

  @override
  void initState() {
    super.initState();
    if (Model.instance.workingFile == null) {
      Model.instance.listFiles(Model.instance.flutterPackageRoot).then((void _) {
        setState(() {});
      });
    }
    Model.instance.addListener(_modelUpdated);
    editingController.addListener(_editingControllerChanged);
  }

  @override
  void dispose() {
    Model.instance.removeListener(_modelUpdated);
    editingController.dispose();
    super.dispose();
  }

  void _editingControllerChanged() {
    if (Model.instance.files == null) {
      return;
    }
    if (editingController.text.isEmpty ||
        !Model.instance.files!.contains(Model.instance.filesystem.file(editingController.text))) {
      Model.instance.clearWorkingFile();
    }
  }

  void _modelUpdated() {
    setState(() {
      // model updated, so force widget update.
    });
  }

  @override
  Widget build(BuildContext context) {
    List<ExpansionPanel> panels = const <ExpansionPanel>[];
    Iterable<SourceElement> elements = const <SourceElement>[];
    if (Model.instance.samples != null) {
      if (Model.instance.currentElement == null) {
        elements = Model.instance.elements!;
      } else {
        elements = <SourceElement>[Model.instance.currentElement!];
      }
      int index = 0;
      panels = elements.map<ExpansionPanel>(
        (SourceElement element) {
          final ExpansionPanel result =
              _createExpansionPanel(element, isExpanded: index == expandedIndex);
          index++;
          return result;
        },
      ).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              if (filesLoading) const CircularProgressIndicator.adaptive(value: null),
              ListView(
                children: <Widget>[
                  ExpansionPanelList(
                    children: panels,
                    expansionCallback: (int index, bool expanded) {
                      setState(() {
                        expandedIndex = expanded ? -1 : index;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
