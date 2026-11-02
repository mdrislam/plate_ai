# plate_ai

Reads Bangladeshi number plates on the phone, in Bangla and English. It finds the plate in a camera
frame and reads it, with no server or internet needed, and no frame leaves the device.

**Android only** (minSdk 24).

## Install

```bash
flutter pub add plate_ai
```

The models are bundled and add about 11 MB, plus ONNX Runtime's native libraries. Release builds
need no ProGuard/R8 setup: the package ships its own keep rule.

## Ready-made scanner

`PlateScanner` handles the models, the camera, and pausing with the app:

```dart
PlateScanner(
  language: PlateLanguage.bangla, // or PlateLanguage.english; can change while scanning
  onPlate: (plate) => print(plate.text(PlateLanguage.bangla)),
)
```

Give it the space you want it to fill, and keep this screen in portrait. Tap the preview to focus;
the flash button is on the preview. If the camera is refused, it shows a message and a retry
button. [example/lib/main.dart](example/lib/main.dart) is a full app with a language switch.

| Option | Default | |
|---|---|---|
| `language` | `english` | Language of the plate on screen. |
| `onPlate` | | Called once for each new plate. |
| `showResult` | `true` | Turn off to show the plate your own way. |
| `confirmReads` | `2` | Reads in a row that must agree. Higher: fewer wrong plates, slower. |
| `minConfidence` | `0.75` | Reads below this are ignored. |
| `resolution` | `high` | Lower saves battery, but the plate must be closer. |
| `hint` | | Text shown until a plate is found. |

## Reading frames yourself

```dart
import 'package:plate_ai/plate_ai.dart';

final ai = PlateAI();
await ai.load();

final read = await ai.read(YFrame(bytes, width, height, stride, rotation));
print(read?.en);     // DHAKA METRO GA 11-2345
print(read?.bn);     // ঢাকা মেট্রো গ ১১-২৩৪৫
print(read?.text(PlateLanguage.bangla)); // the same, by language
print(read?.number); // 11-2345

await ai.dispose(); // frees the models
```

`read` returns null when there is no plate or the reader is unsure. While one read runs, others
return null straight away and are dropped, so calling it for every frame is safe. A single frame
can be misread, so accept a plate only when two reads have the same `number`.

## API

| | |
|---|---|
| `PlateScanner(...)` | The live scanner widget. |
| `PlateLanguage` | `english` or `bangla`. |
| `PlateAI.load()` | Loads the models. Call once, before reading. |
| `PlateAI.read(YFrame)` | The plate in the frame, or null. |
| `PlateAI.dispose()` | Frees the models. `load()` can be called again later. |
| `PlateAI.ready` | Whether the models are loaded. |
| `PlateAI.lastMs` | Time of the last read in ms: prepare, detector, reader. |
| `YFrame(bytes, width, height, stride, rotation)` | One frame's brightness plane. |
| `PlateRead` | `text(language)`, `en`, `bn`, `number`, `conf` (0..1), `box` (x0, y0, x1, y1, 0..1). |

## Limits

- Only the centre square of the frame is searched, so keep the plate inside the box.
- Reads the standard two-line Bangladeshi plate. Other formats return null or a wrong read.
- It is not perfect: dark, blurred or very angled plates can be missed or misread.
