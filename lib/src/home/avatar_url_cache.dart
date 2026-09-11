/// Reuses short-lived avatar URLs so a dashboard refresh keeps the image cache.
class AvatarUrlCache {
  AvatarUrlCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const lifetimeSeconds = 300;
  final DateTime Function() _now;
  final _entries = <String, ({String url, DateTime expires})>{};
  String? _scope;

  Future<Map<String, String>> resolve({
    required String scope,
    required List<String> paths,
    required Future<Map<String, String>> Function(List<String>, int) sign,
  }) async {
    if (_scope != scope) {
      _entries.clear();
      _scope = scope;
    }
    final started = _now();
    _entries.removeWhere(
      (path, entry) => !paths.contains(path) || !entry.expires.isAfter(started),
    );
    final missing = paths.toSet().where((path) {
      final entry = _entries[path];
      return entry == null ||
          !entry.expires.isAfter(started.add(const Duration(seconds: 30)));
    }).toList();
    if (missing.isNotEmpty) {
      try {
        final urls = await sign(missing, lifetimeSeconds);
        // An older request must not refill another crew/account's cache.
        if (_scope != scope) return {};
        for (final path in missing) {
          final url = urls[path];
          if (url != null) {
            _entries[path] = (
              url: url,
              expires: started.add(const Duration(seconds: lifetimeSeconds)),
            );
          }
        }
      } catch (_) {
        // Keep still-valid images during a transient storage failure.
      }
    }
    if (_scope != scope) return {};
    final now = _now();
    return {
      for (final path in paths)
        if (_entries[path] case final entry? when entry.expires.isAfter(now))
          path: entry.url,
    };
  }
}
