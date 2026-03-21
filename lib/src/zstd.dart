import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:zstd_dart/src/zstd_bindings.dart';

/// Sentinel: decompressed size is unknown.
const _contentSizeUnknown = -1; // 0xFFFFFFFFFFFFFFFF as signed

/// Sentinel: error reading frame header.
const _contentSizeError = -2; // 0xFFFFFFFFFFFFFFFE as signed

/// Exception thrown when zstd operations fail.
class ZstdException implements Exception {
  /// Human-readable error description from zstd.
  final String message;

  const ZstdException(this.message);

  @override
  String toString() => 'ZstdException: $message';
}

/// Zstd compression and decompression.
class ZstdCodec {
  /// Compresses [input] using zstd at the given [level] (1-22, default 3).
  static Uint8List compress(Uint8List input, {int level = 3}) {
    final srcSize = input.length;
    final bound = ZSTD_compressBound(srcSize);

    final src = calloc<Uint8>(srcSize);
    final dst = calloc<Uint8>(bound);

    try {
      if (srcSize > 0) {
        src.asTypedList(srcSize).setAll(0, input);
      }

      final result = ZSTD_compress(
        dst.cast(),
        bound,
        src.cast(),
        srcSize,
        level,
      );

      if (ZSTD_isError(result) != 0) {
        throw ZstdException(ZSTD_getErrorName(result).toDartString());
      }

      return Uint8List.fromList(dst.asTypedList(result));
    } finally {
      calloc.free(src);
      calloc.free(dst);
    }
  }

  /// Decompresses zstd-compressed [input].
  ///
  /// Throws [ZstdException] if the input is corrupted or invalid.
  static Uint8List decompress(Uint8List input) {
    if (input.isEmpty) return Uint8List(0);

    final srcSize = input.length;
    final src = calloc<Uint8>(srcSize);

    try {
      src.asTypedList(srcSize).setAll(0, input);

      final contentSize = ZSTD_getFrameContentSize(src.cast(), srcSize);

      if (contentSize == _contentSizeError) {
        throw const ZstdException('Not valid zstd data');
      }

      // If size is unknown, use a heuristic (srcSize * 8, min 64KB).
      final dstCapacity = contentSize == _contentSizeUnknown
          ? (srcSize * 8).clamp(65536, 1 << 30)
          : contentSize;

      final dst = calloc<Uint8>(dstCapacity);

      try {
        final result = ZSTD_decompress(
          dst.cast(),
          dstCapacity,
          src.cast(),
          srcSize,
        );

        if (ZSTD_isError(result) != 0) {
          throw ZstdException(ZSTD_getErrorName(result).toDartString());
        }

        return Uint8List.fromList(dst.asTypedList(result));
      } finally {
        calloc.free(dst);
      }
    } finally {
      calloc.free(src);
    }
  }
}
