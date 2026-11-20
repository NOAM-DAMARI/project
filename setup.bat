@echo off
if not exist android\app\src\main\AndroidManifest.xml goto create_platforms
if not exist ios\Runner\Info.plist goto create_platforms
if not exist web\index.html goto create_platforms
goto resolve_dependencies
:create_platforms
flutter create --platforms=android,ios,web --project-name music_manager .
if errorlevel 1 exit /b %errorlevel%
:resolve_dependencies
flutter pub get
if errorlevel 1 exit /b %errorlevel%
echo Setup complete. See PLATFORM_SETUP.md for Google Drive and platform configuration.
