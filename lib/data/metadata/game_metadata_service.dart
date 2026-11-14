import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/game_item.dart';

@immutable
class MetadataCandidate {
  const MetadataCandidate({
    required this.provider,
    required this.externalId,
    required this.title,
    this.description,
    this.developer,
    this.releaseYear,
    this.iconUrl,
    this.logoUrl,
    this.coverUrl,
    this.bannerUrl,
    this.backgroundUrl,
  });

  final String provider;
  final String externalId;
  final String title;
  final String? description;
  final String? developer;
  final String? releaseYear;
  final String? iconUrl;
  final String? logoUrl;
  final String? coverUrl;
  final String? bannerUrl;
  final String? backgroundUrl;

  MetadataCandidate copyWith({
    String? title,
    String? description,
    String? developer,
    String? releaseYear,
    String? iconUrl,
    String? logoUrl,
    String? coverUrl,
    String? bannerUrl,
    String? backgroundUrl,
  }) => MetadataCandidate(
    provider: provider,
    externalId: externalId,
    title: title ?? this.title,
    description: description ?? this.description,
    developer: developer ?? this.developer,
    releaseYear: releaseYear ?? this.releaseYear,
    iconUrl: iconUrl ?? this.iconUrl,
    logoUrl: logoUrl ?? this.logoUrl,
    coverUrl: coverUrl ?? this.coverUrl,
    bannerUrl: bannerUrl ?? this.bannerUrl,
    backgroundUrl: backgroundUrl ?? this.backgroundUrl,
  );
}

/// Playnite-style metadata lookup and media downloader using the keyless Steam
/// Store API (PT-BR descriptions & official Steam artwork) with optional
/// SteamGridDB API v2 enrichment.
class GameMetadataService {
  GameMetadataService({
    Future<List<MetadataCandidate>> Function(
      String query, {
      String? steamGridDbApiKey,
    })?
    searchOverride,
    Future<MetadataCandidate> Function(
      MetadataCandidate candidate, {
      String? steamGridDbApiKey,
    })?
    detailsOverride,
    Future<Uint8List?> Function(String url)? downloadBytesOverride,
    Future<String> Function()? mediaDirProvider,
  }) : _searchOverride = searchOverride,
       _detailsOverride = detailsOverride,
       _downloadBytesOverride = downloadBytesOverride,
       _mediaDirProvider = mediaDirProvider ?? _defaultMediaDir;

  final Future<List<MetadataCandidate>> Function(
    String query, {
    String? steamGridDbApiKey,
  })?
  _searchOverride;
  final Future<MetadataCandidate> Function(
    MetadataCandidate candidate, {
    String? steamGridDbApiKey,
  })?
  _detailsOverride;
  final Future<Uint8List?> Function(String url)? _downloadBytesOverride;
  final Future<String> Function() _mediaDirProvider;

  static Future<String> _defaultMediaDir() async {
    try {
      final dbDir = await getDatabasesPath();
      return p.normalize(p.join(dbDir, '..', 'app_flutter', 'metadata_media'));
    } on Object {
      return p.join(Directory.systemTemp.path, 'ondadeck_metadata_media');
    }
  }

