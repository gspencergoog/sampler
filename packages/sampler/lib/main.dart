import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:path/path.dart' as path;
import 'package:snippets/snippets.dart';

import 'detail_view.dart';
import 'model.dart';

const FileSystem fs = LocalFileSystem();

const String _kFileOption = 'file';
const String _kFlutterRootOption = 'flutter-root';

void main(List<String> argv) {
  final ArgParser parser = ArgParser();
  parser.addOption(_kFileOption, help: 'Specifies the file to edit samples in.');
  parser.addOption(_kFlutterRootOption,
      help: 'Specifies the location of the Flutter root directory.');
  final ArgResults args = parser.parse(argv);

  Directory? flutterRoot;
  if (args.wasParsed(_kFlutterRootOption)) {
    flutterRoot = fs.directory(args[_kFlutterRootOption] as String);
  }
  File? workingFile;
  if (args.wasParsed(_kFileOption)) {
    workingFile = fs.file(args[_kFileOption]);
  }

  Model.instance = Model(workingFile: workingFile, flutterRoot: flutterRoot, filesystem: fs);

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({Key? key}) : super(key: key);

  static const String _title = 'Sampler';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _title,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),
      routes: <String, WidgetBuilder>{
        '/detailView': (BuildContext context) => const DetailView(),
      },
      home: const Sampler(title: _title),
    );
  }
}

ExpansionPanel createExpansionPanel(CodeSample sample, {bool isExpanded = false}) {
  return ExpansionPanel(
    headerBuilder: (BuildContext context, bool isExpanded) {
      return ListTile(
        title: Text('${sample.start.element}: ${sample.id}'),
        trailing: TextButton(
          child: const Text('SELECT'),
          onPressed: () {
            Model.instance.workingSample = sample;
            Navigator.of(context).pushNamed('/detailView');
          },
        ),
      );
    },
    body: ListTile(
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
    isExpanded: isExpanded,
  );
}

class Sampler extends StatefulWidget {
  const Sampler({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  _SamplerState createState() => _SamplerState();
}

class _SamplerState extends State<Sampler> {
  bool get filesLoading => Model.instance.files == null;
  int expandedIndex = -1;

  @override
  void initState() {
    super.initState();
    if (Model.instance.workingFile == null) {
      Model.instance.listFiles(Model.instance.flutterPackageRoot).then((void _) {
        setState(() {});
      });
    }
    Model.instance.addListener(_modelUpdated);
  }

  @override
  void dispose() {
    Model.instance.removeListener(_modelUpdated);
    super.dispose();
  }

  void _modelUpdated() {
    setState(() {
      // model updated, so force widget update.
    });
  }

  Iterable<File> _fileOptions(TextEditingValue value) {
    if (value.text.isEmpty || Model.instance.files == null) {
      return const Iterable<File>.empty();
    }
    if (value.text.contains(path.separator)) {
      return Model.instance.files!
          .where((File file) => file.path.toLowerCase().contains(value.text.toLowerCase()));
    }
    return Model.instance.files!
        .where((File file) => file.basename.toLowerCase().contains(value.text.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    List<ExpansionPanel> panels = const <ExpansionPanel>[];
    List<CodeSample> samples = const <CodeSample>[];
    if (Model.instance.samples != null) {
      if (Model.instance.workingSample == null) {
        samples = Model.instance.samples!;
      } else {
        samples = <CodeSample>[Model.instance.workingSample!];
      }
      int index = 0;
      panels = samples.map<ExpansionPanel>(
        (CodeSample sample) {
          final ExpansionPanel result =
              createExpansionPanel(sample, isExpanded: index == expandedIndex);
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
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8.0),
                          child: Text('Framework File:',
                              style: Theme.of(context)
                                  .textTheme
                                  .subtitle1!
                                  .copyWith(fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                            child: Autocomplete<File>(
                          optionsBuilder: _fileOptions,
                          displayStringForOption: (File file) => file.path,
                          onSelected: (File file) {
                            Model.instance.setWorkingFile(file);
                          },
                        )),
                        if (Model.instance.samples != null)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 8.0),
                            child: Text('${Model.instance.samples!.length} samples'),
                          ),
                      ],
                    ),
                  ),
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
