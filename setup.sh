#!/usr/bin/env bash
# יוצר תיקיות פלטפורמה רק אם חסרות, ואז פותר את התלויות לפי pubspec.yaml.
set -e
if [[ ! -d android || ! -d ios || ! -d web ]]; then
  flutter create --platforms=android,ios,web --project-name music_manager .
fi
flutter pub get
echo "ההכנה הסתיימה. לפרטי Google Drive והרשאות פלטפורמה עיין ב-PLATFORM_SETUP.md."
