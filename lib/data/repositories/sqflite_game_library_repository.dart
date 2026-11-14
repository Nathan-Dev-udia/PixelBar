import 'dart:convert';
import 'dart:isolate';

import 'package:sqflite/sqflite.dart';

import '../../domain/models/game_item.dart';
import '../../domain/models/launcher_settings.dart';
import '../../domain/repositories/game_library_repository.dart';
import '../db/app_database.dart';
import '../db/game_row_codec.dart';

class SqfliteGameLibraryRepository implements GameLibraryRepository {
  SqfliteGameLibraryRepository(this._database);

  static const _settingsKey = 'launcher_settings';

  final AppDatabase _database;

  @override
  Future<List<GameItem>> loadAll() async {
    final db = await _database.database;
    final rows = await db.query(AppDatabase.gamesTable);
    // Plain copies so the payload is trivially sendable to the isolate.
    final plain = [for (final r in rows) Map<String, Object?>.of(r)];
    return _decode(plain);
  }

  // Static: the isolate closure must not capture `this` (DB handle).
  static Future<List<GameItem>> _decode(List<Map<String, Object?>> rows) =>
      Isolate.run(() => decodeGameRows(rows), debugName: 'decodeGameRows');

  static Future<List<Map<String, Object?>>> _encode(List<GameItem> games) =>
      Isolate.run(() => encodeGameRows(games), debugName: 'encodeGameRows');

  @override
  Future<void> upsertAll(List<GameItem> games) async {
    if (games.isEmpty) return;
    final rows = await _encode(games);
    final db = await _database.database;
    final batch = db.batch();
    for (final row in rows) {
      batch.insert(
        AppDatabase.gamesTable,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> removeByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _database.database;
    final batch = db.batch();
    for (final id in ids) {
      batch.delete(AppDatabase.gamesTable, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> recordLaunch(String id, DateTime at) async {
    final db = await _database.database;
    await db.rawUpdate(
      'UPDATE ${AppDatabase.gamesTable} SET play_count = play_count + 1, last_played_at = ? WHERE id = ?',
      [at.millisecondsSinceEpoch, id],
    );
  }

  @override
  Future<void> setFavorite(String id, {required bool favorite}) =>
      _setFlag(id, 'favorite', favorite);

  @override
  Future<void> setHidden(String id, {required bool hidden}) =>
      _setFlag(id, 'hidden', hidden);

  Future<void> _setFlag(String id, String column, bool value) async {
    final db = await _database.database;
    await db.update(
      AppDatabase.gamesTable,
      {column: value ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<LauncherSettings> loadSettings() async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.settingsTable,
      where: 'key = ?',
      whereArgs: [_settingsKey],
      limit: 1,
    );
    if (rows.isEmpty) return const LauncherSettings();
    try {
      return LauncherSettings.fromJson(
        (jsonDecode(rows.first['value']! as String) as Map)
            .cast<String, Object?>(),
      );
    } on Object {
      return const LauncherSettings();
    }
  }

  @override
  Future<void> saveSettings(LauncherSettings settings) async {
    final db = await _database.database;
    await db.insert(AppDatabase.settingsTable, {
      'key': _settingsKey,
      'value': jsonEncode(settings.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
