import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ffi/ffi.dart';
import 'package:zstd_dart/src/zstd_bindings.dart';
import 'package:zstd_dart/zstd_dart.dart';

void main() {
  group('ZstdCodec', () {
    group('compress + decompress round-trip', () {
      test('empty input', () {
        final input = Uint8List(0);
        final compressed = ZstdCodec.compress(input);
        final decompressed = ZstdCodec.decompress(compressed);
        expect(decompressed, equals(input));
      });

      test('small input', () {
        final input = Uint8List.fromList([1, 2, 3, 4, 5]);
        final compressed = ZstdCodec.compress(input);
        final decompressed = ZstdCodec.decompress(compressed);
        expect(decompressed, equals(input));
      });

      test('repeated data compresses well', () {
        final input = Uint8List(10000);
        for (var i = 0; i < input.length; i++) {
          input[i] = i % 256;
        }
        final compressed = ZstdCodec.compress(input);
        expect(compressed.length, lessThan(input.length));
        final decompressed = ZstdCodec.decompress(compressed);
        expect(decompressed, equals(input));
      });

      test('random data', () {
        final random = Random(42);
        final input = Uint8List(8192);
        for (var i = 0; i < input.length; i++) {
          input[i] = random.nextInt(256);
        }
        final compressed = ZstdCodec.compress(input);
        final decompressed = ZstdCodec.decompress(compressed);
        expect(decompressed, equals(input));
      });

      test('large input (1MB)', () {
        final input = Uint8List(1024 * 1024);
        for (var i = 0; i < input.length; i++) {
          input[i] = i % 256;
        }
        final compressed = ZstdCodec.compress(input);
        final decompressed = ZstdCodec.decompress(compressed);
        expect(decompressed, equals(input));
      });
    });

    group('bounded decompression', () {
      test('rejects advertised content size above the output guard', () {
        final input = Uint8List(8192);
        final compressed = ZstdCodec.compress(input);

        expect(_frameContentSize(compressed), input.length);
        expect(
          () => ZstdCodec.decompress(compressed, maxOutputBytes: 1024),
          throwsA(isA<ZstdException>()),
        );
      });

      test('decodes a high-ratio frame with unknown content size', () {
        final input = Uint8List(512 * 1024);
        final compressed = _compressUnknownContentSize(input);

        expect(_frameContentSize(compressed), _zstdContentSizeUnknown);
        expect(compressed.length * 8, lessThan(input.length));
        expect(ZstdCodec.decompress(compressed), equals(input));
      });

      test(
        'rejects a truncated unknown-size frame but accepts it complete',
        () {
          final input = Uint8List(128 * 1024);
          final compressed = _compressUnknownContentSize(input);
          final truncated = Uint8List.sublistView(
            compressed,
            0,
            compressed.length - 1,
          );

          expect(_frameContentSize(compressed), _zstdContentSizeUnknown);
          expect(ZstdCodec.decompress(compressed), equals(input));
          expect(
            () => ZstdCodec.decompress(truncated),
            throwsA(
              isA<ZstdException>().having(
                (error) => error.message,
                'message',
                equals('Truncated zstd frame'),
              ),
            ),
          );
        },
      );
    });

    group('compression levels', () {
      test('level 1 (fast)', () {
        final input = Uint8List.fromList(List.generate(1000, (i) => i % 256));
        final compressed = ZstdCodec.compress(input, level: 1);
        final decompressed = ZstdCodec.decompress(compressed);
        expect(decompressed, equals(input));
      });

      test('level 22 (max)', () {
        final input = Uint8List.fromList(List.generate(1000, (i) => i % 256));
        final compressed = ZstdCodec.compress(input, level: 22);
        final decompressed = ZstdCodec.decompress(compressed);
        expect(decompressed, equals(input));
      });

      test('higher level produces smaller or equal output', () {
        final input = Uint8List(10000);
        for (var i = 0; i < input.length; i++) {
          input[i] = i % 256;
        }
        final fast = ZstdCodec.compress(input, level: 1);
        final max = ZstdCodec.compress(input, level: 22);
        expect(max.length, lessThanOrEqualTo(fast.length));
      });
      test('validates the native compression-level bounds', () {
        final minimum = ZSTD_minCLevel();
        final maximum = ZSTD_maxCLevel();
        final input = Uint8List.fromList([1, 2, 3, 4]);

        for (final level in [minimum, maximum]) {
          final compressed = ZstdCodec.compress(input, level: level);
          expect(ZstdCodec.decompress(compressed), equals(input));
        }
        expect(
          () => ZstdCodec.compress(input, level: minimum - 1),
          throwsArgumentError,
        );
        expect(
          () => ZstdCodec.compress(input, level: maximum + 1),
          throwsArgumentError,
        );
      });
    });

    group('error handling', () {
      test('corrupted data throws ZstdException', () {
        final corrupted = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
        expect(
          () => ZstdCodec.decompress(corrupted),
          throwsA(isA<ZstdException>()),
        );
      });

      test('truncated compressed data throws ZstdException', () {
        final input = Uint8List.fromList([1, 2, 3, 4, 5]);
        final compressed = ZstdCodec.compress(input);
        // Truncate the compressed data
        final truncated = Uint8List.sublistView(
          compressed,
          0,
          compressed.length ~/ 2,
        );
        expect(
          () => ZstdCodec.decompress(truncated),
          throwsA(isA<ZstdException>()),
        );
      });

      test('ZstdException contains error message', () {
        final corrupted = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
        try {
          ZstdCodec.decompress(corrupted);
          fail('Expected ZstdException');
        } on ZstdException catch (e) {
          expect(e.message, isNotEmpty);
          expect(e.toString(), contains('ZstdException'));
        }
      });
    });
  });

  group('ZstdVersion', () {
    test('matches the bundled zstd version', () {
      expect(ZstdVersion.number, greaterThanOrEqualTo(10000));
      expect(ZstdVersion.number, 10507);
      expect(ZstdVersion.string, '1.5.7');
    });
  });

  group('Zstd streaming', () {
    test('validates encoder compression-level bounds', () {
      final minimum = ZSTD_minCLevel();
      final maximum = ZSTD_maxCLevel();

      for (final level in [minimum, maximum]) {
        final encoder = ZstdStreamEncoder(level: level);
        addTearDown(encoder.dispose);
        expect(encoder.compress(Uint8List.fromList([1, 2, 3])), isNotEmpty);
      }
      expect(() => ZstdStreamEncoder(level: minimum - 1), throwsArgumentError);
      expect(() => ZstdStreamEncoder(level: maximum + 1), throwsArgumentError);
    });

    test('end closes a frame for one-shot decompression', () {
      final encoder = ZstdStreamEncoder();
      addTearDown(encoder.dispose);
      final input = Uint8List.fromList(
        List<int>.generate(200000, (index) => index % 251),
      );

      final flushed = encoder.compress(input);
      expect(
        () => ZstdCodec.decompress(flushed),
        throwsA(isA<ZstdException>()),
      );

      final ending = encoder.end();
      final frame = Uint8List(flushed.length + ending.length)
        ..setRange(0, flushed.length, flushed)
        ..setRange(flushed.length, flushed.length + ending.length, ending);
      expect(ZstdCodec.decompress(frame), equals(input));
    });

    test('compress and end reject use after end', () {
      final encoder = ZstdStreamEncoder();
      addTearDown(encoder.dispose);

      encoder.compress(Uint8List.fromList([1, 2, 3]));
      encoder.end();

      for (final operation in [
        () => encoder.compress(Uint8List.fromList([4])),
        encoder.end,
      ]) {
        expect(
          operation,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('reset()'),
            ),
          ),
        );
      }
    });

    test('end failure poisons the encoder until reset', () {
      final encoder = ZstdStreamEncoder(maxCompressedMessageSize: 1);
      addTearDown(encoder.dispose);

      expect(encoder.end, throwsA(isA<ZstdStreamException>()));
      expect(
        encoder.end,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('reset()'),
          ),
        ),
      );

      encoder.reset();
      expect(encoder.end, throwsA(isA<ZstdStreamException>()));
    });

    test('reset recovers an ended encoder', () {
      final encoder = ZstdStreamEncoder();
      addTearDown(encoder.dispose);

      encoder.compress(Uint8List.fromList([1, 2, 3]));
      encoder.end();
      encoder.reset();

      final input = Uint8List.fromList([9, 8, 7, 6]);
      final flushed = encoder.compress(input);
      final ending = encoder.end();
      final frame = Uint8List(flushed.length + ending.length)
        ..setRange(0, flushed.length, flushed)
        ..setRange(flushed.length, flushed.length + ending.length, ending);
      expect(ZstdCodec.decompress(frame), equals(input));
    });

    test('retains context across flushed WebSocket messages', () {
      final encoder = ZstdStreamEncoder();
      final decoder = ZstdStreamDecoder();
      addTearDown(encoder.dispose);
      addTearDown(decoder.dispose);

      final first = Uint8List.fromList(
        List<int>.generate(200000, (index) => index % 251),
      );
      final second = Uint8List.fromList(
        List<int>.generate(150000, (index) => (index + 37) % 251),
      );
      final firstChunk = encoder.compress(first);
      final secondChunk = encoder.compress(second);

      expect(decoder.feed(firstChunk), equals(first));
      expect(decoder.feed(secondChunk), equals(second));
    });

    test('one-shot decoding cannot decode a later stream chunk', () {
      final encoder = ZstdStreamEncoder();
      addTearDown(encoder.dispose);

      encoder.compress(Uint8List(100000));
      final secondChunk = encoder.compress(Uint8List(100000));

      expect(
        () => ZstdCodec.decompress(secondChunk),
        throwsA(isA<ZstdException>()),
      );
    });

    test('reset starts fresh encoder and decoder contexts', () {
      final encoder = ZstdStreamEncoder();
      final decoder = ZstdStreamDecoder();
      addTearDown(encoder.dispose);
      addTearDown(decoder.dispose);

      final first = Uint8List.fromList(List<int>.filled(10000, 7));
      final second = Uint8List.fromList(List<int>.filled(12000, 11));
      expect(decoder.feed(encoder.compress(first)), equals(first));

      encoder.reset();
      decoder.reset();

      expect(decoder.feed(encoder.compress(second)), equals(second));
    });

    test('accepts more than 10 MiB with the default corruption guard', () {
      final encoder = ZstdStreamEncoder();
      final decoder = ZstdStreamDecoder();
      addTearDown(encoder.dispose);
      addTearDown(decoder.dispose);

      final payload = Uint8List(10 * 1024 * 1024 + 1)
        ..fillRange(0, 10 * 1024 * 1024 + 1, 42);
      final chunk = encoder.compress(payload);

      expect(decoder.feed(chunk), equals(payload));
    });

    test('rejects output above a configured corruption guard', () {
      const limit = 1024 * 1024;
      final encoder = ZstdStreamEncoder();
      final decoder = ZstdStreamDecoder(maxDecompressedMessageSize: limit);
      addTearDown(encoder.dispose);
      addTearDown(decoder.dispose);

      final chunk = encoder.compress(Uint8List(limit + 1));

      expect(() => decoder.feed(chunk), throwsA(isA<ZstdStreamException>()));
    });

    test('decoder poison rejects further feed until reset', () {
      final encoder = ZstdStreamEncoder();
      final decoder = ZstdStreamDecoder();
      addTearDown(encoder.dispose);
      addTearDown(decoder.dispose);

      // Garbage is not a valid zstd stream and fails inside feed.
      expect(
        () => decoder.feed(Uint8List.fromList([0x01, 0x02, 0x03, 0x04])),
        throwsA(isA<ZstdStreamException>()),
      );
      expect(
        () => decoder.feed(Uint8List.fromList([0x05])),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('reset()'),
          ),
        ),
      );

      decoder.reset();
      final payload = Uint8List.fromList([9, 8, 7, 6]);
      expect(decoder.feed(encoder.compress(payload)), equals(payload));
    });

    test('decoder poison from corruption guard then dispose', () {
      const limit = 1024 * 1024;
      final encoder = ZstdStreamEncoder();
      final decoder = ZstdStreamDecoder(maxDecompressedMessageSize: limit);
      addTearDown(encoder.dispose);

      final chunk = encoder.compress(Uint8List(limit + 1));
      expect(() => decoder.feed(chunk), throwsA(isA<ZstdStreamException>()));
      expect(
        () => decoder.feed(Uint8List.fromList([1])),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('reset()'),
          ),
        ),
      );

      // dispose must remain safe after poison without requiring reset first.
      expect(decoder.dispose, returnsNormally);
    });

    test('encoder poison from compressed size guard until reset', () {
      // Tiny guard forces a size rejection on any non-empty compress output.
      // maxCompressedMessageSize is final, so recovery uses a second encoder
      // only to prove reset cleared poison; the guard itself stays at 1 byte.
      final encoder = ZstdStreamEncoder(maxCompressedMessageSize: 1);
      addTearDown(encoder.dispose);

      expect(
        () => encoder.compress(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
        throwsA(isA<ZstdStreamException>()),
      );
      expect(
        () => encoder.compress(Uint8List.fromList([1])),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('reset()'),
          ),
        ),
      );

      encoder.reset();
      // Same instance is usable again; the 1-byte guard still rejects output.
      expect(
        () => encoder.compress(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
        throwsA(isA<ZstdStreamException>()),
      );

      // Fresh encoder with a normal guard proves the stream path still works.
      final recovered = ZstdStreamEncoder();
      final decoder = ZstdStreamDecoder();
      addTearDown(recovered.dispose);
      addTearDown(decoder.dispose);
      final payload = Uint8List.fromList([4, 3, 2, 1]);
      expect(decoder.feed(recovered.compress(payload)), equals(payload));
    });

    test('encoder dispose after poison does not throw', () {
      final encoder = ZstdStreamEncoder(maxCompressedMessageSize: 1);

      expect(
        () => encoder.compress(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
        throwsA(isA<ZstdStreamException>()),
      );
      expect(encoder.dispose, returnsNormally);
    });

    test('empty decoder feed does not poison', () {
      final encoder = ZstdStreamEncoder();
      final decoder = ZstdStreamDecoder();
      addTearDown(encoder.dispose);
      addTearDown(decoder.dispose);

      expect(decoder.feed(Uint8List(0)), isEmpty);
      final payload = Uint8List.fromList([1, 2, 3]);
      expect(decoder.feed(encoder.compress(payload)), equals(payload));
    });
  });
}

