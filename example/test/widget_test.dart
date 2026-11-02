import 'package:flutter_test/flutter_test.dart';
import 'package:plate_ai/plate_ai.dart';

void main() {
  test('a plate reads in the chosen language', () {
    final plate = PlateRead('ক ১১-২৩৪৫', 'KA 11-2345', '11-2345', 1, const [0, 0, 1, 1]);
    expect(plate.text(PlateLanguage.bangla), 'ক ১১-২৩৪৫');
    expect(plate.text(PlateLanguage.english), 'KA 11-2345');
  });
}
