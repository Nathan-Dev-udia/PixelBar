import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../domain/models/theme_layout.dart';

/// Pure-Dart ZIP archive reader/writer safe to execute inside `Isolate.run()`.
///
/// Supports Stored (method 0) and Deflate (method 8) entries, enforces strict
/// anti-path-traversal validation, and guards against zip bombs.
abstract final class ZipArchiveExtractor {
  static const int _localHeaderSig = 0x04034B50;
  static const int _centralHeaderSig = 0x02014B50;
  static const int _eocdSig = 0x06054B50;

  static const int _methodStored = 0;
  static const int _methodDeflate = 8;

  static void extractZipBytes(
    Uint8List bytes,
    String destinationDir, {
    int maxEntries = 500,
    int maxTotalBytes = 64 * 1024 * 1024,
  }) {
    final normalizedRoot = p.normalize(p.absolute(destinationDir));
    Directory(normalizedRoot).createSync(recursive: true);

    final data = ByteData.sublistView(bytes);
    final eocdOffset = _findEocdOffset(bytes, data);
    if (eocdOffset < 0) {
      throw const ThemeManifestException(
        'Arquivo inválido: cabeçalho ZIP (EOCD) não encontrado.',
      );
    }

    final entryCount = data.getUint16(eocdOffset + 10, Endian.little);
    final centralDirSize = data.getUint32(eocdOffset + 12, Endian.little);
    final centralDirOffset = data.getUint32(eocdOffset + 16, Endian.little);

    if (entryCount > maxEntries) {
      throw ThemeManifestException(
        'O pacote excede o limite máximo de $maxEntries arquivos.',
      );
    }
    if (centralDirOffset + centralDirSize > bytes.length) {
      throw const ThemeManifestException(
        'Arquivo ZIP corrompido: diretório central fora dos limites.',
      );
    }

    var cursor = centralDirOffset;
    var totalExtractedBytes = 0;

    for (var i = 0; i < entryCount; i++) {
      if (cursor + 46 > bytes.length ||
          data.getUint32(cursor, Endian.little) != _centralHeaderSig) {
        throw const ThemeManifestException(
          'Arquivo ZIP corrompido no diretório central.',
        );
      }

      final method = data.getUint16(cursor + 10, Endian.little);
      final compressedSize = data.getUint32(cursor + 20, Endian.little);
      final uncompressedSize = data.getUint32(cursor + 24, Endian.little);
      final nameLen = data.getUint16(cursor + 28, Endian.little);
      final extraLen = data.getUint16(cursor + 30, Endian.little);
      final commentLen = data.getUint16(cursor + 32, Endian.little);
      final localHeaderOffset = data.getUint32(cursor + 42, Endian.little);

      final nameStart = cursor + 46;
      final nameEnd = nameStart + nameLen;
      if (nameEnd > bytes.length) {
        throw const ThemeManifestException(
          'Arquivo ZIP corrompido: nome de entrada truncado.',
        );
      }

      final rawName = utf8.decode(
        bytes.sublist(nameStart, nameEnd),
        allowMalformed: true,
      );
      cursor = nameEnd + extraLen + commentLen;

      final isDir = rawName.endsWith('/');
      final cleanRelative = _validateEntryPath(rawName);
      if (cleanRelative == null) {
        continue;
      }

      final outPath = p.normalize(p.join(normalizedRoot, cleanRelative));
      if (!p.isWithin(normalizedRoot, outPath)) {
        throw ThemeManifestException(
          'Path traversal bloqueado no pacote: "$rawName".',
        );
      }

      if (isDir) {
        Directory(outPath).createSync(recursive: true);
        continue;
      }

      if (uncompressedSize > maxTotalBytes ||
          totalExtractedBytes + uncompressedSize > maxTotalBytes) {
        throw const ThemeManifestException(
          'O pacote de tema excede o limite de 64 MB descompactados.',
        );
      }

      if (localHeaderOffset + 30 > bytes.length ||
          data.getUint32(localHeaderOffset, Endian.little) != _localHeaderSig) {
        throw ThemeManifestException(
          'Cabeçalho local inválido para "$rawName".',
        );
      }

      final localNameLen = data.getUint16(
        localHeaderOffset + 26,
        Endian.little,
      );
      final localExtraLen = data.getUint16(
        localHeaderOffset + 28,
        Endian.little,
      );
      final payloadStart =
          localHeaderOffset + 30 + localNameLen + localExtraLen;
      final payloadEnd = payloadStart + compressedSize;
      if (payloadEnd > bytes.length) {
        throw ThemeManifestException(
          'Dados compactados truncados para "$rawName".',
        );
      }

      final compressedSlice = Uint8List.sublistView(
        bytes,
        payloadStart,
        payloadEnd,
      );
      final Uint8List content;
      if (method == _methodStored) {
        content = compressedSlice;
      } else if (method == _methodDeflate) {
        content = Uint8List.fromList(
          ZLibCodec(raw: true).decode(compressedSlice),
        );
      } else {
        throw ThemeManifestException(
          'Método de compressão ZIP ($method) não suportado para "$rawName".',
        );
      }

      totalExtractedBytes += content.length;
      if (totalExtractedBytes > maxTotalBytes) {
        throw const ThemeManifestException(
          'O pacote de tema excede o limite de 64 MB descompactados.',
        );
      }

      final outFile = File(outPath);
      outFile.parent.createSync(recursive: true);
      outFile.writeAsBytesSync(content, flush: false);
    }
  }

