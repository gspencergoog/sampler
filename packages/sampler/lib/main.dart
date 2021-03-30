import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:path/path.dart' as path;
import 'package:snippets/snippets.dart';

const FileSystem fs = LocalFileSystem();

class Model extends ChangeNotifier {
  Model({
    File? workingFile,
    Directory? flutterRoot,
  })  : _workingFile = workingFile,
        flutterRoot = flutterRoot ?? _findFlutterRoot(),
        _dartdocParser = SnippetDartdocParser(),
        _snippetGenerator = SnippetGenerator();

  static Directory _findFlutterRoot() {
    return fs.directory(getFlutterRoot());
  }

  Future<void> listFiles(Directory directory, {String suffix = '.dart'}) async {
    final List<File> foundDartFiles = <File>[];
    await for (FileSystemEntity entity in directory.list(recursive: true)) {
      if (entity is Directory || !entity.basename.endsWith(suffix)) {
        continue;
      }
      if (entity is Link) {
        final String resolvedPath = entity.resolveSymbolicLinksSync();
        if (!(await fs.isFile(resolvedPath))) {
          continue;
        }
        entity = fs.file(resolvedPath);
      }
      final File relativePath =
          fs.file(path.relative(entity.absolute.path, from: directory.absolute.path));
      if (path.split(relativePath.path).contains('test')) {
        continue;
      }
      foundDartFiles.add(relativePath);
    }
    files = foundDartFiles;
  }

  File? _workingFile;

  File? get workingFile => _workingFile;

  set workingFile(File? value) {
    if (_workingFile == value) {
      return;
    }
    _workingFile = value;
    if (_workingFile == null) {
      _samples = null;
      return;
    }
    _samples = _dartdocParser
        .parse(fs.file(path.join(flutterPackageRoot.absolute.path, _workingFile!.path)));
    samples!.forEach(_snippetGenerator.generateCode);
    print('Loaded ${samples!.length} samples from ${_workingFile!.path}');
    notifyListeners();
  }

  CodeSample? _workingSample;

  CodeSample? get workingSample => _workingSample;

  set workingSample(CodeSample? workingSample) {
    _workingSample = workingSample;
    notifyListeners();
  }
  List<CodeSample>? _samples;

  List<CodeSample>? get samples => _samples;

  Directory flutterRoot;
  Directory get flutterPackageRoot =>
      flutterRoot.childDirectory('packages').childDirectory('flutter');
  List<File>? files;

  final SnippetDartdocParser _dartdocParser;
  final SnippetGenerator _snippetGenerator;
}

Model model = Model();

const String _kFileOption = 'file';

void main(List<String> argv) {
  final ArgParser parser = ArgParser();
  parser.addOption(_kFileOption, help: 'Specifies the file to edit samples in.');
  final ArgResults args = parser.parse(argv);

  if (args.wasParsed(_kFileOption)) {
    model.workingFile = fs.file(args[_kFileOption]);
  }

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
        primarySwatch: Colors.red,
      ),
      home: const Sampler(title: _title),
    );
  }
}

class Sampler extends StatefulWidget {
  const Sampler({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  _SamplerState createState() => _SamplerState();
}

class _SamplerState extends State<Sampler> {
  bool get filesLoading => model.files == null;
  int expandedIndex = -1;

  @override
  void initState() {
    super.initState();
    if (model.workingFile == null) {
      model.listFiles(model.flutterPackageRoot).then((void _) {
        setState(() {});
      });
    }
  }

  Iterable<File> _fileOptions(TextEditingValue value) {
    if (value.text.isEmpty || model.files == null) {
      return const Iterable<File>.empty();
    }
    if (value.text.contains(path.separator)) {
      return model.files!.where((File file) => file.path.contains(value.text));
    }
    return model.files!.where((File file) => file.basename.contains(value.text));
  }

  Iterable<CodeSample> _sampleOptions(TextEditingValue value) {
    if (value.text.isEmpty || model.samples == null) {
      return const Iterable<CodeSample>.empty();
    }
    final Iterable<CodeSample> result = model.samples!.where((CodeSample sample) => sample.id.contains(value.text));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    List<ExpansionPanel> panels = const <ExpansionPanel>[];
    List<CodeSample> samples = const <CodeSample>[];
    if (model.samples != null) {
      if (model.workingSample == null) {
        samples = model.samples!;
      } else {
        samples = <CodeSample>[model.workingSample!];
      }
      int index = 0;
      panels = samples.map<ExpansionPanel>(
        (CodeSample sample) {
          final ExpansionPanel result = ExpansionPanel(
            headerBuilder: (BuildContext context, bool isExpanded) {
              return ListTile(
                title: Text('${sample.start.element}: ${sample.id}'),
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
            isExpanded: index == expandedIndex,
          );
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
                  Row(
                    children: <Widget>[
                      const Text('File: '),
                      Expanded(
                          child: Autocomplete<File>(
                        optionsBuilder: _fileOptions,
                        displayStringForOption: (File file) => file.path,
                        onSelected: (File file) {
                          setState(() {
                            model.workingFile = file;
                          });
                        },
                      )),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      const Text('Example: '),
                      Expanded(
                          child: Autocomplete<CodeSample>(
                        optionsBuilder: _sampleOptions,
                        displayStringForOption: (CodeSample sample) => sample.id,
                        onSelected: (CodeSample sample) {
                          print('Selected ${sample.id}');
                          setState(() {
                            model.workingSample = sample;
                          });
                        },
                      )),
                    ],
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
