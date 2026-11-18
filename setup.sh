#!/usr/bin/env bash
# One-time setup for the Flutter app. Run from the project root:  ./setup.sh
# Needs: Flutter 3.22 or newer on your PATH.
set -euo pipefail
cd "$(dirname "$0")/app"

command -v flutter >/dev/null || { echo "Flutter is not installed or not on PATH."; exit 1; }

echo "==> Generating Android, iOS and web projects"
# Keep our source safe while Flutter generates the platform folders.
backup="$(mktemp -d)"
cp -R lib test pubspec.yaml analysis_options.yaml "$backup/"
flutter create --org com.ojapos --project-name oja_pos --platforms=android,ios,web .
rm -rf lib test
cp -R "$backup/lib" "$backup/test" .
cp "$backup/pubspec.yaml" "$backup/analysis_options.yaml" .
rm -rf "$backup"

echo "==> Adding packages"
flutter pub add firebase_core firebase_auth cloud_firestore http qr_flutter url_launcher \
  intl google_fonts flutter_secure_storage web_socket_channel pointycastle crypto
flutter pub add dev:flutter_lints

echo "==> Allowing internet access in Android release builds"
manifest="android/app/src/main/AndroidManifest.xml"
if [ -f "$manifest" ] && ! grep -q "android.permission.INTERNET" "$manifest"; then
  perl -0pi -e 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' "$manifest"
fi

echo "==> Installing the Oja POS logo as the app icon and favicon"
cp -R branding/android/. android/app/src/main/res/
cp -R branding/ios/. ios/
cp -R branding/web/. web/
# Friendly app name on every platform.
perl -pi -e 's|android:label="[^"]*"|android:label="Oja POS"|' "$manifest"
perl -pi -e 's|<string>Oja Pos</string>|<string>Oja POS</string>|' ios/Runner/Info.plist
perl -pi -e 's|<title>[^<]*</title>|<title>Oja POS</title>|; s|content="oja_pos"|content="Oja POS"|' web/index.html
perl -pi -e 's|"(short_)?name": "[^"]*"|"$1name": "Oja POS"|; s|"(background_color\|theme_color)": "[^"]*"|"$1": "#0B6E4F"|' web/manifest.json

echo "==> Running tests (Lightning wallet cryptography)"
flutter test

cat <<'NEXT'

Setup complete. Next:

  1. Connect Firebase (creates lib/firebase_options.dart):
       dart pub global activate flutterfire_cli
       cd app && flutterfire configure --platforms=android,ios,web

  2. Deploy the Worker (see README, "Backend"), then run the app:
       flutter run --dart-define=API_BASE_URL=https://oja-pos-api.<your-subdomain>.workers.dev

NEXT
