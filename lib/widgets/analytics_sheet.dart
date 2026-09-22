import 'package:flutter/material.dart';

import '../stats_store.dart';
import '../theme.dart';

const double _barHeight = 22;

/// Bottom sheet showing Tune (flat/correct/sharp) accuracy breakdowns. Direct port of the
/// Android app's TuneAnalyticsSheet.
class TuneAnalyticsSheet extends StatefulWidget {
  const TuneAnalyticsSheet({super.key});

  @override
  State<TuneAnalyticsSheet> createState() => _TuneAnalyticsSheetState();
}

class _TuneAnalyticsSheetState extends State<TuneAnalyticsSheet> {
  BreakdownMode _mode = BreakdownMode.overall;
  late Future<List<TuneStatsRow>> _rows;

  @override
  void initState() {
    super.initState();
    _rows = StatsStore.tuneRows(_mode);
  }

  void _setMode(BreakdownMode mode) {
    setState(() {
      _mode = mode;
      _rows = StatsStore.tuneRows(mode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _AnalyticsScaffold(
      title: 'Adjust Analytics',
      legend: const [('Flat', flatPurple), ('Correct', correctWhite), ('Sharp', sharpOrange)],
      mode: _mode,
      onModeChange: _setMode,
      body: FutureBuilder<List<TuneStatsRow>>(
        future: _rows,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const [];
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              final total = row.flat + row.correct + row.sharp;
              final fractions = total > 0
                  ? [row.flat / total, row.correct / total, row.sharp / total]
                  : [0.0, 0.0, 0.0];
              return _StatRow(
                label: row.label,
                fractions: fractions,
                colors: const [flatPurple, correctWhite, sharpOrange],
                percentTexts: [
                  _pctLabel(row.flat, total),
                  _pctLabel(row.correct, total),
                  _pctLabel(row.sharp, total),
                ],
                belowTexts: [
                  row.flat > 0 ? 'Avg: ${row.avgFlatCents.round()}c' : null,
                  null,
                  row.sharp > 0 ? 'Avg: ${row.avgSharpCents.round()}c' : null,
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Bottom sheet showing Guess (correct/close/wrong) accuracy breakdowns. Direct port of the
/// Android app's GuessAnalyticsSheet.
class GuessAnalyticsSheet extends StatefulWidget {
  const GuessAnalyticsSheet({super.key});

  @override
  State<GuessAnalyticsSheet> createState() => _GuessAnalyticsSheetState();
}

class _GuessAnalyticsSheetState extends State<GuessAnalyticsSheet> {
  BreakdownMode _mode = BreakdownMode.overall;
  late Future<List<GuessStatsRow>> _rows;

  @override
  void initState() {
    super.initState();
    _rows = StatsStore.guessRows(_mode);
  }

  void _setMode(BreakdownMode mode) {
    setState(() {
      _mode = mode;
      _rows = StatsStore.guessRows(mode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _AnalyticsScaffold(
      title: 'Guess Analytics',
      legend: const [('Correct', correctGreen), ('Close', closeYellow), ('Wrong', wrongRed)],
      mode: _mode,
      onModeChange: _setMode,
      body: FutureBuilder<List<GuessStatsRow>>(
        future: _rows,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const [];
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              final total = row.correct + row.close + row.wrong;
              final fractions = total > 0
                  ? [row.correct / total, row.close / total, row.wrong / total]
                  : [0.0, 0.0, 0.0];
              return _StatRow(
                label: row.label,
                fractions: fractions,
                colors: const [correctGreen, closeYellow, wrongRed],
                percentTexts: [
                  _pctLabel(row.correct, total),
                  _pctLabel(row.close, total),
                  _pctLabel(row.wrong, total),
                ],
                belowTexts: null,
              );
            },
          );
        },
      ),
    );
  }
}

class _AnalyticsScaffold extends StatelessWidget {
  final String title;
  final List<(String, Color)> legend;
  final BreakdownMode mode;
  final ValueChanged<BreakdownMode> onModeChange;
  final Widget body;

  const _AnalyticsScaffold({
    required this.title,
    required this.legend,
    required this.mode,
    required this.onModeChange,
    required this.body,
  });

  static const _options = [
    (BreakdownMode.overall, 'Overall'),
    (BreakdownMode.byTone, 'By Letter'),
    (BreakdownMode.byOctave, 'By Octave'),
    (BreakdownMode.byToneOctave, 'By Letter+Octave'),
  ];

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Container(
        color: surfaceGray,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 14,
                children: [
                  for (final (label, color) in legend)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 4),
                        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (value, label) in _options)
                    _breakdownChip(label, mode == value, () => onModeChange(value)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _breakdownChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: selected ? accentGold : darkGray, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(color: selected ? darkGray : Colors.white, fontSize: 11)),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final List<double> fractions;
  final List<Color> colors;
  final List<String?> percentTexts;
  final List<String?>? belowTexts;

  const _StatRow({
    required this.label,
    required this.fractions,
    required this.colors,
    required this.percentTexts,
    required this.belowTexts,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          _MidpointLabels(fractions: fractions, texts: percentTexts, colors: colors),
          SizedBox(
            height: _barHeight,
            child: Row(
              children: [
                for (var i = 0; i < fractions.length; i++)
                  if (fractions[i] > 0)
                    Expanded(flex: (fractions[i] * 10000).round(), child: Container(color: colors[i]))
                  else
                    const SizedBox.shrink(),
              ],
            ),
          ),
          if (belowTexts != null)
            _MidpointLabels(fractions: fractions, texts: belowTexts!, colors: colors, fontSize: 10),
        ],
      ),
    );
  }
}

/// Places each non-null label centered over its segment's horizontal midpoint, but clamps the
/// label's x-offset to stay within the bar's own bounds so a thin segment's text can never spill
/// past the screen edge. Port of the Android app's custom MidpointLabels Layout.
class _MidpointLabels extends StatelessWidget {
  final List<double> fractions;
  final List<String?> texts;
  final List<Color> colors;
  final double fontSize;

  const _MidpointLabels({required this.fractions, required this.texts, required this.colors, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var cumulative = 0.0;
        final children = <Widget>[];
        var height = 0.0;

        for (var i = 0; i < fractions.length; i++) {
          final segMid = cumulative + fractions[i] / 2;
          cumulative += fractions[i];
          final text = texts[i];
          if (text == null) continue;

          final style = TextStyle(color: colors[i], fontSize: fontSize, fontWeight: FontWeight.bold);
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
          )..layout();
          height = height > painter.height ? height : painter.height;

          final midX = segMid * width;
          final maxX = (width - painter.width).clamp(0.0, double.infinity);
          final x = (midX - painter.width / 2).clamp(0.0, maxX);

          children.add(Positioned(left: x, top: 0, child: Text(text, style: style)));
        }

        return SizedBox(width: width, height: height, child: Stack(children: children));
      },
    );
  }
}

String? _pctLabel(int count, int total) {
  if (total <= 0 || count <= 0) return null;
  return '${((count / total) * 100).round()}%';
}
