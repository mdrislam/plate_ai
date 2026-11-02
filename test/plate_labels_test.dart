import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plate_ai/plate_ai.dart';
import 'package:plate_ai/plate_labels.dart';

void main() {
  test('Bangla and English labels line up', () {
    expect(districtsBn.length, districtsEn.length);
    expect(seriesBn.length, seriesEn.length);
  });

  test('read before load is refused', () {
    final frame = YFrame(Uint8List(4), 2, 2, 2, 0);
    expect(() => PlateAI().read(frame), throwsStateError);
  });
}
