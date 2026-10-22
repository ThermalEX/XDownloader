import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/library_search.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';

import '../support/app_fixture.dart';

void main() {
  test(
    'all normalized words match across fields without storing the query',
    () async {
      final store = MemorySnapshotStore();
      final settings = SettingsRepository(store);
      await settings.initialize();
      final search = LibrarySearch(settings);
      addTearDown(search.dispose);
      addTearDown(settings.dispose);
      expect(search.matches([null]), isTrue);
      search.text.text = '  MUSIC\n 猫 123456 ';
      search.update(search.text.text);
      expect(
        search.matches(['Music 猫', Uri.parse('https://x.com/a/status/123456')]),
        isTrue,
      );
      expect(search.matches(['Music 狗', '123456']), isFalse);
      search.update('https://twitter.com/old/status/123456?s=20');
      expect(search.matches(['https://x.com/new/status/123456']), isTrue);
      final before = Map.of(store.values);
      await settings.edit((s) => s.copyWith(privacyMode: true));
      expect(search.text.text, isEmpty);
      expect(search.isEmpty, isTrue);
      expect(store.values.keys.toSet(), {...before.keys, 'settings'});
      expect(store.values.values.join(), isNot(contains('MUSIC')));
    },
  );
}
