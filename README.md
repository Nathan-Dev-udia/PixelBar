# OndaDeck

> **OndaDeck** (desenvolvido pela **Onda Pixel**) é um launcher/frontend de jogos para Android em experiência de console de mesa (*10-foot experience*), focado em ports de recompilação estática (*recomp*), jogos nativos Android e emuladores externos, com suporte a temas declarativos importáveis pela comunidade (`.ondatheme` / `.zip`).

---

## Visão Geral e Funcionalidades

- **Biblioteca Unificada em SQLite (WAL):** indexação local ultrarrápida para jogos nativos Android, ports *recomp* e ROMs via emuladores externos (RetroArch, Dolphin, NetherSX2 e perfis customizados).
- **Ponte Nativa Android (SAF + PackageManager):**
  - Detecção automática de jogos instalados (`CATEGORY_GAME`) e adição manual de qualquer APK/port instalado.
  - Suporte moderno ao **Storage Access Framework (SAF)** (`takePersistableUriPermission`) compatível com Android 13+ sem permissões legadas bloqueadas.
  - Lançamento universal (`launchTarget`) para APKs nativos e `Intent` com `ClipData`, permissões temporárias de URI e `extras` fortemente tipados para emuladores.
- **Navegação 100% Gamepad-First:** operação completa via D-Pad, analógico esquerdo (mapeado nativamente em Kotlin com deadzone e histerese) e botões A/B/X/Y/L1/R1/START/SELECT, mantendo suporte secundário por toque.
- **Motor de Temas Data-Driven (`DataDrivenThemeEngine`):** temas importáveis via `.zip` ou `.ondatheme` sem recompilar o aplicativo. O app já inclui dois layouts built-in no menu: `wireframe_debug` (*Onda Default*) e `psp_xmb` (*PSP XMB - PlayStation Portable*, com barra horizontal superior em estilo XMB, indicador *Memory Stick™*, miniaturas 16:9 `ICON0`, bateria de 3 barras e ondas de seda).
- **Gerenciador de Temas & Editor de Cores:** instale pacotes da comunidade, troque de tema instantaneamente, personalize qualquer token de cor por HSV / Paleta Rápida / Hexadecimal (salvos em `user_overrides.json`) e restaure o padrão original a qualquer momento.
- **Auto-Updater Integrado via GitHub Releases:** verifica silenciosamente ao abrir (e sob demanda em *Configurações -> Verificar Atualizações*) novas versões `v1.0.<build>` publicadas em `Nathan-Dev-udia/PixelBar/releases/latest`, baixa o `.apk` com barra de progresso e dispara o instalador nativo Android via `FileProvider`.

---

## Arquitetura & Performance no Android

O launcher foi projetado para ceder praticamente toda a RAM, CPU e GPU quando um jogo está em execução:

- **Hibernação em 2 Níveis (`LifecycleMemoryManager`):**
  - **Soft** (`paused` / `inactive`): limpa imediatamente `PaintingBinding.instance.imageCache` (`clear()` e `clearLiveImages()`) e notifica serviços de áudio/mídia.
  - **Hard** (antes do lançamento de qualquer jogo): desmonta completamente a subárvore do tema ativo, aguarda 1 frame para liberar todas as texturas `ui.Image` e shaders da GPU, limpa o cache de imagens e só então dispara a `Intent` do jogo.
- **Teto Rígido de Texturas (≤ 60 MB):** `imageCache.maximumSizeBytes` limitado a **60 MB** (ou **32 MB** em dispositivos `isLowRamDevice`). Todas as imagens passam por `BudgetImage`, decodificando exatamente em `tamanho_lógico × devicePixelRatio` (`cacheWidth` / `cacheHeight`).
- **Zero `BackdropFilter` Dinâmico:** fundos animados utilizam **Fragment Shaders GLSL** (`.frag`) compilados pelo motor **Impeller**, evitando quedas de FPS em GPUs Mali e Adreno.
- **I/O e Parsing Fora da UI Thread:** toda descompactação `.zip`/`.ondatheme`, validação, leitura/gravação de overrides, parsing de JSON e indexação de biblioteca rodam em `Isolate.run()` no Dart e em `ExecutorService` dedicado no Kotlin.

