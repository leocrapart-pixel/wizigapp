#!/usr/bin/env python3
"""Print "x y label" for every calculator button in a uiautomator dump."""
import re
import sys
import xml.etree.ElementTree as ET

WANTED = {
    "Pick a number",
    "Roll",
    "Flip the coin",
    "Generate",
    "Split",
    "Calculate",
    "Grow it",
}


def main(path: str) -> int:
    try:
        root = ET.parse(path).getroot()
    except Exception as exc:  # noqa: BLE001 - diagnostics only
        print(f"dump parse failed: {exc}")
        return 0

    found = 0
    for node in root.iter("node"):
        text = (node.get("text") or "").strip()
        if text not in WANTED:
            continue
        match = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds") or "")
        if not match:
            continue
        left, top, right, bottom = (int(group) for group in match.groups())
        print(f"{(left + right) // 2} {(top + bottom) // 2} {text}")
        found += 1

    print(f"# this screen: {found} buttons", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
