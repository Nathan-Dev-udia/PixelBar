# OndaDeck — Arquitetura do Projeto

> **OndaDeck** (desenvolvido pela **Onda Pixel**) é um launcher/frontend de jogos para Android em experiência de console ("10-foot experience"), focado em ports de recompilação estática (*recomp*), jogos nativos Android e emuladores externos, com suporte a temas intercambiáveis e customizáveis via JSON.

---

## 1. Visão Geral & Stack Tecnológica

- **Framework UI:** Flutter (Dart) utilizando o motor de renderização **Impeller** (`io.flutter.embedding.android.EnableImpeller = true`) para previsibilidade de frame times e ausência de jank por compilação de shaders em runtime.
- **Gerenciamento de Estado:** **Riverpod** (`flutter_riverpod` / `NotifierProvider`) mantendo uma única árvore de estado imutável (`LibraryState`).
- **Banco Local Ultrarrápido:** **SQLite** via `sqflite` configurado em modo `WAL` (`PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL`) com índices em `(kind, platform)`, `last_played_at` e `sort_title`.
- **Ponte Nativa Mínima:** **Kotlin** (`com.ondapixel.ondadeck`) exposta exclusivamente via `MethodChannel` (`com.ondapixel.ondadeck/launcher`), sem lógica de negócio ou estado de UI no lado Android.

---

## 2. Estrutura Modular de Diretórios

```text
lib/
├── core/                         # Infraestrutura transversal de runtime e performance
│   ├── input/
│   │   └── gamepad_input.dart    # Intents e bindings de controle Bluetooth/USB
│   ├── media/
│   │   └── budget_image.dart     # BudgetImage (ResizeImage obrigatório com cacheWidth/cacheHeight)
│   ├── memory/
│   │   └── lifecycle_memory_manager.dart # Hibernação (soft/hard) e teto de 60 MB
│   ├── rendering/
│   │   └── shader_background.dart # Wrapper de FragmentProgram (.frag GLSL) sem BackdropFilter
│   └── state/
│       └── library_controller.dart # Providers Riverpod e orquestração da biblioteca
│
├── domain/                       # Núcleo puro (zero dependência de Flutter UI, sqflite ou MethodChannel)
│   ├── models/
│   │   ├── emulator_profile.dart # Templates de lançamento de emuladores (RetroArch, Dolphin, NetherSX2)
│   │   ├── game_item.dart        # Entidade principal de jogo e MediaAssets locais
│   │   ├── launch_config.dart    # Contrato declarativo de lançamento (package / intent + extras tipados)
│   │   ├── launcher_settings.dart# Preferências globais do usuário
│   │   ├── library_state.dart    # Snapshot imutável entregue aos temas
│   │   ├── platform_models.dart  # InstalledApp, SafEntry, PersistedUri, DeviceProfile, LaunchException
│   │   ├── theme_layout.dart     # AST declarativa (ThemeLayoutNode) e validação de assets relativos
│   │   └── theme_manifest.dart   # Schema de manifesto de temas (manifest.json / theme.json + cores)
│   ├── repositories/
│   │   ├── game_library_repository.dart # Interface de persistência
│   │   └── launcher_gateway.dart        # Interface da ponte nativa Android
│   └── services/
│       ├── library_indexer.dart  # Agrupamento e ordenação por categorias (Isolate-safe)
│       └── library_merger.dart   # Reconciliação de APKs instalados x banco local (Isolate-safe)
│
├── data/                         # Implementações de I/O e cache local
│   ├── db/
│   │   ├── app_database.dart     # Abertura e migração do SQLite WAL
│   │   └── game_row_codec.dart   # Serialização em lote fora da UI thread
│   ├── repositories/
│   │   └── sqflite_game_library_repository.dart
│   ├── sync/
│   │   └── library_sync_service.dart # Sincronização de pacotes + extração de ícones em PNG
│   └── theme/
│       ├── theme_manifest_loader.dart # Leitura de assets/SAF + parse em Isolate.run()
│       ├── theme_package_service.dart # Instalação .zip/.ondatheme via SAF + user_overrides.json + FontLoader
│       └── zip_archive_extractor.dart # Descompactador ZIP puro Dart com bloqueio de path traversal
│
├── platform/
│   └── native_launcher_channel.dart # Wrapper Dart do MethodChannel('com.ondapixel.ondadeck/launcher')
│
└── themes/                       # Camada visual 100% desacoplada
    ├── console_theme_widget.dart # Contrato abstrato ConsoleThemeWidget + ThemeEngineRegistry
    ├── data_driven/
    │   └── data_driven_theme_engine.dart # Motor declarativo (layout.json, bindings {{...}}, gamepad/D-Pad)
    ├── manager/
    │   └── theme_manager_screen.dart     # Gerenciador de Temas, importação SAF e editor HSV/Hex
    └── wireframe_debug/
        └── wireframe_debug_theme.dart    # Tema minimalista de diagnóstico/validação
```

