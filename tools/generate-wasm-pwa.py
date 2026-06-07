#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: 2026 GCompris contributors
#
# SPDX-License-Identifier: GPL-3.0-or-later

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import urllib.request
from pathlib import Path


RUNTIME_SUFFIXES = {
    ".data",
    ".html",
    ".js",
    ".mjs",
    ".symbols",
    ".wasm",
    ".worker.js",
}

DATA_DOWNLOAD_BASE = "https://cdn.kde.org/gcompris/data3"
EAGER_RCC = {
    "activities.rcc",
    "activities_light.rcc",
    "core.rcc",
    "menu.rcc",
}


def copy_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def copy_runtime(runtime_dir: Path, output_dir: Path, app_name: str) -> None:
    for path in runtime_dir.iterdir():
        if not path.is_file():
            continue
        if path.name == "qtloader.js" or path.name.startswith(app_name):
            if any(path.name.endswith(suffix) for suffix in RUNTIME_SUFFIXES) or path.name == "qtloader.js":
                copy_file(path, output_dir / path.name)


def copy_tree(src: Path, dst: Path) -> None:
    if not src.exists():
        return
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def download_file(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        return
    print(f"Downloading lazy asset {destination.name}")
    with urllib.request.urlopen(url) as response, destination.open("wb") as out_file:
        shutil.copyfileobj(response, out_file)


def populate_lazy_voice_assets(output_dir: Path, app_name: str) -> None:
    data_dir = output_dir / "share" / app_name / "rcc" / "data3"
    for voices_dir in sorted(data_dir.glob("voices-*")):
        contents = voices_dir / "Contents"
        if not contents.exists():
            continue
        # Only populate the active compressed-audio voice directory. Stale
        # Contents-only directories can exist in incremental build trees.
        if not any(voices_dir.glob("*.rcc")):
            continue
        for line in contents.read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if len(parts) < 2:
                continue
            filename = parts[1]
            download_file(
                f"{DATA_DOWNLOAD_BASE}/{voices_dir.name}/{filename}",
                voices_dir / filename,
            )


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()[:12]


def all_files(root: Path) -> list[str]:
    files = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        files.append(path.relative_to(root).as_posix())
    return files


def write_index(output_dir: Path, app_name: str, default_locale: str) -> None:
    js_name = f"{app_name}.js"
    # EXPORT_NAME used in the CMake MODULARIZE=1 link flags must match here.
    entry_fn = "createGComprisApp"
    html_lang = default_locale.split("_", 1)[0].split("-", 1)[0]
    html = f"""<!doctype html>
<html lang="{html_lang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="theme-color" content="#0c6fb8">
  <meta name="description" content="GCompris educational activities">
  <link rel="manifest" href="manifest.webmanifest">
  <link rel="icon" href="logo.png">
  <title>GCompris</title>
  <style>
    html, body {{ padding: 0; margin: 0; overflow: hidden; height: 100%; background: #102d42; }}
    #qtscreen {{ width: 100%; height: 100%; }}
    #status {{
      position: fixed;
      inset: 0;
      display: grid;
      place-items: center;
      color: white;
      font: 600 18px system-ui, sans-serif;
      background: #102d42;
    }}
    #start {{
      margin-top: 1.25rem;
      padding: 0.7rem 1.2rem;
      border: 0;
      border-radius: 0.4rem;
      color: white;
      background: #0c6fb8;
      font: 600 16px system-ui, sans-serif;
      cursor: pointer;
    }}
    body.loading #start {{ display: none; }}
    body.ready #status {{ display: none; }}
  </style>
</head>
<body>
  <figure id="status">
    <center style="margin-top:1.5em; line-height:150%">
      <strong>GCompris</strong><br>
      <div id="loadmsg">Ready to start</div>
      <button id="start" type="button">Start</button>
    </center>
  </figure>
  <div id="qtscreen"></div>
  <script src="{js_name}"></script>
  <script src="qtloader.js"></script>
  <script>
    let started = false;

    async function init() {{
      if (started)
        return;
      started = true;
      document.body.classList.add("loading");

      if ("serviceWorker" in navigator)
        // updateViaCache:"none" makes the browser bypass the HTTP cache when
        // checking service-worker.js for updates, so a new worker is picked up
        // on the next visit instead of being pinned by GitHub Pages' caching.
        navigator.serviceWorker.register("service-worker.js", {{ updateViaCache: "none" }});

      const qtscreen = document.getElementById("qtscreen");
      const status   = document.getElementById("status");
      const loadmsg  = document.getElementById("loadmsg");
      loadmsg.textContent = "Loading GCompris...";

      try {{
        const persistentHome = "/home/web_user";
        const mountPersistentStorage = (module) => {{
          const FS = module.FS;
          // IDBFS is registered on FS.filesystems by -lidbfs.js; it is not a
          // bare global in this callback's scope (it only is inside EM_ASM).
          const IDBFS = FS && FS.filesystems && FS.filesystems.IDBFS;
          if (!FS || !FS.syncfs || !IDBFS)
            return;

          module.gcomprisPersistentMounts ??= {{}};
          if (!module.gcomprisPersistentMounts[persistentHome]) {{
            FS.mkdirTree(persistentHome);
            FS.mount(IDBFS, {{}}, persistentHome);
            module.gcomprisPersistentMounts[persistentHome] = true;
          }}

          module.addRunDependency("gcompris-idbfs-restore");
          FS.syncfs(true, err => {{
            if (err)
              console.error("GCompris persistent filesystem restore failed", err);
            module.gcomprisPersistentFsReady = true;
            module.removeRunDependency("gcompris-idbfs-restore");
          }});
        }};

        const instance = await qtLoad({{
          preRun: [mountPersistentStorage],
          qt: {{
            entryFunction: window.{entry_fn},
            containerElements: [qtscreen],
            onLoaded: () => {{ document.body.classList.add("ready"); }},
            onExit: (e) => {{
              document.body.classList.remove("loading");
              document.body.classList.remove("ready");
              loadmsg.textContent = e.text ?? ("Exit code " + e.code);
              status.style.display = "grid";
              console.error("GCompris exited", e);
            }}
          }}
        }});
      }} catch (e) {{
        document.body.classList.remove("loading");
        loadmsg.textContent = "Load error: " + e.message;
        console.error(e);
      }}
    }}
    window.addEventListener("load", () => {{
      const start = document.getElementById("start");
      start.addEventListener("click", init, {{ once: true }});
      window.addEventListener("keydown", init, {{ once: true }});
    }});
  </script>
</body>
</html>
"""
    (output_dir / "index.html").write_text(html, encoding="utf-8")


def write_manifest(output_dir: Path, default_locale: str) -> None:
    manifest_lang = default_locale.replace("_", "-")
    manifest = {
        "name": "GCompris",
        "short_name": "GCompris",
        "description": "Educational activities for children",
        "lang": manifest_lang,
        "start_url": ".",
        "scope": ".",
        "display": "fullscreen",
        "background_color": "#102d42",
        "theme_color": "#0c6fb8",
        "orientation": "any",
        "icons": [
            {
                "src": "icon-192.png",
                "sizes": "192x192",
                "type": "image/png",
                "purpose": "any maskable",
            },
            {
                "src": "icon-512.png",
                "sizes": "512x512",
                "type": "image/png",
                "purpose": "any maskable",
            },
        ],
    }
    (output_dir / "manifest.webmanifest").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def is_lazy_data_pack(filename: str) -> bool:
    prefix = "share/gcompris-qt/rcc/data3/"
    if not filename.startswith(prefix):
        return False
    relative = filename[len(prefix):]
    return (
        relative.startswith("voices-")
        or relative.startswith("backgroundMusic/")
        or relative.startswith("words/")
    )


def is_lazy_activity_pack(filename: str) -> bool:
    prefix = "share/gcompris-qt/rcc/"
    if not filename.startswith(prefix) or not filename.endswith(".rcc"):
        return False
    basename = filename.rsplit("/", 1)[-1]
    return "/" not in filename[len(prefix):] and basename not in EAGER_RCC


def write_service_worker(output_dir: Path, version: str, default_locale: str) -> None:
    all_file_list = all_files(output_dir)
    # Exclude large binary blobs from the SW precache — the browser's HTTP cache
    # handles them. Trying to cache a 100+ MB .data file in Cache Storage causes
    # an OOM/quota failure that breaks the entire service worker install.
    BYPASS_EXTENSIONS = {".data", ".wasm"}
    precache_files = [
        f for f in all_file_list
        if not any(f.endswith(ext) for ext in BYPASS_EXTENSIONS)
        and not is_lazy_data_pack(f)
        and not is_lazy_activity_pack(f)
    ]
    cache_seed = "\n".join(f"{name}:{file_hash(output_dir / name)}" for name in all_file_list)
    cache_name = f"gcompris-{version}-{hashlib.sha256(cache_seed.encode()).hexdigest()[:12]}"
    worker = f"""const CACHE_NAME = "{cache_name}";
const PRECACHE_URLS = {json.dumps(precache_files, indent=2)};

self.addEventListener("install", event => {{
  // Precache each URL independently. cache.addAll() rejects atomically if any
  // single request fails (e.g. a momentarily-missing asset), which would leave
  // the previous, possibly broken, service worker active. allSettled lets the
  // new worker install and take over even if some assets are not yet available;
  // the runtime fetch handler will cache them on demand later.
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => Promise.allSettled(
        PRECACHE_URLS.map(url => cache.add(url).catch(err => {{
          console.warn("Service worker precache skipped", url, err);
        }}))
      ))
      .then(() => self.skipWaiting())
  );
}});

self.addEventListener("activate", event => {{
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys
        .filter(key => key.startsWith("gcompris-") && key !== CACHE_NAME)
        .map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
}});

self.addEventListener("fetch", event => {{
  if (event.request.method !== "GET") {{
    return;
  }}
  // Let large binary assets (.data, .wasm) pass through to the browser HTTP cache.
  const url = new URL(event.request.url);
  if (url.pathname.endsWith(".data") || url.pathname.endsWith(".wasm")) {{
    return;
  }}
  const isLazyDataResource = url.pathname.includes("/data3/voices-") ||
    url.pathname.includes("/data3/backgroundMusic/") ||
    url.pathname.includes("/data3/words/");
  const isActivityResource = url.pathname.includes("/share/gcompris-qt/rcc/") &&
    url.pathname.endsWith(".rcc") &&
    !url.pathname.includes("/data3/");
  if (isLazyDataResource || isActivityResource) {{
    event.respondWith(
      caches.open(CACHE_NAME).then(cache =>
        cache.match(event.request).then(cached => {{
          if (cached) {{
            return cached;
          }}
          return fetch(event.request).then(response => {{
            if (response.ok) {{
              cache.put(event.request, response.clone());
            }}
            return response;
          }});
        }})
      )
    );
    return;
  }}
  event.respondWith(
    caches.match(event.request).then(cached => {{
      if (cached) {{
        return cached;
      }}
      if (event.request.mode === "navigate") {{
        return caches.match("index.html");
      }}
      return fetch(event.request);
    }})
  );
}});
"""
    (output_dir / "service-worker.js").write_text(worker, encoding="utf-8")


def create_icon(source: Path, destination: Path, size: int) -> None:
    for command in (
        ["sips", "-z", str(size), str(size), str(source), "--out", str(destination)],
        ["magick", str(source), "-resize", f"{size}x{size}!", str(destination)],
        ["convert", str(source), "-resize", f"{size}x{size}!", str(destination)],
    ):
        if shutil.which(command[0]) is None:
            continue
        try:
            subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        except subprocess.CalledProcessError:
            continue
    copy_file(source, destination)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a static PWA bundle for a Qt WebAssembly GCompris build.")
    parser.add_argument("--runtime-dir", required=True, type=Path)
    parser.add_argument("--data-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--app-name", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--default-locale", default="en_US")
    args = parser.parse_args()

    if not args.runtime_dir.exists():
        raise SystemExit(f"Runtime directory does not exist: {args.runtime_dir}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for child in args.output_dir.iterdir():
        if child.is_dir():
            shutil.rmtree(child)
        else:
            child.unlink()

    copy_runtime(args.runtime_dir, args.output_dir, args.app_name)
    copy_tree(args.data_dir, args.output_dir / "share" / args.app_name)
    populate_lazy_voice_assets(args.output_dir, args.app_name)
    logo = Path("logo.png")
    copy_file(logo, args.output_dir / "logo.png")
    create_icon(logo, args.output_dir / "icon-192.png", 192)
    create_icon(logo, args.output_dir / "icon-512.png", 512)

    write_index(args.output_dir, args.app_name, args.default_locale)
    write_manifest(args.output_dir, args.default_locale)
    write_service_worker(args.output_dir, args.version, args.default_locale)

    print(f"PWA bundle written to {args.output_dir}")
    print(f"Precached files: {len(all_files(args.output_dir))}")


if __name__ == "__main__":
    main()
