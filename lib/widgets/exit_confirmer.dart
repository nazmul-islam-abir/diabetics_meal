import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a screen so the Android hardware back button / iOS edge-swipe only
/// closes the app after the user confirms via a second tap within a short
/// window. While a non-root route is on the navigator stack, the default
/// pop behavior is preserved so the user can navigate back normally with
/// the same gesture — this is what gives the app a "professional" feel
/// (back = pop, back-from-root = "press back again to exit").
///
/// Backed by [PopScope] (the replacement for the deprecated
/// `WillPopScope`). On Android 13+ predictive back is supported natively
/// if the underlying route is a standard [PageRoute].
class ExitConfirmer extends StatefulWidget {
  final Widget child;
  final String message;
  final Duration window;
  final String confirmLabel;
  final String cancelLabel;

  const ExitConfirmer({
    super.key,
    required this.child,
    this.message = 'অ্যাপ থেকে বের হতে চান?',
    this.window = const Duration(seconds: 2),
    this.confirmLabel = 'বের হন',
    this.cancelLabel = 'থাকুন',
  });

  @override
  State<ExitConfirmer> createState() => _ExitConfirmerState();
}

class _ExitConfirmerState extends State<ExitConfirmer> {
  DateTime? _lastBackPress;

  Future<void> _handleBack() async {
    // If a sub-route is already on the stack, pop it. We always control
    // navigation here (canPop: false), so we have to call pop ourselves
    // — otherwise the system just swallows the back gesture.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      HapticFeedback.selectionClick();
      navigator.pop();
      return;
    }

    // Root route. First press shows a confirmation; second press within
    // the window exits the app cleanly via SystemNavigator so the OS can
    // animate the activity away.
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < widget.window) {
      HapticFeedback.mediumImpact();
      await SystemNavigator.pop();
      return;
    }

    _lastBackPress = now;
    HapticFeedback.lightImpact();
    final shouldExit = await _showDialog();
    if (shouldExit == true) {
      await SystemNavigator.pop();
      return;
    }
    // Reset so the user has to press back twice again.
    _lastBackPress = null;
  }

  Future<bool?> _showDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('অ্যাপ বন্ধ করবেন?'),
          content: Text(widget.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(widget.cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(widget.confirmLabel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // We are intercepting the back gesture so the system MUST NOT pop on
      // its own — we decide whether to pop (sub-route) or exit (root).
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: widget.child,
    );
  }
}
