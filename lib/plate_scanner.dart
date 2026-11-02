import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'plate_ai.dart';

/// A ready-made live scanner: camera preview, guide box and the plate in the chosen [language].
///
/// Handles the models, the camera and pausing with the app. A plate counts once two reads in a
/// row agree; [onPlate] is then called once, and again only for a different plate.
class PlateScanner extends StatefulWidget {
  const PlateScanner({super.key, this.language = PlateLanguage.english, this.onPlate, this.showResult = true});

  /// The language of the plate shown on screen. Can change while scanning.
  final PlateLanguage language;

  /// Called with each new plate. Use `plate.text(language)`, or `plate.en` and `plate.bn`.
  final ValueChanged<PlateRead>? onPlate;

  /// Whether to show the plate on the preview; turn off to show it your own way.
  final bool showResult;

  @override
  State<PlateScanner> createState() => _PlateScannerState();
}

class _PlateScannerState extends State<PlateScanner> with WidgetsBindingObserver {
  static const _minGap = Duration(milliseconds: 150); // leaves the CPU free for a smooth preview

  final _ai = PlateAI();
  final _plate = ValueNotifier<PlateRead?>(null); // so a new plate rebuilds only its label
  final _watch = Stopwatch()..start();
  CameraController? _camera;
  Duration _last = -_minGap;
  String? _lastNumber, _error;
  bool _opening = false;

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
    if (_camera != null || _opening || !mounted) return;
    _opening = true;
    CameraController? camera;
    try {
      final back = (await availableCameras()).firstWhere((c) => c.lensDirection == CameraLensDirection.back);
      camera = CameraController(back, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await camera.initialize();
      await camera.startImageStream((image) => _onFrame(image, back.sensorOrientation));
      if (mounted) {
        setState(() => _camera = camera);
      } else {
        await camera.dispose();
      }
    } on Exception catch (e) {
      await camera?.dispose();
      if (mounted) setState(() => _error = '$e');
    } finally {
      _opening = false;
    }
  }

  Future<void> _closeCamera() async {
    final camera = _camera;
    if (camera == null) return;
    if (mounted) setState(() => _camera = null); // drop the preview before the controller goes
    await camera.dispose();
  }

  Future<void> _onFrame(CameraImage image, int rotation) async {
    if (_watch.elapsed - _last < _minGap) return;
    _last = _watch.elapsed;
    final y = image.planes[0];
    final read = await _ai.read(YFrame(y.bytes, image.width, image.height, y.bytesPerRow, rotation));
    if (read == null || !mounted) return;
    final confirmed = read.number == _lastNumber;
    _lastNumber = read.number;
    if (!confirmed || read.number == _plate.value?.number) return;
    _plate.value = read;
    widget.onPlate?.call(read);
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
    _plate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        if (camera != null) Center(child: RepaintBoundary(child: CameraPreview(camera))),
        const IgnorePointer(child: Center(child: FractionallySizedBox(widthFactor: 0.85, child: _GuideBox()))),
        if (_error != null || widget.showResult)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ValueListenableBuilder(
                  valueListenable: _plate,
                  builder: (_, plate, _) => Text(
                    _error ?? plate?.text(widget.language) ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Marks the centre square, the only part of a frame searched for a plate.
class _GuideBox extends StatelessWidget {
  const _GuideBox();

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white70, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
}
