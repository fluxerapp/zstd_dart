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

  /// Creates an exception with a human-readable [message].
  const ZstdException(this.message);

  @override
  String toString() => 'ZstdException: $message';
}

/// Exception thrown when a streaming zstd operation fails.
class ZstdStreamException extends ZstdException {
  /// Creates a streaming exception with a human-readable error message.
  const ZstdStreamException(super.message);

  @override
  String toString() => 'ZstdStreamException: $message';
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

/// Stateful encoder for a continuous zstd stream.
///
/// Each [compress] call flushes the bytes for one transport message without
/// ending the stream. The encoder context is retained until [reset] or
/// [dispose].
///
/// After a [ZstdStreamException] from [compress], the instance is poisoned and
/// rejects further use until [reset]. Reset starts a new stream and drops prior
/// context, so transport consumers should usually discard the connection instead.
class ZstdStreamEncoder {
  /// Default guard against runaway allocation after a native stream failure.
  ///
  /// This is not a protocol limit.
  static const int defaultMaxCompressedMessageSize = 64 * 1024 * 1024;

  static const int _compressionLevel = 3;
  static const int _nativeOutputSize = 64 * 1024;

  /// Maximum compressed output accepted from one input message.
  final int maxCompressedMessageSize;

  Pointer<ZSTD_CCtx> _context = nullptr;
  bool _disposed = false;
  // Native stream state is already partially advanced when compress fails.
  bool _poisoned = false;

  /// Creates an encoder with a per-message compressed output guard.
  ///
  /// [maxCompressedMessageSize] must be greater than zero.
  ZstdStreamEncoder({
    this.maxCompressedMessageSize = defaultMaxCompressedMessageSize,
  }) {
    if (maxCompressedMessageSize <= 0) {
      throw ArgumentError.value(
        maxCompressedMessageSize,
        'maxCompressedMessageSize',
        'must be greater than zero',
      );
    }
    _context = _createContext();
  }

  /// Compresses and flushes the next chunk in the current stream.
  ///
  /// After a [ZstdStreamException], this encoder is poisoned until [reset].
  Uint8List compress(Uint8List chunk) {
    _ensureUsable();

    final source = calloc<Uint8>(chunk.length);
    final nativeOutput = calloc<Uint8>(_nativeOutputSize);
    final input = calloc<ZSTD_inBuffer>();
    final output = calloc<ZSTD_outBuffer>();

    try {
      if (chunk.isNotEmpty) {
        source.asTypedList(chunk.length).setAll(0, chunk);
      }
      input.ref
        ..src = source.cast()
        ..size = chunk.length
        ..pos = 0;
      output.ref
        ..dst = nativeOutput.cast()
        ..size = _nativeOutputSize
        ..pos = 0;

      var compressed = Uint8List(_nativeOutputSize);
      var compressedLength = 0;
      var remaining = 1;

      while (input.ref.pos < input.ref.size || remaining != 0) {
        final inputPosition = input.ref.pos;
        output.ref.pos = 0;
        remaining = ZSTD_compressStream2(_context, output, input, zstdEFlush);
        if (ZSTD_isError(remaining) != 0) {
          _poisoned = true;
          throw ZstdStreamException(
            ZSTD_getErrorName(remaining).toDartString(),
          );
        }

        final produced = output.ref.pos;
        if (compressedLength + produced > maxCompressedMessageSize) {
          _poisoned = true;
          throw ZstdStreamException(
            'Compressed message exceeds the '
            '$maxCompressedMessageSize byte limit',
          );
        }

        final requiredLength = compressedLength + produced;
        if (requiredLength > compressed.length) {
          var nextLength = compressed.length * 2;
          while (nextLength < requiredLength) {
            nextLength *= 2;
          }
          if (nextLength > maxCompressedMessageSize) {
            nextLength = maxCompressedMessageSize;
          }
          final grown = Uint8List(nextLength);
          grown.setRange(0, compressedLength, compressed);
          compressed = grown;
        }
        if (produced > 0) {
          compressed.setRange(
            compressedLength,
            requiredLength,
            nativeOutput.asTypedList(produced),
          );
          compressedLength = requiredLength;
        }

        if (input.ref.pos == inputPosition &&
            produced == 0 &&
            (input.ref.pos < input.ref.size || remaining != 0)) {
          _poisoned = true;
          throw const ZstdStreamException('Encoder made no progress');
        }
      }

      return Uint8List.sublistView(compressed, 0, compressedLength);
    } finally {
      calloc.free(output);
      calloc.free(input);
      calloc.free(nativeOutput);
      calloc.free(source);
    }
  }

  /// Replaces the encoder context with a fresh stream.
  ///
  /// Clears a prior poison state. Prior stream context is discarded.
  void reset() {
    if (_disposed) {
      throw const ZstdStreamException('Encoder has been disposed');
    }
    final replacement = _createContext();
    ZSTD_freeCCtx(_context);
    _context = replacement;
    _poisoned = false;
  }

  /// Releases the native encoder context.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    ZSTD_freeCCtx(_context);
    _context = nullptr;
  }

  static Pointer<ZSTD_CCtx> _createContext() {
    final context = ZSTD_createCCtx();
    if (context == nullptr) {
      throw const ZstdStreamException('Failed to create compression context');
    }
    final result = ZSTD_CCtx_setParameter(
      context,
      zstdCCompressionLevel,
      _compressionLevel,
    );
    if (ZSTD_isError(result) != 0) {
      final message = ZSTD_getErrorName(result).toDartString();
      ZSTD_freeCCtx(context);
      throw ZstdStreamException(message);
    }
    return context;
  }

