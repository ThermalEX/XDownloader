import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/data/backup/backup_zip.dart';

const maxBytes = 16 * 1024 * 1024;

List<int> fixture(Map<String, List<int>> files, {bool stored = false}) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(
      ArchiveFile.bytes(entry.key, entry.value)
        ..compression = stored ? CompressionType.none : CompressionType.deflate,
    );
  }
  return ZipEncoder().encodeBytes(archive, modified: DateTime.utc(2026));
}

int read16(List<int> bytes, int offset) =>
    bytes[offset] | bytes[offset + 1] << 8;

int read32(List<int> bytes, int offset) =>
    read16(bytes, offset) | read16(bytes, offset + 2) << 16;

void write16(List<int> bytes, int offset, int value) {
  bytes[offset] = value & 255;
  bytes[offset + 1] = value >> 8 & 255;
}

void write32(List<int> bytes, int offset, int value) {
  write16(bytes, offset, value & 65535);
  write16(bytes, offset + 2, value >> 16);
}

int central(List<int> bytes) => read32(bytes, bytes.length - 6);

void main() {
  test('exports a standard ZIP readable by an independent ZIP decoder', () {
    final bytes = BackupZip.encode({
      'backup.json': utf8.encode('{"version":1}'),
      'files/封面.bin': [0, 255, 5, 42],
    });
    expect(bytes.take(4), [0x50, 0x4b, 3, 4]);
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(
      utf8.decode(archive.find('backup.json')!.readBytes()!),
      '{"version":1}',
    );
    expect(archive.find('files/封面.bin')!.readBytes(), [0, 255, 5, 42]);
  });

  test('imports independently encoded stored and deflated multi-file ZIPs', () {
    for (final stored in [false, true]) {
      expect(
        BackupZip.decode(
          fixture({
            'backup.json': [123, 125],
            'files/data.bin': [0, 255, 127],
            'files/empty': [],
          }, stored: stored),
        ),
        {
          'backup.json': [123, 125],
          'files/data.bin': [0, 255, 127],
          'files/empty': [],
        },
      );
    }
  });

  test('encoding is deterministic regardless of map insertion order', () {
    final one = BackupZip.encode({
      'files/z': [3],
      'backup.json': [1, 2],
    });
    final two = BackupZip.encode({
      'backup.json': [1, 2],
      'files/z': [3],
    });
    expect(one, two);
    expect(BackupZip.encode(BackupZip.decode(one)), one);
  });

  test('encoded bytes and decoded file maps are deeply immutable', () {
    final source = <int>[1, 2, 3];
    final bytes = BackupZip.encode({'backup.json': source});
    source[0] = 9;
    expect(() => bytes[0] = 0, throwsUnsupportedError);
    final files = BackupZip.decode(bytes);
    expect(files['backup.json'], [1, 2, 3]);
    expect(() => files['other'] = [], throwsUnsupportedError);
    expect(() => files['backup.json']![0] = 9, throwsUnsupportedError);
  });

  test('rejects corrupt stored data even with verify disabled upstream', () {
    final bytes = fixture({
      'backup.json': [10, 20, 30],
    }, stored: true);
    final start = 30 + read16(bytes, 26) + read16(bytes, 28);
    bytes[start] ^= 1;
    expect(() => BackupZip.decode(bytes), throwsFormatException);
  });

  test(
    'rejects CRC metadata that disagrees between local and central records',
    () {
      final bytes = fixture({
        'backup.json': [1, 2],
      });
      write32(bytes, central(bytes) + 16, 0);
      expect(() => BackupZip.decode(bytes), throwsFormatException);
    },
  );

  test(
    'rejects invalid, truncated, appended and missing-directory archives',
    () {
      final bytes = fixture({
        'backup.json': [1, 2],
      });
      for (final broken in <List<int>>[
        [],
        utf8.encode('{"old":"json"}'),
        bytes.sublist(0, bytes.length - 1),
        bytes.sublist(0, central(bytes)),
        [...bytes, 0],
      ]) {
        expect(() => BackupZip.decode(broken), throwsFormatException);
      }
    },
  );

  test('rejects duplicate names before the upstream decoder merges them', () {
    final bytes = fixture({
      'files/aa': [1],
      'files/bb': [2],
    });
    final first = central(bytes);
    final second =
        first +
        46 +
        read16(bytes, first + 28) +
        read16(bytes, first + 30) +
        read16(bytes, first + 32);
    final secondLocal = read32(bytes, second + 42);
    bytes.setRange(second + 46, second + 54, utf8.encode('files/aa'));
    bytes.setRange(secondLocal + 30, secondLocal + 38, utf8.encode('files/aa'));
    expect(() => BackupZip.decode(bytes), throwsFormatException);
  });

  test(
    'rejects traversal, absolute, empty segments and unsafe portable names',
    () {
      for (final name in [
        '../backup.json',
        '/backup.json',
        'C:/backup.json',
        'files/../bad',
        'files/./bad',
        'files//bad',
        'files/bad\u0000',
        'files/bad:',
        'files/trailing.',
        'files/ space',
        'files/',
      ]) {
        expect(
          () => BackupZip.encode({
            name: [1],
          }),
          throwsFormatException,
          reason: name,
        );
        expect(
          () => BackupZip.decode(
            fixture({
              name: [1],
            }),
          ),
          throwsFormatException,
          reason: name,
        );
      }
      expect(
        () => BackupZip.encode({
          'files\\bad': [1],
        }),
        throwsFormatException,
      );
      final bytes = fixture({
        'files/bad': [1],
      });
      bytes[35] = 92;
      bytes[central(bytes) + 51] = 92;
      expect(() => BackupZip.decode(bytes), throwsFormatException);
    },
  );

  test(
    'rejects symbolic links and non-regular Unix entries before decoding',
    () {
      for (final mode in [0xa1ff, 0x41ed, 0x21a4]) {
        final bytes = fixture({
          'backup.json': [0xff],
        });
        final offset = central(bytes);
        write16(bytes, offset + 4, 0x0314);
        write32(bytes, offset + 38, mode << 16);
        expect(() => BackupZip.decode(bytes), throwsFormatException);
      }
    },
  );

  test(
    'rejects encryption flags and unsupported compression on either record',
    () {
      for (final flag in [1, 0x40, 0x2000]) {
        final bytes = fixture({
          'backup.json': [1],
        });
        write16(bytes, 6, read16(bytes, 6) | flag);
        write16(
          bytes,
          central(bytes) + 8,
          read16(bytes, central(bytes) + 8) | flag,
        );
        expect(() => BackupZip.decode(bytes), throwsFormatException);
      }
      for (final offset in [8, -1]) {
        final bytes = fixture({
          'backup.json': [1],
        });
        write16(bytes, offset == -1 ? central(bytes) + 10 : offset, 12);
        expect(() => BackupZip.decode(bytes), throwsFormatException);
      }
    },
  );

  test(
    'rejects compressed input, expanded totals and file counts over limits',
    () {
      expect(
        () => BackupZip.decode(Uint8List(maxBytes + 1)),
        throwsFormatException,
      );
      expect(
        () => BackupZip.encode({'backup.json': Uint8List(maxBytes + 1)}),
        throwsFormatException,
      );
      final tooMany = {for (var i = 0; i < 129; i++) 'files/$i': <int>[]};
      expect(() => BackupZip.encode(tooMany), throwsFormatException);
      expect(() => BackupZip.decode(fixture(tooMany)), throwsFormatException);
      final bytes = fixture({
        'backup.json': [1],
      });
      write32(bytes, central(bytes) + 24, maxBytes + 1);
      expect(() => BackupZip.decode(bytes), throwsFormatException);
      final twoFiles = fixture({
        'files/a': [1],
        'files/b': [2],
      });
      final first = central(twoFiles);
      final second =
          first +
          46 +
          read16(twoFiles, first + 28) +
          read16(twoFiles, first + 30) +
          read16(twoFiles, first + 32);
      write32(twoFiles, first + 24, maxBytes ~/ 2 + 1);
      write32(twoFiles, second + 24, maxBytes ~/ 2 + 1);
      expect(() => BackupZip.decode(twoFiles), throwsFormatException);
    },
  );

  test('bounds a deflate bomb even when its claimed expanded size is tiny', () {
    final bytes = fixture({'backup.json': Uint8List(1024 * 1024)});
    write32(bytes, central(bytes) + 24, 1);
    // A streaming writer leaves local sizes zero and records them after data.
    // Also alter that descriptor, so matching metadata cannot hide expansion.
    final directory = central(bytes);
    if (read16(bytes, 6) & 8 != 0) {
      write32(bytes, directory - 4, 1);
    } else {
      write32(bytes, 22, 1);
    }
    expect(() => BackupZip.decode(bytes), throwsFormatException);
  });

  test(
    'recovers exact CRC-checked bytes when the standard codec tolerates BFINAL',
    () {
      final bytes = fixture({'backup.json': List.filled(100, 65)});
      final start = 30 + read16(bytes, 26) + read16(bytes, 28);
      expect(bytes[start] & 1, 1);
      bytes[start] &= 0xfe;
      expect(BackupZip.decode(bytes)['backup.json'], List.filled(100, 65));
    },
  );

  test('rejects ZIP64, split disks and inconsistent local name or size', () {
    final valid = fixture({
      'backup.json': [1, 2, 3],
    });
    final mutations = <void Function(List<int>)>[
      (b) => write32(b, central(b) + 24, 0xffffffff),
      (b) => write16(b, b.length - 18, 1),
      (b) => write16(b, central(b) + 34, 1),
      (b) => b[30] = 120,
      (b) => write32(b, 18, 999),
    ];
    for (final mutate in mutations) {
      final bytes = valid.toList();
      mutate(bytes);
      expect(() => BackupZip.decode(bytes), throwsFormatException);
    }
  });
}
