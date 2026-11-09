#!/usr/bin/env bash
# Runs every check in the repo. The rules tests need Java 21 or newer.
set -euo pipefail
cd "$(dirname "$0")/.."

for project in . packages/kirana_core apps/admin; do
  echo "== $project"
  (cd "$project" && flutter pub get >/dev/null && flutter analyze --no-pub && flutter test --no-pub)
done

echo "== firestore rules"
(cd firebase_tests && npm ci --no-audit --no-fund >/dev/null && npm test)