  void _ensureUsable() {
    if (_disposed) {
      throw const ZstdStreamException('Encoder has been disposed');
    }
    if (_poisoned) {
      throw StateError(
        'ZstdStreamEncoder is poisoned after a failed compress; '
        'call reset() to start a new stream',
      );
    }
  }
}

/// Stateful decoder for a continuous zstd stream.
///
/// Each [feed] call returns only the bytes produced from that compressed
/// chunk. The decoder context is retained until [reset] or [dispose].
///
/// After a [ZstdStreamException] from [feed], the instance is poisoned and
/// rejects further use until [reset]. Reset starts a new stream and drops prior
/// context, so transport consumers should usually discard the connection instead.
class ZstdStreamDecoder {
  /// Default guard against runaway allocation from corrupted stream data.
  ///
  /// This is not a protocol limit. Legitimate outbound payloads are unbounded.
  static const int defaultMaxDecompressedMessageSize = 64 * 1024 * 1024;

  static const int _nativeOutputSize = 64 * 1024;

  /// Maximum output accepted from one compressed message.
  final int maxDecompressedMessageSize;

  Pointer<ZSTD_DCtx> _context = nullptr;
  bool _disposed = false;
  // Native stream state is already partially advanced when feed fails.
  bool _poisoned = false;

  /// Creates a decoder with a per-message decompressed output guard.
  ///
  /// [maxDecompressedMessageSize] must be greater than zero.
  ZstdStreamDecoder({
    this.maxDecompressedMessageSize = defaultMaxDecompressedMessageSize,
  }) {
    if (maxDecompressedMessageSize <= 0) {
      throw ArgumentError.value(
        maxDecompressedMessageSize,
        'maxDecompressedMessageSize',
        'must be greater than zero',
      );
    }
    _context = _createContext();
  }

  /// Decompresses the next chunk from the current stream.
  ///
  /// Throws [ZstdStreamException] for invalid input, decoder failures, or
  /// output larger than [maxDecompressedMessageSize].
  ///
  /// After a [ZstdStreamException], this decoder is poisoned until [reset].
  Uint8List feed(Uint8List chunk) {
    _ensureUsable();
    if (chunk.isEmpty) {
      return Uint8List(0);
    }

    final source = calloc<Uint8>(chunk.length);
    final nativeOutput = calloc<Uint8>(_nativeOutputSize);
    final input = calloc<ZSTD_inBuffer>();
    final output = calloc<ZSTD_outBuffer>();

    try {
      source.asTypedList(chunk.length).setAll(0, chunk);
      input.ref
        ..src = source.cast()
        ..size = chunk.length
        ..pos = 0;
      output.ref
        ..dst = nativeOutput.cast()
        ..size = _nativeOutputSize
        ..pos = 0;

      var decoded = Uint8List(_nativeOutputSize);
      var decodedLength = 0;

      while (input.ref.pos < input.ref.size ||
          output.ref.pos == _nativeOutputSize) {
        final inputPosition = input.ref.pos;
        output.ref.pos = 0;

        final result = ZSTD_decompressStream(_context, output, input);
        if (ZSTD_isError(result) != 0) {
          _poisoned = true;
          throw ZstdStreamException(ZSTD_getErrorName(result).toDartString());
        }

        final produced = output.ref.pos;
        if (decodedLength + produced > maxDecompressedMessageSize) {
          _poisoned = true;
          throw ZstdStreamException(
            'Decompressed message exceeds the '
            '$maxDecompressedMessageSize byte limit',
          );
        }

        final requiredLength = decodedLength + produced;
        if (requiredLength > decoded.length) {
          var nextLength = decoded.length * 2;
          while (nextLength < requiredLength) {
            nextLength *= 2;
          }
          if (nextLength > maxDecompressedMessageSize) {
            nextLength = maxDecompressedMessageSize;
          }
          final grown = Uint8List(nextLength);
          grown.setRange(0, decodedLength, decoded);
          decoded = grown;
        }
        if (produced > 0) {
          decoded.setRange(
            decodedLength,
            requiredLength,
            nativeOutput.asTypedList(produced),
          );
          decodedLength = requiredLength;
        }

        if (input.ref.pos == inputPosition &&
            produced == 0 &&
            input.ref.pos < input.ref.size) {
          _poisoned = true;
          throw const ZstdStreamException('Decoder made no progress');
        }
      }

      return Uint8List.sublistView(decoded, 0, decodedLength);
    } finally {
      calloc.free(output);
      calloc.free(input);
      calloc.free(nativeOutput);
      calloc.free(source);
    }
  }

  /// Replaces the decoder context with a fresh stream.
  ///
  /// Clears a prior poison state. Prior stream context is discarded.
  void reset() {
    if (_disposed) {
      throw const ZstdStreamException('Decoder has been disposed');
    }
    final replacement = _createContext();
    ZSTD_freeDCtx(_context);
    _context = replacement;
    _poisoned = false;
  }

  /// Releases the native decoder context.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    ZSTD_freeDCtx(_context);
    _context = nullptr;
  }

  static Pointer<ZSTD_DCtx> _createContext() {
    final context = ZSTD_createDCtx();
    if (context == nullptr) {
      throw const ZstdStreamException('Failed to create decompression context');
    }
    return context;
  }

  void _ensureUsable() {
    if (_disposed) {
      throw const ZstdStreamException('Decoder has been disposed');
    }
    if (_poisoned) {
      throw StateError(
        'ZstdStreamDecoder is poisoned after a failed feed; '
        'call reset() to start a new stream',
      );
    }
  }
}
