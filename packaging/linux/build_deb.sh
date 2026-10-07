#!/usr/bin/env bash
# Packs the Flutter Linux bundle into a .deb for Ubuntu 24.04+.
# Usage: packaging/linux/build_deb.sh <version> <output.deb>
set -euo pipefail

VERSION="$1"
OUT="$2"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
APP_ID="io.github.endermen9932.instant_share"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

install -d "$STAGE/DEBIAN" "$STAGE/opt/instantshare" "$STAGE/usr/bin" \
  "$STAGE/usr/share/applications" "$STAGE/usr/share/doc/instantshare"
cp -a "$BUNDLE/." "$STAGE/opt/instantshare/"
ln -s /opt/instantshare/instant_share "$STAGE/usr/bin/instantshare"
install -m 644 "$ROOT/packaging/linux/$APP_ID.desktop" "$STAGE/usr/share/applications/"
for dir in "$ROOT"/packaging/linux/icons/*; do
  size="$(basename "$dir")"
  install -d "$STAGE/usr/share/icons/hicolor/$size/apps"
  install -m 644 "$dir/$APP_ID.png" "$STAGE/usr/share/icons/hicolor/$size/apps/"
done
install -m 644 "$ROOT/LICENSE" "$STAGE/usr/share/doc/instantshare/copyright"

SIZE_KB="$(du -sk "$STAGE" | cut -f1)"
cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: instantshare
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: $SIZE_KB
Maintainer: Endermen9932 <noreply@github.com>
Homepage: https://github.com/Endermen9932/instantShare
Depends: libgtk-3-0t64 | libgtk-3-0, libglib2.0-0t64 | libglib2.0-0, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, gstreamer1.0-plugins-good, libstdc++6, libc6
Recommends: xdg-desktop-portal, zenity
Description: Dateien per animierten QR-Codes teilen
 InstantShare überträgt Dateien und Text zwischen Laptop, Handy und Tablet
 über eine Folge feiner, wechselnder QR-Codes – ohne Netzwerk, ohne Konto.
 Drei Stufen (Schnell, Ausgewogen, Langsam) passen Dichte und Tempo an
 Display und Kamera an. Zum Empfangen wird die Webcam genutzt.
CONTROL

cat > "$STAGE/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
POSTINST
chmod 755 "$STAGE/DEBIAN/postinst"
cp "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

find "$STAGE" -type d -exec chmod 755 {} +
dpkg-deb --root-owner-group --build "$STAGE" "$OUT"
echo "Built $OUT"
