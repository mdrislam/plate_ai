import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'plate_ai.dart';

/// A ready-made live scanner: camera preview, scan area, focus, flash, and the plate in the chosen
/// [language].
///
/// Handles the models, the camera, the camera permission and pausing with the app. A plate counts
/// once [confirmReads] reads in a row agree; [onPlate] is then called once, and again only for a
/// different plate. Works in portrait: lock your app to portrait on this screen.
class PlateScanner extends StatefulWidget {
  const PlateScanner({
    super.key,
    this.language = PlateLanguage.english,
    this.onPlate,
    this.showResult = true,
    this.confirmReads = 2,
    this.minConfidence = 0.75,
    this.resolution = ResolutionPreset.high,
    this.hint = 'Keep the plate inside the box',
    this.onlyNew = false,
  }) : assert(confirmReads >= 1);

  /// Opens a live scanner that stays open and lists each new plate, skipping duplicates.
  ///
  /// Returns the plates found when the user taps Done or goes back.
  ///
  /// ```dart
  /// final plates = await PlateScanner.scanAll(context);
  /// ```
  static Future<List<PlateRead>> scanAll(
    BuildContext context, {
    PlateLanguage language = PlateLanguage.english,
    int confirmReads = 2,
    double minConfidence = 0.75,
    ResolutionPreset resolution = ResolutionPreset.high,
  }) async {
    final plates = <PlateRead>[];
    await Navigator.of(context).push<void>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ScanAllPage(
        plates: plates,
        language: language,
        confirmReads: confirmReads,
        minConfidence: minConfidence,
        resolution: resolution,
      ),
    ));
    return plates;
  }

  /// Opens a full-screen scanner, like a QR scanner, and returns the first plate it finds.
  ///
  /// Returns null if the user goes back without scanning.
  ///
  /// ```dart
  /// final plate = await PlateScanner.scan(context);
  /// if (plate != null) print(plate.en);
  /// ```
  static Future<PlateRead?> scan(
    BuildContext context, {
    PlateLanguage language = PlateLanguage.english,
    int confirmReads = 2,
    double minConfidence = 0.75,
    ResolutionPreset resolution = ResolutionPreset.high,
    String hint = 'Keep the plate inside the box',
  }) {
    var done = false; // a second plate can arrive while the page is closing
    return Navigator.of(context).push<PlateRead>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (page) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(fit: StackFit.expand, children: [
            PlateScanner(
              language: language,
              confirmReads: confirmReads,
              minConfidence: minConfidence,
              resolution: resolution,
              hint: hint,
              onPlate: (plate) {
                if (done) return;
                done = true;
                Navigator.of(page).pop(plate);
              },
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton.filledTonal(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(page).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ),
          ]),
        ),
    ));
  }

  /// The language of the plate shown on screen. Can change while scanning.
  final PlateLanguage language;

  /// Called with each new plate. Use `plate.text(language)`, or `plate.en` and `plate.bn`.
  final ValueChanged<PlateRead>? onPlate;

  /// Whether to show the plate on the preview; turn off to show it your own way.
  final bool showResult;

  /// How many reads in a row must agree. Higher means fewer wrong plates but a slower result.
  final int confirmReads;

  /// Reads below this confidence (0..1) are ignored.
  final double minConfidence;

  /// Camera quality. A lower one uses less battery but needs the plate closer.
  final ResolutionPreset resolution;

  /// Shown until a plate is found.
  final String hint;

  /// Calls [onPlate] only once per plate number, even if a plate comes back later.
  final bool onlyNew;

  @override
  State<PlateScanner> createState() => _PlateScannerState();
}

class _PlateScannerState extends State<PlateScanner> with WidgetsBindingObserver {
  static const _minGap = Duration(milliseconds: 150); // leaves the CPU free for a smooth preview

