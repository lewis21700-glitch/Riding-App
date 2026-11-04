# RideApp

RideApp is a ride-booking project with a Flutter Android client, a FastAPI service backed by MySQL, and a React admin site.

## Project layout

- `MOBILE/mobile` — Flutter passenger and driver application.
- `BACKEND/fastapi` — FastAPI REST API, MySQL database migrations, admin bootstrap, and test suite. See its [setup guide](BACKEND/fastapi/README.md).
- `admin` — React/Vite admin dashboard portal for real-time dispatch, income tracking, driver payouts, and fleet management.
- `docs` — project overview, sprint coverage, and project documentation.
- `MOBILE/archive` — preserved older Flutter snapshots; use `MOBILE/mobile` for the current app.
- `ARCHIVE` — preserved auxiliary repository metadata.

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

To enable Android push notifications, configure the Firebase Android app in the Firebase console and pass its public app options to Flutter at build/run time:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api --dart-define=FIREBASE_API_KEY=your-api-key --dart-define=FIREBASE_APP_ID=1:123456789:android:abcdef --dart-define=FIREBASE_MESSAGING_SENDER_ID=123456789 --dart-define=FIREBASE_PROJECT_ID=your-firebase-project
```

Use the matching Firebase project ID and server service-account credentials in `BACKEND/fastapi/.env`. Push support stays inactive when the Flutter options or backend credentials are absent. Firebase app options are public identifiers; never pass a service-account private key to the app or commit it.

Use HTTPS and a deployed API URL for release builds. Debug builds allow HTTP for local development only.

## Verify and package

Run backend tests from `BACKEND/fastapi` with `python -m pytest`. Run the admin production build from `admin` with `npm run build`. Run the Flutter checks from `MOBILE/mobile` with `flutter analyze` and `flutter test`. Build an Android debug APK with `flutter build apk --debug`; Gradle writes it to `build/app/outputs/flutter-apk/app-debug.apk`.

The Android Gradle configuration supports the Java 25 runtime bundled with current Android Studio. The app targets Android API 24 and later.

## Current integration scope

Local ride booking, driver matching/state transitions, tracking, cash payments, confirmed KHQR payments, receipts, ratings, and ride history are implemented across the API and mobile app. Push delivery and KHQR payment confirmation require Firebase and Bakong merchant credentials, respectively; both integrations remain disabled until configured. The project targets dynamic USD KHQR rather than card processing, since Stripe does not currently support Cambodia-based merchant accounts. See the backend guide for provider setup, local fare/geocoding behavior, and production security settings.
