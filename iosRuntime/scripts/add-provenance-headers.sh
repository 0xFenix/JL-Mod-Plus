#!/bin/bash
# One-shot provenance pass: prepend the Apache-2.0 derivation notice to every
# adopted Java source file that arrived without a copyright header.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)/java/src"
HEADER='/*
 * Derived from J2ME-Decade (iOS Edition) <https://github.com/darkrose00x-ux/j2me-ios>,
 * licensed under the Apache License, Version 2.0. That project states its J2ME API
 * layer is ported from J2ME-Loader <https://github.com/nikita36078/J2ME-Loader>,
 * whose javax.microedition sources are Copyright 2012 Kulikov Dmitriy,
 * 2017-2020 Nikita Shakarun, 2019-2023 Yury Kharchenko, Apache License 2.0.
 *
 * JL-Mod Plus modifications: removed the M3G (javax.microedition.m3g), MascotCapsule
 * micro3D, JBlend/Vodafone J3D, Bluetooth, Location and AMMS packages, which are
 * outside the iOS runtime scope.
 */'
count=0
while IFS= read -r -d '' f; do
  if head -3 "$f" | grep -q 'Derived from J2ME-Decade'; then continue; fi
  tmp="$(mktemp)"
  printf '%s\n' "$HEADER" > "$tmp"
  cat "$f" >> "$tmp"
  mv "$tmp" "$f"
  count=$((count+1))
done < <(find "$ROOT" -name '*.java' -print0)
echo "headers added: $count"
