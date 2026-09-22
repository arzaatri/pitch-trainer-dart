import 'package:flutter/material.dart';

import '../theme.dart';

/// Oval toggle shown below the pause button on the post-submission screen, for switching the
/// reference tone that's playing between the correct note and the note the user guessed/tuned to.
class GuessToggleButton extends StatelessWidget {
  final bool isShowingCorrect;
  final VoidCallback onToggle;

  const GuessToggleButton({super.key, required this.isShowingCorrect, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.5,
      child: SizedBox(
        height: 40,
        child: ElevatedButton(
          onPressed: onToggle,
          style: ElevatedButton.styleFrom(
            backgroundColor: isShowingCorrect ? accentGold : surfaceGray,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sync, size: 16, color: isShowingCorrect ? darkGray : Colors.white),
              const SizedBox(width: 6),
              Text(
                isShowingCorrect ? 'Correct' : 'Your guess',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isShowingCorrect ? darkGray : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
