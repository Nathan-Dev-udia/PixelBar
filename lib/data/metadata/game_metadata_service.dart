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

/// Playnite-style metadata lookup and media downloader using keyless multi-platform
/// sources: Steam Store (PC/Multi), Nintendo Europe (Switch/Wii/3DS/Retro),
/// Wikipedia PT/EN (PS2/PS3/PSP/Nintendo/Console exclusives), plus optional
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

  static const String _userAgent =
      'OndaDeck/1.0 (https://github.com/Nathan-Dev-udia/PixelBar)';

  // ---- Isolate-safe network helpers -----------------------------------------

  static Future<List<MetadataCandidate>> _searchRemoteSync(
    String query,
    String steamGridDbApiKey,
  ) async {
    final batches = await Future.wait<List<MetadataCandidate>>([
      _searchSteam(query),
      _searchNintendo(query),
      _searchWikipedia(query, lang: 'pt'),
      _searchWikipedia(query, lang: 'en'),
      if (steamGridDbApiKey.isNotEmpty)
        _searchSteamGridDb(query, steamGridDbApiKey),
    ]);

    final combined = <MetadataCandidate>[];
    for (final batch in batches) {
      combined.addAll(batch);
    }

    return rankAndDeduplicateCandidates(query, combined);
  }

  /// Ranks candidates by title relevance and artwork availability while
  /// removing exact duplicate `(provider, externalId)` entries.
  static List<MetadataCandidate> rankAndDeduplicateCandidates(
    String query,
    List<MetadataCandidate> candidates,
  ) {
    final seenKeys = <String>{};
    final unique = <MetadataCandidate>[];
    for (final c in candidates) {
      final key = '${c.provider}:${c.externalId}';
      if (seenKeys.add(key)) {
        unique.add(c);
      }
    }

    final normQuery = _normalizeTitle(query);
    final queryTokens = normQuery
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    int score(MetadataCandidate c) {
      final normTitle = _normalizeTitle(c.title);
      var s = 0;
      if (normTitle == normQuery) {
        s += 100;
      } else if (normTitle.startsWith(normQuery)) {
        s += 75;
      } else if (normTitle.contains(normQuery)) {
        s += 55;
      } else if (queryTokens.isNotEmpty) {
        var matched = 0;
        for (final token in queryTokens) {
          if (normTitle.contains(token)) matched++;
        }
        s += ((matched * 45) ~/ queryTokens.length);
      }

      if (c.coverUrl != null && c.coverUrl!.isNotEmpty) s += 16;
      if (c.bannerUrl != null && c.bannerUrl!.isNotEmpty) s += 8;
      if (c.description != null && c.description!.isNotEmpty) s += 6;

      if (c.provider == 'Steam' || c.provider.startsWith('Nintendo')) {
        s += 8;
      } else if (c.provider == 'Wikipedia PT') {
        s += 5;
      } else if (c.provider == 'Wikipedia EN') {
        s += 3;
      }
      return s;
    }

    unique.sort((a, b) => score(b).compareTo(score(a)));
    return unique;
  }

  static Future<List<MetadataCandidate>> _searchSteam(String query) async {
    final results = <MetadataCandidate>[];
    try {
      final steamUri = Uri.parse(
        'https://store.steampowered.com/api/storesearch/?term=${Uri.encodeQueryComponent(query)}&l=brazilian&cc=BR',
      );
      final raw = await _httpGetJson(steamUri);
      if (raw is Map) {
        final items = raw['items'];
        if (items is List) {
          for (final item in items.take(8)) {
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
      // Non-fatal: other providers still return results.
    }
    return results;
  }

  static Future<List<MetadataCandidate>> _searchNintendo(String query) async {
    try {
      final uri = Uri.parse(
        'https://searching.nintendo-europe.com/pt/select?q=${Uri.encodeQueryComponent(query)}&fq=type:GAME&rows=8&wt=json',
      );
      final raw = await _httpGetJson(uri);
      return parseNintendoResponse(raw);
    } on Object {
      return const [];
    }
  }

  /// Parses the official Nintendo Europe public Solr JSON response into
  /// [MetadataCandidate] items (Switch, Wii U, Wii, 3DS, DS, GameCube, N64, SNES, NES, GBA).
  static List<MetadataCandidate> parseNintendoResponse(Object? raw) {
    if (raw is! Map) return const [];
    final response = raw['response'];
    if (response is! Map) return const [];
    final docs = response['docs'];
    if (docs is! List) return const [];

    final results = <MetadataCandidate>[];
    for (final doc in docs.take(8)) {
      if (doc is! Map) continue;
      final id = doc['fs_id']?.toString() ?? '';
      final title = (doc['title'] as String? ?? '').trim();
      if (id.isEmpty || title.isEmpty) continue;

      final systems = doc['system_names_txt'];
      final systemLabel = systems is List && systems.isNotEmpty
          ? systems.first.toString().trim()
          : '';
      final providerLabel = systemLabel.isNotEmpty
          ? 'Nintendo ($systemLabel)'
          : 'Nintendo';

      final descRaw =
          (doc['product_catalog_description_s'] as String?) ??
          (doc['excerpt'] as String?) ??
          '';
      final description = _stripHtml(descRaw);

      final publisher = (doc['publisher'] as String? ?? '').trim();

      String? year;
      final dates = doc['dates_released_dts'];
      if (dates is List && dates.isNotEmpty) {
        year = _extractYear(dates.first.toString());
      }
      year ??= _extractYear(doc['pretty_date_s']?.toString() ?? '');

      final squareUrl = _normalizeImageUrl(
        (doc['image_url_sq_s'] as String?) ??
            (doc['wishlist_email_square_image_url_s'] as String?),
      );
      final packshotUrl = _normalizeImageUrl(doc['image_url'] as String?);
      final bannerUrl = _normalizeImageUrl(
        (doc['image_url_h2x1_s'] as String?) ??
            (doc['wishlist_email_banner640w_image_url_s'] as String?) ??
            squareUrl ??
            packshotUrl,
      );

      results.add(
        MetadataCandidate(
          provider: providerLabel,
          externalId: id,
          title: title,
          description: description.isNotEmpty ? description : null,
          developer: publisher.isNotEmpty ? publisher : 'Nintendo',
          releaseYear: year,
          iconUrl: squareUrl ?? packshotUrl,
          coverUrl: packshotUrl ?? squareUrl,
          bannerUrl: bannerUrl,
          backgroundUrl: bannerUrl ?? packshotUrl ?? squareUrl,
        ),
      );
    }
    return results;
  }

  static Future<List<MetadataCandidate>> _searchWikipedia(
    String query, {
    required String lang,
  }) async {
    try {
      final searchTerm = lang == 'en' ? '$query video game' : query;
      final uri = Uri.parse(
        'https://$lang.wikipedia.org/w/api.php'
        '?action=query'
        '&generator=search'
        '&gsrsearch=${Uri.encodeQueryComponent(searchTerm)}'
        '&gsrlimit=6'
        '&prop=pageimages|extracts'
        '&pilicense=any'
        '&piprop=original|thumbnail'
        '&pithumbsize=600'
        '&exintro=1'
        '&explaintext=1'
        '&exsentences=4'
        '&format=json',
      );
      final raw = await _httpGetJson(uri);
      return parseWikipediaResponse(raw, lang: lang);
    } on Object {
      return const [];
    }
  }

  /// Parses MediaWiki `action=query` (`pageimages|extracts`) JSON into
  /// console/multi-platform [MetadataCandidate] items (PS2, PS3, PSP, Nintendo, etc.).
  static List<MetadataCandidate> parseWikipediaResponse(
    Object? raw, {
    required String lang,
  }) {
    if (raw is! Map) return const [];
    final queryNode = raw['query'];
    if (queryNode is! Map) return const [];
    final pages = queryNode['pages'];
    if (pages is! Map) return const [];

    final entries = pages.values.whereType<Map>().toList()
      ..sort((a, b) {
        final ai = (a['index'] as num?)?.toInt() ?? 999;
        final bi = (b['index'] as num?)?.toInt() ?? 999;
        return ai.compareTo(bi);
      });

    final providerLabel = lang == 'pt' ? 'Wikipedia PT' : 'Wikipedia EN';
    final results = <MetadataCandidate>[];

    for (final page in entries) {
      final pageId = page['pageid']?.toString() ?? '';
      final rawTitle = (page['title'] as String? ?? '').trim();
      final extract = (page['extract'] as String? ?? '').trim();
      if (pageId.isEmpty || rawTitle.isEmpty) continue;
      if (!_looksLikeVideoGameArticle(rawTitle, extract)) continue;

      final cleanTitle = _cleanWikipediaTitle(rawTitle);
      final original = page['original'];
      final thumb = page['thumbnail'];
      final originalUrl = original is Map
          ? _normalizeImageUrl(original['source'] as String?)
          : null;
      final thumbUrl = thumb is Map
          ? _normalizeImageUrl(thumb['source'] as String?)
          : null;
      final bestImage = originalUrl ?? thumbUrl;

      results.add(
        MetadataCandidate(
          provider: providerLabel,
          externalId: '$lang:$pageId',
          title: cleanTitle,
          description: extract.isNotEmpty ? extract : null,
          developer: _extractDeveloperFromSummary(extract),
          releaseYear: _extractYear(extract),
          iconUrl: thumbUrl ?? originalUrl,
          coverUrl: bestImage,
          bannerUrl: bestImage,
          backgroundUrl: bestImage,
        ),
      );
    }
    return results;
  }

  static Future<List<MetadataCandidate>> _searchSteamGridDb(
    String query,
    String steamGridDbApiKey,
  ) async {
    final results = <MetadataCandidate>[];
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
    return results;
  }

  static bool _looksLikeVideoGameArticle(String title, String extract) {
    final haystack = '${title.toLowerCase()} ${extract.toLowerCase()}';
    const keywords = [
      'jogo eletrônico',
      'jogo eletrónico',
      'video game',
      'videogame',
      'playstation',
      'ps2',
      'ps3',
      'ps4',
      'ps5',
      'psp',
      'ps vita',
      'nintendo',
      'gamecube',
      'game boy',
      'super nintendo',
      'snes',
      'n64',
      'wii',
      'switch',
      'xbox',
      'sega',
      'dreamcast',
      'mega drive',
      'atari',
      'arcade',
      'console',
      'hack and slash',
      'role-playing',
      'rpg',
      'action-adventure',
      'ação-aventura',
      'first-person shooter',
      'platformer',
      'jogo de plataforma',
      'desenvolvido pela',
      'desenvolvido por',
      'developed by',
      'remaster',
      'coletânea',
      'collection',
    ];
    return keywords.any(haystack.contains);
  }

  static String _cleanWikipediaTitle(String title) {
    return title
        .replaceAll(
          RegExp(
            r'\s*\((?:\d{4}\s+)?(?:video game|jogo eletrônico|jogo eletrónico|jogo|game|series|franchise|série)\)$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  static String? _extractYear(String text) {
    final match = RegExp(r'\b(19[7-9]\d|20\d{2})\b').firstMatch(text);
    return match?.group(1);
  }

  static String? _extractDeveloperFromSummary(String extract) {
    if (extract.isEmpty) return null;
    final patterns = [
      RegExp(
        r'desenvolvido (?:pela|pelo|por) ([^.,;\n]+?)(?:\s+e publicado|\s+para|[.,;])',
        caseSensitive: false,
      ),
      RegExp(
        r'developed by ([^.,;\n]+?)(?:\s+and published|\s+for|[.,;])',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(extract);
      final dev = match?.group(1)?.trim();
      if (dev != null && dev.isNotEmpty && dev.length <= 60) {
        return dev;
      }
    }
    return null;
  }

  static String? _normalizeImageUrl(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return null;
  }

  static String _normalizeTitle(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
      req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
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
      req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
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
