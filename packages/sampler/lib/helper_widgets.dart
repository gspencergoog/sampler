// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:platform/platform.dart';

import 'model.dart';
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
    Platform platform = const LocalPlatform(),
  })  : _fileBrowserName = _getFileBrowserName(platform),
        assert(file == null || file.absolute.path.contains(location.absolute.path),
            'Supplied file must be within location directory'),
        super(key: key);

  final Directory location;
  final File? file;
  final String label;
  final String _fileBrowserName;

  static String _getFileBrowserName(Platform platform) {
    switch (platform.operatingSystem) {
      case 'windows':
        return 'EXPLORER';
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
    return DefaultTextStyle(
      style: labelStyle,
      child: Container(
        color: Colors.grey.shade300,
        padding: const EdgeInsets.all(4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8.0, end: 8.0),
              child: Text('$label${label.isNotEmpty ? ' ' : ''}${file?.path ?? location.path}'),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8.0, end: 8.0),
              child: IconButton(
                  tooltip: 'Copy path to clipboard',
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: location.absolute.path));
                  }),
            ),
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
                      openInIde(type, file ?? location);
                    }),
              ),
          ],
        ),
      ),
    );
  }
}
