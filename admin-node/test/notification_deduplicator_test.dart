import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mdm_admin_app/services/notification_deduplicator.dart';

void main() {
  group('NotificationDeduplicator Tests', () {
    late NotificationDeduplicator deduplicator;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      deduplicator = NotificationDeduplicator(
        storageKey: 'test_storage_key',
        maxEntries: 10,
      );
      deduplicator.resetMemoryForTest();
    });

    test('Acquires fresh key once, rejects duplicates', () async {
      expect(await deduplicator.tryAcquire('key_1'), isTrue);
      expect(await deduplicator.tryAcquire('key_1'), isFalse);
      expect(await deduplicator.tryAcquire('key_2'), isTrue);
    });

    test('hasSeen reflects acquired keys', () async {
      expect(await deduplicator.hasSeen('unseen_key'), isFalse);
      expect(await deduplicator.tryAcquire('unseen_key'), isTrue);
      expect(await deduplicator.hasSeen('unseen_key'), isTrue);
    });

    test('Prunes old keys when maxEntries exceeded (FIFO eviction)', () async {
      for (int i = 0; i < 15; i++) {
        expect(await deduplicator.tryAcquire('item_$i'), isTrue);
      }
      // item_0 to item_4 should be evicted since maxEntries is 10
      expect(await deduplicator.hasSeen('item_0'), isFalse);
      expect(await deduplicator.hasSeen('item_1'), isFalse);
      expect(await deduplicator.hasSeen('item_14'), isTrue);
      expect(await deduplicator.hasSeen('item_10'), isTrue);
    });

    test('Empty or null key returns true without crashing', () async {
      expect(await deduplicator.tryAcquire(''), isTrue);
      expect(await deduplicator.tryAcquire(null), isTrue);
    });
  });
}
