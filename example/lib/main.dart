import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:plate_ai/plate_ai.dart';

void main() => runApp(const MaterialApp(home: ScanPage()));

/// Live scanner: reads the camera on the phone and shows a plate once two reads in a row agree.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  final _ai = PlateAI();
  CameraController? _camera;
  String? _lastNumber, _error;
  PlateRead? _plate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      await _ai.load();
      await _openCamera();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _openCamera() async {
    if (_camera != null) return;
    final back = (await availableCameras()).firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    final camera = CameraController(back, ResolutionPreset.high,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
    await camera.initialize();
    if (!mounted) return camera.dispose();
    await camera.startImageStream((image) => _onFrame(image, back.sensorOrientation));
    setState(() => _camera = camera);
  }

  Future<void> _closeCamera() async {
    final camera = _camera;
    if (camera == null) return;
    if (mounted) setState(() => _camera = null); // drop the preview before the controller goes
    await camera.dispose();
  }

  Future<void> _onFrame(CameraImage image, int rotation) async {
    final y = image.planes[0];
    final read = await _ai.read(YFrame(y.bytes, image.width, image.height, y.bytesPerRow, rotation));
    if (read == null || !mounted) return;
    if (read.number == _lastNumber) setState(() => _plate = read);
    _lastNumber = read.number;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _openCamera();
    } else if (state == AppLifecycleState.paused) {
      _closeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _ai.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (camera != null) Center(child: CameraPreview(camera)),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _error ?? _plate?.en ?? (camera == null ? 'Starting...' : 'Point at a number plate'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
