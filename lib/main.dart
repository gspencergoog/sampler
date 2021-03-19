import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:args/args.dart';

class Model {
  Model({this.file});

  File? file;
}

Model model = Model();

FileSystem fs = LocalFileSystem();

const String _kFileOption = 'file';

void main(List<String> argv) {
  final ArgParser parser = ArgParser();
  parser.addOption(_kFileOption, help: 'Specifies the file to edit samples in.');
  final ArgResults args = parser.parse(argv);

  if (args.wasParsed(_kFileOption)) {
    model.file = fs.file(args[_kFileOption]);
  }

  runApp(MainApp());
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

class Sample {
  Sample({required this.id, required this.codeBlocks});

  String id;
  String description;
  File template;
  Map<String, String> codeBlocks;
}

class SampleModel {
  SampleModel({required this.file}) { parseFile(file); }
  File file;
  List<Sample> snippets = <Sample>[];
  
  void parseFile(File file) {
    
  }
}

class Sampler extends StatefulWidget {
  const Sampler({Key? key, required this.title}) : super(key: key);
  
  final String title;

  @override
  _SamplerState createState() => _SamplerState();
}

class _SamplerState extends State<Sampler> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'You have pushed the button this many times:',
            ),
            Text(
              'foo',
              style: Theme.of(context).textTheme.headline4,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
