#!/usr/bin/env bash
set -euo pipefail

flutter_version="3.47.8"
flutter_dir="${TMPDIR:-/tmp}/flutter-${flutter_version}"

if [ ! -x "$flutter_dir/bin/flutter" ]; then
  git clone --depth 1 --branch "$flutter_version" \
    https://github.com/flutter/flutter.git "$flutter_dir"
fi

export PATH="$flutter_dir/bin:$PATH"
flutter config --no-analytics
flutter pub get
flutter build web --release \
  --dart-define="GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-}"
