import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
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
}
