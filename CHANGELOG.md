# Changelog

## 1.1.0 - 2026-07-20

- Add stateful `ZstdStreamEncoder` and `ZstdStreamDecoder` APIs for continuous zstd streams with a flush per transport message.
- Add configurable 64 MiB default guards for compressed and decompressed per-message output.
- Add `ZstdStreamException`, stream reset support, and idempotent native context disposal.
- Make stream failure states explicit: after a `ZstdStreamException`, the encoder or decoder is poisoned until `reset()`.
- Bound one-shot decompression output while supporting unknown-size frames independently of compression ratio.

## 1.0.0

- Initial release with one-shot zstd compression and decompression.
