RIDE APP - SPRINT 3 MOBILE

This is the complete Flutter source package for the Android Sprint 3 rider app.

WORKING PROJECT PATH:
D:\RIDE APP\MOBILE\mobile

IMPORTANT:
1. Open this folder as a Flutter project in Android Studio.
2. Do not copy only lib/main.dart; this package includes the Android platform folder.
3. Run `flutter pub get`.
4. Select the Pixel 7 emulator.
5. Run the app.

ANDROID:
- Location permissions are included.
- INTERNET permission is included.
- Cleartext HTTP is enabled for the local development backend.
- The emulator uses http://10.0.2.2:3000/api to reach the Windows host at localhost:3000.
- During an active trip, driver GPS is shared with the passenger and an ongoing Android notification explains that sharing continues while RideApp is in the background. Sharing stops when the trip ends; location is not collected for background tracking outside an active trip.
- Live tracking maps use OpenStreetMap tiles by default and show map attribution. For deployment, configure `MAP_TILE_URL` and `MAP_ATTRIBUTION` with a tile provider and licence appropriate to expected usage.

BACKEND:
Sprint 3 booking requires matching backend endpoints:
POST /api/login
POST /api/users
POST /api/fare/estimate
POST /api/rides
GET  /api/my-rides?rider_id=ID

Do not delete your old mobile_backup folder until the new project is tested.
