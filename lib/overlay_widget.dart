// overlay_widget.dart — Overlay functionality removed.
// flutter_overlay_window was removed due to crashes on notification tap.
import 'package:flutter/material.dart';

class OverlayWidget extends StatelessWidget {
  const OverlayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
