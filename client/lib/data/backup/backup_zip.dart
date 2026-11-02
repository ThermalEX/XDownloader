import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A bounded, in-memory ZIP container. It never extracts paths to disk.
class BackupZip {
  static const maxBytes = 16 * 1024 * 1024;
  static const maxFiles = 128;

  static List<int> encode(Map<String, List<int>> files) {
    if (files.length > maxFiles) {
      throw const FormatException('备份文件数量过多');
    }
    var size = 0;
    final archive = Archive();
    final names = files.keys.toList()..sort();
    for (final name in names) {
      _checkPath(name);
      final bytes = files[name]!;
      size += bytes.length;
      if (size > maxBytes) {
        throw const FormatException('备份解压后超过 16 MiB');
      }
      _checkBytes(bytes);
      archive.add(ArchiveFile.bytes(name, Uint8List.fromList(bytes)));
    }
    final bytes = ZipEncoder().encodeBytes(
      archive,
      modified: DateTime.utc(2000, 1, 1),
    );
    if (bytes.length > maxBytes) {
      throw const FormatException('备份 ZIP 超过 16 MiB');
    }
    return bytes.asUnmodifiableView();
  }

  static Map<String, List<int>> decode(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('备份 ZIP 超过 16 MiB');
    }
    _checkBytes(bytes);
    final input = Uint8List.fromList(bytes);
    try {
      // ZipDecoder can eagerly decompress symlinks and merges duplicate names.
      // Validate every record before allowing it to construct any entries.
      final headers = _preflight(input);
      final archive = ZipDecoder().decodeBytes(input);
      if (archive.length != headers.length) {
        throw const FormatException('备份 ZIP 文件数量不一致');
      }
      final result = <String, List<int>>{};
      for (final header in headers) {
        final file = archive.find(header.filename);
        if (file == null || !file.isFile || file.isSymbolicLink) {
          throw const FormatException('备份 ZIP 包含不支持的文件');
        }
        // archive 4.5.2 bounds decoding to the preflighted expanded size.
        // Its ZipDecoder verify option does not check CRC, so do it here.
        // Standard codec end-marker recovery still requires exact size and CRC.
        final content = file.readBytes();
        if (content == null ||
            content.length != header.uncompressedSize ||
            getCrc32(content) != header.crc32) {
          throw const FormatException('备份 ZIP 文件长度或校验和错误');
        }
        result[header.filename] = Uint8List.fromList(content)
            .asUnmodifiableView();
      }
      return Map.unmodifiable(result);
    } on ArchiveException {
      throw const FormatException('备份 ZIP 已损坏或解压大小超限');
    } on FormatException {
      rethrow;
    } on RangeError {
      throw const FormatException('备份 ZIP 已截断');
    } on StateError {
      throw const FormatException('备份 ZIP 格式无效');
    }
  }

  static List<ZipFileHeader> _preflight(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    int u16(int offset) => data.getUint16(offset, Endian.little);
    int u32(int offset) => data.getUint32(offset, Endian.little);
    void require(bool valid) {
      if (!valid) throw const FormatException('备份 ZIP 结构无效');
    }

    require(bytes.length >= 22);
    var end = -1;
    for (
      var offset = bytes.length - 22;
      offset >= max(0, bytes.length - 22 - 65535);
      offset--
    ) {
      if (u32(offset) == ZipDirectory.eocdSignature) {
        end = offset;
        break;
      }
    }
    require(end >= 0);
    require(end + 22 + u16(end + 20) == bytes.length);
    final count = u16(end + 10);
    final directorySize = u32(end + 12);
    final directoryStart = u32(end + 16);
    require(u16(end + 4) == 0 && u16(end + 6) == 0);
    require(u16(end + 8) == count && count <= maxFiles);
    require(directoryStart + directorySize == end);
    require(directoryStart <= end);
    // No ZIP64 locator/EOCD or other records may hide between these regions.
    if (end >= 20) {
      require(u32(end - 20) != ZipDirectory.zip64EocdLocatorSignature);
    }

    final names = <String>{};
    final headers = <ZipFileHeader>[];
    var cursor = directoryStart;
    var expandedSize = 0;
    for (var i = 0; i < count; i++) {
      require(cursor + 46 <= end);
      require(u32(cursor) == ZipFileHeader.signature);
      final nameLength = u16(cursor + 28);
      final extraLength = u16(cursor + 30);
      final commentLength = u16(cursor + 32);
      final next = cursor + 46 + nameLength + extraLength + commentLength;
      require(next <= end);
      final rawName = utf8.decode(
        Uint8List.sublistView(bytes, cursor + 46, cursor + 46 + nameLength),
      );
      _checkPath(rawName);
      require(names.add(rawName));
      _checkExtra(bytes, cursor + 46 + nameLength, extraLength);
      final header = ZipFileHeader()
        ..read(
          InputMemoryStream(
            bytes,
            offset: cursor + 4,
            length: next - cursor - 4,
          ),
        );
      require(header.filename == rawName);
      require(header.versionNeededToExtract <= 20);
      require(header.diskNumberStart == 0);
      require(header.localHeaderOffset < directoryStart);
      _checkFlags(header.generalPurposeBitFlag, header.compressionMethod);
      final fileType = (header.externalFileAttributes >> 16) & 0xf000;
      require(fileType == 0 || fileType == 0x8000);
      require(header.externalFileAttributes & 0x10 == 0);
      require(header.compressedSize <= maxBytes);
      expandedSize += header.uncompressedSize;
      require(expandedSize <= maxBytes);
      if (header.compressionMethod == 0) {
        require(header.compressedSize == header.uncompressedSize);
      }
      headers.add(header);
      cursor = next;
    }
    require(cursor == end);

    final byOffset = headers.toList()
      ..sort((a, b) => a.localHeaderOffset.compareTo(b.localHeaderOffset));
    cursor = 0;
    for (final header in byOffset) {
      final offset = header.localHeaderOffset;
      require(offset == cursor && offset + 30 <= directoryStart);
      require(u32(offset) == ZipFile.zipSignature);
      require(u16(offset + 4) == header.versionNeededToExtract);
      require(u16(offset + 6) == header.generalPurposeBitFlag);
      require(u16(offset + 8) == header.compressionMethod);
      final nameLength = u16(offset + 26);
      final extraLength = u16(offset + 28);
      final contentStart = offset + 30 + nameLength + extraLength;
      final contentEnd = contentStart + header.compressedSize;
      require(contentStart <= directoryStart && contentEnd <= directoryStart);
      final localName = utf8.decode(
        Uint8List.sublistView(bytes, offset + 30, offset + 30 + nameLength),
      );
      require(localName == header.filename);
      _checkExtra(bytes, offset + 30 + nameLength, extraLength);
      final hasDescriptor = header.generalPurposeBitFlag & 8 != 0;
      for (final field in [
        (14, header.crc32),
        (18, header.compressedSize),
        (22, header.uncompressedSize),
      ]) {
        final local = u32(offset + field.$1);
        require(local == field.$2 || (hasDescriptor && local == 0));
      }
      cursor = contentEnd;
      if (hasDescriptor) {
        require(cursor + 12 <= directoryStart);
        if (u32(cursor) == 0x08074b50) cursor += 4;
        require(cursor + 12 <= directoryStart);
        require(u32(cursor) == header.crc32);
        require(u32(cursor + 4) == header.compressedSize);
        require(u32(cursor + 8) == header.uncompressedSize);
        cursor += 12;
      }
    }
    require(cursor == directoryStart);
    return headers;
  }

  static void _checkFlags(int flags, int method) {
    // Only UTF-8, a data descriptor and deflate's compression-level bits.
    if (flags & ~0x080e != 0 ||
        (method != 0 && method != 8) ||
        (method == 0 && flags & 6 != 0)) {
      throw const FormatException('备份 ZIP 使用了不支持的压缩或加密方式');
    }
  }

  static void _checkExtra(Uint8List bytes, int start, int length) {
    final data = ByteData.sublistView(bytes);
    final end = start + length;
    var cursor = start;
    while (cursor < end) {
      if (cursor + 4 > end) {
        throw const FormatException('备份 ZIP 扩展字段已截断');
      }
      final id = data.getUint16(cursor, Endian.little);
      final size = data.getUint16(cursor + 2, Endian.little);
      cursor += 4 + size;
      if (cursor > end || id == 1 || id == 0x9901) {
        throw const FormatException('备份 ZIP 包含不支持的扩展字段');
      }
    }
  }

  static void _checkPath(String name) {
    if (name.isEmpty ||
        utf8.encode(name).length > 1024 ||
        RegExp(r'[\x00-\x1f\x7f\\<>:"|?*]').hasMatch(name)) {
      throw const FormatException('备份 ZIP 文件路径无效');
    }
    for (final segment in name.split('/')) {
      if (segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.trim() != segment ||
          segment.endsWith('.')) {
        throw const FormatException('备份 ZIP 文件路径无效');
      }
    }
  }

  static void _checkBytes(List<int> bytes) {
    if (bytes.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('备份包含无效字节');
    }
  }
}
