import 'dart:convert';
import 'dart:typed_data';

import 'package:zstd_dart/zstd_dart.dart';

void main() {
  final encoder = ZstdStreamEncoder();
  final decoder = ZstdStreamDecoder();

  try {
    for (final message in ['first message', 'second message']) {
      final input = Uint8List.fromList(utf8.encode(message));
      final compressed = encoder.compress(input);
      final decompressed = decoder.feed(compressed);
      print(utf8.decode(decompressed));
    }
  } finally {
    encoder.dispose();
    decoder.dispose();
  }
}
