import 'package:flutter/material.dart';

import '../theme.dart';

/// Oval pause/resume control shown below a panel's submit/continue button.
class PauseButton extends StatelessWidget {
  final bool isPaused;
  final VoidCallback onToggle;

  const PauseButton({super.key, required this.isPaused, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.5,
      child: SizedBox(
        height: 40,
        child: ElevatedButton(
          onPressed: onToggle,
          style: ElevatedButton.styleFrom(
            backgroundColor: surfaceGray,
            shape: const StadiumBorder(),
          ),
          child: Icon(isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
