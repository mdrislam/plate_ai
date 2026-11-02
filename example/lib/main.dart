import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plate_ai/plate_ai.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(MaterialApp(
    title: 'Plate AI',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF0B7A4B), brightness: Brightness.dark),
    home: const ScanPage(),
  ));
}

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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<PlateLanguage>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: PlateLanguage.english, label: Text('EN')),
                ButtonSegment(value: PlateLanguage.bangla, label: Text('বাংলা')),
              ],
              selected: {_language},
              onSelectionChanged: (s) => setState(() => _language = s.first),
            ),
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
            child: _found.isEmpty
                ? const Center(child: Text('Plates you scan will appear here'))
                : ListView.builder(
                    itemCount: _found.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: const Icon(Icons.directions_car_outlined),
                      title: Text(_found[i].text(_language)),
                    ),
                  ),
          ),
        ]),
      );
}
