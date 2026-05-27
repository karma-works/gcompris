# GCompris WebAssembly PWA

This directory documents the WebAssembly/PWA build path for GCompris.

The goal is a pure web deployment: static files served over HTTPS, installable
as a Progressive Web App, and usable offline after the first successful load.
The first supported offline language bundle is German.

## Requirements

- Qt for WebAssembly, Qt 6.8 or newer recommended.
- Emscripten version matching the selected Qt for WebAssembly kit.
- CMake and Ninja or another CMake generator.
- `msgattrib`, provided by gettext, for translation generation.
- Network access when `DOWNLOAD_ASSETS` downloads German voices, words, and
  background music.

## Build

Set `QT_WASM_PREFIX` to the Qt WebAssembly kit root, or set
`QT_WASM_TOOLCHAIN` directly.

```sh
QT_WASM_PREFIX="$HOME/Qt/6.9.0/wasm_singlethread" tools/build-wasm-pwa.sh
```

The wrapper configures CMake with:

- `BUILD_SERVER=OFF`
- `PACKAGE_GCOMPRIS=OFF`
- `WITH_DOWNLOAD=OFF`
- `GCOMPRIS_WASM_PWA=ON`
- `GCOMPRIS_WASM_DEFAULT_LOCALE=de_DE`
- `DOWNLOAD_ASSETS=words,music,de`

The generated PWA is written to:

```text
build-wasm/pwa
```

## Run Locally

Service workers require `localhost` or HTTPS.

```sh
python3 -m http.server 8000 -d build-wasm/pwa
```

Then open:

```text
http://localhost:8000/
```

## Offline Acceptance Checks

For the first milestone, verify all of the following:

- The app loads in Chrome, Firefox, and Safari.
- The initial locale is German.
- German is visible in the configuration language list as `Deutsch`.
- German UI strings load from `gcompris_qt_de.qm`.
- German voices are available from `data3/voices-ogg`.
- A language/reading activity can load German datasets such as
  `content-de.json` or `default-de.json` when present.
- The browser offers installation as a PWA.
- After installation and one complete online launch, the app opens with the
  network disabled.
- The service worker precaches the generated `.wasm`, `.js`, `.data`, `.rcc`,
  translation, German voice, words, and music files.

## Notes

Qt for WebAssembly runs inside the browser sandbox. The build embeds the
generated `share/gcompris-qt` tree into Emscripten's virtual filesystem using
`--preload-file`, and the PWA generator also copies the same tree into the
static output directory so the service worker can cache it.

Some areas still need browser testing after the first successful build:

- Qt Multimedia behavior for voices and effects.
- Persistent settings/progress through browser storage.
- Startup time and payload size.
- Activities that assume native filesystem or socket behavior.
