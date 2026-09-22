import 'package:flutter/material.dart';

import '../controllers/guess_controller.dart';
import '../note_utils.dart';
import '../theme.dart';
import '../widgets/guess_toggle_button.dart';
import '../widgets/pause_button.dart';
import '../widgets/wheel_picker.dart';

class GuessScreen extends StatelessWidget {
  final GuessController controller;

  const GuessScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: isLandscape ? _GuessScreenLandscape(controller: controller) : _GuessScreenPortrait(controller: controller),
        );
      },
    );
  }
}

class _GuessScreenPortrait extends StatelessWidget {
  final GuessController controller;

  const _GuessScreenPortrait({required this.controller});

  @override
  Widget build(BuildContext context) {
    final octaveLabels = octaveRange.map((o) => o.toString()).toList();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!controller.isComplete) ...[
          const Text(
            'Listen, then guess the note',
            style: TextStyle(fontSize: 20, color: Colors.white70, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: WheelPicker(
                    items: [for (final t in tones) displayName(t)],
                    selectedIndex: controller.guessToneIndex,
                    onSelectedIndexChange: controller.selectGuessTone,
                    accentColor: accentGold,
                    enabledRange: controller.isEasyMode ? controller.easyToneRange : null,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: WheelPicker(
                    items: octaveLabels,
                    selectedIndex: controller.guessOctave - octaveRangeStart,
                    onSelectedIndexChange: (i) => controller.selectGuessOctave(octaveRangeStart + i),
                    accentColor: accentGold,
                    scrollEnabled: !controller.isEasyMode,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: controller.isPaused ? null : controller.submit,
              style: ElevatedButton.styleFrom(backgroundColor: surfaceGray),
              child: const Text('SUBMIT GUESS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          PauseButton(isPaused: controller.isPaused, onToggle: controller.togglePause),
        ] else ...[
          guessFeedbackText(controller.feedback, fontSize: 34),
          const SizedBox(height: 12),
          Text('It was ${controller.targetNoteName}', style: const TextStyle(fontSize: 20, color: Colors.white70)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: controller.nextNote,
              style: ElevatedButton.styleFrom(backgroundColor: accentGold),
              child: const Text('CONTINUE', style: TextStyle(fontWeight: FontWeight.w800, color: darkGray)),
            ),
          ),
          const SizedBox(height: 12),
          PauseButton(isPaused: controller.isPaused, onToggle: controller.togglePause),
          const SizedBox(height: 12),
          GuessToggleButton(isShowingCorrect: controller.isShowingCorrectTone, onToggle: controller.toggleCorrectTone),
        ],
      ],
    );
  }
}

/// See TuneScreen's landscape doc comment - same rationale: the wheel pickers (or the revealed
/// answer) sit on the left, the primary action button stacks above Pause and the post-submission
/// correct/guessed toggle on the right. The wheel pickers also shrink from 5 to 3 visible rows
/// here since landscape has much less height to spare.
class _GuessScreenLandscape extends StatelessWidget {
  final GuessController controller;

  const _GuessScreenLandscape({required this.controller});

  @override
  Widget build(BuildContext context) {
    final octaveLabels = octaveRange.map((o) => o.toString()).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!controller.isComplete) ...[
                  const Text(
                    'Listen, then guess the note',
                    style: TextStyle(fontSize: 15, color: Colors.white70, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: WheelPicker(
                            items: [for (final t in tones) displayName(t)],
                            selectedIndex: controller.guessToneIndex,
                            onSelectedIndexChange: controller.selectGuessTone,
                            accentColor: accentGold,
                            enabledRange: controller.isEasyMode ? controller.easyToneRange : null,
                            visibleRows: 3,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: WheelPicker(
                            items: octaveLabels,
                            selectedIndex: controller.guessOctave - octaveRangeStart,
                            onSelectedIndexChange: (i) => controller.selectGuessOctave(octaveRangeStart + i),
                            accentColor: accentGold,
                            scrollEnabled: !controller.isEasyMode,
                            visibleRows: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  guessFeedbackText(controller.feedback, fontSize: 26),
                  const SizedBox(height: 8),
                  Text('It was ${controller.targetNoteName}', style: const TextStyle(fontSize: 15, color: Colors.white70)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: controller.isComplete ? controller.nextNote : (controller.isPaused ? null : controller.submit),
                    style: ElevatedButton.styleFrom(backgroundColor: controller.isComplete ? accentGold : surfaceGray),
                    child: Text(
                      controller.isComplete ? 'CONTINUE' : 'SUBMIT GUESS',
                      style: TextStyle(
                        fontWeight: controller.isComplete ? FontWeight.w800 : FontWeight.bold,
                        color: controller.isComplete ? darkGray : Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                PauseButton(isPaused: controller.isPaused, onToggle: controller.togglePause),
                if (controller.isComplete) ...[
                  const SizedBox(height: 10),
                  GuessToggleButton(isShowingCorrect: controller.isShowingCorrectTone, onToggle: controller.toggleCorrectTone),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Widget guessFeedbackText(GuessFeedback feedback, {required double fontSize}) {
  final (message, color) = switch (feedback) {
    GuessFeedback.correct => ('Correct!', correctGreen),
    GuessFeedback.close => ('Close!', closeYellow),
    GuessFeedback.wrong => ('Wrong', wrongRed),
    GuessFeedback.none => ('', Colors.white),
  };
  return Text(message, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: color));
}
