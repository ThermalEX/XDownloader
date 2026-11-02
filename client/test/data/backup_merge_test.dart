import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/data/backup/backup_merge.dart';

Map<String, Object?> favorite(String id, String title, String category) => {
  'postId': id,
  'url': 'https://x.com/i/status/$id',
  'title': title,
  'category': category,
  'author': title,
  'createdAt': '2026-11-01T00:00:00.000Z',
};
Map<String, Object?> source(String id, String host) => {
  'id': id,
  'name': host,
  'endpoint': 'https://$host/api?url={urlenc}',
  'kind': 'scrape',
  'method': 'GET',
  'body': '',
  'builtin': false,
};
Map<String, Object?> sources(
  List<Map<String, Object?>> rows, {
  String current = 'xdl',
  List<String> order = const [],
}) => {
  'custom': rows,
  'current': current,
  'order': order,
  'fallback': true,
  'protection': {'mode': 'off', 'interval': 15},
};

void main() {
  test(
    'archive conflict replaces a definition whose earlier identity was removed',
    () {
      final incoming = [
        source('A', 'third.example'),
        source('B', 'first.example'),
      ];
      for (final rows in [incoming, incoming.reversed.toList()]) {
        final result = BackupMerge.plan(
          {
            'sources': sources([
              source('A', 'first.example'),
              source('B', 'second.example'),
            ], current: 'B'),
          },
          {'sources': sources(rows, current: 'B')},
          replace: false,
          preferArchive: true,
          sections: {'sources'},
        );
        final value = result['sources']!;
        expect(value['custom'], [
          source('A', 'third.example'),
          source('B', 'first.example'),
        ]);
        expect(value['current'], 'B');
        expect((value['order'] as List).where((id) => id == 'B').length, 1);
      }
    },
  );

  test(
    'new sources keep archive relative priority after every existing source',
    () {
      final result = BackupMerge.plan(
        {
          'sources': sources(
            [source('local', 'a.example')],
            order: ['local', 'xdl'],
          ),
        },
        {
          'sources': sources(
            [source('first', 'b.example'), source('second', 'c.example')],
            order: ['second', 'first', 'xdl'],
          ),
        },
        replace: false,
        preferArchive: true,
        sections: {'sources'},
      );
      final order = result['sources']!['order'] as List;
      expect(order.indexOf('second'), greaterThan(order.indexOf('local')));
      expect(order.indexOf('first'), greaterThan(order.indexOf('second')));
    },
  );

  test('merge chooses a complete conflict record and unions categories without deleting', () {
    final local = <String, Map<String, Object?>>{
      'favorites': {
        'items': [
          favorite('12345', 'local', 'local'),
          favorite('23456', 'keep', ''),
        ],
        'categories': ['empty', 'local'],
        'sort': 'newest',
      },
    };
    final incoming = <String, Map<String, Object?>>{
      'favorites': {
        'items': [
          favorite('12345', 'archive', 'archive'),
          favorite('34567', 'new', ''),
        ],
        'categories': ['archive'],
        'sort': 'oldest',
      },
    };
    for (final prefer in [false, true]) {
      final result = BackupMerge.plan(
        local,
        incoming,
        replace: false,
        preferArchive: prefer,
        sections: {'favorites'},
      );
      final rows = result['favorites']!['items'] as List;
      expect(rows.length, 3);
      expect(
        rows.first,
        favorite(
          '12345',
          prefer ? 'archive' : 'local',
          prefer ? 'archive' : 'local',
        ),
      );
      expect(result['favorites']!['categories'], ['empty', 'local', 'archive']);
      expect(result['favorites']!['sort'], prefer ? 'oldest' : 'newest');
    }
  });

  test('replace empty selected groups clears favorites and leaves absent groups alone', () {
    final result = BackupMerge.plan(
      {
        'favorites': {
          'items': [favorite('12345', 'a', '')],
        },
      },
      {
        'favorites': {'items': [], 'categories': []},
      },
      replace: true,
      preferArchive: true,
      sections: {'favorites', 'settings'},
    );
    expect(result.keys, ['favorites']);
    expect(result['favorites']!['items'], isEmpty);
  });

  test(
    'settings conflicts are explicit values and never restore local secrets',
    () {
      final local = <String, Map<String, Object?>>{
        'settings': {
          'themeMode': 'dark',
          'autoClipboard': false,
          'privacyMode': true,
          'privacyPasswordHash': 'local-secret',
        },
      };
      final incoming = <String, Map<String, Object?>>{
        'settings': {
          'themeMode': 'light',
          'autoClipboard': true,
          'privacyMode': false,
          'privacyPasswordHash': 'remote-secret',
        },
      };
      final keep = BackupMerge.plan(
        local,
        incoming,
        replace: false,
        preferArchive: false,
        sections: {'settings'},
      );
      expect(keep['settings']!['autoClipboard'], false);
      final adopt = BackupMerge.plan(
        local,
        incoming,
        replace: true,
        preferArchive: true,
        sections: {'settings'},
      );
      expect(adopt['settings']!['themeMode'], 'light');
      expect(adopt['settings']!['privacyMode'], true);
      expect(adopt['settings']!['privacyPasswordHash'], 'local-secret');
    },
  );

  test('source identity dedup remaps incoming current and priority without duplicate builtins', () {
    final result = BackupMerge.plan(
      {
        'sources': sources(
          [source('local', 'a.example')],
          order: ['fx', 'local'],
        ),
      },
      {
        'sources': sources(
          [source('remote', 'a.example'), source('new', 'b.example')],
          current: 'remote',
          order: ['remote', 'new', 'xdl'],
        ),
      },
      replace: false,
      preferArchive: true,
      sections: {'sources'},
    );
    final value = result['sources']!;
    expect((value['custom'] as List).map((e) => (e as Map)['id']), [
      'local',
      'new',
    ]);
    expect(value['current'], 'local');
    expect((value['order'] as List).where((e) => e == 'local').length, 1);
    expect(
      (value['order'] as List).indexOf('new'),
      greaterThan((value['order'] as List).indexOf('local')),
    );
  });

  test('same source id different definition respects conflict side and selection stays valid', () {
    for (final prefer in [false, true]) {
      final result = BackupMerge.plan(
        {
          'sources': sources([source('same', 'a.example')], current: 'same'),
        },
        {
          'sources': sources([source('same', 'b.example')], current: 'same'),
        },
        replace: false,
        preferArchive: prefer,
        sections: {'sources'},
      );
      final value = result['sources']!;
      expect(
        (value['custom'] as List).single,
        source('same', prefer ? 'b.example' : 'a.example'),
      );
      expect(value['current'], 'same');
    }
  });

  test('invalid selection falls back to current built-in and overflow rejects whole merge', () {
    final replace = BackupMerge.plan(
      {},
      {
        'sources': sources([], current: 'deleted', order: ['deleted', 'xdl']),
      },
      replace: true,
      preferArchive: true,
      sections: {'sources'},
    );
    expect(replace['sources']!['current'], 'xdl');
    expect(replace['sources']!['order'], isNot(contains('deleted')));
    final rows = List.generate(50, (i) => source('c$i', 'host$i.example'));
    expect(
      () => BackupMerge.plan(
        {'sources': sources(rows)},
        {
          'sources': sources([source('extra', 'extra.example')]),
        },
        replace: false,
        preferArchive: false,
        sections: {'sources'},
      ),
      throwsFormatException,
    );
  });

  test('chained identity and ID collisions preserve the incoming selected definition', () {
    final incoming = [source('one', 'b.example'), source('two', 'c.example')];
    for (final incomingRows in [incoming, incoming.reversed.toList()]) {
      final result = BackupMerge.plan(
        {
          'sources': sources(
            [source('one', 'a.example'), source('two', 'b.example')],
            current: 'one',
            order: ['one', 'two'],
          ),
        },
        {
          'sources': sources(
            incomingRows,
            current: 'one',
            order: ['one', 'two'],
          ),
        },
        replace: false,
        preferArchive: true,
        sections: {'sources'},
      );
      final value = result['sources']!;
      final rows = value['custom'] as List;
      final selected = rows.cast<Map>().singleWhere(
        (row) => row['id'] == value['current'],
      );
      expect(selected['endpoint'], 'https://b.example/api?url={urlenc}');
      expect(rows.map((row) => (row as Map)['endpoint']).toSet(), {
        'https://b.example/api?url={urlenc}',
        'https://c.example/api?url={urlenc}',
      });
      expect(rows.length, 2);
    }
  });
}
