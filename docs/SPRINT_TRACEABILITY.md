# RideApp sprint traceability

This map connects the requested stories to the implementation and the checks available in this repository. “Implemented” means the code path exists; it does not imply that an external provider or a physical Android device has been configured and exercised.

## Sprint 1 — Auth engine and database setup

| Story | Implementation | Verification |
| --- | --- | --- |
| US-001 Passenger registration and login | `POST /api/register`, `POST /api/login` | `tests/test_api.py`: authentication and password tests |
| US-002 Driver registration and onboarding | Driver role registration; onboarding prompt; `/api/my-vehicle` | API tests cover driver registration and vehicle setup |
| US-003 Role-based access control | `require_role`, ownership checks on user and ride routes | API tests cover role-denied requests |
| US-004 Passenger and driver profiles | `GET/PUT /api/profile`; admin user/driver routes | Profile routes and admin UI are implemented |
| US-005 Driver vehicle information | `GET/POST /api/my-vehicle`; admin `/api/vehicles` | Ride workflow tests register vehicles |
| US-006 JWT authentication | Signed JWTs, database-backed account/role lookup, Argon2 password hashes | API tests cover login, invalid credentials, and legacy hash upgrade |
| Sprint deliverable | MySQL schema, startup checks, Swagger at `/docs`, Postman collection | Import `postman/RideApp.postman_collection.json`; configure its base URL and tokens |

## Sprint 2 — Driver availability and user management

| Story | Implementation | Verification |
| --- | --- | --- |
| US-007 Passenger profile management | Mobile profile editor and `PUT /api/profile` | API route and Flutter UI implemented |
| US-008 Driver profile management | Shared profile editor and admin driver management | API routes and admin UI implemented |
| US-009 Driver vehicle registration | Driver vehicle form and admin vehicle CRUD | Ride workflow test covers registration |
| US-010 Driver online/offline | Availability endpoint; online sharing starts and offline stops | API tests cover availability preconditions |
| US-011 Driver availability management | Online state requires a vehicle; active rides prevent going offline | API tests cover these restrictions |
| US-012 Push notification setup | FCM token registration, inbox persistence, optional Firebase Admin delivery | Delivery requires Firebase project and service-account credentials; inbox works without them |

## Sprint 3 — Ride booking and fare engine

| Story | Implementation | Verification |
| --- | --- | --- |
| US-013 View current location | Flutter Geolocator current-position action | Requires device location permission and location services |
| US-014 Select pickup | Pickup address input or current GPS position | Mobile booking form and fare endpoint |
| US-015 Select destination | Destination input and OpenStreetMap geocoding | Named-place geocoding requires network access |
| US-016 Distance and fare estimate | Coordinate distance estimate and ride-type fare rules | API tests verify coordinate and explicit-distance estimates |
| US-017 Select ride type | Car, Tuk Tuk, Motorbike, and Direct Ride options | Implemented in booking flow and API validation |
| US-018 Request a ride | `POST /api/rides`, persistent ride events, driver offer generation | API workflow test covers request and matching |
| US-019 Checkout/booking summary | Fare estimate and confirmation in mobile booking flow | Implemented in Flutter |

Fare distance is a demo estimate (straight-line distance multiplied by 1.25), not turn-by-turn routing. Configure a routing provider before using it as a production quote.

## Sprint 4 — Driver matching and ride state machine

| Story | Implementation | Verification |
| --- | --- | --- |
| US-020 Find nearby available drivers | Compatible drivers with a location updated in the last five minutes are offered rides within `RIDE_MATCH_RADIUS_KM` (10 km by default) | API test covers a nearby match, a distant exclusion, and a driver who comes online later |
| US-021 Send ride request to driver | Ride offers and inbox/FCM notification | API workflow test checks offer and notification behavior |
| US-022 Driver accept/reject | Conditional ride claim, compatible vehicle checks, offer status | API workflow test covers accept and rejection constraints |
| US-023 Passenger ride confirmation | Ride status and notifications exposed in passenger history | Flutter history refresh and notification UI |
| US-024 Ride status management | Requested → accepted → ongoing → completed, with cancellation transitions | API workflow tests exercise lifecycle and invalid transitions |
| US-025 Cancel ride | Passenger cancellation while unassigned; driver cancellation while assigned | Implemented with transition checks |
| US-026 Start trip | Driver changes accepted ride to ongoing | Implemented in driver ride actions |

If pickup coordinates are unavailable, the demo cannot calculate proximity and offers the ride to all compatible online drivers. Online location sharing runs only while a driver is online; trip location sharing is limited to the assigned active ride.

## Sprint 5 — Tracking and payment

| Story | Implementation | Verification |
| --- | --- | --- |
| US-027 Real-time driver location | Driver GPS stream posts location updates | Requires location permission and an active app/device session |
| US-028 Passenger live tracking | Ride-scoped tracking endpoint and Flutter map refresh | Implemented; live device/emulator verification remains environment-dependent |
| US-029 Complete trip | Driver completion action | API workflow test covers completion |
| US-030 Final fare calculation | Distance fare for normal rides; driver-entered final fare for Direct Ride | API tests cover both fare paths |
| US-031 Cash payment | `POST /api/payments` | API test verifies one payment per ride and receipt |
| US-032 Digital payment | Dynamic USD KHQR, status verification with Bakong, confirmation before receipt | Requires a real merchant account and Bakong API token; simulated provider responses are tested |
| US-033 Ride history and receipt | Passenger history and owner-checked receipt endpoint | API and mobile flows are implemented |

## Sprint 6 — Admin, hardening, and demo preparation

| Story | Implementation | Verification |
| --- | --- | --- |
| US-034 Admin dashboard | React/Vite dashboard | `npm run build` |
| US-035 Manage passengers and drivers | Admin user/driver routes and management screens | Routes and UI implemented |
| US-036 Ride and payment records | Admin ride/payment views and API endpoints | Routes and UI implemented |
| US-037 Passenger and driver rating | Both rider and driver submit one ride rating; admin ratings endpoint and Ratings page | API workflow test covers two-sided rating and admin listing |
| US-038 System hardening | JWT/role checks, password hashing, production secret/CORS validation, input limits | API tests cover auth and selected security conditions |
| US-039 End-to-end test script | `scripts/e2e_smoke.py` | Run against a disposable development database only; it creates records |
| US-040 OpenAPI/Swagger | FastAPI-generated OpenAPI and `/docs` | Available when the backend is running |

## Remaining setup for a full external demo

- Start MySQL and configure `BACKEND/fastapi/.env`; the local E2E smoke script has not been run because it writes to its configured database.
- Configure Firebase credentials to verify actual push delivery; the automated tests verify inbox behavior and that provider failures do not block rides.
- Configure Bakong merchant credentials to perform a real KHQR payment; automated tests simulate paid, pending, mismatched, and unauthorized cases.
- Run Flutter analysis/tests and a device/emulator walkthrough in an Android environment. Flutter tooling did not complete in the current workspace session.
