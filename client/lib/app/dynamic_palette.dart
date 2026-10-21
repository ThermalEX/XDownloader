import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

class DynamicPalette {
  const DynamicPalette({this.light, this.dark});
  final ColorScheme? light, dark;
}

Future<DynamicPalette> loadDynamicPalette() async {
  Future<DynamicPalette> read() async {
    try {
      final core = await DynamicColorPlugin.getCorePalette();
      if (core != null) {
        return DynamicPalette(
          light: core.toColorScheme(),
          dark: core.toColorScheme(brightness: Brightness.dark),
        );
      }
    } catch (_) {
      /* Unsupported platforms fall back to the saved seed. */
    }
    try {
      final accent = await DynamicColorPlugin.getAccentColor();
      if (accent != null) {
        return DynamicPalette(
          light: ColorScheme.fromSeed(seedColor: accent),
          dark: ColorScheme.fromSeed(
            seedColor: accent,
            brightness: Brightness.dark,
          ),
        );
      }
    } catch (_) {
      /* Color lookup must not turn into a storage error. */
    }
    return const DynamicPalette();
  }

  return read().timeout(
    const Duration(seconds: 3),
    onTimeout: () => const DynamicPalette(),
  );
}
