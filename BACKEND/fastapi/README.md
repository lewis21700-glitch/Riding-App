# RideApp FastAPI backend

This service uses the existing MySQL database and preserves the `/api` response shapes consumed by the admin site. Swagger is available at `http://localhost:3000/docs`.

## Windows setup

1. Install Python 3.11 or later and MySQL 8. The existing project uses the `ride_app` database. For a fresh database, run `sql/schema.sql` in MySQL.
2. From this folder, create and activate a virtual environment, install the requirements, and copy `.env.example` to `.env`:

   ```powershell
   py -3 -m venv .venv
   .\.venv\Scripts\Activate.ps1
   python -m pip install -r requirements.txt
   Copy-Item .env.example .env
   ```

3. Set `DATABASE_URL` and a private, random `JWT_SECRET` in `.env`. Set the database URL credentials to your local MySQL user. Do not commit `.env`.
4. Start the API on port 3000:

   ```powershell
   python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 3000
   ```

Dynamic USD KHQR is optional. Create a merchant Bakong account and request an Open API token from the [Bakong Open API portal](https://api-bakong.nbc.gov.kh/), then set `BAKONG_ACCOUNT_ID`, `BAKONG_MERCHANT_NAME`, `BAKONG_MERCHANT_CITY`, `BAKONG_PHONE_NUMBER`, and `BAKONG_API_TOKEN` in the backend `.env`. For the integration test environment use `BAKONG_API_BASE_URL=https://sit-api-bakong.nbc.org.kh/v1`; production uses `https://api-bakong.nbc.gov.kh/v1`. Keep the token private. The generated dynamic QR expires after `BAKONG_QR_EXPIRY_MINUTES` (1–10). The API creates a receipt only after Bakong confirms the fare amount, USD currency, and configured merchant account.

5. Create the first admin account with `python scripts/create_admin.py`. The password is entered interactively and saved as an Argon2 hash.
6. Open `../admin` in another terminal, copy `.env.example` to `.env`, set `VITE_API_URL` to the FastAPI server origin (for example `http://localhost:3000`), then run `npm install` and `npm run dev`. The Flutter app uses `10.0.2.2:3000` from the Android emulator. For a physical Android device, pass `--dart-define=API_BASE_URL=http://YOUR_COMPUTER_LAN_IP:3000/api` and allow that debug-only HTTP connection on your private network.

## End-to-end smoke test

With the API running against a disposable development/test database, execute:

```powershell
python scripts/e2e_smoke.py --api-url http://127.0.0.1:3000 --allow-writes
```

The script checks API/database health, Swagger/OpenAPI, passenger and driver registration/login, role restrictions, vehicle onboarding, fare estimate, driver matching, inbox notification, trip lifecycle and location tracking, cash payment and receipt, rating, and ride history. It creates two uniquely named accounts, a vehicle, ride, payment, rating, notifications, and location record; those records are intentionally not deleted. Use only a development/test database. Omit `--allow-writes` to see the safety guard. Remote API hosts also require `--allow-nonlocal` as an additional safeguard.

For interactive API checks, import [`postman/RideApp.postman_collection.json`](postman/RideApp.postman_collection.json) into Postman. Set `baseUrl`, account emails/passwords, and admin credentials; register each test account once, then run its login request to save its token. Collection requests create and modify records, so use a development database. KHQR requests need a separate unpaid completed ride: set `khqrRideId` to that ride because the cash-payment request marks `rideId` paid. Real confirmation also requires Bakong merchant configuration.

See [`../../docs/SPRINT_TRACEABILITY.md`](../../docs/SPRINT_TRACEABILITY.md) for story-to-code coverage and external setup still needed for a full demo.

## Compatibility and security

Existing legacy plaintext and bcrypt passwords are accepted at login once and upgraded to Argon2. New registrations and password changes always use Argon2. Role claims are looked up against MySQL on each authenticated request so deleted or changed accounts lose access immediately. Set `APP_ENV=production` and provide a private `JWT_SECRET` of at least 32 characters before deployment; startup rejects the development secret and wildcard CORS in production. Database/schema failures stop application startup rather than leaving a partially working API.

The local demo estimates road distance as 1.25 times the straight-line distance. It accepts explicit distances and coordinate pairs; named places are resolved with OpenStreetMap Nominatim. Configure a descriptive `GEOCODER_USER_AGENT` before using that service beyond local testing. Cash payments are recorded only after ride completion. For optional device push, create a Firebase project, keep its service-account JSON outside Git, and set `GOOGLE_APPLICATION_CREDENTIALS` (plus `FIREBASE_PROJECT_ID` when needed) in the backend environment. Without Firebase credentials, the API continues to save inbox notifications and ride actions normally. For optional KHQR, see the setup steps above; payment remains unavailable until a real merchant account and Bakong Open API token are supplied.

Drivers who are online share their location so rides with a known pickup coordinate can be offered within `RIDE_MATCH_RADIUS_KM` (10 km by default). Location reports older than five minutes are ignored. The mobile app stops sharing when the driver goes offline; while on a trip it shares only for the assigned active ride. If a pickup cannot be geocoded, the demo offers it to all compatible online drivers because there is no coordinate to compare.

The FastAPI service runs on port 3000 and serves all mobile client, admin dashboard, dispatch, and payment endpoints.
