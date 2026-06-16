import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BackGestureDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onBack;
  final bool enabled;
  final bool Function()? shouldIgnore;

  const BackGestureDetector({
    super.key,
    required this.child,
    required this.onBack,
    this.enabled = true,
    this.shouldIgnore,
  });

  @override
  State<BackGestureDetector> createState() => _BackGestureDetectorState();
}

class _BackGestureDetectorState extends State<BackGestureDetector> {
  static const int kBackMouseButton = 8; // standard back button on mouse

  double _swipeDistance = 0;
  double _trackpadBackSwipeDistance = 0;
  double _trackpadBackSwipeCrossAxisDistance = 0;
  bool _didTriggerTrackpadBackSwipe = false;
  bool _isMouseButtonDown = false;
  bool _ignoreCurrentBackDrag = false;

  bool _isModifierPressed() {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    if (event.kind == PointerDeviceKind.mouse && event.buttons != 0) {
      _isMouseButtonDown = true;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kBackMouseButton) != 0) {
      if (widget.shouldIgnore?.call() ?? false) return;
      widget.onBack();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      _isMouseButtonDown = false;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      _isMouseButtonDown = false;
    }
  }

  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    _trackpadBackSwipeDistance = 0;
    _trackpadBackSwipeCrossAxisDistance = 0;
    _didTriggerTrackpadBackSwipe = false;
  }

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!widget.enabled || _isModifierPressed()) return;
    if (widget.shouldIgnore?.call() ?? false) return;
    if (_didTriggerTrackpadBackSwipe || (event.scale - 1.0).abs() >= 0.01) {
      return;
    }

    _trackpadBackSwipeDistance += event.panDelta.dx;
    _trackpadBackSwipeCrossAxisDistance += event.panDelta.dy.abs();

    if (_trackpadBackSwipeDistance > 80 &&
        _trackpadBackSwipeDistance.abs() >
            _trackpadBackSwipeCrossAxisDistance * 1.6) {
      _didTriggerTrackpadBackSwipe = true;
      widget.onBack();
    }
  }

  void _handlePanZoomEnd(PointerPanZoomEndEvent event) {
    _trackpadBackSwipeDistance = 0;
    _trackpadBackSwipeCrossAxisDistance = 0;
    _didTriggerTrackpadBackSwipe = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      onPointerSignal: (event) {
        if (!widget.enabled || _isModifierPressed()) return;
        if (widget.shouldIgnore?.call() ?? false) return;
        if (event is PointerScrollEvent &&
            event.scrollDelta.dx > 48 &&
            event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs() * 1.6) {
          widget.onBack();
        }
      },
      onPointerPanZoomStart: _handlePanZoomStart,
      onPointerPanZoomUpdate: _handlePanZoomUpdate,
      onPointerPanZoomEnd: _handlePanZoomEnd,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          _swipeDistance = 0;
          _ignoreCurrentBackDrag = _isMouseButtonDown;
        },
        onHorizontalDragUpdate: (details) {
          if (!widget.enabled || _ignoreCurrentBackDrag) return;
          if (widget.shouldIgnore?.call() ?? false) return;
          _swipeDistance += details.delta.dx;
        },
        onHorizontalDragEnd: (details) {
          if (!widget.enabled || _ignoreCurrentBackDrag) return;
          if (widget.shouldIgnore?.call() ?? false) return;
          final velocity = details.primaryVelocity ?? 0;
          if (_swipeDistance > 80 || velocity > 520) {
            widget.onBack();
          }
          _swipeDistance = 0;
          _ignoreCurrentBackDrag = false;
        },
        onHorizontalDragCancel: () {
          _swipeDistance = 0;
          _ignoreCurrentBackDrag = false;
        },
        child: widget.child,
      ),
    );
  }
}
