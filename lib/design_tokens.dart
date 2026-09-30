/// Design tokens for the app.
///
/// The point of this file is that a number appears once. Spacing, radii and
/// the type scale were previously inline literals scattered across the
/// screens, which is how a list ends up with 14 on one row and 16 on the next
/// and nobody can say which was intended.
///
/// Everything here is a constant, so the widgets that use it stay const where
/// they can be and a change to the scale moves every screen at once.
library;

import 'package:flutter/material.dart';

/// Spacing scale. Multiples of 4, so anything divides evenly.
abstract final class Insets {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
  static const double giant = 48;

  /// Standard screen gutter.
  static const double gutter = lg;
}

/// Corner radii. Cards are softer than controls, which is the usual
/// convention: the larger the surface, the rounder it reads.
abstract final class Radii {
  static const double control = 14;
  static const double card = 20;
  static const double sheet = 24;
  static const double dialog = 28;
  static const double pill = 999;
}

/// Motion. Short and few: this is a scorekeeping app used one-handed between
/// shots, and animation competes with the numbers.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// Brand colours that sit outside the generated scheme.
///
/// The scheme is derived from [brandGreen]; these are the few roles worth
/// pinning by hand, because a scorecard app has a small set of colours that
/// carry meaning rather than decoration.
abstract final class Brand {
  /// Deep pine. The seed for the whole palette.
  static const Color green = Color(0xFF1C6248);

  /// The darker end of the scorecard hero and bottom navigation.
  static const Color forest = Color(0xFF153E32);

  /// A brighter fairway green, used only as a companion to [forest].
  static const Color fairway = Color(0xFF247A55);

  /// Brass, for the one accent a golfer reads as a result rather than a
  /// control. Used sparingly: a trophy total, a best round.
  static const Color brass = Color(0xFFC19A50);

  /// A calm neutral page background in the light theme.
  static const Color canvas = Color(0xFFF4F7F4);

  /// Near-black green for the dark theme canvas.
  static const Color canvasDark = Color(0xFF111A16);

  /// The par line on a scorecard. Deliberately quiet.
  static const Color par = Color(0xFF8A8F98);

  /// Negative space on dark surfaces, for the "no rounds yet" states.
  static const Color onSurfaceVariantDark = Color(0xFFBFC4C9);
}

/// Type scale.
///
/// No bundled font: an added typeface is a few hundred kilobytes on a phone
/// and a loading state on web, and the platform's own UI font is already
/// tuned for legibility at small sizes. What is tuned here is size, weight
/// and tracking, which is most of what makes text look designed.
abstract final class AppType {
  /// Tabular figures matter more than anything else here: scores, yardages
  /// and differentials are all columns of numbers that have to line up.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static const TextStyle score = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    fontFeatures: tabular,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static const TextStyle title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static const TextStyle body = TextStyle(fontSize: 15, height: 1.35);

  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  /// Small all-caps-ish metadata: dates, formats, "CH 12".
  static const TextStyle meta = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    fontFeatures: tabular,
  );
}
