import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Maximum compressed size for a given source size.
@Native<Size Function(Size)>()
external int ZSTD_compressBound(int srcSize);

/// Compresses [src] into [dst].
/// Returns compressed size on success, or an error code.
@Native<Size Function(Pointer<Void>, Size, Pointer<Void>, Size, Int32)>()
external int ZSTD_compress(
  Pointer<Void> dst,
  int dstCapacity,
  Pointer<Void> src,
  int srcSize,
  int compressionLevel,
);

/// Returns the decompressed content size from a zstd frame header.
/// Returns ZSTD_CONTENTSIZE_UNKNOWN or ZSTD_CONTENTSIZE_ERROR on failure.
@Native<Uint64 Function(Pointer<Void>, Size)>()
external int ZSTD_getFrameContentSize(Pointer<Void> src, int srcSize);

/// Decompresses [src] into [dst].
/// Returns decompressed size on success, or an error code.
@Native<Size Function(Pointer<Void>, Size, Pointer<Void>, Size)>()
external int ZSTD_decompress(
  Pointer<Void> dst,
  int dstCapacity,
  Pointer<Void> src,
  int srcSize,
);

/// Returns non-zero if [code] is an error.
@Native<Uint32 Function(Size)>()
external int ZSTD_isError(int code);

/// Returns a human-readable error description.
@Native<Pointer<Utf8> Function(Size)>()
external Pointer<Utf8> ZSTD_getErrorName(int code);
