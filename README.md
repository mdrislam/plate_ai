# plate_ai

Reads Bangladeshi number plates on the phone. Android only; no server or internet needed.

```yaml
dependencies:
  plate_ai:
    git:
      url: https://gitlab.com/kamrul09/vehicle-scan.git
      path: packages/plate_ai
```

```dart
final ai = PlateAI();
await ai.load();

// From a camera stream image: the brightness (Y) plane and the sensor orientation.
final plane = image.planes[0];
final read = await ai.read(YFrame(plane.bytes, image.width, image.height,
    plane.bytesPerRow, controller.description.sensorOrientation));

print(read?.en); // DHAKA METRO GA 11-2345
print(read?.bn); // ঢাকা মেট্রো গ ১১-২৩৪৫
```

`read` returns null when no plate is found or the reader is unsure. Send one frame at a time:
wait for each `read` to finish before sending the next.