  Future<List<MetadataCandidate>> search(
    String query, {
    String? steamGridDbApiKey,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    if (_searchOverride != null) {
      return _searchOverride(trimmed, steamGridDbApiKey: steamGridDbApiKey);
    }
    final apiKey = steamGridDbApiKey?.trim() ?? '';
    return Isolate.run(
      () => _searchRemoteSync(trimmed, apiKey),
      debugName: 'GameMetadataService.search',
    );
  }

  Future<MetadataCandidate> fetchDetails(
    MetadataCandidate candidate, {
    String? steamGridDbApiKey,
  }) async {
    if (_detailsOverride != null) {
      return _detailsOverride(candidate, steamGridDbApiKey: steamGridDbApiKey);
    }
    final apiKey = steamGridDbApiKey?.trim() ?? '';
    return Isolate.run(
      () => _fetchDetailsRemoteSync(candidate, apiKey),
      debugName: 'GameMetadataService.fetchDetails',
    );
  }

  Future<GameItem> downloadAndApply({
    required GameItem game,
    required MetadataCandidate candidate,
    String? steamGridDbApiKey,
    bool applyText = true,
    bool downloadIcon = true,
    bool downloadLogo = true,
    bool downloadCover = true,
    bool downloadBanner = true,
    bool downloadBackground = true,
  }) async {
    final detailed = await fetchDetails(
      candidate,
      steamGridDbApiKey: steamGridDbApiKey,
    );

    final mediaRoot = await _mediaDirProvider();
    final safeGameId = game.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final gameMediaDir = p.join(mediaRoot, safeGameId);
    final stamp = DateTime.now().millisecondsSinceEpoch;

    Future<String?> fetchSlot(String? url, String prefix, String ext) async {
      if (url == null || url.isEmpty) return null;
      final bytes = _downloadBytesOverride != null
          ? await _downloadBytesOverride(url)
          : await Isolate.run(
              () => _downloadBytesSync(url),
              debugName: 'download_$prefix',
            );
      if (bytes == null || bytes.isEmpty) return null;
      final filePath = p.join(gameMediaDir, '${prefix}_$stamp$ext');
      await Isolate.run(() {
        Directory(gameMediaDir).createSync(recursive: true);
        File(filePath).writeAsBytesSync(bytes, flush: true);
      }, debugName: 'save_$prefix');
      return filePath;
    }

    String extensionFor(String? url, {String fallback = '.jpg'}) {
      if (url == null) return fallback;
      final pathPart = Uri.tryParse(url)?.path.toLowerCase() ?? '';
      if (pathPart.endsWith('.png')) return '.png';
      if (pathPart.endsWith('.webp')) return '.webp';
      if (pathPart.endsWith('.ico')) return '.ico';
      return fallback;
    }

    final iconPath = downloadIcon
        ? await fetchSlot(
            detailed.iconUrl,
            'icon',
            extensionFor(detailed.iconUrl),
          )
        : null;
    final logoPath = downloadLogo
        ? await fetchSlot(
            detailed.logoUrl,
            'logo',
            extensionFor(detailed.logoUrl, fallback: '.png'),
          )
        : null;
    final coverPath = downloadCover
        ? await fetchSlot(
            detailed.coverUrl,
            'cover',
            extensionFor(detailed.coverUrl),
          )
        : null;
    final bannerPath = downloadBanner
        ? await fetchSlot(
            detailed.bannerUrl,
            'banner',
            extensionFor(detailed.bannerUrl),
          )
        : null;
    final bgPath = downloadBackground
        ? await fetchSlot(
            detailed.backgroundUrl,
            'bg',
            extensionFor(detailed.backgroundUrl),
          )
        : null;

    final nextMedia = game.media.copyWith(
      iconPath: iconPath ?? game.media.iconPath,
      logoPath: logoPath ?? game.media.logoPath,
      coverPath: coverPath ?? game.media.coverPath,
      bannerPath: bannerPath ?? game.media.bannerPath,
      backgroundPath: bgPath ?? game.media.backgroundPath,
    );

    if (!applyText) {
      return game.copyWith(media: nextMedia);
    }

    return game.copyWith(
      title: detailed.title.trim().isNotEmpty ? detailed.title.trim() : null,
      titleCustomized: true,
      description:
          detailed.description != null &&
              detailed.description!.trim().isNotEmpty
          ? detailed.description!.trim()
          : game.description,
      developer:
          detailed.developer != null && detailed.developer!.trim().isNotEmpty
          ? detailed.developer!.trim()
          : game.developer,
      releaseYear:
          detailed.releaseYear != null &&
              detailed.releaseYear!.trim().isNotEmpty
          ? detailed.releaseYear!.trim()
          : game.releaseYear,
      media: nextMedia,
    );
  }

  // ---- Isolate-safe network helpers -----------------------------------------

  static Future<List<MetadataCandidate>> _searchRemoteSync(
    String query,
    String steamGridDbApiKey,
  ) async {
    final results = <MetadataCandidate>[];

    // 1. Keyless Steam Store Search API (free, no key required).
    try {
      final steamUri = Uri.parse(
        'https://store.steampowered.com/api/storesearch/?term=${Uri.encodeQueryComponent(query)}&l=brazilian&cc=BR',
      );
      final raw = await _httpGetJson(steamUri);
      if (raw is Map) {
        final items = raw['items'];
        if (items is List) {
          for (final item in items.take(12)) {
            if (item is! Map) continue;
            final id = item['id'];
            final name = item['name'] as String?;
            if (id == null || name == null || name.isEmpty) continue;
            final idStr = '$id';
            results.add(
              MetadataCandidate(
                provider: 'Steam',
                externalId: idStr,
                title: name,
                iconUrl: item['tiny_image'] as String?,
                logoUrl:
                    'https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/$idStr/logo.png',
                coverUrl:
                    'https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/$idStr/library_600x900.jpg',
                bannerUrl:
                    'https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/$idStr/header.jpg',
                backgroundUrl:
                    'https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/$idStr/library_hero.jpg',
              ),
            );
          }
        }
      }
    } on Object {
      // Non-fatal: still allow optional SteamGridDB lookup below.
    }

    // 2. Optional SteamGridDB v2 autocomplete when the user provided a key.
    if (steamGridDbApiKey.isNotEmpty) {
      try {
        final sgdbUri = Uri.parse(
          'https://www.steamgriddb.com/api/v2/search/autocomplete/${Uri.encodeComponent(query)}',
        );
        final raw = await _httpGetJson(
          sgdbUri,
          headers: {'Authorization': 'Bearer $steamGridDbApiKey'},
        );
        if (raw is Map && raw['success'] == true) {
          final data = raw['data'];
          if (data is List) {
            for (final item in data.take(10)) {
              if (item is! Map) continue;
              final id = item['id'];
              final name = item['name'] as String?;
              if (id == null || name == null || name.isEmpty) continue;
              final releaseDate = item['release_date'];
              String? year;
              if (releaseDate is num && releaseDate > 0) {
                year =
                    '${DateTime.fromMillisecondsSinceEpoch(releaseDate.toInt() * 1000, isUtc: true).year}';
              }
              results.add(
                MetadataCandidate(
                  provider: 'SteamGridDB',
                  externalId: '$id',
                  title: name,
                  releaseYear: year,
                ),
              );
            }
          }
        }
      } on Object {
        // Non-fatal fallback.
      }
    }

    return results;
  }

  static Future<MetadataCandidate> _fetchDetailsRemoteSync(
    MetadataCandidate candidate,
    String steamGridDbApiKey,
  ) async {
    if (candidate.provider == 'Steam') {
      try {
        final uri = Uri.parse(
          'https://store.steampowered.com/api/appdetails?appids=${Uri.encodeQueryComponent(candidate.externalId)}&l=brazilian',
        );
        final raw = await _httpGetJson(uri);
        if (raw is Map) {
          final entry = raw[candidate.externalId];
          if (entry is Map && entry['success'] == true) {
            final data = entry['data'];
            if (data is Map) {
              final shortDesc = _stripHtml(
                data['short_description'] as String? ?? '',
              );
              final devs = data['developers'];
              final dev = devs is List && devs.isNotEmpty
                  ? '${devs.first}'
                  : null;
              String? year;
              final rel = data['release_date'];
              if (rel is Map) {
                final dateStr = rel['date'] as String? ?? '';
                final yearMatch = RegExp(
                  r'\b(19|20)\d{2}\b',
                ).firstMatch(dateStr);
                year = yearMatch?.group(0);
              }
              final headerImage = data['header_image'] as String?;
              final bgRaw = data['background_raw'] as String?;
              final bgFallback = data['background'] as String?;
              return candidate.copyWith(
                title: data['name'] as String? ?? candidate.title,
                description: shortDesc.isNotEmpty
                    ? shortDesc
                    : candidate.description,
                developer: dev ?? candidate.developer,
                releaseYear: year ?? candidate.releaseYear,
                bannerUrl: headerImage ?? candidate.bannerUrl,
                backgroundUrl:
                    bgRaw ??
                    candidate.backgroundUrl ??
                    bgFallback ??
                    headerImage,
              );
            }
          }
        }
      } on Object {
        // Keep base Steam candidate URLs if appdetails fails or times out.
      }
      return candidate;
    }

    if (candidate.provider == 'SteamGridDB' && steamGridDbApiKey.isNotEmpty) {
      final headers = {'Authorization': 'Bearer $steamGridDbApiKey'};
      Future<String?> firstAsset(String endpoint) async {
        try {
          final uri = Uri.parse(
            'https://www.steamgriddb.com/api/v2/$endpoint/game/${Uri.encodeComponent(candidate.externalId)}',
          );
          final raw = await _httpGetJson(uri, headers: headers);
          if (raw is Map && raw['success'] == true) {
            final data = raw['data'];
            if (data is List && data.isNotEmpty) {
              final first = data.first;
              if (first is Map) {
                return first['url'] as String?;
              }
            }
          }
        } on Object {
          return null;
        }
        return null;
      }

      final coverUrl = await firstAsset('grids');
      final heroUrl = await firstAsset('heroes');
      final logoUrl = await firstAsset('logos');
      final iconUrl = await firstAsset('icons');
      return candidate.copyWith(
        coverUrl: coverUrl ?? candidate.coverUrl,
        backgroundUrl: heroUrl ?? candidate.backgroundUrl,
        bannerUrl: heroUrl ?? coverUrl ?? candidate.bannerUrl,
        logoUrl: logoUrl ?? candidate.logoUrl,
        iconUrl: iconUrl ?? candidate.iconUrl,
      );
    }

    return candidate;
  }

  static Future<Object?> _httpGetJson(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'OndaDeck/1.0');
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 12));
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  static Future<Uint8List?> _downloadBytesSync(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'OndaDeck/1.0');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
        // Guard against oversized responses (> 10 MB).
        if (builder.length > 10 * 1024 * 1024) {
          return null;
        }
      }
      return builder.takeBytes();
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String _stripHtml(String input) {
    if (input.isEmpty) return '';
    return input
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
