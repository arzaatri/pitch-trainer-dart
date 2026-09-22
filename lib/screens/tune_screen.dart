import 'package:flutter/material.dart';

import '../controllers/tune_controller.dart';
import '../theme.dart';
import '../widgets/guess_toggle_button.dart';
import '../widgets/pause_button.dart';

class TuneScreen extends StatelessWidget {
  final TuneController controller;

  const TuneScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: isLandscape ? _TuneScreenLandscape(controller: controller) : _TuneScreenPortrait(controller: controller),
        );
      },
    );
  }
}

class _TuneScreenPortrait extends StatelessWidget {
  final TuneController controller;

  const _TuneScreenPortrait({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          controller.targetNoteName,
          style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w800, color: accentGold),
        ),
        Text(controller.feedback, style: TextStyle(fontSize: 18, color: tuneFeedbackColor(controller.feedback))),
        const SizedBox(height: 60),
        if (!controller.isComplete) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              pitchStepButton('-${controller.difficulty.moveStepCents}¢', () => controller.adjustPitch(-1)),
              pitchStepButton('+${controller.difficulty.moveStepCents}¢', () => controller.adjustPitch(1)),
            ],
          ),
          const SizedBox(height: 60),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: controller.isPaused ? null : controller.submit,
              style: ElevatedButton.styleFrom(backgroundColor: surfaceGray),
              child: const Text('CHECK PITCH', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          PauseButton(isPaused: controller.isPaused, onToggle: controller.togglePause),
        ] else ...[
          const Text('Now playing perfect reference...', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 24),
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

/// Landscape has far less vertical room than horizontal, so a plain vertical stack (the portrait
/// layout) pushes the lower buttons off the bottom of the screen. Instead the screen splits into
/// two columns: note name/feedback/pitch controls on the left, and the primary action button
/// (CHECK PITCH / CONTINUE) stacked above Pause and the post-submission correct/guess toggle on
/// the right. Both columns are scrollable as a safety net so nothing is ever unreachable even on
/// a very short landscape screen.
class _TuneScreenLandscape extends StatelessWidget {
  final TuneController controller;

  const _TuneScreenLandscape({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  controller.targetNoteName,
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: accentGold),
                ),
                Text(controller.feedback, style: TextStyle(fontSize: 14, color: tuneFeedbackColor(controller.feedback))),
                const SizedBox(height: 14),
                if (!controller.isComplete)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _landscapePitchStepButton('-${controller.difficulty.moveStepCents}¢', () => controller.adjustPitch(-1)),
                      const SizedBox(width: 12),
                      _landscapePitchStepButton('+${controller.difficulty.moveStepCents}¢', () => controller.adjustPitch(1)),
                    ],
                  )
                else
                  const Text('Now playing perfect reference...', style: TextStyle(color: Colors.white70, fontSize: 12)),
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
                      controller.isComplete ? 'CONTINUE' : 'CHECK PITCH',
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

  Widget _landscapePitchStepButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: 84,
      height: 64,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: const BorderSide(color: accentGold, width: 2),
        ),
        child: Text(label, style: const TextStyle(fontSize: 15, color: accentGold), maxLines: 1),
      ),
    );
  }
}

Widget pitchStepButton(String label, VoidCallback onPressed) {
  return SizedBox(
    width: 110,
    height: 110,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: accentGold, width: 2),
      ),
      child: Text(label, style: const TextStyle(fontSize: 22, color: accentGold)),
    ),
  );
}

Color tuneFeedbackColor(String feedback) {
  if (feedback == 'Perfect Match!') return correctGreen;
  if (feedback.startsWith('Close!')) return closeYellow;
  return Colors.white70;
}
