import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/plate_labels.dart';

export 'plate_scanner.dart';

/// The language a plate is shown in.
enum PlateLanguage { english, bangla }

/// One plate read on the phone: Bangla as on the plate, and English.
class PlateRead {
  PlateRead(this.bn, this.en, this.number, this.conf, this.box);
  /// Bangla, as on the plate: `ঢাকা মেট্রো গ ১১-২৩৪৫`. Only the number if the area line was unclear.
  final String bn;
  /// English: `DHAKA METRO GA 11-2345`. Only the number if the area line was unclear.
  final String en;
  /// The number alone, `11-2345`. Compare reads on this.
  final String number;
  /// The plate in [language]: [en] or [bn].
  String text(PlateLanguage language) => language == PlateLanguage.bangla ? bn : en;

  /// The weakest digit's probability, 0..1.
  final double conf;
  /// The plate in the upright frame, 0..1: x0, y0, x1, y1.
  final List<double> box;
}

/// A frame's brightness plane, sensor-oriented, plus how to turn it upright.
///
/// [stride] is the bytes per row; [rotation] is the camera's sensor orientation: 0, 90, 180 or 270.
class YFrame {
  YFrame(this.bytes, this.width, this.height, this.stride, this.rotation);
  final Uint8List bytes;
  final int width, height, stride, rotation;
}

const _bnDigits = '০১২৩৪৫৬৭৮৯';
const _metroBn = 'মেট্রো';
const _minDigitConf = 0.6, _minAreaConf = 0.35;
final _heads = <int>[districtsBn.length, 2, seriesBn.length, 10, 10, 10, 10, 10, 10];

/// Detector + reader on the phone. The models run in native code on a background thread, so the
/// UI and camera preview stay smooth; no frame ever leaves the device.
///
/// Call [load] once, [read] for each frame, and [dispose] when done, to free the models' memory.
class PlateAI {
  static const _ch = MethodChannel('plate_ai/engine');
  bool _busy = false;

  /// Whether [load] has finished and [read] can be used.
  bool ready = false;

  /// How long the last [read] took in milliseconds: prepare, detector, reader.
  List<double> lastMs = const [];

  /// Loads both models. Takes about a second; calling it again does nothing.
  Future<void> load() async {
    await _ch.invokeMethod('load');
    ready = true;
  }

  /// The plate in this frame, or null when none is found or the reader isn't sure.
  ///
  /// Also null, without reading, while an earlier [read] is still running, so a camera stream can
  /// call this for every frame and the frames in between are simply dropped.
  /// Throws a [StateError] before [load], and a [PlatformException] if the frame is malformed.
  Future<PlateRead?> read(YFrame f) async {
    if (!ready) throw StateError('Call load() before read()');
    if (_busy) return null;
    _busy = true;
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('read', {
        'bytes': f.bytes, 'width': f.width, 'height': f.height, 'stride': f.stride, 'rotation': f.rotation,
        'detSize': detSize, 'readerH': readerH, 'readerW': readerW, 'heads': _heads,
      });
      if (r == null) return null;
      lastMs = (r['ms'] as List).cast<double>();
      if (r['picks'] == null) return null;
      return _decode((r['picks'] as List).cast<int>(), (r['confs'] as List).cast<double>(),
          (r['box'] as List).cast<double>());
    } finally {
      _busy = false;
    }
  }

  /// Frees the models. Call [load] again to use this object afterwards.
  Future<void> dispose() async {
    ready = false;
    await _ch.invokeMethod('close');
  }

  PlateRead? _decode(List<int> picks, List<double> confs, List<double> box) {
    final digitConf = confs.sublist(3).reduce(math.min);
    if (digitConf < _minDigitConf) {
      debugPrint('plate_ai: unsure ${picks.sublist(3).join()} digit probs ${confs.sublist(3).map((c) => c.toStringAsFixed(2)).join(",")}');
      return null;
    }
    final d = picks.sublist(3).join();
    final number = '${d.substring(0, 2)}-${d.substring(2)}';
    final bnNumber = number.split('').map((c) => c == '-' ? '-' : _bnDigits[int.parse(c)]).join();
    final metro = picks[1] == 1;
    final areaSure = math.min(confs[0], confs[2]) >= _minAreaConf;
    final bn = areaSure
        ? '${districtsBn[picks[0]]}${metro ? ' $_metroBn' : ''} ${seriesBn[picks[2]]} $bnNumber'
        : bnNumber;
    final en = areaSure ? '${districtsEn[picks[0]]}${metro ? ' METRO' : ''} ${seriesEn[picks[2]]} $number' : number;
    return PlateRead(bn, en, number, digitConf, box);
  }
}
