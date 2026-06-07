#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: 2026 GCompris contributors
#
# SPDX-License-Identifier: GPL-3.0-or-later

import argparse
import shutil
from pathlib import Path


EAGER_RCC = {
    "activities.rcc",
    "activities_light.rcc",
    "core.rcc",
    "menu.rcc",
}

LAZY_DATA_DIRS = {
    "backgroundMusic",
    "words",
}


def read_activities(path: Path) -> list[str]:
    activities = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            activities.append(line)
    return activities


def main() -> None:
    parser = argparse.ArgumentParser(description="Create the reduced WASM preload data tree.")
    parser.add_argument("--data-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--activities-file", required=True, type=Path)
    args = parser.parse_args()

    if args.output_dir.exists():
        shutil.rmtree(args.output_dir)
    shutil.copytree(args.data_dir, args.output_dir)

    rcc_dir = args.output_dir / "rcc"
    removed = 0
    for activity in read_activities(args.activities_file):
        rcc = rcc_dir / f"{activity}.rcc"
        if rcc.name in EAGER_RCC:
            continue
        if rcc.exists():
            rcc.unlink()
            removed += 1

    data_dir = rcc_dir / "data3"
    removed_data_files = 0
    if data_dir.exists():
        for child in data_dir.iterdir():
            if child.name in LAZY_DATA_DIRS or child.name.startswith("voices-"):
                if child.is_dir():
                    for rcc in child.glob("*.rcc"):
                        rcc.unlink()
                        removed_data_files += 1
                elif child.suffix == ".rcc":
                    child.unlink()
                    removed_data_files += 1

    print(
        f"WASM preload tree written to {args.output_dir}; "
        f"removed {removed} lazy activity RCCs and {removed_data_files} lazy data RCCs"
    )


if __name__ == "__main__":
    main()
