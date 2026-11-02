import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plate_ai/plate_ai.dart';
import 'package:plate_ai/src/plate_labels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plate_ai/engine');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final frame = YFrame(Uint8List(4), 2, 2, 2, 0);
  Map<String, Object?> reply(double digitConf, [double areaConf = 0.9]) => {
        'picks': [0, 1, 2, 1, 1, 2, 3, 4, 5],
        'confs': [areaConf, 0.9, areaConf, for (var i = 0; i < 6; i++) digitConf],
        'box': [0.1, 0.1, 0.5, 0.5],
        'ms': [1.0, 2.0, 3.0],
      };
  void answer(Object? Function(MethodCall) f) => messenger.setMockMethodCallHandler(channel, (c) async => f(c));

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Bangla and English labels line up', () {
    expect(districtsBn.length, districtsEn.length);
    expect(seriesBn.length, seriesEn.length);
  });

  test('read before load is refused', () {
    expect(() => PlateAI().read(frame), throwsStateError);
  });

  test('a read comes back in both languages', () async {
    answer((c) => c.method == 'read' ? reply(0.9) : true);
    final ai = PlateAI();
    await ai.load();
    final plate = (await ai.read(frame))!;
    expect(plate.en, 'DHAKA METRO GA 11-2345');
    expect(plate.text(PlateLanguage.bangla), 'ঢাকা মেট্রো গ ১১-২৩৪৫');
    expect(plate.number, '11-2345');
    expect(ai.lastMs, [1.0, 2.0, 3.0]);
  });

  test('an unclear area line gives only the number', () async {
    answer((c) => c.method == 'read' ? reply(0.9, 0.1) : true);
    final ai = PlateAI();
    await ai.load();
    expect((await ai.read(frame))!.en, '11-2345');
  });

  test('unsure digits give no plate', () async {
    answer((c) => c.method == 'read' ? reply(0.3) : true);
    final ai = PlateAI();
    await ai.load();
    expect(await ai.read(frame), isNull);
  });

  test('a frame sent during a read is dropped', () async {
    var reads = 0;
    answer((c) {
      if (c.method == 'read') reads++;
      return c.method == 'read' ? reply(0.9) : true;
    });
    final ai = PlateAI();
    await ai.load();
    final results = await Future.wait([ai.read(frame), ai.read(frame)]);
    expect(reads, 1);
    expect(results[1], isNull);
  });

  test('dispose stops reads until load', () async {
    answer((c) => true);
    final ai = PlateAI();
    await ai.load();
    await ai.dispose();
    expect(() => ai.read(frame), throwsStateError);
  });

  testWidgets('the scanner offers a retry when it cannot start', (tester) async {
    answer((c) => throw PlatformException(code: 'LOAD', message: 'broken'));
    await tester.pumpWidget(const MaterialApp(home: PlateScanner()));
    await tester.pump();
    await tester.pump();
    expect(find.text('Try again'), findsOneWidget);
  });
}
