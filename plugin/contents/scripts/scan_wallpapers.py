#!/usr/bin/env python3
"""Scan a Steam Workshop directory for Wallpaper Engine wallpapers.

Reads project.json from each workshop subdirectory and outputs a JSON array
with metadata for all found wallpapers. Used by the KDE wallpaper plugin's
config UI via Plasma's executable DataSource.

Usage: python3 scan_wallpapers.py /path/to/steamapps/workshop/content/431960
"""

import json
import os
import sys


def scan(workshop_path):
    results = []
    if not os.path.isdir(workshop_path):
        return results

    for entry in sorted(os.listdir(workshop_path)):
        project_file = os.path.join(workshop_path, entry, "project.json")
        if not os.path.isfile(project_file):
            continue
        try:
            with open(project_file, encoding="utf-8") as f:
                data = json.load(f)
            data["workshopId"] = entry
            data["dirPath"] = os.path.join(workshop_path, entry)
            results.append(data)
        except Exception:
            pass

    return results


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else ""
    print(json.dumps(scan(path)))
