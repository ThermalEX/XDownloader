import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

class DynamicPalette {
  const DynamicPalette({this.light, this.dark});
  final ColorScheme? light, dark;
}

ColorScheme dynamicSurfaces(ColorScheme scheme, Color Function(int) neutral) {
  final dark = scheme.brightness == Brightness.dark;
  // The legacy OS surface uses tone10 in dark mode, colliding with modern
  // surfaceContainerLow. Resolve all surface roles from the same OS palette.
  return scheme.copyWith(
    surface: neutral(dark ? 6 : 98),
    surfaceDim: neutral(dark ? 6 : 87),
    surfaceBright: neutral(dark ? 24 : 98),
    surfaceContainerLowest: neutral(dark ? 4 : 100),
    surfaceContainerLow: neutral(dark ? 10 : 96),
    surfaceContainer: neutral(dark ? 12 : 94),
    surfaceContainerHigh: neutral(dark ? 17 : 92),
    surfaceContainerHighest: neutral(dark ? 22 : 90),
  );
}

Future<DynamicPalette> loadDynamicPalette() async {
  Future<DynamicPalette> read() async {
    try {
      final core = await DynamicColorPlugin.getCorePalette();
      if (core != null) {
        return DynamicPalette(
          light: dynamicSurfaces(
            core.toColorScheme(),
            (tone) => Color(core.neutral.get(tone)),
          ),
          dark: dynamicSurfaces(
            core.toColorScheme(brightness: Brightness.dark),
            (tone) => Color(core.neutral.get(tone)),
          ),
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
