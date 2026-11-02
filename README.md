# plate_ai

Reads Bangladeshi number plates on the phone, in Bangla and English. It finds the plate in a camera
frame and reads it, with no server or internet needed, and no frame leaves the device.

**Android only** (minSdk 24).

## Install

```yaml
dependencies:
  plate_ai:
    git:
      url: https://github.com/mdrislam/plate_ai.git
```

The models are bundled and add about 11 MB, plus ONNX Runtime's native libraries. Release builds
need no ProGuard/R8 setup: the package ships its own keep rule.

## Use

```dart
import 'package:plate_ai/plate_ai.dart';

final ai = PlateAI();
await ai.load();

final read = await ai.read(YFrame(bytes, width, height, stride, rotation));
print(read?.en);     // DHAKA METRO GA 11-2345
print(read?.bn);     // ঢাকা মেট্রো গ ১১-২৩৪৫
print(read?.number); // 11-2345

await ai.dispose(); // frees the models
```

`read` returns null when there is no plate or the reader is unsure.

### With the camera plugin

Ask for YUV frames, and pass the first plane with the sensor orientation:

```dart
final camera = CameraController(description, ResolutionPreset.high,
    enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
await camera.initialize();
await camera.startImageStream((image) async {
  final y = image.planes[0];
  final read = await ai.read(YFrame(y.bytes, image.width, image.height, y.bytesPerRow,
      description.sensorOrientation));
  if (read != null) print(read.en);
});
```

Call `read` for every frame: while one read runs, the others return null straight away and are
dropped. A single frame can be misread, so accept a plate only when two reads have the same `number`.
[example/lib/main.dart](example/lib/main.dart) is a complete scanner that does this.

## API

| | |
|---|---|
| `PlateAI.load()` | Loads the models. Call once, before reading. |
| `PlateAI.read(YFrame)` | The plate in the frame, or null. |
| `PlateAI.dispose()` | Frees the models. `load()` can be called again later. |
| `PlateAI.ready` | Whether the models are loaded. |
| `PlateAI.lastMs` | Time of the last read in ms: prepare, detector, reader. |
| `YFrame(bytes, width, height, stride, rotation)` | One frame's brightness plane. |
| `PlateRead` | `en`, `bn`, `number`, `conf` (0..1), `box` (x0, y0, x1, y1, 0..1). |

## Limits

- Only the centre square of the frame is searched, so keep the plate near the middle.
- Reads the standard two-line Bangladeshi plate. Other formats return null or a wrong read.
- It is not perfect: dark, blurred or very angled plates can be missed or misread.
