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
    html = f"""<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="theme-color" content="#0c6fb8">
  <meta name="description" content="GCompris educational activities">
  <link rel="manifest" href="manifest.webmanifest">
  <link rel="icon" href="logo.png">
  <title>GCompris</title>
  <style>
    html, body, #screen {{
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: #102d42;
    }}
    #screen {{
      position: fixed;
      inset: 0;
      touch-action: none;
    }}
    #status {{
      position: fixed;
      inset: 0;
      display: grid;
      place-items: center;
      color: white;
      font: 600 18px system-ui, sans-serif;
      pointer-events: none;
    }}
    body.ready #status {{
      display: none;
    }}
  </style>
</head>
<body>
  <div id="screen"></div>
  <div id="status">GCompris wird geladen...</div>
  <script src="qtloader.js"></script>
  <script src="{js_name}"></script>
  <script>
    if ("serviceWorker" in navigator) {{
      window.addEventListener("load", () => navigator.serviceWorker.register("service-worker.js"));
    }}

    const screen = document.getElementById("screen");
    qtLoad({{
      arguments: ["--locale", "{default_locale}", "--fullscreen"],
      qt: {{
        containerElements: [screen],
        onLoaded: () => document.body.classList.add("ready"),
        onExit: () => document.body.classList.remove("ready")
      }}
    }});
  </script>
</body>
</html>
"""
    (output_dir / "index.html").write_text(html, encoding="utf-8")


def write_manifest(output_dir: Path) -> None:
    manifest = {
        "name": "GCompris",
        "short_name": "GCompris",
        "description": "Educational activities for children",
        "lang": "de",
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


def write_service_worker(output_dir: Path, version: str) -> None:
    files = all_files(output_dir)
    cache_seed = "\n".join(f"{name}:{file_hash(output_dir / name)}" for name in files)
    cache_name = f"gcompris-{version}-{hashlib.sha256(cache_seed.encode()).hexdigest()[:12]}"
    worker = f"""const CACHE_NAME = "{cache_name}";
const PRECACHE_URLS = {json.dumps(files, indent=2)};

self.addEventListener("install", event => {{
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(PRECACHE_URLS))
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
    parser.add_argument("--default-locale", default="de_DE")
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
    logo = Path("logo.png")
    copy_file(logo, args.output_dir / "logo.png")
    create_icon(logo, args.output_dir / "icon-192.png", 192)
    create_icon(logo, args.output_dir / "icon-512.png", 512)

    write_index(args.output_dir, args.app_name, args.default_locale)
    write_manifest(args.output_dir)
    write_service_worker(args.output_dir, args.version)

    print(f"PWA bundle written to {args.output_dir}")
    print(f"Precached files: {len(all_files(args.output_dir))}")


if __name__ == "__main__":
    main()
