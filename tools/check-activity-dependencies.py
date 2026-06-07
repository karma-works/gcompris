#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: 2026 GCompris contributors
#
# SPDX-License-Identifier: GPL-3.0-or-later

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ACTIVITIES_DIR = ROOT / "src" / "activities"
MENU_QML = ACTIVITIES_DIR / "menu" / "Menu.qml"


def sibling_activity_imports() -> dict[str, list[str]]:
    activity_names = {path.name for path in ACTIVITIES_DIR.iterdir() if path.is_dir()}
    import_pattern = re.compile(r'^\s*import\s+"\.\./([^"/]+)')
    dependencies: dict[str, set[str]] = {}

    for activity in sorted(activity_names):
        for qml in (ACTIVITIES_DIR / activity).rglob("*.qml"):
            for line in qml.read_text(encoding="utf-8", errors="ignore").splitlines():
                match = import_pattern.match(line)
                if not match:
                    continue
                dependency = match.group(1)
                if dependency in activity_names and dependency != activity:
                    dependencies.setdefault(activity, set()).add(dependency)

    return {
        activity: sorted(dependencies[activity])
        for activity in sorted(dependencies)
    }


def menu_activity_dependencies() -> dict[str, list[str]]:
    text = MENU_QML.read_text(encoding="utf-8")
    match = re.search(
        r"readonly property var activityDependencies:\s*\(\{(?P<body>.*?)\n\s*\}\)",
        text,
        flags=re.S,
    )
    if not match:
        raise SystemExit("Could not find activityDependencies in Menu.qml")

    return json.loads("{" + match.group("body") + "\n}")


def main() -> int:
    expected = sibling_activity_imports()
    actual = menu_activity_dependencies()
    if actual != expected:
        print("Menu.qml activityDependencies is out of sync with sibling activity imports.", file=sys.stderr)
        print("Expected:", json.dumps(expected, indent=2, sort_keys=True), file=sys.stderr)
        print("Actual:", json.dumps(actual, indent=2, sort_keys=True), file=sys.stderr)
        return 1
    print(f"Verified {len(actual)} activity dependency entries.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