Consulte [ARCHITECTURE.md](ARCHITECTURE.md) para detalhes completos das camadas (`lib/core`, `lib/domain`, `lib/data`, `lib/platform`, `lib/themes`).

---

## Guia Completo de Criação de Temas para a Comunidade

Qualquer pessoa pode criar e compartilhar novos layouts visuais para o **OndaDeck** empacotando arquivos JSON e assets locais em um arquivo `.zip` ou `.ondatheme`.

### 1. Estrutura Interna do Pacote (`.zip` / `.ondatheme`)

```text
meu-tema.ondatheme (ou .zip)
├── manifest.json          # (Obrigatório) Metadados, tokens de cores e fontes
├── layout.json            # (Obrigatório) Árvore declarativa de widgets
├── preview.png            # (Opcional) Miniatura exibida no Gerenciador de Temas
├── sounds/                # (Opcional) Efeitos sonoros e música de fundo
│   ├── move.wav
│   ├── select.wav
│   ├── back.wav
│   └── bgm.ogg
├── fonts/                 # (Opcional) Fontes .ttf carregadas via FontLoader
│   └── Orbitron-Bold.ttf
└── assets/                # (Opcional) Fundos estáticos, overlays, ícones
    └── overlay.png
```

> **Segurança:** durante a importação em `Isolate.run()`, o OndaDeck bloqueia caminhos absolutos, barras invertidas e tentativas de *path traversal* (`../`), além de verificar se todo arquivo referenciado realmente existe dentro do pacote.

---

### 2. Schema do `manifest.json`

| Campo | Tipo | Obrigatório | Descrição |
| :--- | :--- | :---: | :--- |
| `schemaVersion` | `int` | Não | Versão do schema (padrão: `1`). |
| `id` | `string` | **Sim** | Identificador único (`a-z`, `A-Z`, `0-9`, `-`, `_`). |
| `name` | `string` | **Sim** | Nome exibido no Gerenciador de Temas. |
| `author` | `string` | Não | Nome do criador do tema. |
| `version` | `string` | Não | Versão semântica (ex.: `"1.0.0"`). |
| `description` | `string` | Não | Descrição curta do estilo visual. |
| `previewImage` | `string` | Não | Caminho relativo da imagem de preview dentro do pacote. |
| `engine` | `string` | Não | Use `"data_driven"` (padrão quando omitido). |
| `colors` | `object` | Não | Mapa de tokens editáveis no Editor de Cores (`#RRGGBB` ou `#AARRGGBB`). |
| `sounds` | `object` | Não | Caminhos relativos para `move`, `select`, `back` e `bgm` + `volume` (`0.0`–`1.0`). |
| `fonts` | `object` | Não | Mapa `NomeDaFamilia -> caminho/relativo.ttf`. Fontes em `fonts/*.ttf` também são registradas automaticamente pelo nome do arquivo. |

**Tokens recomendados em `colors`** (todos editáveis pelo usuário em `user_overrides.json`):
- `primary`, `accent`, `background`, `surface`, `textPrimary`, `textSecondary`, `focusGlow`, `favorite`, `danger`.

---

### 3. Variáveis de Data-Binding Disponíveis

Use `{{variavel}}` em textos (`MetadataText.text`), imagens (`DynamicBackground.image`, `GameArtwork.src`) ou cores (`{{theme.accent}}`):

#### Jogo em Foco (`selectedGame`)
- `{{selectedGame.title}}` — Título do jogo selecionado.
- `{{selectedGame.clearLogo}}` — Caminho da logo transparente (`clearLogo`) do jogo.
- `{{selectedGame.heroBanner}}` — Caminho do banner/hero art do jogo.
- `{{selectedGame.cover}}` — Capa principal (com fallback para ícone).
- `{{selectedGame.icon}}` — Ícone do aplicativo/jogo.
- `{{selectedGame.background}}` — Imagem de fundo do jogo.
- `{{selectedGame.platform}}` — Plataforma em caixa alta (`ANDROID`, `GC`, `PS2`, etc.).
- `{{selectedGame.kind}}` — Tipo (`androidNative`, `recompPort`, `emulated`).
- `{{selectedGame.playCount}}` — Quantidade de vezes executado.
- `{{selectedGame.lastPlayed}}` — Data/hora da última execução ou `"Nunca"`.

