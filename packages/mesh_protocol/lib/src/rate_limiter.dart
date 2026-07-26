/// Simple sliding-window packet rate limiter for flood control.
class RateLimiter {
  RateLimiter({
    this.maxEvents = 12,
    this.window = const Duration(seconds: 10),
  });

  final int maxEvents;
  final Duration window;
  final List<DateTime> _times = [];

  /// Returns true if the event is allowed.
  bool allow([DateTime? now]) {
    final t = now ?? DateTime.now().toUtc();
    final cutoff = t.subtract(window);
    _times.removeWhere((x) => x.isBefore(cutoff));
    if (_times.length >= maxEvents) return false;
    _times.add(t);
    return true;
  }

  void reset() => _times.clear();
}
