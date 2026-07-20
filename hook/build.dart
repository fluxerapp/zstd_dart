import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final packageRoot = input.packageRoot.toFilePath();
    final sources = _collectSources(packageRoot, [
      'third_party/zstd/lib/common',
      'third_party/zstd/lib/compress',
      'third_party/zstd/lib/decompress',
    ]);

    final builder = CBuilder.library(
      name: 'zstd',
      assetName: 'src/zstd_bindings.dart',
      sources: sources,
      defines: {
        'ZSTD_MULTITHREAD': '0',
        'ZSTD_LEGACY_SUPPORT': '0',
        'ZSTD_DISABLE_ASM': '1',
        // MSVC needs dllexport; without it the DLL exports nothing and dart:ffi lookups fail.
        if (input.config.code.targetOS == OS.windows) 'ZSTD_DLL_EXPORT': '1',
      },
    );

    await builder.run(input: input, output: output);
  });
}

List<String> _collectSources(String packageRoot, List<String> dirs) {
  final sources = <String>[];
  for (final dir in dirs) {
    final directory = Directory('$packageRoot/$dir');
    for (final file in directory.listSync()) {
      if (file is File && file.path.endsWith('.c')) {
        // Return path relative to package root.
        sources.add('$dir/${file.uri.pathSegments.last}');
      }
    }
  }
  return sources;
}
