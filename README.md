# zstd_dart

Zstd compression and decompression for Dart, using native build hooks to compile the [zstd C library](https://github.com/facebook/zstd) at build time via `package:native_toolchain_c`.

## Usage

```dart
import 'dart:typed_data';
import 'package:zstd_dart/zstd_dart.dart';

// Compress
final input = Uint8List.fromList([1, 2, 3, 4, 5]);
final compressed = ZstdCodec.compress(input);

// Decompress
final decompressed = ZstdCodec.decompress(compressed);

// Custom compression level (1-22, default 3)
final highCompression = ZstdCodec.compress(input, level: 19);
```

## How it works

The package uses Dart's native build hooks (`package:hooks`) to compile zstd C sources from `third_party/zstd/` into a shared library at build time. FFI bindings in `lib/src/zstd_bindings.dart` use `@Native` annotations to link to the compiled library automatically.

## Requirements

- Dart SDK `>=3.10.0`
- A C compiler available on the build host (provided by the Dart/Flutter toolchain)
