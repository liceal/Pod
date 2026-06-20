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
  int _activeTouchPointerCount = 0;
  int? _backSwipePointer;
  double _pointerBackSwipeDistance = 0;
  double _pointerBackSwipeCrossAxisDistance = 0;
  bool _didTriggerPointerBackSwipe = false;
  bool _suppressDragRecognizerBack = false;

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
    if (event.kind != PointerDeviceKind.mouse) {
      _activeTouchPointerCount++;
      if (_activeTouchPointerCount == 1) {
        _backSwipePointer = event.pointer;
        _pointerBackSwipeDistance = 0;
        _pointerBackSwipeCrossAxisDistance = 0;
        _didTriggerPointerBackSwipe = false;
        _suppressDragRecognizerBack = false;
      } else {
        _backSwipePointer = null;
        _pointerBackSwipeDistance = 0;
        _pointerBackSwipeCrossAxisDistance = 0;
        _didTriggerPointerBackSwipe = false;
      }
    }
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kBackMouseButton) != 0) {
      if (widget.shouldIgnore?.call() ?? false) return;
      widget.onBack();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!widget.enabled ||
        event.kind == PointerDeviceKind.mouse ||
        _backSwipePointer != event.pointer ||
        _activeTouchPointerCount != 1 ||
        _didTriggerPointerBackSwipe ||
        _isModifierPressed()) {
      return;
    }
    if (widget.shouldIgnore?.call() ?? false) return;

    _pointerBackSwipeDistance += event.delta.dx;
    _pointerBackSwipeCrossAxisDistance += event.delta.dy.abs();

    if (_pointerBackSwipeDistance > 80 &&
        _pointerBackSwipeDistance.abs() >
            _pointerBackSwipeCrossAxisDistance * 1.6) {
      _didTriggerPointerBackSwipe = true;
      _suppressDragRecognizerBack = true;
      widget.onBack();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      _isMouseButtonDown = false;
    } else {
      _activeTouchPointerCount = (_activeTouchPointerCount - 1)
          .clamp(0, 1000)
          .toInt();
      if (_backSwipePointer == event.pointer || _activeTouchPointerCount == 0) {
        _backSwipePointer = null;
        _pointerBackSwipeDistance = 0;
        _pointerBackSwipeCrossAxisDistance = 0;
        _didTriggerPointerBackSwipe = false;
      }
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      _isMouseButtonDown = false;
    } else {
      _activeTouchPointerCount = (_activeTouchPointerCount - 1)
          .clamp(0, 1000)
          .toInt();
      if (_backSwipePointer == event.pointer || _activeTouchPointerCount == 0) {
        _backSwipePointer = null;
        _pointerBackSwipeDistance = 0;
        _pointerBackSwipeCrossAxisDistance = 0;
        _didTriggerPointerBackSwipe = false;
      }
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
      onPointerMove: _handlePointerMove,
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
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          MouseExcludingHorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                MouseExcludingHorizontalDragGestureRecognizer
              >(() => MouseExcludingHorizontalDragGestureRecognizer(), (
                MouseExcludingHorizontalDragGestureRecognizer instance,
              ) {
                instance
                  ..onStart = (_) {
                    _swipeDistance = 0;
                    _ignoreCurrentBackDrag = _isMouseButtonDown;
                  }
                  ..onUpdate = (details) {
                    if (!widget.enabled || _ignoreCurrentBackDrag) return;
                    if (widget.shouldIgnore?.call() ?? false) return;
                    _swipeDistance += details.delta.dx;
                  }
                  ..onEnd = (details) {
                    if (_suppressDragRecognizerBack) {
                      _swipeDistance = 0;
                      _ignoreCurrentBackDrag = false;
                      _suppressDragRecognizerBack = false;
                      return;
                    }
                    if (!widget.enabled || _ignoreCurrentBackDrag) return;
                    if (widget.shouldIgnore?.call() ?? false) return;
                    final velocity = details.primaryVelocity ?? 0;
                    if (_swipeDistance > 80 || velocity > 520) {
                      widget.onBack();
                    }
                    _swipeDistance = 0;
                    _ignoreCurrentBackDrag = false;
                  }
                  ..onCancel = () {
                    _swipeDistance = 0;
                    _ignoreCurrentBackDrag = false;
                    _suppressDragRecognizerBack = false;
                  };
              }),
        },
        child: widget.child,
      ),
    );
  }
}

class MouseExcludingHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  MouseExcludingHorizontalDragGestureRecognizer({super.debugOwner});

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      return false;
    }
    return super.isPointerAllowed(event);
  }
}