const _zstdContentSizeUnknown = -1;
const _zstdCContentSizeFlag = 200;

int _frameContentSize(Uint8List frame) {
  final source = calloc<Uint8>(frame.length);
  try {
    source.asTypedList(frame.length).setAll(0, frame);
    return ZSTD_getFrameContentSize(source.cast(), frame.length);
  } finally {
    calloc.free(source);
  }
}

Uint8List _compressUnknownContentSize(Uint8List input) {
  final context = ZSTD_createCCtx();
  if (context == nullptr) {
    throw StateError('Failed to create fixture compression context');
  }

  final source = calloc<Uint8>(input.length);
  final destinationCapacity = ZSTD_compressBound(input.length);
  final destination = calloc<Uint8>(destinationCapacity);
  final inputBuffer = calloc<ZSTD_inBuffer>();
  final outputBuffer = calloc<ZSTD_outBuffer>();

  try {
    final parameterResult = ZSTD_CCtx_setParameter(
      context,
      _zstdCContentSizeFlag,
      0,
    );
    if (ZSTD_isError(parameterResult) != 0) {
      throw StateError(ZSTD_getErrorName(parameterResult).toDartString());
    }

    source.asTypedList(input.length).setAll(0, input);
    inputBuffer.ref
      ..src = source.cast()
      ..size = input.length
      ..pos = 0;
    outputBuffer.ref
      ..dst = destination.cast()
      ..size = destinationCapacity
      ..pos = 0;

    var remaining = 1;
    while (remaining != 0) {
      final inputPosition = inputBuffer.ref.pos;
      final outputPosition = outputBuffer.ref.pos;
      remaining = ZSTD_compressStream2(
        context,
        outputBuffer,
        inputBuffer,
        zstdEEnd,
      );
      if (ZSTD_isError(remaining) != 0) {
        throw StateError(ZSTD_getErrorName(remaining).toDartString());
      }
      if (inputBuffer.ref.pos == inputPosition &&
          outputBuffer.ref.pos == outputPosition) {
        throw StateError('Fixture compressor made no progress');
      }
      if (outputBuffer.ref.pos == outputBuffer.ref.size && remaining != 0) {
        throw StateError('Fixture compression buffer is too small');
      }
    }

    return Uint8List.fromList(destination.asTypedList(outputBuffer.ref.pos));
  } finally {
    calloc.free(outputBuffer);
    calloc.free(inputBuffer);
    calloc.free(destination);
    calloc.free(source);
    ZSTD_freeCCtx(context);
  }
}
