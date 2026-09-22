import 'package:flutter/material.dart';

const Color darkGray = Color(0xFF121212);
const Color surfaceGray = Color(0xFF1E1E1E);
const Color accentGold = Color(0xFFDBBA0C);

// Guess feedback colors (also reused for Tune's "Perfect Match!"/"Close!" feedback).
const Color correctGreen = Color(0xFF4CAF50);
const Color closeYellow = Color(0xFFFFC107);
const Color wrongRed = Color(0xFFF44336);

// Tune ("Adjust") analytics colors.
const Color flatPurple = Color(0xFF9C7BFF);
const Color correctWhite = Color(0xFFF5F5F5);
const Color sharpOrange = Color(0xFFFF9800);

ThemeData buildAppTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accentGold,
      brightness: Brightness.dark,
      primary: accentGold,
      surface: surfaceGray,
    ),
    scaffoldBackgroundColor: darkGray,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
  );
}
