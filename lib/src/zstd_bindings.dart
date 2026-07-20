import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Opaque zstd decompression context.
final class ZSTD_DCtx extends Opaque {}

/// Opaque zstd compression context.
final class ZSTD_CCtx extends Opaque {}

/// Input consumed by zstd streaming operations.
final class ZSTD_inBuffer extends Struct {
  external Pointer<Void> src;

  @Size()
  external int size;

  @Size()
  external int pos;
}

/// Output produced by zstd streaming operations.
final class ZSTD_outBuffer extends Struct {
  external Pointer<Void> dst;

  @Size()
  external int size;

  @Size()
  external int pos;
}

/// Keep the stream open for more input.
const int zstdEContinue = 0;

/// Flush all currently available output without ending the stream.
const int zstdEFlush = 1;

/// End the current frame.
const int zstdEEnd = 2;

/// Compression-level parameter for [ZSTD_CCtx_setParameter].
const int zstdCCompressionLevel = 100;

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

/// Creates a reusable streaming decompression context.
@Native<Pointer<ZSTD_DCtx> Function()>()
external Pointer<ZSTD_DCtx> ZSTD_createDCtx();

/// Releases a streaming decompression context.
@Native<Size Function(Pointer<ZSTD_DCtx>)>()
external int ZSTD_freeDCtx(Pointer<ZSTD_DCtx> dctx);

/// Decompresses part of a stream, updating [input] and [output] positions.
@Native<
  Size Function(
    Pointer<ZSTD_DCtx>,
    Pointer<ZSTD_outBuffer>,
    Pointer<ZSTD_inBuffer>,
  )
>()
external int ZSTD_decompressStream(
  Pointer<ZSTD_DCtx> dctx,
  Pointer<ZSTD_outBuffer> output,
  Pointer<ZSTD_inBuffer> input,
);

/// Creates a reusable streaming compression context.
@Native<Pointer<ZSTD_CCtx> Function()>()
external Pointer<ZSTD_CCtx> ZSTD_createCCtx();

/// Sets a compression context parameter.
@Native<Size Function(Pointer<ZSTD_CCtx>, Int32, Int32)>()
external int ZSTD_CCtx_setParameter(
  Pointer<ZSTD_CCtx> cctx,
  int parameter,
  int value,
);

/// Releases a streaming compression context.
@Native<Size Function(Pointer<ZSTD_CCtx>)>()
external int ZSTD_freeCCtx(Pointer<ZSTD_CCtx> cctx);

/// Compresses part of a stream using a zstd end directive.
@Native<
  Size Function(
    Pointer<ZSTD_CCtx>,
    Pointer<ZSTD_outBuffer>,
    Pointer<ZSTD_inBuffer>,
    Int32,
  )
>()
external int ZSTD_compressStream2(
  Pointer<ZSTD_CCtx> cctx,
  Pointer<ZSTD_outBuffer> output,
  Pointer<ZSTD_inBuffer> input,
  int endDirective,
);

/// Returns non-zero if [code] is an error.
@Native<Uint32 Function(Size)>()
external int ZSTD_isError(int code);

/// Returns a human-readable error description.
@Native<Pointer<Utf8> Function(Size)>()
external Pointer<Utf8> ZSTD_getErrorName(int code);
