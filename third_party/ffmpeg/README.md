# FFmpeg (מקור) לעיבוד שמע

התיקייה הזו מכילה את קוד המקור של **FFmpeg 9.0.2** (רישיון LGPL, ראה `ffmpeg-9.0.2/COPYING.LGPLv2.1`).
האפליקציה משתמשת בו לחיתוך קטעי שמע (ו-fade בקצוות כדי שלא ייווצר קליק / "טטוח") ולהפחתת רעש.

## Windows: הבינארי כבר בפרויקט

`third_party/ffmpeg/bin/ffmpeg.exe` מוטמע בפרויקט (ראה `NOTICE.md`). אין צורך לבנות כלום; `flutter build windows` מעתיק אותו ל-`ffmpeg/` ליד ה-EXE, והאפליקציה עובדת בלי אינטרנט.

## בנייה מהמקור (אופציונלי, LGPL בלי GPL)

(פעם אחת לכל מחשב)

- Linux / macOS:
  ```
  bash third_party/ffmpeg/build.sh
  ```
- אחרי עדכון: להריץ מחדש את `build.sh` (הבינארי צריך את הפילטר `anlmdn` להפחתת רעש).
- Windows: להריץ את הסקריפט מ-MSYS2 (או Git Bash) עם הכלים של MSYS2 (`gcc`, `make`):
  ```
  bash third_party/ffmpeg/build.sh
  ```

הפלט נכתב ל-`third_party/ffmpeg/bin/ffmpeg` (או `ffmpeg.exe` ב-Windows).

## איך האפליקציה מוצאת אותו

1. `ffmpeg/` ליד הקובץ הרץ (ב-Windows: ה-CMake מעתיק את `bin/` לשם בבנייה של `flutter build windows`).
2. `third_party/ffmpeg/bin` של הפרויקט (בזמן `flutter run`).
3. `ffmpeg` מה-PATH של המערכת.

אם לא נמצא אף אחד מהם, החיתוך יציג הודעה שה-FFmpeg לא זמין במכשיר.

## הערות

- הבנייה כוללת רק מה שצריך לעיבוד שמע (MP3, WAV, FLAC, OGG, AAC, פלט M4A/AAC), בלי רכיבי רשת ובלי רכיבי GPL.
- `build/` ו-`bin/` נוצרים בבנייה ואינם נשמרים ב-git.
