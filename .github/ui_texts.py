#!/usr/bin/env python3
"""Print the non-empty text nodes of a uiautomator dump, one per line."""
import sys
import xml.etree.ElementTree as ET


def main(path: str) -> int:
    try:
        root = ET.parse(path).getroot()
    except Exception as exc:  # noqa: BLE001 - diagnostics only
        print(f"dump parse failed: {exc}")
        return 0

    for node in root.iter("node"):
        text = (node.get("text") or "").strip()
        if text:
            print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
