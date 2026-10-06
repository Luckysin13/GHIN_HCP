import 'whs.dart';

/// Competition formats with their WHS Playing Handicap allowance (Rule 6.2).
///
/// The foursomes rows describe pair play and therefore carry no single-player
/// Course Handicap percentage; their strokes come from the combined Course
/// Handicaps of the two pairings instead.
enum PlayFormat {
  medal(
    displayName: 'Stroke Play',
    allowanceLabel: '95%',
    allowance: individualStrokePlayAllowance,
  ),
  individualMatch(
    displayName: 'Match Play',
    allowanceLabel: '100%',
    allowance: individualMatchPlayAllowance,
  ),
  fourBallStroke(
    displayName: 'Best Ball (stroke)',
    allowanceLabel: '85%',
    allowance: fourBallStrokePlayAllowance,
  ),
  fourBallMatch(
    displayName: 'Best Ball (match)',
    allowanceLabel: '90%',
    allowance: fourBallMatchPlayAllowance,
  ),
  foursomesStroke(
    displayName: 'Alternate Shot (stroke)',
    allowanceLabel: '50% of combined CH',
    allowance: foursomesStrokePlayAllowance,
  ),
  foursomesMatch(
    displayName: 'Alternate Shot (match)',
    allowanceLabel: '50% of CH difference',
    allowance: foursomesMatchPlayAllowance,
  ),
  best1Of4(
    displayName: 'Best Ball',
    allowanceLabel: '75%',
    allowance: best1Of4Allowance,
  ),
  best2Of4(
    displayName: 'Best 2 Ball',
    allowanceLabel: '85%',
    allowance: best2Of4Allowance,
  ),
  best3Of4(
    displayName: 'Best 3 Ball',
    allowanceLabel: '100%',
    allowance: best3Of4Allowance,
  ),
  best4Of4(
    displayName: 'Best 4 Ball',
    allowanceLabel: '100%',
    allowance: best4Of4Allowance,
  );

  final String displayName;
  final String allowanceLabel;
  final double allowance;

  const PlayFormat({
    required this.displayName,
    required this.allowanceLabel,
    required this.allowance,
  });

  /// Whether [allowance] applies to a single player's Course Handicap. The
  /// foursomes formats need both players (or both pairings) and are not in
  /// this set.
  bool get appliesToSinglePlayer =>
      this != PlayFormat.foursomesStroke && this != PlayFormat.foursomesMatch;
}