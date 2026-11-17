#!/usr/bin/env python3
"""Konvertiert die Wireshark-'manuf'-Datei in das kompakte RedScan-Format.

Ausgabe: eine Zeile pro Präfix  ->  HEXPRÄFIX<TAB>Hersteller
  6 Hex-Zeichen = /24 (MA-L), 7 = /28 (MA-M), 9 = /36 (MA-S)
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
out = {}
with open(src, encoding="utf-8", errors="replace") as f:
    for line in f:
        if not line.strip() or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.rstrip("\n").split("\t")]
        if len(parts) < 2:
            continue
        prefix = parts[0]
        vendor = parts[2] if len(parts) > 2 and parts[2] else parts[1]
        bits = 24
        if "/" in prefix:
            prefix, b = prefix.split("/")
            bits = int(b)
        hexs = prefix.replace(":", "").replace("-", "").upper()
        n = {24: 6, 28: 7, 36: 9}.get(bits)
        if n is None or len(hexs) < n:
            continue
        out[hexs[:n]] = vendor.replace("\t", " ")

with open(dst, "w", encoding="utf-8") as f:
    for k in sorted(out):
        f.write(f"{k}\t{out[k]}\n")
print(f"{len(out)} Einträge geschrieben -> {dst}")
