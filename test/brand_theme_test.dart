import 'package:bloomstep/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color foreground, Color background) {
  final values = [foreground.computeLuminance(), background.computeLuminance()]
    ..sort((a, b) => b.compareTo(a));
  return (values[0] + 0.05) / (values[1] + 0.05);
}

void main() {
  test('Budlark light and dark palettes preserve readable primary roles', () {
    final light = BloomstepTheme.light();
    final dark = BloomstepTheme.dark();

    expect(BloomstepTheme.canvas, const Color(0xFFF7F4EF));
    expect(light.colorScheme.primary, BloomstepTheme.lightPrimary);
    expect(light.colorScheme.onPrimary, BloomstepTheme.lightSurface);
    expect(light.scaffoldBackgroundColor, BloomstepTheme.canvas);
    expect(
      contrast(light.colorScheme.primary, light.scaffoldBackgroundColor),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(light.colorScheme.onPrimary, light.colorScheme.primary),
      greaterThanOrEqualTo(4.5),
    );

    expect(dark.colorScheme.primary, BloomstepTheme.darkPrimary);
    expect(dark.colorScheme.onPrimary, BloomstepTheme.darkCanvas);
    expect(dark.scaffoldBackgroundColor, BloomstepTheme.darkCanvas);
    expect(
      contrast(dark.colorScheme.primary, dark.scaffoldBackgroundColor),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(dark.colorScheme.onPrimary, dark.colorScheme.primary),
      greaterThanOrEqualTo(4.5),
    );
  });
}
