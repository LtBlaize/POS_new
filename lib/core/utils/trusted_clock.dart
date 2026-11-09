// Server-anchored clock. Unsynced and without a floor it behaves like DateTime.now().
class TrustedClock {
  TrustedClock._();
  static DateTime? _serverAtSync;
  static final Stopwatch _sw = Stopwatch();
  static DateTime? _floor;
  static final Stopwatch _floorSw = Stopwatch();

  static void reset() {
    _serverAtSync = null;
    _floor = null;
    _sw.reset();
    _floorSw.reset();
  }

  /// Call with the server's now() right after a successful fetch.
  static void sync(DateTime serverNow) {
    _serverAtSync = serverNow;
    _sw
      ..reset()
      ..start();
  }

  /// Offline restart: the last server-confirmed time is a lower bound, so
  /// rolling the device clock back before it cannot extend access.
  static void setFloor(DateTime t) {
    if (_serverAtSync != null) return;
    _floor = t;
    _floorSw
      ..reset()
      ..start();
  }

  static DateTime now() {
    final base = _serverAtSync;
    if (base != null) return base.add(_sw.elapsed);
    final dev = DateTime.now();
    final f = _floor;
    if (f == null) return dev;
    final floored = f.add(_floorSw.elapsed);
    return dev.isBefore(floored) ? floored : dev;
  }
}
