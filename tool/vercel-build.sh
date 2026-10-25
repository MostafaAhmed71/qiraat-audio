#!/usr/bin/env bash
set -euo pipefail
sdk_path="/tmp/qiraat-flutter-3.35.4"
if [ ! -d "$sdk_path" ]; then git clone --depth 1 --branch 3.35.4 https://github.com/flutter/flutter.git "$sdk_path"; fi
test "$(git -C "$sdk_path" rev-parse HEAD)" = "d693b4b9dbac2acd4477aea4555ca6dcbea44ba2"
export PATH="$sdk_path/bin:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true
flutter pub get
flutter build web --release --no-web-resources-cdn --pwa-strategy=none
python3 tool/pwa.py
