# RideApp

RideApp is a ride-booking project with a Flutter Android client, a FastAPI service backed by MySQL, and a React admin site.

## Project layout

- `MOBILE/mobile` — Flutter passenger and driver app. Open `RideApp.code-workspace` in VS Code to keep Dart analysis scoped to the active app rather than the archived mobile copies.
- `BACKEND/fastapi` — FastAPI API, MySQL schema, admin bootstrap script, and API tests. See its [setup guide](BACKEND/fastapi/README.md).
- `admin` — React/Vite admin site. Its API origin is configured with `VITE_API_URL` (see `admin/.env.example`).

## Run locally

1. Start MySQL and follow the [FastAPI setup guide](BACKEND/fastapi/README.md) to configure the database and launch the API on port 3000.
2. In `admin`, copy `.env.example` to `.env`, install packages with `npm install`, then run `npm run dev`.
3. Open `RideApp.code-workspace` in VS Code or open `MOBILE/mobile` directly in Android Studio. From that Flutter project, run:

   ```powershell
   flutter pub get
   flutter run
   ```

The Android emulator reaches the host API at `10.0.2.2:3000`. For a physical device on the same private network, pass the computer's LAN address, for example:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:3000/api
```

Use HTTPS and a deployed API URL for release builds. Debug builds allow HTTP for local development only.

## Verify and package

Run backend tests from `BACKEND/fastapi` with `python -m pytest`. Run the admin production build from `admin` with `npm run build`. Run the Flutter checks from `MOBILE/mobile` with `flutter analyze` and `flutter test`. Build an Android debug APK with `flutter build apk --debug`; Gradle writes it to `build/app/outputs/flutter-apk/app-debug.apk`.

The Android Gradle configuration supports the Java 25 runtime bundled with current Android Studio. The app targets Android API 24 and later.

## Current integration scope

Local ride booking, driver matching/state transitions, tracking, cash payment records, and ride history are implemented across the API and mobile app. Card processing and actual push notification delivery require provider credentials and are not enabled yet. See the backend guide for the local fare and geocoding behavior and production security settings.
