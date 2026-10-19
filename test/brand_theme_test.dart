import 'package:budlark/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color foreground, Color background) {
  final values = [foreground.computeLuminance(), background.computeLuminance()]
    ..sort((a, b) => b.compareTo(a));
  return (values[0] + 0.05) / (values[1] + 0.05);
}

void main() {
  test('Budlark light and dark palettes preserve readable primary roles', () {
    final light = BudlarkTheme.light();
    final dark = BudlarkTheme.dark();

    expect(BudlarkTheme.canvas, const Color(0xFFF7F4EF));
    expect(light.colorScheme.primary, BudlarkTheme.lightPrimary);
    expect(light.colorScheme.onPrimary, BudlarkTheme.lightSurface);
    expect(light.scaffoldBackgroundColor, BudlarkTheme.canvas);
    expect(
      contrast(light.colorScheme.primary, light.scaffoldBackgroundColor),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(light.colorScheme.onPrimary, light.colorScheme.primary),
      greaterThanOrEqualTo(4.5),
    );

    expect(dark.colorScheme.primary, BudlarkTheme.darkPrimary);
    expect(dark.colorScheme.onPrimary, BudlarkTheme.darkCanvas);
    expect(dark.scaffoldBackgroundColor, BudlarkTheme.darkCanvas);
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