#### Categoria, Biblioteca e Tema
- `{{selectedCategory.title}}` — Nome da categoria ativa (`Android`, `Favoritos`, etc.).
- `{{selectedCategory.count}}` — Quantidade de itens na categoria ativa.
- `{{library.totalGames}}` — Total de jogos únicos indexados.
- `{{theme.id}}`, `{{theme.name}}`, `{{theme.author}}`, `{{theme.version}}` — Metadados do tema.
- `{{theme.<token>}}` — Cor atual do token (ex.: `{{theme.accent}}`, `{{theme.textPrimary}}`), já considerando customizações do usuário em `user_overrides.json`.

---

### 4. Componentes Suportados no `layout.json`

Todo nó possui `"type": "<Componente>"`, propriedades do componente e opcionalmente `"child"` (um filho) ou `"children"` (lista de filhos).

| Componente (`type`) | Propriedades Principais | Função |
| :--- | :--- | :--- |
| `Stack` | `alignment`, `fit` (`"loose"` \| `"expand"`) | Empilha filhos (ex.: fundo + camada de UI). |
| `Row` | `mainAxisAlignment`, `crossAxisAlignment`, `mainAxisSize` | Organiza filhos horizontalmente. |
| `Column` | `mainAxisAlignment`, `crossAxisAlignment`, `mainAxisSize` | Organiza filhos verticalmente. |
| `Positioned` | `top`, `bottom`, `left`, `right`, `width`, `height` (px ou `"50%"`) | Posiciona filho dentro de um `Stack`. |
| `Padding` | `padding` ou `horizontal`, `vertical`, `left`, `right`, `top`, `bottom` | Aplica espaçamento interno ao filho. |
| `Container` | `width`, `height` (px ou `"%"`), `color`, `borderColor`, `borderWidth`, `borderRadius`, `padding`, `margin`, `alignment`, `image`, `flex` | Caixa estilizada com borda, fundo ou imagem. |
| `DynamicBackground` | `shader` (`"ps3_wave"`), `color`, `secondaryColor`, `image` (`"{{selectedGame.heroBanner}}"` ou arquivo local) | Renderiza shader GLSL, imagem com crossfade ou cor sólida sem `BackdropFilter`. |
| `MediaCarousel` | `direction` (`"horizontal"` \| `"vertical"` \| `"crossbar"`), `itemAsset` (`"cover"` \| `"banner"` \| `"icon"` \| `"clearLogo"`), `itemWidth`, `itemHeight`, `spacing`, `focusScale`, `soundOnMove`, `width`, `height` | Lista navegável por D-Pad, analógico e toque. O modo `"crossbar"` exibe abas de categoria estilo XMB acima do carrossel. |
| `GameArtwork` | `assetType` (`"cover"` \| `"clearLogo"` \| `"heroBanner"` \| `"icon"` \| `"background"`), `src`, `width`, `height`, `borderRadius`, `fit` | Exibe arte do jogo focado respeitando `cacheWidth`/`cacheHeight`. |
| `MetadataText` | `text`, `color`, `fontSize`, `fontWeight` (`"bold"`, `"w600"`, `"normal"`), `fontFamily`, `letterSpacing`, `maxLines`, `textAlign` | Exibe texto com bindings e fontes do pacote. |

---

### 5. Exemplo Completo Pronto para Copiar e Colar

Crie uma pasta com `manifest.json` e `layout.json` abaixo e compacte os arquivos diretamente na raiz de um `.zip` (ou renomeie para `.ondatheme`):

#### `manifest.json`
```json
{
  "schemaVersion": 1,
  "id": "neon_xmb_community",
  "name": "Neon XMB Community",
  "author": "Comunidade Onda Pixel",
  "version": "1.0.0",
  "description": "Tema estilo Crossbar com ondas GLSL e cores editáveis.",
  "engine": "data_driven",
  "colors": {
    "primary": "#141824",
    "accent": "#00E5FF",
    "background": "#070910",
    "surface": "#101522",
    "textPrimary": "#F4F6FB",
    "textSecondary": "#8B97B0",
    "focusGlow": "#00E5FF"
  }
}
```

