import 'package:flutter/material.dart';
import 'package:plate_ai/plate_ai.dart';

void main() => runApp(const MaterialApp(home: ScanPage()));

/// A live scanner with a language switch, and a list of the plates found.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  var _language = PlateLanguage.english;
  final _found = <PlateRead>[];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Plate AI'), actions: [
          SegmentedButton<PlateLanguage>(
            segments: const [
              ButtonSegment(value: PlateLanguage.english, label: Text('EN')),
              ButtonSegment(value: PlateLanguage.bangla, label: Text('বাংলা')),
            ],
            selected: {_language},
            onSelectionChanged: (s) => setState(() => _language = s.first),
          ),
        ]),
        body: Column(children: [
          Expanded(
            flex: 3,
            child: PlateScanner(
              language: _language,
              onPlate: (plate) => setState(() => _found.insert(0, plate)),
            ),
          ),
          Expanded(
            child: ListView(children: [
              for (final plate in _found) ListTile(title: Text(plate.text(_language))),
            ]),
          ),
        ]),
      );
}
