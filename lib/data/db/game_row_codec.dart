import 'dart:convert';

import '../../domain/models/game_item.dart';
import '../../domain/models/launch_config.dart';

/// Top-level (isolate-friendly) row ⇄ model conversion.

Map<String, Object?> gameToRow(GameItem g) => {
  'id': g.id,
  'title': g.title,
  'sort_title': g.sortTitle,
  'kind': g.kind.name,
  'source': g.source.name,
  'platform': g.platform,
  'category_override': g.categoryOverride,
  'launch_json': jsonEncode(g.launch.toJson()),
  'media_json': jsonEncode(g.media.toJson()),
  'favorite': g.favorite ? 1 : 0,
  'hidden': g.hidden ? 1 : 0,
  'play_count': g.playCount,
  'last_played_at': g.lastPlayedAt?.millisecondsSinceEpoch,
  'added_at': g.addedAt.millisecondsSinceEpoch,
};

GameItem gameFromRow(Map<String, Object?> row) {
  final lastPlayed = row['last_played_at'] as int?;
  return GameItem(
    id: row['id']! as String,
    title: row['title']! as String,
    kind: GameKind.values.asNameMap()[row['kind']] ?? GameKind.androidNative,
    source: GameSource.values.asNameMap()[row['source']] ?? GameSource.scanned,
    platform: row['platform']! as String,
    categoryOverride: row['category_override'] as String?,
    launch: LaunchConfig.fromJson(
      (jsonDecode(row['launch_json']! as String) as Map)
          .cast<String, Object?>(),
    ),
    media: MediaAssets.fromJson(
      (jsonDecode(row['media_json']! as String) as Map).cast<String, Object?>(),
    ),
    favorite: row['favorite'] == 1,
    hidden: row['hidden'] == 1,
    playCount: row['play_count'] as int? ?? 0,
    lastPlayedAt: lastPlayed == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastPlayed),
    addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at']! as int),
  );
}

/// Decodes rows, skipping (not crashing on) corrupt entries.
List<GameItem> decodeGameRows(List<Map<String, Object?>> rows) {
  final out = <GameItem>[];
  for (final r in rows) {
    try {
      out.add(gameFromRow(r));
    } on Object {
      // A single bad row must never take the launcher down.
    }
  }
  return out;
}

List<Map<String, Object?>> encodeGameRows(List<GameItem> games) => [
  for (final g in games) gameToRow(g),
];
