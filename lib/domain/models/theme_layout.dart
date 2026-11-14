import 'dart:convert';

import 'package:flutter/foundation.dart';

class ThemeManifestException implements Exception {
  const ThemeManifestException(this.message);
  final String message;

  @override
  String toString() => 'ThemeManifestException: $message';
}

/// Supported declarative widget nodes inside `layout.json`.
enum ThemeNodeType {
  stack('Stack'),
  row('Row'),
  column('Column'),
  positioned('Positioned'),
  padding('Padding'),
  container('Container'),
  dynamicBackground('DynamicBackground'),
  mediaCarousel('MediaCarousel'),
  gameArtwork('GameArtwork'),
  metadataText('MetadataText');

  const ThemeNodeType(this.jsonName);
  final String jsonName;

  static final Map<String, ThemeNodeType> _byName = {
    for (final v in values) v.jsonName: v,
  };

  static ThemeNodeType? fromJsonName(String? raw) =>
      raw == null ? null : _byName[raw];
}

/// Validates that a static relative asset path inside a theme package does not
/// escape the theme directory (`../`, backslashes, or leading `/`).
void validateSafeRelativeAssetPath(String path, {required String context}) {
  if (path.isEmpty || path.contains('{{') || path.contains('://')) {
    return;
  }
  if (path.startsWith('/') ||
      path.contains('\\') ||
      path.contains(':') ||
      path.split('/').contains('..')) {
    throw ThemeManifestException(
      'Caminho inseguro em $context: "$path". Use apenas caminhos relativos dentro do pacote.',
    );
  }
}

/// Declarative AST node parsed from `layout.json` and interpreted by
/// `DataDrivenThemeEngine`.
@immutable
class ThemeLayoutNode {
  const ThemeLayoutNode({
    required this.type,
    this.props = const {},
    this.children = const [],
  });

  final ThemeNodeType type;
  final Map<String, Object?> props;
  final List<ThemeLayoutNode> children;

  static const Set<String> _assetPropKeys = {'image', 'src', 'soundOnMove'};