#### `layout.json`
```json
{
  "type": "Stack",
  "children": [
    {
      "type": "DynamicBackground",
      "shader": "ps3_wave",
      "color": "{{theme.background}}",
      "secondaryColor": "{{theme.surface}}"
    },
    {
      "type": "Padding",
      "horizontal": 28,
      "vertical": 18,
      "child": {
        "type": "Column",
        "crossAxisAlignment": "stretch",
        "children": [
          {
            "type": "Row",
            "mainAxisAlignment": "spaceBetween",
            "crossAxisAlignment": "center",
            "children": [
              {
                "type": "MetadataText",
                "text": "ONDADECK • {{selectedCategory.title}}",
                "color": "{{theme.accent}}",
                "fontSize": 18,
                "fontWeight": "bold",
                "letterSpacing": 1.2
              },
              {
                "type": "MetadataText",
                "text": "{{library.totalGames}} JOGOS",
                "color": "{{theme.textSecondary}}",
                "fontSize": 13
              }
            ]
          },
          {
            "type": "Padding",
            "top": 14,
            "bottom": 14,
            "child": {
              "type": "MediaCarousel",
              "direction": "crossbar",
              "itemAsset": "cover",
              "itemWidth": 140,
              "itemHeight": 140,
              "spacing": 14,
              "focusScale": 1.08
            }
          },
          {
            "type": "Container",
            "padding": 14,
            "color": "{{theme.primary}}",
            "borderColor": "{{theme.focusGlow}}",
            "borderWidth": 1.5,
            "borderRadius": 10,
            "child": {
              "type": "Row",
              "crossAxisAlignment": "center",
              "children": [
                {
                  "type": "GameArtwork",
                  "assetType": "cover",
                  "width": 64,
                  "height": 64,
                  "borderRadius": 8
                },
                {
                  "type": "Padding",
                  "left": 14,
                  "child": {
                    "type": "Column",
                    "crossAxisAlignment": "start",
                    "children": [
                      {
                        "type": "MetadataText",
                        "text": "{{selectedGame.title}}",
                        "color": "{{theme.textPrimary}}",
                        "fontSize": 18,
                        "fontWeight": "bold",
                        "maxLines": 1
                      },
                      {
                        "type": "MetadataText",
                        "text": "{{selectedGame.platform}} • {{selectedGame.playCount}} execuções • Último: {{selectedGame.lastPlayed}}",
                        "color": "{{theme.textSecondary}}",
                        "fontSize": 12,
                        "maxLines": 1
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  ]
}
```

---

## Auto-Updater Integrado (GitHub Releases)

O **OndaDeck / PixelBar** atualiza a si mesmo diretamente pelo aplicativo usando as Releases públicas de [`Nathan-Dev-udia/PixelBar`](https://github.com/Nathan-Dev-udia/PixelBar/releases/latest), sem precisar de lojas ou gerenciadores externos:

- **Versionamento automático em CI (`.github/workflows/release-apk.yml`):** cada build na branch `main` compila o APK `arm64` com `--build-name=1.0.${{ github.run_number }}` e `--build-number=${{ github.run_number }}`, publicando a tag `v1.0.<build>` como release oficial (`latest`).
- **Checagem silenciosa + manual:** `AppUpdateService` usa `package_info_plus` para comparar o `buildNumber` instalado com `/releases/latest` ao abrir o launcher (sem bloquear a UI) e também pelo botão **"Verificar Atualizações"** nas *Configurações*.
- **Download + Instalação Nativa Android:** ao confirmar no modal estilo console (navegável por D-Pad/A/B e toque), o `.apk` é baixado com barra de progresso para o cache temporário do app, os arquivos antigos são limpos automaticamente e o `LauncherPlugin` solicita `REQUEST_INSTALL_PACKAGES` (se ainda não concedido) antes de abrir o `PackageInstaller` via `FileProvider`.

---

## Como Rodar e Testar

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```
