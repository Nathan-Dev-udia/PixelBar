import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the SQLite connection. sqflite executes queries on a native
/// background thread; row decoding happens in an isolate (see repository).
class AppDatabase {
  AppDatabase({this.fileName = 'ondadeck.db'});

  static const int schemaVersion = 1;
  static const gamesTable = 'games';
  static const settingsTable = 'settings';

  final String fileName;
  Future<Database>? _db;

  Future<Database> get database => _db ??= _open(fileName);

  static Future<Database> _open(String fileName) async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, fileName),
      version: schemaVersion,
      onConfigure: (db) async {
        // PRAGMAs return rows; on Android they must go through rawQuery.
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.rawQuery('PRAGMA synchronous=NORMAL');
      },
      onCreate: (db, version) async {
        final batch = db.batch()
          ..execute('''
            CREATE TABLE $gamesTable (
              id TEXT PRIMARY KEY NOT NULL,
              title TEXT NOT NULL,
              sort_title TEXT NOT NULL,
              kind TEXT NOT NULL,
              source TEXT NOT NULL,
              platform TEXT NOT NULL,
              category_override TEXT,
              launch_json TEXT NOT NULL,
              media_json TEXT NOT NULL,
              favorite INTEGER NOT NULL DEFAULT 0,
              hidden INTEGER NOT NULL DEFAULT 0,
              play_count INTEGER NOT NULL DEFAULT 0,
              last_played_at INTEGER,
              added_at INTEGER NOT NULL
            )''')
          ..execute(
            'CREATE INDEX idx_games_kind_platform ON $gamesTable(kind, platform)',
          )
          ..execute(
            'CREATE INDEX idx_games_last_played ON $gamesTable(last_played_at DESC)',
          )
          ..execute(
            'CREATE INDEX idx_games_sort_title ON $gamesTable(sort_title)',
          )
          ..execute('''
            CREATE TABLE $settingsTable (
              key TEXT PRIMARY KEY NOT NULL,
              value TEXT NOT NULL
            )''');
        await batch.commit(noResult: true);
      },
    );
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await (await db)?.close();
  }
}
