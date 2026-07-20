# zstd_dart

Zstandard compression for Dart with one-shot and stateful streaming APIs. The bundled zstd C sources are compiled by a native build hook.

## One-shot usage

```dart
import 'dart:typed_data';

import 'package:zstd_dart/zstd_dart.dart';

final input = Uint8List.fromList([1, 2, 3, 4, 5]);
final compressed = ZstdCodec.compress(input);
final decompressed = ZstdCodec.decompress(compressed);

// The default compression level is 3. Negative fast levels through the
// bundled zstd maximum are supported and validated.
final highCompression = ZstdCodec.compress(input, level: 19);
```

## Continuous streaming

Use one encoder and one decoder for the lifetime of a continuous connection-level stream. `ZstdStreamEncoder` accepts a `level` option that defaults to 3. Each `compress` call flushes the bytes for one transport message without ending the zstd frame. Later compressed messages can depend on earlier stream state, so they are not independently decodable with `ZstdCodec.decompress` or a fresh decoder.

```dart
final encoder = ZstdStreamEncoder();
final decoder = ZstdStreamDecoder();
try {
  final firstMessage = Uint8List.fromList([1, 2, 3]);
  final secondMessage = Uint8List.fromList([4, 5, 6]);

  final firstDecoded = decoder.feed(encoder.compress(firstMessage));
  final secondDecoded = decoder.feed(encoder.compress(secondMessage));

  assert(firstDecoded.length == firstMessage.length);
  assert(secondDecoded.length == secondMessage.length);
} finally {
  encoder.dispose();
  decoder.dispose();
}
```

For a file or independently decodable frame, append the bytes from `end()` to the bytes returned by prior `compress` calls. Unlike a flush, `end()` closes the frame. Further `compress()` or `end()` calls throw `StateError` until `reset()` starts a new stream.

```dart
final fileEncoder = ZstdStreamEncoder(level: 5);
try {
  final frame = Uint8List.fromList([
    ...fileEncoder.compress(input),
    ...fileEncoder.end(),
  ]);
  final restored = ZstdCodec.decompress(frame);
  assert(restored.length == input.length);
} finally {
  fileEncoder.dispose();
}
```

Call `reset` on both sides when the protocol starts a fresh stream, such as after reconnecting. Call `dispose` when the connection closes to release the native contexts. Disposal is idempotent. Using an encoder or decoder after disposal throws `ZstdStreamException`.

The decoder's `maxDecompressedMessageSize` is a corruption guard applied separately to the output of each `feed` call. It defaults to 64 MiB and is not a total stream limit or protocol payload limit. Set it to the largest decompressed transport message your application accepts. The encoder has a matching `maxCompressedMessageSize` output guard. Exceeding either configured guard throws `ZstdStreamException`.

## Error semantics

A `ZstdStreamException` from `compress`, `end`, or `feed` poisons that instance. Further calls throw `StateError` until `reset()`. Reset starts a new stream and discards prior context, so transport-level consumers should typically drop the connection instead of continuing on the same stream.

## Runtime version

`ZstdVersion.number` returns the numeric bundled zstd runtime version, and `ZstdVersion.string` returns its dotted form.

```dart
print(ZstdVersion.number); // 10507
print(ZstdVersion.string); // 1.5.7
```

## How it works

The package includes zstd C sources under `third_party/zstd/`. Dart's native build hooks compile the required sources into a shared library through `package:native_toolchain_c`. FFI bindings in `lib/src/zstd_bindings.dart` use `@Native` annotations to link to that library automatically. The build hook does not download sources at build time.

## Requirements

- Dart SDK `>=3.10.0`
- Android, iOS, Linux, macOS, or Windows
- A C compiler available on the build host
