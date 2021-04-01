// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:platform/platform.dart';

import 'utils.dart';

class DataLabel extends StatelessWidget {
  const DataLabel({Key? key, this.label = '', this.data = ''}) : super(key: key);

  final String label;
  final String data;

  @override
  Widget build(BuildContext context) {
    final TextStyle labelStyle = Theme.of(context).textTheme.bodyText2!;
    return DefaultTextStyle(
      style: labelStyle,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8.0, end: 8.0),
              child: Text(label),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8.0, end: 8.0),
              child: Text(data, style: labelStyle.copyWith(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class OutputLocation extends StatelessWidget {
  OutputLocation({
    Key? key,
    required this.location,
    this.file,
    this.label = '',
    this.startLine = 0,
    Platform platform = const LocalPlatform(),
  })  : _fileBrowserName = _getFileBrowserName(platform),
        assert(file == null || file.absolute.path.contains(location.absolute.path),
            'Supplied file must be within location directory'),
        super(key: key);

  final Directory location;
  final File? file;
  final String label;
  final String _fileBrowserName;
  final int startLine;

  static String _getFileBrowserName(Platform platform) {
    switch (platform.operatingSystem) {
      case 'windows':
        return 'FILE EXPLORER';
      case 'macos':
        return 'FINDER';
      case 'linux':
      default:
        return 'FILE BROWSER';
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle labelStyle = Theme.of(context).textTheme.bodyText2!;
    final String path = file?.path ?? location.absolute.path;
    return DefaultTextStyle(
      style: labelStyle,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Column(
          children: <Widget>[
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8.0, end: 8.0),
                child: Text('$label${label.isNotEmpty ? ' ' : ''}$path'),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8.0, end: 8.0),
                child: IconButton(
                    tooltip: 'Copy path to clipboard',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: path));
                    }),
              ),
            ]),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8.0, end: 8.0),
                  child: TextButton(
                      child: Text('OPEN IN $_fileBrowserName'),
                      onPressed: () {
                        openFileBrowser(file?.parent ?? location);
                      }),
                ),
                for (final IdeType type in IdeType.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8.0, end: 8.0),
                    child: TextButton(
                        child: Text('OPEN IN ${getIdeName(type).toUpperCase()}'),
                        onPressed: () {
                          openInIde(type, file ?? location, startLine: startLine);
                        }),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// The default Material-style Autocomplete text field.
class AutocompleteField extends StatelessWidget {
  const AutocompleteField({
    Key? key,
    required this.focusNode,
    required this.textEditingController,
    required this.onFieldSubmitted,
    this.trailing,
  }) : super(key: key);

  final FocusNode focusNode;

  final VoidCallback onFieldSubmitted;

  final TextEditingController textEditingController;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextFormField(
            controller: textEditingController,
            focusNode: focusNode,
            onFieldSubmitted: (String value) {
              onFieldSubmitted();
            },
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
