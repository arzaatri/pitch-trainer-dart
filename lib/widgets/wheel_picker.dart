import 'package:flutter/material.dart';

const double _itemHeight = 44.0;
const int _defaultVisibleRows = 5; // must be odd; middle row is the selection

/// A snapping "wheel" list: drag/fling to scroll, the centered row is the current selection.
/// Port of the Android app's WheelPicker (a centered LazyColumn there) on top of Flutter's
/// built-in [ListWheelScrollView], which already snaps to the centered item.
class WheelPicker extends StatefulWidget {
  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onSelectedIndexChange;
  final Color accentColor;
  final bool scrollEnabled;

  /// Restricts selection to a sub-range [start, end) - other items are dimmed and unselectable.
  final (int, int)? enabledRange;
  final int visibleRows;

  const WheelPicker({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelectedIndexChange,
    this.accentColor = Colors.amber,
    this.scrollEnabled = true,
    this.enabledRange,
    this.visibleRows = _defaultVisibleRows,
  });

  @override
  State<WheelPicker> createState() => _WheelPickerState();
}

class _WheelPickerState extends State<WheelPicker> {
  late FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(initialItem: widget.selectedIndex);
  }

  @override
  void didUpdateWidget(WheelPicker old) {
    super.didUpdateWidget(old);
    // Re-center when selectedIndex changes from outside (e.g. locked to a fixed value in easy
    // mode), not just from the user's own scroll gesture.
    if (widget.selectedIndex != _controller.selectedItem && widget.selectedIndex != old.selectedIndex) {
      _controller.animateToItem(
        widget.selectedIndex,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  bool _isEnabled(int index) {
    final range = widget.enabledRange;
    if (range == null) return true;
    return index >= range.$1 && index < range.$2;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = _itemHeight * widget.visibleRows;
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: _itemHeight,
            diameterRatio: 2.2,
            physics: widget.scrollEnabled ? const FixedExtentScrollPhysics() : const NeverScrollableScrollPhysics(),
            onSelectedItemChanged: (index) {
              if (_isEnabled(index)) {
                widget.onSelectedIndexChange(index);
              } else {
                // Snap back to the nearest enabled item instead of leaving the wheel parked on a
                // disabled one.
                final range = widget.enabledRange!;
                final clamped = index.clamp(range.$1, range.$2 - 1);
                _controller.animateToItem(
                  clamped,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.items.length,
              builder: (context, index) {
                final selected = index == widget.selectedIndex;
                final enabled = _isEnabled(index);
                return Center(
                  child: Text(
                    widget.items[index],
                    style: TextStyle(
                      fontSize: selected ? 20 : 16,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      color: !enabled
                          ? Colors.white24
                          : selected
                              ? widget.accentColor
                              : Colors.white70,
                    ),
                  ),
                );
              },
            ),
          ),
          IgnorePointer(
            child: Container(
              height: _itemHeight,
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: widget.accentColor.withValues(alpha: 0.4)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
