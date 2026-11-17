#!/usr/bin/env python3
"""Erzeugt das Windows-Icon (.ico) aus dem 1024×1024-PNG von Tools/make_icon.swift.

Aufruf:
  swift Tools/make_icon.swift /tmp/icon_1024.png
  python3 Tools/make_ico.py /tmp/icon_1024.png windows/src/RedScan.App/Assets/RedScan.ico
"""
import sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA")
# Das macOS-Motiv hat ringsum Rand für den Schatten – für Windows etwas enger zuschneiden,
# damit das Icon auch bei 16×16 noch gut erkennbar ist.
w, h = img.size
m = int(w * 0.06)
img = img.crop((m, m, w - m, h - m))
sizes = [(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64), (128, 128), (256, 256)]
img.save(dst, format="ICO", sizes=sizes)
print(f"Icon geschrieben: {dst} ({len(sizes)} Größen)")