Lado nativo Android (`android/app/src/main/kotlin/com/ondapixel/ondadeck/`):
- `MainActivity.kt`: registra o plugin, encaminha `onActivityResult` (SAF) e intercepta `dispatchGenericMotionEvent`.
- `LauncherPlugin.kt`: executa `PackageManager`, extração de ícones, SAF, downsampling de imagens e disparo de `Intent` em pool de threads de background.
- `AnalogDpadMapper.kt`: converte analógicos esquerdos e HAT D-Pad em `KeyEvent.KEYCODE_DPAD_*` com deadzone e histerese.

---

## 3. Isolamento de UI (Theme Engine)

A camada de temas é **100% passiva** em relação a dados e sistema operacional:
- Nenhum tema pode importar `lib/data/`, `lib/platform/`, `sqflite` ou `MethodChannel`.
- Todo tema herda de `ConsoleThemeWidget` (`lib/themes/console_theme_widget.dart`), recebendo um snapshot imutável `LibraryState` (contendo categorias, `GameItem`, `MediaAssets`, `ThemeManifest`, `AudioTheme` e `LauncherSettings`).
- Toda interação do usuário é emitida exclusivamente por callbacks padronizados:
  - `onSelectGame(GameItem)` — foco/seleção atual na navegação
  - `onLaunchGame(GameItem)` — solicitação de execução do título
  - `onOpenSettings()` — abertura de configurações do sistema
  - `onAddApps()` — abertura do seletor manual de aplicativos instalados
  - `onToggleFavorite(GameItem)` — alternância de favorito
  - `onRescan()` — nova varredura de pacotes/biblioteca
- O `ThemeEngineRegistry` mapeia o campo `engine` do `manifest.json` (`data_driven` por padrão, além de engines nativos como `wireframe_debug`) para o respectivo construtor de `ConsoleThemeWidget`.

