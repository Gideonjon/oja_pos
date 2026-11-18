#!/usr/bin/env bash
# Builds the website: the landing page at the root and the Flutter web app
# under /app/. The landing page's "Log in" and "Create account" buttons open
# /app/?mode=login and /app/?mode=signup.
#
#   ./build_web.sh https://oja-pos-api.<subdomain>.workers.dev
#   npx wrangler pages deploy landing --project-name oja-pos
set -euo pipefail
API="${1:?Usage: ./build_web.sh <worker URL>}"
cd "$(dirname "$0")"

echo "==> Building the Flutter web app"
(cd app && flutter build web --release --base-href /app/ --dart-define=API_BASE_URL="$API")
rm -rf landing/app
cp -R app/build/web landing/app

if [ -f app/build/app/outputs/flutter-apk/app-release.apk ]; then
  mkdir -p landing/downloads
  cp app/build/app/outputs/flutter-apk/app-release.apk landing/downloads/oja-pos.apk
  echo "==> Copied the Android APK for the download button"
fi

echo
echo "Done. The site is in landing/. Preview it with:"
echo "  npx serve landing     (then open http://localhost:3000)"
echo "Deploy it with:"
echo "  npx wrangler pages deploy landing --project-name oja-pos"
