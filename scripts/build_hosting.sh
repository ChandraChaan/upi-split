#!/usr/bin/env bash
# Builds everything Firebase Hosting serves into build/hosting:
#   /       the web admin (apps/admin)
#   /shop/  the Shop for iPhones and browsers (apps/shop_web)
# Then deploy with: firebase deploy --only hosting
set -euo pipefail
cd "$(dirname "$0")/.."

out="$PWD/build/hosting"
rm -rf "$out"

(cd apps/admin && flutter pub get >/dev/null && flutter build web --release -o "$out")
(cd apps/shop_web && flutter pub get >/dev/null &&
  flutter build web --release --base-href /shop/ -o "$out/shop")

echo "Built $out"
