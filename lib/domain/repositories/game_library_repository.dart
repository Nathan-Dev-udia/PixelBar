import '../models/game_item.dart';
import '../models/launcher_settings.dart';

/// Persistence boundary for the library (implemented in `lib/data`).
abstract interface class GameLibraryRepository {
  Future<List<GameItem>> loadAll();
  Future<void> upsertAll(List<GameItem> games);
  Future<void> removeByIds(List<String> ids);
  Future<void> recordLaunch(String id, DateTime at);
  Future<void> setFavorite(String id, {required bool favorite});
  Future<void> setHidden(String id, {required bool hidden});
  Future<LauncherSettings> loadSettings();
  Future<void> saveSettings(LauncherSettings settings);
}
