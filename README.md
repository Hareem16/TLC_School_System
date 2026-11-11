# TLC School System

A Flutter-based school management application for The Learning Circle Secondary School.

## Project information

- Application: TLC School System
- School: The Learning Circle Secondary School
- Developer credit: Developed by FAKHRA RASHID
- Framework: Flutter
- Language: Dart
- Local database: SQLite
- Cloud platform: Supabase
- Desktop: Windows 10/11 (64-bit)
- Mobile: Android

## Main project folders

- `lib/` â€” Application source code
- `lib/data/` â€” Database and repository services
- `lib/auth/` â€” Authentication and user access
- `lib/cloud/` â€” Supabase and device-related services
- `lib/backup/` â€” Database backup functionality
- `assets/` â€” School logo, wallpapers and fonts
- `assets/fonts/` â€” DanceCrazeBV font
- `android/` â€” Android configuration
- `windows/` â€” Windows configuration
- `test/` â€” Automated tests
- `tool/` â€” Development utilities

## Development checks

```powershell
flutter doctor -v
flutter analyze
flutter test
```

## Database safety

The application uses local SQLite storage.

- Never delete the active database to troubleshoot an update.
- Never uninstall the Android application if its local records must be preserved.
- Create and validate a database backup before migrations.
- Preserve the database filename, schema compatibility and existing records.
- Never commit database files, exports, private credentials or signing keys.

## Android application identity

Current package ID: `com.example.tlc_school_system`

Current project version: `1.0.0+1`

Android updates must preserve the package ID and signing certificate. Increase the Android build number for every published update.

The current release configuration uses the Android debug signing identity. Preserve it for compatibility with the currently installed application until a safe signing migration is planned.

## Centralized update system

The planned architecture is:

- GitHub Releases â€” Windows and Android release packages.
- TLC school website â€” Public download and release information.
- Central update manifest â€” Versions, download URLs and checksums.
- Windows â€” Controlled update and installation workflow.
- Android â€” APK download followed by Android installation approval.

The centralized updater is under development. Automatic updates are not yet available.

## Cloud and synchronization status

Supabase is configured in the project. This does not mean local school records are already synchronized.

Windows and Android currently maintain separate local databases. Records entered on one device do not automatically appear on another.

## Repository safety

The Git ignore configuration excludes local databases, signing keys, generated builds, release packages, environment files and local safety copies.

Never publish private credentials or school database records.