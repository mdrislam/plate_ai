import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plate_ai/plate_ai.dart';

void main() => runApp(const MaterialApp(home: Demo()));

class Demo extends StatefulWidget {
  const Demo({super.key});

  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  String _text = 'Reading...';

  @override
  void initState() {
    super.initState();
    _run();
  }

  /// Reads the bundled photo through the same call a camera frame uses.
  Future<void> _run() async {
    final data = await rootBundle.load('assets/plate.jpg');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final image = (await codec.getNextFrame()).image;
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    final grey = Uint8List(image.width * image.height);
    for (var i = 0; i < grey.length; i++) {
      grey[i] = (rgba[i * 4] * 299 + rgba[i * 4 + 1] * 587 + rgba[i * 4 + 2] * 114) ~/ 1000;
    }
    final ai = PlateAI();
    await ai.load();
    final r = await ai.read(YFrame(grey, image.width, image.height, image.width, 0));
    debugPrint('plate_ai_demo: ${r?.en} ${r?.bn} ms=${ai.lastMs}');
    setState(() => _text = r?.en ?? 'No plate found');
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(_text, style: const TextStyle(fontSize: 22))));
}
