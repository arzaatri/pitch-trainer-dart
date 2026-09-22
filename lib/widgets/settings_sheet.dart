import 'package:flutter/material.dart';

import '../note_utils.dart';
import '../settings_store.dart';
import '../sound_font.dart';
import '../theme.dart';

const double _labelCellWidth = 64;
const double _gridCellSize = 32;

enum _CautionKind { none, high, low }

/// Bottom sheet for choosing which notes are in play (a tone x octave toggle grid), the
/// instrument, and vibrato. Direct port of the Android app's SettingsSheet.
class SettingsSheet extends StatefulWidget {
  final String title;
  final List<bool> active;
  final void Function(int toneIndex, int octave) onToggleCell;
  final void Function(int toneIndex) onToggleRow;
  final void Function(int octave) onToggleColumn;
  final VoidCallback onReset;
  final Instrument instrument;
  final ValueChanged<Instrument> onSelectInstrument;
  final bool isVibratoEnabled;
  final VoidCallback onToggleVibrato;

  const SettingsSheet({
    super.key,
    required this.title,
    required this.active,
    required this.onToggleCell,
    required this.onToggleRow,
    required this.onToggleColumn,
    required this.onReset,
    required this.instrument,
    required this.onSelectInstrument,
    required this.isVibratoEnabled,
    required this.onToggleVibrato,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  bool _highWarningDismissed = false;
  bool _lowWarningDismissed = false;

  @override
  void initState() {
    super.initState();
    SettingsStore.isHighPitchWarningDismissed().then((v) => setState(() => _highWarningDismissed = v));
    SettingsStore.isLowPitchWarningDismissed().then((v) => setState(() => _lowWarningDismissed = v));
  }

  Future<void> _runGuarded(_CautionKind kind, VoidCallback action) async {
    final dismissed = switch (kind) {
      _CautionKind.high => _highWarningDismissed,
      _CautionKind.low => _lowWarningDismissed,
      _CautionKind.none => true,
    };
    if (kind == _CautionKind.none || dismissed) {
      action();
      return;
    }
    final dontShowAgain = await _showCautionDialog(kind);
    if (dontShowAgain == null) return; // cancelled
    if (dontShowAgain) {
      if (kind == _CautionKind.high) {
        await SettingsStore.setHighPitchWarningDismissed(true);
        setState(() => _highWarningDismissed = true);
      } else if (kind == _CautionKind.low) {
        await SettingsStore.setLowPitchWarningDismissed(true);
        setState(() => _lowWarningDismissed = true);
      }
    }
    action();
  }

  /// Returns null if cancelled, otherwise whether "don't show again" was checked.
  Future<bool?> _showCautionDialog(_CautionKind kind) {
    final message = kind == _CautionKind.high
        ? 'Notes from F5 upward are very high-pitched and can be unpleasant to listen to.'
        : 'Notes below G3 may be difficult to hear clearly on some device speakers.';
    var dontShowAgain = false;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Heads up'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setDialogState(() => dontShowAgain = !dontShowAgain),
                child: Row(
                  children: [
                    Checkbox(
                      value: dontShowAgain,
                      onChanged: (v) => setDialogState(() => dontShowAgain = v ?? false),
                    ),
                    const Text("Don't show this again"),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, dontShowAgain), child: const Text('Enable anyway')),
          ],
        ),
      ),
    );
  }

  _CautionKind _wouldRowEnableCaution(int toneIndex) {
    final slots = [for (final o in octaveRange) noteSlot(toneIndex, o)];
    final allOn = slots.every((s) => widget.active[s]);
    if (allOn) return _CautionKind.none; // this tap would turn the row OFF, not on
    final newlyActive = slots.where((s) => !widget.active[s]);
    if (newlyActive.any(isHighCautionSlot)) return _CautionKind.high;
    if (newlyActive.any(isLowCautionSlot)) return _CautionKind.low;
    return _CautionKind.none;
  }

  _CautionKind _wouldColumnEnableCaution(int octave) {
    final slots = [for (var t = 0; t < tones.length; t++) noteSlot(t, octave)];
    final allOn = slots.every((s) => widget.active[s]);
    if (allOn) return _CautionKind.none;
    final newlyActive = slots.where((s) => !widget.active[s]);
    if (newlyActive.any(isHighCautionSlot)) return _CautionKind.high;
    if (newlyActive.any(isLowCautionSlot)) return _CautionKind.low;
    return _CautionKind.none;
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Container(
        color: surfaceGray,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.title, style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                ElevatedButton(onPressed: widget.onReset, child: const Text('Reset')),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  for (final inst in Instrument.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ElevatedButton(
                          onPressed: () => widget.onSelectInstrument(inst),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: inst == widget.instrument ? accentGold : darkGray,
                            foregroundColor: inst == widget.instrument ? darkGray : Colors.white,
                          ),
                          child: Text(inst.label),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.instrument == Instrument.violin)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InkWell(
                  onTap: widget.onToggleVibrato,
                  child: Row(
                    children: [
                      Checkbox(value: widget.isVibratoEnabled, onChanged: (_) => widget.onToggleVibrato()),
                      const Text('Vibrato', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: _labelCellWidth, height: _gridCellSize),
                        for (final octave in octaveRange)
                          _gridHeaderCell(
                            '$octave',
                            () => _runGuarded(_wouldColumnEnableCaution(octave), () => widget.onToggleColumn(octave)),
                          ),
                      ],
                    ),
                    for (var toneIndex = 0; toneIndex < tones.length; toneIndex++)
                      Row(
                        children: [
                          SizedBox(
                            width: _labelCellWidth,
                            height: _gridCellSize,
                            child: InkWell(
                              onTap: () => _runGuarded(_wouldRowEnableCaution(toneIndex), () => widget.onToggleRow(toneIndex)),
                              child: Center(
                                child: Text(displayName(tones[toneIndex]), style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ),
                            ),
                          ),
                          for (final octave in octaveRange) _buildCell(toneIndex, octave),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(int toneIndex, int octave) {
    final slot = noteSlot(toneIndex, octave);
    final isActive = widget.active[slot];
    final isHigh = isHighCautionSlot(slot);
    final isLow = isLowCautionSlot(slot);
    final kind = isHigh ? _CautionKind.high : (isLow ? _CautionKind.low : _CautionKind.none);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: InkWell(
        onTap: () => _runGuarded(!isActive ? kind : _CautionKind.none, () => widget.onToggleCell(toneIndex, octave)),
        child: Container(
          width: _gridCellSize,
          height: _gridCellSize,
          color: isActive ? accentGold : darkGray,
          alignment: Alignment.center,
          child: isHigh
              ? const Text('!', style: TextStyle(color: wrongRed, fontSize: 14, fontWeight: FontWeight.w800))
              : isLow
                  ? const Text('*', style: TextStyle(color: wrongRed, fontSize: 14, fontWeight: FontWeight.w800))
                  : null,
        ),
      ),
    );
  }

  Widget _gridHeaderCell(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: _gridCellSize,
        height: _gridCellSize,
        child: Center(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
      ),
    );
  }
}