### 3.1 Motor Declarativo de Temas (`DataDrivenThemeEngine`) & Pacotes da Comunidade
- Pacotes `.zip` / `.ondatheme` são selecionados via Android SAF (`pickFile` + `copyDocumentToCache`), e **descompactados e validados obrigatoriamente dentro de `Isolate.run()`** (`ZipArchiveExtractor` + `ThemePackageService`) para `app_flutter/themes/<theme_id>/`.
- **Segurança:** entradas contendo `..`, `\`, `:`, caminhos absolutos ou fuga de diretório são rejeitadas antes de escrever no disco; todos os assets referenciados em `manifest.json` e `layout.json` têm existência verificada no pacote extraído.
- **Fontes Dinâmicas:** arquivos `.ttf` declarados ou descobertos em `fonts/` são registrados via `FontLoader` no carregamento do tema.
- **Editor de Cores Não-Destrutivo:** customizações feitas pelo usuário na `ThemeManagerDialog` são gravadas em `user_overrides.json` dentro da pasta do tema, preservando `manifest.json` intacto para restauração instantânea.
- **`DataDrivenThemeEngine`:** interpreta a árvore AST (`ThemeLayoutNode`) composta por `Stack`, `Row`, `Column`, `Positioned`, `Padding`, `Container`, `DynamicBackground` (shader GLSL, cor sólida ou hero banner com crossfade), `MediaCarousel` (`horizontal`/`vertical`/`crossbar`), `GameArtwork` (sempre via `BudgetImage` com `cacheWidth`/`cacheHeight`) e `MetadataText`, avaliando bindings `{{selectedGame.*}}`, `{{selectedCategory.*}}`, `{{library.*}}` e `{{theme.*}}`.

---

## 4. Regras Críticas de Performance e Memória (Android)

O launcher deve ceder praticamente 100% de RAM, CPU e GPU enquanto um jogo ou emulador estiver em execução:

### 4.1 Hibernação em 2 Níveis (`LifecycleMemoryManager`)
- **`HibernationLevel.soft`** (disparado em `AppLifecycleState.inactive`, `hidden`, `paused` ou `detached`): limpa `PaintingBinding.instance.imageCache` (`clear()` e `clearLiveImages()`), notifica todos os `HibernationParticipant` registrados (para pausar BGM/SFX/vídeo e liberar buffers temporários).
- **`HibernationLevel.hard`** (disparado explicitamente via `prepareForLaunch()` antes do disparo do `Intent` em `launchTarget`): sinaliza ao shell raiz (`OndaDeckApp`) para **desmontar completamente a subárvore do tema ativo**, aguarda 1 frame (`WidgetsBinding.instance.endOfFrame`) garantindo o `dispose()` de todos os `ui.Image`, shaders e controladores de animação, e só então limpa o `imageCache` novamente antes de abrir o jogo. Ao retornar ao foco (`AppLifecycleState.resumed`), a árvore é remontada restaurando o foco no último `focusedGameId`.

### 4.2 Teto Rígido de Cache de Texturas & `BudgetImage`
- `imageCache.maximumSizeBytes` é limitado a no máximo **60 MB** (`60 * 1024 * 1024` bytes) e `maximumSize = 300` entradas.
- Em dispositivos com restrição de memória (`ActivityManager.isLowRamDevice` ou `memoryClassMb <= 192`), o teto cai automaticamente para **32 MB**.
- **Regra obrigatória:** todas as imagens locais (ícones, capas, banners, backgrounds) nos temas devem ser renderizadas via `BudgetImage.file(...)`, que aplica `ResizeImage` usando `width * devicePixelRatio` e `height * devicePixelRatio` (`cacheWidth` / `cacheHeight`), impedindo decodificação de texturas 4K em memória para miniaturas.

### 4.3 Proibição de `BackdropFilter` Dinâmico Empilhado
- É **terminantemente proibido** utilizar `BackdropFilter` animado sobre fundos dinâmicos ou listas complexas, evitando quedas severas de FPS em GPUs móveis (Mali/Adreno).
- Fundos animados devem usar **Fragment Shaders GLSL** leves (`shaders/wave_background.frag` via `ShaderBackground` dentro de `RepaintBoundary`) ou imagens pré-processadas/borradas em background.

### 4.4 I/O e Parsing 100% Fora da UI Thread
- No **Dart**: `ThemeManifest.parse`, `LibraryIndexer.build`, `LibraryMerger.mergeInstalledApps`, `decodeGameRows` e `encodeGameRows` executam via `Isolate.run()`.
- No **Kotlin**: consultas ao `PackageManager`, renderização/cache de ícones PNG, travessia de árvores SAF (`DocumentsContract`), leitura de textos e decodificação com `inSampleSize` + compressão WebP (`importArtwork`) rodam em `ExecutorService` dedicado, devolvendo apenas caminhos de arquivo ou mapas leves para a main thread.

---

## 5. Ponte Nativa Android (`com.ondapixel.ondadeck`)

Canal único: `MethodChannel("com.ondapixel.ondadeck/launcher")`.

- **Listagem de Pacotes (`getInstalledApps`, `getAppIcons`, `isPackageInstalled`):**
  - Usa `PackageManager` com `<uses-permission android:name="android.permission.QUERY_ALL_PACKAGES" />` e `<queries>` declaradas no `AndroidManifest.xml`.
  - Detecta jogos via `ApplicationInfo.CATEGORY_GAME` (API 26+) e `FLAG_IS_GAME` (legado), além de atividades Leanback/TV, permitindo também listagem completa para adição manual.
  - Gera cache persistente de ícones em `filesDir/icons/<pkg>_<versionCode>_<size>.png`.
- **Storage Access Framework (SAF Moderno - Android 13+):**
  - `pickDirectory` (`ACTION_OPEN_DOCUMENT_TREE`) e `pickFile` (`ACTION_OPEN_DOCUMENT`) requisitando `FLAG_GRANT_PERSISTABLE_URI_PERMISSION | FLAG_GRANT_READ_URI_PERMISSION | FLAG_GRANT_WRITE_URI_PERMISSION` e persistindo via `contentResolver.takePersistableUriPermission(...)`.
  - `getPersistedUris`, `releasePersistedUri`, `listDirectory` (varredura recursiva via `DocumentsContract`), `importArtwork` (downsample + WebP em cache privado) e `readText` (leitura segura limitada a 2 MB).
- **Lançamento Universal (`launchTarget`):**
  - **`type: "package"`:** inicia a `Activity` padrão ou Leanback de jogos nativos Android e ports *recomp* via `packageName` (ou `ComponentName` explícito).
  - **`type: "intent"`:** constrói `Intent` customizado (ex.: `Intent.ACTION_VIEW` ou `MAIN`), anexa `data` (`Uri`) + `mimeType`, aplica `ClipData` e `FLAG_GRANT_READ_URI_PERMISSION` / `FLAG_GRANT_WRITE_URI_PERMISSION` para URIs `content://`, mapeia `flags` (`NEW_TASK`, `CLEAR_TASK`, etc.) e injeta `extras` fortemente tipados (`string`, `int`, `long`, `float`, `double`, `bool`, `stringList`, `stringArray`, `uri`) exigidos por emuladores como RetroArch, Dolphin e NetherSX2.

---

## 6. Navegação 100% Gamepad-First

- Todo fluxo do launcher (grade/lista de jogos, troca de categorias, diálogos de adição manual e configurações) é operado via controle Bluetooth/USB usando o sistema nativo do Flutter: `FocusNode` / `FocusTraversalGroup`, `Shortcuts` (`GamepadShortcuts.bindings`) e `Actions`.
- Mapeamento padrão:
  - **D-Pad / Analógico Esquerdo** (via `AnalogDpadMapper.kt`): navegação direcional (`DirectionalFocusIntent`) com deadzone (`0.45`) e histerese (`0.25`).
  - **A / Select / Enter**: confirmar / iniciar jogo (`ActivateIntent`).
  - **B / Esc / Backspace**: voltar / fechar modal (`GamepadBackIntent`).
  - **X**: ação contextual / adicionar app manual (`GamepadContextIntent`).
  - **Y**: ação secundária / alternar favorito (`GamepadAltIntent`).
  - **L1 / R1**: navegar entre categorias (`GamepadPageIntent`).
  - **Start / Select**: configurações (`GamepadMenuIntent`) e rescan (`GamepadSelectIntent`).
- O toque na tela permanece funcional como fallback secundário sem comprometer a navegação por foco.
