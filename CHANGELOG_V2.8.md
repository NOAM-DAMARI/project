# V2.8 — מערכת לשיעורים

## Included in this package
- Lessons-only web app branded as "מערכת לשיעורים" in the Flutter app title, browser title, and manifest.
- Replaced the inline splash image with `web/splash.png` (the supplied logo).
- Default GitHub repository changed to `LessonSong`; repository setup guide updated.
- Transcript comparison choices are deduplicated by transcript ID to prevent duplicate DropdownButton values.
- File upload screen shows completed, pending, and failed counts while GitHub uploads are running.
- Added JSON settings export/import for GitHub connection and transcription settings. Empty imported fields are ignored.
- Added a double-confirmed local-data and media-cache reset when GitHub is not actively connected.
- DJ page uses a fixed-height queue section; the lesson/song lists and queue scroll independently.
- ZIP import table uses more compact row heights and column spacing while retaining horizontal scrolling.
- App version updated to 2.8.0.

## Not included yet
- FFmpeg-based audio trimming and noise reduction.
- ID3v2.3 MP3 tag editor and artwork embedding.
- Automatic media-cache/data refresh behavior beyond the existing GitHub synchronization.

## Validation
Flutter SDK is not available in the packaging environment; Flutter analyze/build was not run. Source-level checks and ZIP contents were inspected.

## v2.8.9
- הוסרו ייבואים כפולים של dart:typed_data (pdf_preview_screen, export_service, media_download, zip_import_flow).
- audio_processing_engine_web תקין לבניית JS ו-Wasm (ללא toJS על List וללא בדיקת טיפוס JS בזמן ריצה).
- web/index.html כולל <base href="$FLUTTER_BASE_HREF">.
- Android: Kotlin compilerOptions (JVM 17) במקום kotlinOptions.
- כפתורי מאגר: חבר מאגר, ייבא מהמאגר, סנכרן (שומר ומייבא חסרים), העלה רק מה שחסר.

## v2.8.10
- מסך הפתיחה: האפליקציה נטענת בלי Service Worker ומנקה מטמון ישן, כדי שגרסה ישנה לא תיתקע על התמונה. זמן ההמתנה הוארך ל-60 שניות, ובמקרה של קובץ חסר מוצגת הודעה עם שם הקובץ.
- audio_processing_engine_web נכתב מחדש בלי extension types (תואם JS ו-Wasm).
- הוסר ייבוא מיותר של dart:typed_data ב-storage_io.
- Android: חזרה ל-AGP 8.11.1, Kotlin 2.2.20 ו-Gradle 8.14.3, כי AGP 9 נכשל עם share_plus.

## v2.8.11
- נוספו תיקיות linux ו-macos מלאות, והושלמו קבצים חסרים ב-android וב-ios (נוצרו עם flutter create, בלי לשנות קבצים קיימים).
- מסך הפתיחה: עברית תקינה גם בשרת שלא מגדיר UTF-8, תיקון base href שלא הוחלף, וטעינה חלופית כשאין flutter_bootstrap.js.
- download_bytes_web עבר מ-dart:html ל-package:web.
- תוקנו אזהרות flutter analyze (zip_bytes, zip_import_flow, audio_processing, storage_io).
- test/widget_test.dart חדש שעובד עם StartupGate. כל 25 הבדיקות עוברות.
- web_build_ready/: גרסת Web בנויה ומוכנה להעלאה לאחסון.
