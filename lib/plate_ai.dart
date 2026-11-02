import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'plate_labels.dart';

/// One plate read on the phone: Bangla as on the plate, and English.
class PlateRead {
  PlateRead(this.bn, this.en, this.number, this.conf, this.box);
  final String bn; // "ঢাকা মেট্রো গ ১১-২৩৪৫"
  final String en; // "DHAKA METRO GA 11-2345"
  final String number; // "11-2345", what reads are compared on
  final double conf; // weakest digit's probability
  final List<double> box; // plate in the upright frame, 0..1: x0, y0, x1, y1
}

/// The brightness plane of a camera frame, sensor-oriented, plus how to turn it upright.
class YFrame {
  YFrame(this.bytes, this.width, this.height, this.stride, this.rotation);
  final Uint8List bytes;
  final int width, height, stride, rotation;
}

const _bnDigits = '০১২৩৪৫৬৭৮৯';
const _metroBn = 'মেট্রো';
const _minDigitConf = 0.6, _minAreaConf = 0.35;
final _heads = [districtsBn.length, 2, seriesBn.length, 10, 10, 10, 10, 10, 10];

/// Detector + reader on the phone. The models run in native code (PlateEngine.kt) on a background
/// thread, so the UI and camera preview stay smooth; no frame ever leaves the device.
class PlateAI {
  static const _ch = MethodChannel('plate_ai/engine');
  bool ready = false;
  List<double> lastMs = const []; // prepare, detector, reader

  Future<void> load() async {
    await _ch.invokeMethod('load');
    ready = true;
  }

  /// The plate in this frame, or null when none is found or the reader isn't sure.
  Future<PlateRead?> read(YFrame f) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('read', {
      'bytes': f.bytes, 'width': f.width, 'height': f.height, 'stride': f.stride, 'rotation': f.rotation,
      'detSize': detSize, 'readerH': readerH, 'readerW': readerW, 'heads': _heads,
    });
    if (r == null) return null;
    lastMs = (r['ms'] as List).cast<double>();
    if (r['picks'] == null) return null;
    return _decode((r['picks'] as List).cast<int>(), (r['confs'] as List).cast<double>(),
        (r['box'] as List).cast<double>());
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
