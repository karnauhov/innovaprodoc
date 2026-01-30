import 'dart:ui';

class TimerHandle {
  final VoidCallback fn;
  final int ms;
  bool _active = true;
  TimerHandle(this.fn, this.ms) {
    Future.delayed(Duration(milliseconds: ms), () {
      if (_active) fn();
    });
  }
  void cancel() => _active = false;
}