  /// Creates a valid ZIP archive in memory (useful for tests & export).
  static Uint8List createZipBytes(
    Map<String, Uint8List> files, {
    bool compress = true,
  }) {
    final out = BytesBuilder(copy: false);
    final central = BytesBuilder(copy: false);
    var offset = 0;

    for (final entry in files.entries) {
      final nameBytes = utf8.encode(entry.key);
      final raw = entry.value;
      final crc = _crc32(raw);

      var method = _methodStored;
      var payload = raw;
      if (compress && raw.isNotEmpty) {
        final deflated = Uint8List.fromList(ZLibCodec(raw: true).encode(raw));
        if (deflated.length < raw.length) {
          method = _methodDeflate;
          payload = deflated;
        }
      }

      final localHeader = ByteData(30);
      localHeader.setUint32(0, _localHeaderSig, Endian.little);
      localHeader.setUint16(4, 20, Endian.little);
      localHeader.setUint16(8, method, Endian.little);
      localHeader.setUint32(14, crc, Endian.little);
      localHeader.setUint32(18, payload.length, Endian.little);
      localHeader.setUint32(22, raw.length, Endian.little);
      localHeader.setUint16(26, nameBytes.length, Endian.little);

      out.add(localHeader.buffer.asUint8List());
      out.add(nameBytes);
      out.add(payload);

      final centralHeader = ByteData(46);
      centralHeader.setUint32(0, _centralHeaderSig, Endian.little);
      centralHeader.setUint16(4, 20, Endian.little);
      centralHeader.setUint16(6, 20, Endian.little);
      centralHeader.setUint16(10, method, Endian.little);
      centralHeader.setUint32(16, crc, Endian.little);
      centralHeader.setUint32(20, payload.length, Endian.little);
      centralHeader.setUint32(24, raw.length, Endian.little);
      centralHeader.setUint16(28, nameBytes.length, Endian.little);
      centralHeader.setUint32(42, offset, Endian.little);

      central.add(centralHeader.buffer.asUint8List());
      central.add(nameBytes);

      offset += 30 + nameBytes.length + payload.length;
    }

    final centralBytes = central.toBytes();
    out.add(centralBytes);

    final eocd = ByteData(22);
    eocd.setUint32(0, _eocdSig, Endian.little);
    eocd.setUint16(8, files.length, Endian.little);
    eocd.setUint16(10, files.length, Endian.little);
    eocd.setUint32(12, centralBytes.length, Endian.little);
    eocd.setUint32(16, offset, Endian.little);
    out.add(eocd.buffer.asUint8List());

    return out.toBytes();
  }

  static int _findEocdOffset(Uint8List bytes, ByteData data) {
    if (bytes.length < 22) return -1;
    final minOffset = (bytes.length - 65557).clamp(0, bytes.length - 22);
    for (var i = bytes.length - 22; i >= minOffset; i--) {
      if (data.getUint32(i, Endian.little) == _eocdSig) {
        return i;
      }
    }
    return -1;
  }

  static String? _validateEntryPath(String rawName) {
    if (rawName.isEmpty || rawName.contains('\x00')) {
      throw ThemeManifestException('Entrada ZIP inválida: "$rawName".');
    }
    if (rawName.contains('\\') || rawName.contains(':')) {
      throw ThemeManifestException(
        'Path traversal bloqueado no pacote: "$rawName".',
      );
    }
    if (rawName.startsWith('/')) {
      throw ThemeManifestException(
        'Caminho absoluto bloqueado no pacote: "$rawName".',
      );
    }
    final trimmed = rawName.endsWith('/')
        ? rawName.substring(0, rawName.length - 1)
        : rawName;
    if (trimmed.isEmpty || trimmed == '.') {
      return null;
    }
    final segments = trimmed.split('/');
    for (final seg in segments) {
      if (seg == '..' || seg.isEmpty) {
        throw ThemeManifestException(
          'Path traversal bloqueado no pacote: "$rawName".',
        );
      }
    }
    return segments.join(Platform.pathSeparator);
  }

  static int _crc32(Uint8List bytes) {
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc ^= b;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : (crc >>> 1);
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}
