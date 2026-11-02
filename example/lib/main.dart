import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plate_ai/plate_ai.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(MaterialApp(
    title: 'Plate AI',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF0B7A4B), brightness: Brightness.dark),
    home: const HomePage(),
  ));
}

/// Scans like a QR code: tap the button, get a plate back, use it.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var _language = PlateLanguage.english;
  final _found = <PlateRead>[];

  Future<void> _scan() async {
    final plate = await PlateScanner.scan(context, language: _language);
    if (plate != null) setState(() => _found.insert(0, plate));
  }

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
        body: _found.isEmpty
            ? const Center(child: Text('Tap Scan to read a number plate'))
            : ListView.builder(
                itemCount: _found.length,
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.directions_car_outlined),
                  title: Text(_found[i].text(_language)),
                ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _scan,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan'),
        ),
      );
}