  /// Pure & synchronous: execute inside `Isolate.run()`.
  static ThemeLayoutNode parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw ThemeManifestException('layout.json inválido: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const ThemeManifestException(
        'A raiz do layout.json deve ser um objeto JSON.',
      );
    }
    return ThemeLayoutNode.fromJson(decoded);
  }

  factory ThemeLayoutNode.fromJson(Map<String, Object?> json) {
    final rawType = json['type'];
    if (rawType is! String) {
      throw const ThemeManifestException(
        'Todo nó do layout.json precisa de um campo "type" (String).',
      );
    }
    final type = ThemeNodeType.fromJsonName(rawType);
    if (type == null) {
      throw ThemeManifestException(
        'Componente "$rawType" não suportado no layout.json.',
      );
    }

    final parsedProps = <String, Object?>{};
    final nestedProps = json['props'];
    if (nestedProps is Map) {
      for (final e in nestedProps.entries) {
        parsedProps['${e.key}'] = _freezeValue(e.value);
      }
    }
    for (final entry in json.entries) {
      if (entry.key == 'type' ||
          entry.key == 'children' ||
          entry.key == 'child' ||
          entry.key == 'props') {
        continue;
      }
      parsedProps[entry.key] = _freezeValue(entry.value);
    }

    for (final key in _assetPropKeys) {
      final value = parsedProps[key];
      if (value is String) {
        validateSafeRelativeAssetPath(value, context: '${type.jsonName}.$key');
      }
    }

    final parsedChildren = <ThemeLayoutNode>[];
    final rawChild = json['child'];
    if (rawChild != null) {
      if (rawChild is! Map) {
        throw ThemeManifestException(
          '"child" em ${type.jsonName} deve ser um objeto JSON.',
        );
      }
      parsedChildren.add(
        ThemeLayoutNode.fromJson(rawChild.cast<String, Object?>()),
      );
    }
    final rawChildren = json['children'];
    if (rawChildren != null) {
      if (rawChildren is! List) {
        throw ThemeManifestException(
          '"children" em ${type.jsonName} deve ser uma lista JSON.',
        );
      }
      for (final item in rawChildren) {
        if (item is! Map) {
          throw ThemeManifestException(
            'Cada item em "children" de ${type.jsonName} deve ser um objeto JSON.',
          );
        }
        parsedChildren.add(
          ThemeLayoutNode.fromJson(item.cast<String, Object?>()),
        );
      }
    }

    return ThemeLayoutNode(
      type: type,
      props: Map.unmodifiable(parsedProps),
      children: List.unmodifiable(parsedChildren),
    );
  }

  /// Collects all static relative asset paths referenced anywhere in this tree.
  Set<String> collectReferencedAssets() {
    final assets = <String>{};
    void visit(ThemeLayoutNode node) {
      for (final key in _assetPropKeys) {
        final v = node.props[key];
        if (v is String &&
            v.isNotEmpty &&
            !v.contains('{{') &&
            !v.contains('://')) {
          assets.add(v);
        }
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(this);
    return assets;
  }

  /// Fallback console layout when a manifest has no custom `layout.json`.
  static ThemeLayoutNode defaultConsoleLayout() => const ThemeLayoutNode(
    type: ThemeNodeType.stack,
    children: [
      ThemeLayoutNode(
        type: ThemeNodeType.dynamicBackground,
        props: {'shader': 'onda_grid', 'color': '{{theme.background}}'},
      ),
      ThemeLayoutNode(
        type: ThemeNodeType.padding,
        props: {'horizontal': 24.0, 'vertical': 16.0},
        children: [
          ThemeLayoutNode(
            type: ThemeNodeType.column,
            props: {'crossAxisAlignment': 'stretch'},
            children: [
              ThemeLayoutNode(
                type: ThemeNodeType.row,
                props: {'mainAxisAlignment': 'spaceBetween'},
                children: [
                  ThemeLayoutNode(
                    type: ThemeNodeType.metadataText,
                    props: {
                      'text': 'ONDADECK // {{selectedCategory.title}}',
                      'color': '{{theme.accent}}',
                      'fontSize': 16.0,
                      'fontWeight': 'bold',
                    },
                  ),
                  ThemeLayoutNode(
                    type: ThemeNodeType.metadataText,
                    props: {
                      'text': '{{library.totalGames}} JOGOS',
                      'color': '{{theme.textSecondary}}',
                      'fontSize': 13.0,
                    },
                  ),
                ],
              ),
              ThemeLayoutNode(
                type: ThemeNodeType.padding,
                props: {'top': 18.0, 'bottom': 18.0},
                children: [
                  ThemeLayoutNode(
                    type: ThemeNodeType.mediaCarousel,
                    props: {
                      'direction': 'horizontal',
                      'itemAsset': 'cover',
                      'itemWidth': 148.0,
                      'itemHeight': 148.0,
                      'spacing': 14.0,
                      'focusScale': 1.06,
                    },
                  ),
                ],
              ),
              ThemeLayoutNode(
                type: ThemeNodeType.row,
                props: {'crossAxisAlignment': 'center'},
                children: [
                  ThemeLayoutNode(
                    type: ThemeNodeType.gameArtwork,
                    props: {
                      'assetType': 'cover',
                      'width': 72.0,
                      'height': 72.0,
                      'borderRadius': 10.0,
                    },
                  ),
                  ThemeLayoutNode(
                    type: ThemeNodeType.padding,
                    props: {'left': 16.0},
                    children: [
                      ThemeLayoutNode(
                        type: ThemeNodeType.column,
                        props: {'crossAxisAlignment': 'start'},
                        children: [
                          ThemeLayoutNode(
                            type: ThemeNodeType.metadataText,
                            props: {
                              'text': '{{selectedGame.title}}',
                              'color': '{{theme.textPrimary}}',
                              'fontSize': 20.0,
                              'fontWeight': 'bold',
                            },
                          ),
                          ThemeLayoutNode(
                            type: ThemeNodeType.metadataText,
                            props: {
                              'text':
                                  '{{selectedGame.platform}} • {{selectedGame.kind}} • {{selectedGame.playCount}}x',
                              'color': '{{theme.textSecondary}}',
                              'fontSize': 13.0,
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  static Object? _freezeValue(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.unmodifiable({
        for (final e in value.entries) '${e.key}': _freezeValue(e.value),
      });
    }
    if (value is List) {
      return List<Object?>.unmodifiable([
        for (final e in value) _freezeValue(e),
      ]);
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeLayoutNode &&
      other.type == type &&
      _deepEquals(other.props, props) &&
      listEquals(other.children, children);

  @override
  int get hashCode =>
      Object.hash(type, _deepHash(props), Object.hashAll(children));
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_deepEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? value) => switch (value) {
  final Map m => Object.hashAllUnordered(
    m.entries.map((e) => Object.hash(e.key, _deepHash(e.value))),
  ),
  final List l => Object.hashAll(l.map(_deepHash)),
  _ => value.hashCode,
};
