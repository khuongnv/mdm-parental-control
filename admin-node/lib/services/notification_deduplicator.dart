import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent bounded FIFO deduplicator for parent notifications.
///
/// Survives app restarts and cross-isolate (FCM background handler -> main)
/// transitions via `SharedPreferences.reload()`, while guarding against
/// same-millisecond races using an in-memory mirror.
class NotificationDeduplicator {
  static const String defaultStorageKey = 'vfam_notified_event_keys_fifo_v1';
  static const int defaultMaxEntries = 200;

  static final NotificationDeduplicator instance = NotificationDeduplicator();

  final String storageKey;
  final int maxEntries;
  final SharedPreferences? _injectedPrefs;

  final List<String> _fifoQueue = <String>[];
  final Set<String> _seenSet = <String>{};
  Future<void> _serialChain = Future<void>.value();

  NotificationDeduplicator({
    SharedPreferences? prefs,
    this.storageKey = defaultStorageKey,
    this.maxEntries = defaultMaxEntries,
  }) : _injectedPrefs = prefs;

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serialChain = _serialChain.then((_) async {
      try {
        final result = await action();
        if (!completer.isCompleted) completer.complete(result);
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<SharedPreferences> _getPrefs({required bool reload}) async {
    final prefs = _injectedPrefs ?? await SharedPreferences.getInstance();
    if (reload) {
      try {
        await prefs.reload();
      } catch (_) {}
    }
    return prefs;
  }

  void _syncMemoryFromPersisted(List<String> persisted) {
    for (final item in persisted) {
      if (item.isNotEmpty && _seenSet.add(item)) {
        _fifoQueue.add(item);
      }
    }
    while (_fifoQueue.length > maxEntries) {
      final evicted = _fifoQueue.removeAt(0);
      _seenSet.remove(evicted);
    }
  }

  /// Attempts to acquire the deduplication lock for [key].
  /// Returns `true` if [key] has not been seen yet (and records it),
  /// or `false` if [key] was already recorded.
  Future<bool> tryAcquire(String? key, {bool reloadPrefs = true}) {
    final normalized = key?.trim() ?? '';
    if (normalized.isEmpty) {
      return Future<bool>.value(true);
    }
    if (_seenSet.contains(normalized)) {
      return Future<bool>.value(false);
    }

    return _synchronized(() async {
      if (_seenSet.contains(normalized)) {
        return false;
      }

      final prefs = await _getPrefs(reload: reloadPrefs);
      final persisted = prefs.getStringList(storageKey) ?? const <String>[];
      _syncMemoryFromPersisted(persisted);

      if (_seenSet.contains(normalized)) {
        return false;
      }

      _seenSet.add(normalized);
      _fifoQueue.add(normalized);
      while (_fifoQueue.length > maxEntries) {
        final evicted = _fifoQueue.removeAt(0);
        _seenSet.remove(evicted);
      }

      await prefs.setStringList(storageKey, List<String>.from(_fifoQueue));
      return true;
    });
  }

  /// Checks whether [key] has already been seen without mutating state.
  Future<bool> hasSeen(String? key, {bool reloadPrefs = true}) {
    final normalized = key?.trim() ?? '';
    if (normalized.isEmpty) {
      return Future<bool>.value(false);
    }
    if (_seenSet.contains(normalized)) {
      return Future<bool>.value(true);
    }

    return _synchronized(() async {
      if (_seenSet.contains(normalized)) {
        return true;
      }
      final prefs = await _getPrefs(reload: reloadPrefs);
      final persisted = prefs.getStringList(storageKey) ?? const <String>[];
      _syncMemoryFromPersisted(persisted);
      return _seenSet.contains(normalized);
    });
  }

  /// Clears in-memory state (useful for tests).
  void resetMemoryForTest() {
    _fifoQueue.clear();
    _seenSet.clear();
  }
}
