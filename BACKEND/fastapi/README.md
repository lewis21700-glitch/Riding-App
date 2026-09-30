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

5. Create the first admin account with `python scripts/create_admin.py`. The password is entered interactively and saved as an Argon2 hash.
6. Open `../admin` in another terminal, copy `.env.example` to `.env`, set `VITE_API_URL` to the FastAPI server origin (for example `http://localhost:3000`), then run `npm install` and `npm run dev`. The Flutter app uses `10.0.2.2:3000` from the Android emulator. For a physical Android device, pass `--dart-define=API_BASE_URL=http://YOUR_COMPUTER_LAN_IP:3000/api` and allow that debug-only HTTP connection on your private network.

## Compatibility and security

Existing legacy plaintext and bcrypt passwords are accepted at login once and upgraded to Argon2. New registrations and password changes always use Argon2. Role claims are looked up against MySQL on each authenticated request so deleted or changed accounts lose access immediately. Set `APP_ENV=production` and provide a private `JWT_SECRET` of at least 32 characters before deployment; startup rejects the development secret and wildcard CORS in production. Database/schema failures stop application startup rather than leaving a partially working API.

The local demo estimates road distance as 1.25 times the straight-line distance. It accepts explicit distances and coordinate pairs; named places are resolved with OpenStreetMap Nominatim. Configure a descriptive `GEOCODER_USER_AGENT` before using that service beyond local testing. Cash payments are recorded only after ride completion. Card payments and push delivery need provider credentials and are intentionally reported as unconfigured until those accounts are supplied; the API can store device tokens for a future Firebase integration.

The Express implementation at `../server.js` is retained for reference; run the FastAPI service instead so only one process owns port 3000.