  final _ai = PlateAI();
  final _plate = ValueNotifier<PlateRead?>(null); // so a new plate rebuilds only its label
  final _watch = Stopwatch()..start();
  final _seen = <String>{};
  CameraController? _camera;
  Duration _last = -_minGap;
  String? _lastNumber, _error;
  int _agreeing = 0;
  bool _opening = false, _paused = false, _torch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      await _ai.load();
      await _openCamera();
    } on CameraException catch (e) {
      _fail(
        e.code.startsWith('CameraAccess')
            ? 'Camera permission is needed. If it stays blocked, allow it in the phone settings.'
            : 'The camera could not start: ${e.description ?? e.code}',
      );
    } on Exception catch (e) {
      _fail('$e');
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _openCamera() async {
    if (_camera != null || _opening || _paused || !mounted) return;
    _opening = true;
    CameraController? camera;
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => throw CameraException('NoCamera', 'This device has no back camera.'),
      );
      camera = CameraController(back, widget.resolution, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await camera.initialize();
      await camera.startImageStream((image) => _onFrame(image, back.sensorOrientation));
      if (mounted && !_paused) {
        setState(() {
          _camera = camera;
          _torch = false;
        });
      } else {
        await camera.dispose();
      }
    } on Exception {
      await camera?.dispose();
      rethrow;
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
    if (!mounted || !_ai.ready || _watch.elapsed - _last < _minGap) return;
    _last = _watch.elapsed;
    final y = image.planes[0];
    final PlateRead? read;
    try {
      read = await _ai.read(YFrame(y.bytes, image.width, image.height, y.bytesPerRow, rotation));
    } on Exception {
      return; // one bad frame, or closing: the next frame tries again
    } on StateError {
      return;
    }
    if (read == null || read.conf < widget.minConfidence || !mounted) return;
    _agreeing = read.number == _lastNumber ? _agreeing + 1 : 1;
    _lastNumber = read.number;
    if (_agreeing < widget.confirmReads || read.number == _plate.value?.number) return;
    if (widget.onlyNew && !_seen.add(read.number)) return;
    _plate.value = read;
    HapticFeedback.lightImpact();
    widget.onPlate?.call(read);
  }

  Future<void> _focus(TapUpDetails tap, Size size) async {
    final point = Offset(tap.localPosition.dx / size.width, tap.localPosition.dy / size.height);
    try {
      await _camera?.setFocusPoint(point);
      await _camera?.setExposurePoint(point);
    } on CameraException {
      // not every camera can focus on a point
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _camera?.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torch = !_torch);
    } on CameraException {
      _fail('This device has no flash.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _paused = false;
      if (_error == null) unawaited(_openCamera().catchError((Object e) => _fail('$e')));
    } else if (state == AppLifecycleState.paused) {
      _paused = true;
      unawaited(_closeCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    unawaited(_ai.dispose().catchError((Object _) {})); // nothing left to do if closing fails
    _plate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final error = _error;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (camera != null) _Preview(camera: camera, onTap: _focus),
          if (error != null)
            _ErrorView(message: error, onRetry: _start)
          else if (camera == null)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else ...[
            if (widget.showResult)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: SafeArea(
                  child: ValueListenableBuilder(
                    valueListenable: _plate,
                    builder: (_, plate, _) => _ResultCard(text: plate?.text(widget.language), hint: widget.hint),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton.filledTonal(
                  tooltip: 'Flash',
                  onPressed: _toggleTorch,
                  icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanAllPage extends StatefulWidget {
  const _ScanAllPage({
    required this.plates,
    required this.language,
    required this.confirmReads,
    required this.minConfidence,
    required this.resolution,
  });

  final List<PlateRead> plates; // filled as plates are found, so going back keeps them too
  final PlateLanguage language;
  final int confirmReads;
  final double minConfidence;
  final ResolutionPreset resolution;

  @override
  State<_ScanAllPage> createState() => _ScanAllPageState();
}

class _ScanAllPageState extends State<_ScanAllPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('${widget.plates.length} found'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
        ),
        body: Column(children: [
          Expanded(
            flex: 3,
            child: PlateScanner(
              language: widget.language,
              confirmReads: widget.confirmReads,
              minConfidence: widget.minConfidence,
              resolution: widget.resolution,
              onlyNew: true,
              onPlate: (plate) => setState(() => widget.plates.insert(0, plate)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.plates.length,
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(Icons.directions_car_outlined),
                title: Text(widget.plates[i].text(widget.language)),
              ),
            ),
          ),
        ]),
      );
}

/// The preview filling its space, with the scan area on top. Tap to focus.
class _Preview extends StatelessWidget {
  const _Preview({required this.camera, required this.onTap});

  final CameraController camera;
  final void Function(TapUpDetails, Size) onTap;

  @override
  Widget build(BuildContext context) {
    final size = camera.value.previewSize ?? const Size(1280, 720);
    final portrait = Size(size.shortestSide, size.longestSide);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox.fromSize(
          size: portrait,
          child: RepaintBoundary(
            child: GestureDetector(
              onTapUp: (tap) => onTap(tap, portrait),
              child: CameraPreview(
                camera,
                child: const IgnorePointer(child: CustomPaint(painter: _ScanArea())),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dims all but the centre square, the only part of a frame searched for a plate.
class _ScanArea extends CustomPainter {
  const _ScanArea();

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width,
      height: size.width,
    ).deflate(size.width * 0.04);
    final radius = Radius.circular(size.width * 0.03);
    final hole = RRect.fromRectAndRadius(box, radius);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole)),
      Paint()..color = const Color(0x8C000000),
    );
    canvas.drawRRect(
      hole,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.006,
    );
  }

  @override
  bool shouldRepaint(_ScanArea oldDelegate) => false;
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.text, required this.hint});

  final String? text;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final found = text != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: found ? const Color(0xFF0B7A4B) : Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text ?? hint,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: found ? 21 : 15,
          fontWeight: found ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
