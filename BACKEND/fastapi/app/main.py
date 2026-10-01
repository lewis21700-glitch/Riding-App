from __future__ import annotations

import hmac
import logging
import math
import os
import re
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Literal

import httpx
import jwt
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field
from fastapi.exceptions import RequestValidationError
from pwdlib import PasswordHash
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.engine import Engine

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("rideapp")
load_dotenv()

APP_ENV = os.getenv("APP_ENV", "development").strip().lower()
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "mysql+pymysql://root:1234@127.0.0.1:3306/ride_app?charset=utf8mb4",
)
JWT_SECRET = os.getenv("JWT_SECRET", "local-development-only-change-before-deploy-32chars")
JWT_EXPIRE_MINUTES = int(os.getenv("JWT_EXPIRE_MINUTES", "480"))
CORS_ORIGINS = [
    origin.strip()
    for origin in os.getenv(
        "CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173"
    ).split(",")
    if origin.strip()
]
GEOCODER_USER_AGENT = os.getenv(
    "GEOCODER_USER_AGENT", "RideAppDemo/1.0 (local demo)"
)
FIREBASE_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID", "").strip()
engine: Engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_recycle=1800)
password_hash = PasswordHash.recommended()
_firebase_app = None

RIDE_ALIASES = {
    "car": "Car",
    "tuktuk": "Tuk Tuk",
    "tuk tuk": "Tuk Tuk",
    "motorbike": "Motorbike",
    "direct": "Direct Ride",
    "direct ride": "Direct Ride",
}
FARE_RULES = {
    "Car": (1.50, 0.75, 2.50),
    "Tuk Tuk": (1.00, 0.55, 2.00),
    "Motorbike": (0.75, 0.40, 1.50),
}


def rows(sql: str, params: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    with engine.connect() as conn:
        result = conn.execute(text(sql), params or {})
        return [dict(row) for row in result.mappings().all()]


def execute(sql: str, params: dict[str, Any] | None = None) -> tuple[int, int | None]:
    with engine.begin() as conn:
        result = conn.execute(text(sql), params or {})
        return result.rowcount, result.lastrowid


def ensure_schema() -> None:
    """Additive setup for Sprint 2-6 tables; preserve the existing project tables."""
    statements = [
        """CREATE TABLE IF NOT EXISTS notifications (
          id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NULL, title VARCHAR(255) NOT NULL,
          message TEXT NOT NULL, type VARCHAR(50) DEFAULT 'system', is_read TINYINT(1) DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, INDEX idx_notifications_user (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""",
        """CREATE TABLE IF NOT EXISTS driver_locations (
          driver_id INT PRIMARY KEY, ride_id INT NULL, latitude DECIMAL(10,7) NOT NULL,
          longitude DECIMAL(10,7) NOT NULL, heading DECIMAL(7,2) NULL,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          CONSTRAINT fk_location_driver FOREIGN KEY (driver_id) REFERENCES users(id) ON DELETE CASCADE,
          INDEX idx_location_ride (ride_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""",
        """CREATE TABLE IF NOT EXISTS ride_offers (
          ride_id INT NOT NULL, driver_id INT NOT NULL, status ENUM('offered','rejected','accepted') NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (ride_id,driver_id), INDEX idx_offer_driver_status (driver_id,status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""",
        """CREATE TABLE IF NOT EXISTS ride_events (
          id INT AUTO_INCREMENT PRIMARY KEY, ride_id INT NOT NULL, actor_id INT NULL,
          event_type VARCHAR(40) NOT NULL, details JSON NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, INDEX idx_ride_event (ride_id,id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""",
        """CREATE TABLE IF NOT EXISTS ratings (
          id INT AUTO_INCREMENT PRIMARY KEY, ride_id INT NOT NULL, rater_id INT NOT NULL,
          ratee_id INT NOT NULL, score TINYINT NOT NULL, comment VARCHAR(500) NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, UNIQUE KEY uq_ride_rater (ride_id,rater_id),
          INDEX idx_ratee (ratee_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""",
        """CREATE TABLE IF NOT EXISTS push_tokens (
          id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, token VARCHAR(512) NOT NULL,
          platform VARCHAR(20) NOT NULL DEFAULT 'android', created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE KEY uq_push_token (token), INDEX idx_push_user (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""",
    ]
    with engine.begin() as conn:
        for statement in statements:
            conn.execute(text(statement))
        # Older Sprint 3 installations may not yet have destination coordinates.
        existing = {
            row["COLUMN_NAME"]
            for row in conn.execute(
                text("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS "
                     "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='rides'")
            ).mappings()
        }
        for name, sql_type in (
            ("destination_lat", "DECIMAL(10,7) NULL"),
            ("destination_lng", "DECIMAL(10,7) NULL"),
            ("estimated_fare", "DECIMAL(10,2) NULL"),
        ):
            if name not in existing:
                conn.execute(text(f"ALTER TABLE rides ADD COLUMN {name} {sql_type}"))


@asynccontextmanager
async def lifespan(_: FastAPI):
    validate_security_configuration()
    ensure_schema()
    logger.info("RideApp database schema ready")
    yield
    engine.dispose()


app = FastAPI(
    title="RideApp API",
    description="Authentication, driver operations, ride booking, tracking and administration.",
    version="1.0.0",
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


class RegisterBody(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    email: EmailStr
    phone: str = Field(default="", max_length=30)
    password: str = Field(min_length=8, max_length=128)
    role: Literal["rider", "driver"] = "rider"


class LoginBody(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class ProfileBody(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    phone: str = Field(default="", max_length=30)


class VehicleBody(BaseModel):
    vehicle_type: str = Field(min_length=2, max_length=50)
    vehicle_model: str = Field(min_length=2, max_length=100)
    plate_number: str = Field(min_length=2, max_length=30)


class RideBody(BaseModel):
    pickup_location: str = Field(min_length=2, max_length=255)
    destination: str | None = Field(default=None, max_length=255)
    ride_type: str = "Car"
    distance_km: float | None = Field(default=None, ge=0, le=1000)
    pickup_lat: float | None = Field(default=None, ge=-90, le=90)
    pickup_lng: float | None = Field(default=None, ge=-180, le=180)
    destination_lat: float | None = Field(default=None, ge=-90, le=90)
    destination_lng: float | None = Field(default=None, ge=-180, le=180)


class FareBody(BaseModel):
    pickup: str | None = None
    destination: str | None = None
    ride_type: str = "Car"
    distance_km: float | None = Field(default=None, ge=0, le=1000)
    pickup_lat: float | None = Field(default=None, ge=-90, le=90)
    pickup_lng: float | None = Field(default=None, ge=-180, le=180)
    destination_lat: float | None = Field(default=None, ge=-90, le=90)
    destination_lng: float | None = Field(default=None, ge=-180, le=180)


class AvailabilityBody(BaseModel):
    availability: Literal["online", "offline", "available", "busy", "on_ride"]


class DriverRideAction(BaseModel):
    status: Literal["accepted", "rejected", "ongoing", "completed", "cancelled"]
    final_fare: float | None = Field(default=None, ge=0, le=100000)


class PaymentBody(BaseModel):
    ride_id: int = Field(gt=0)
    payment_method: Literal["cash", "card"] = "cash"


class LocationBody(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    heading: float | None = Field(default=None, ge=0, le=360)


class RatingBody(BaseModel):
    ride_id: int = Field(gt=0)
    score: int = Field(ge=1, le=5)
    comment: str | None = Field(default=None, max_length=500)


def fail(code: int, message: str) -> None:
    raise HTTPException(status_code=code, detail=message)


def validate_security_configuration() -> None:
    if APP_ENV in ("production", "prod"):
        if len(JWT_SECRET) < 32 or JWT_SECRET == "local-development-only-change-before-deploy-32chars":
            raise RuntimeError("Production requires a private JWT_SECRET with at least 32 characters")
        if "*" in CORS_ORIGINS:
            raise RuntimeError("Production CORS_ORIGINS cannot contain a wildcard")


def jwt_subject(authorization: str | None = Header(default=None)) -> dict[str, Any]:
    if not authorization or not authorization.lower().startswith("bearer "):
        fail(401, "Authentication required")
    try:
        payload = jwt.decode(authorization[7:].strip(), JWT_SECRET, algorithms=["HS256"])
        user_id = int(payload["sub"])
        found = rows("SELECT id,name,email,phone,role,availability FROM users WHERE id=:id", {"id": user_id})
        if not found:
            fail(401, "Account no longer exists")
        return found[0]
    except HTTPException:
        raise
    except (jwt.InvalidTokenError, KeyError, TypeError, ValueError):
        fail(401, "Invalid or expired token")


def require_role(*roles: str):
    def dependency(user: dict[str, Any] = Depends(jwt_subject)) -> dict[str, Any]:
        if user["role"] not in roles:
            fail(403, f"{' or '.join(roles).title()} access required")
        return user
    return dependency


def user_view(user: dict[str, Any]) -> dict[str, Any]:
    return {key: user.get(key) for key in ("id", "name", "email", "phone", "role", "availability")}


def token_for(user: dict[str, Any]) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {"sub": str(user["id"]), "email": user["email"], "role": user["role"],
         "iat": now, "exp": now + timedelta(minutes=JWT_EXPIRE_MINUTES)},
        JWT_SECRET,
        algorithm="HS256",
    )


def normalize_ride_type(value: str) -> str:
    key = re.sub(r"\s+", " ", value.strip()).lower()
    ride_type = RIDE_ALIASES.get(key)
    if not ride_type:
        fail(422, "Ride type must be Car, Tuk Tuk, Motorbike or Direct Ride")
    return ride_type


def normalize_vehicle_type(value: str) -> str:
    return re.sub(r"[\s-]+", "", value.strip().lower())


def vehicle_matches_ride(ride_type: str, vehicle_type: str) -> bool:
    if ride_type == "Direct Ride":
        return True
    return normalize_vehicle_type(ride_type) == normalize_vehicle_type(vehicle_type)


def distance_between(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6371.0088
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lam = math.radians(lon2 - lon1)
    a = math.sin(delta_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lam / 2) ** 2
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


async def geocode(place: str) -> tuple[float, float] | None:
    # Coordinates and GPS strings work offline; named places use OpenStreetMap's public geocoder.
    match = re.search(r"(-?\d{1,3}(?:\.\d+)?)\s*[, ]\s*(-?\d{1,3}(?:\.\d+)?)", place)
    if match:
        lat, lng = float(match.group(1)), float(match.group(2))
        if -90 <= lat <= 90 and -180 <= lng <= 180:
            return lat, lng
    if len(place.strip()) < 3 or "replace-with-your-contact" in GEOCODER_USER_AGENT:
        return None
    try:
        async with httpx.AsyncClient(timeout=5, headers={"User-Agent": GEOCODER_USER_AGENT}) as client:
            response = await client.get(
                "https://nominatim.openstreetmap.org/search",
                params={"q": place, "format": "jsonv2", "limit": 1},
            )
            response.raise_for_status()
            candidates = response.json()
            if candidates:
                return float(candidates[0]["lat"]), float(candidates[0]["lon"])
    except (httpx.HTTPError, ValueError, KeyError):
        logger.info("Geocoding failed for a place lookup")
    return None


def fare_for(ride_type: str, distance_km: float) -> float:
    base, per_km, minimum = FARE_RULES[ride_type]
    return round(max(minimum, base + per_km * distance_km), 2)


def notify(user_id: int | None, title: str, message: str, kind: str = "system") -> None:
    execute(
        "INSERT INTO notifications(user_id,title,message,type) VALUES(:uid,:title,:message,:kind)",
        {"uid": user_id, "title": title, "message": message, "kind": kind},
    )
    if user_id is None:
        return
    tokens = rows("SELECT token FROM push_tokens WHERE user_id=:user", {"user": user_id})
    if not tokens:
        return
    try:
        from firebase_admin import credentials, get_app, initialize_app, messaging

        global _firebase_app
        if _firebase_app is None:
            try:
                _firebase_app = get_app()
            except ValueError:
                options = {"httpTimeout": 5}
                if FIREBASE_PROJECT_ID:
                    options["projectId"] = FIREBASE_PROJECT_ID
                credential_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
                credential = credentials.Certificate(credential_path) if credential_path else None
                _firebase_app = initialize_app(credential, options=options)
        token_values = [str(row["token"]) for row in tokens]
        for offset in range(0, len(token_values), 500):
            batch_tokens = token_values[offset:offset + 500]
            response = messaging.send_each_for_multicast(
                messaging.MulticastMessage(
                    tokens=batch_tokens,
                    notification=messaging.Notification(title=title, body=message),
                    data={"type": kind},
                ),
                app=_firebase_app,
            )
            expired = [
                batch_tokens[index]
                for index, result in enumerate(response.responses)
                if not result.success and getattr(result.exception, "code", None)
                in {"messaging/registration-token-not-registered", "messaging/invalid-registration-token"}
            ]
            for token in expired:
                execute("DELETE FROM push_tokens WHERE token=:token", {"token": token})
    except Exception:
        # Inbox persistence and ride actions must remain available without FCM credentials.
        logger.warning("Push notification delivery failed for user %s", user_id)


def add_ride_offer(ride_id: int, driver_id: int) -> bool:
    statement = (
        "INSERT OR IGNORE INTO ride_offers(ride_id,driver_id,status) VALUES(:ride,:driver,'offered')"
        if engine.dialect.name == "sqlite"
        else "INSERT IGNORE INTO ride_offers(ride_id,driver_id,status) VALUES(:ride,:driver,'offered')"
    )
    count, _ = execute(statement, {"ride": ride_id, "driver": driver_id})
    return bool(count)


def set_ride_offer(ride_id: int, driver_id: int, offer_status: str) -> None:
    statement = (
        "INSERT INTO ride_offers(ride_id,driver_id,status) VALUES(:ride,:driver,:status) "
        "ON CONFLICT(ride_id,driver_id) DO UPDATE SET status=excluded.status"
        if engine.dialect.name == "sqlite"
        else "INSERT INTO ride_offers(ride_id,driver_id,status) VALUES(:ride,:driver,:status) "
        "ON DUPLICATE KEY UPDATE status=VALUES(status)"
    )
    execute(statement, {"ride": ride_id, "driver": driver_id, "status": offer_status})


def notify_ride_offer(ride_id: int, driver_id: int) -> None:
    if add_ride_offer(ride_id, driver_id):
        notify(driver_id, "New ride request", f"Ride #{ride_id} is waiting for a driver.", "ride")


def offer_ride_to_available_drivers(ride_id: int, ride_type: str) -> None:
    candidates = rows(
        "SELECT DISTINCT u.id,v.vehicle_type FROM users u JOIN vehicles v ON v.driver_id=u.id "
        "WHERE u.role='driver' AND u.availability='available'"
    )
    for candidate in candidates:
        if vehicle_matches_ride(ride_type, candidate["vehicle_type"]):
            notify_ride_offer(ride_id, candidate["id"])


def offer_pending_rides_to_driver(driver_id: int) -> None:
    vehicle_types = [item["vehicle_type"] for item in rows(
        "SELECT vehicle_type FROM vehicles WHERE driver_id=:driver", {"driver": driver_id}
    )]
    if not vehicle_types:
        return
    pending = rows("SELECT id,ride_type FROM rides WHERE status='requested' AND driver_id IS NULL")
    for ride in pending:
        if any(vehicle_matches_ride(ride["ride_type"], vehicle_type)
               for vehicle_type in vehicle_types):
            notify_ride_offer(ride["id"], driver_id)


def save_driver_location(driver_id: int, ride_id: int | None, location: LocationBody) -> None:
    if engine.dialect.name == "sqlite":
        statement = (
            "INSERT INTO driver_locations(driver_id,ride_id,latitude,longitude,heading) "
            "VALUES(:driver,:ride,:lat,:lng,:heading) ON CONFLICT(driver_id) DO UPDATE SET "
            "ride_id=excluded.ride_id,latitude=excluded.latitude,longitude=excluded.longitude,"
            "heading=excluded.heading,updated_at=CURRENT_TIMESTAMP"
        )
    else:
        statement = (
            "INSERT INTO driver_locations(driver_id,ride_id,latitude,longitude,heading) "
            "VALUES(:driver,:ride,:lat,:lng,:heading) ON DUPLICATE KEY UPDATE ride_id=:ride,"
            "latitude=:lat,longitude=:lng,heading=:heading,updated_at=CURRENT_TIMESTAMP"
        )
    execute(statement, {"driver": driver_id, "ride": ride_id, "lat": location.latitude,
                        "lng": location.longitude, "heading": location.heading})


def event(ride_id: int, actor_id: int | None, kind: str, details: str | None = None) -> None:
    execute(
        "INSERT INTO ride_events(ride_id,actor_id,event_type,details) VALUES(:ride,:actor,:kind,:details)",
        {"ride": ride_id, "actor": actor_id, "kind": kind, "details": details},
    )


@app.get("/")
def root():
    return {"name": "RideApp API", "docs": "/docs", "health": "/health"}


@app.get("/health")
def health():
    try:
        rows("SELECT 1 AS ok")
        return {"status": "ok", "database": "connected"}
    except Exception:
        logger.exception("Health check database failure")
        fail(503, "Database is unavailable")


@app.post("/api/register", status_code=201)
@app.post("/api/users", status_code=201)
def register(body: RegisterBody):
    email = str(body.email).strip().lower()
    try:
        _, user_id = execute(
            "INSERT INTO users(name,email,phone,password,role,availability) "
            "VALUES(:name,:email,:phone,:password,:role,:availability)",
            {"name": body.name.strip(), "email": email, "phone": body.phone.strip(),
             "password": password_hash.hash(body.password), "role": body.role,
             "availability": "offline" if body.role == "driver" else None},
        )
    except Exception as exc:
        if "1062" in str(exc) or "Duplicate" in str(exc):
            fail(409, "Email already exists")
        raise
    user = rows("SELECT id,name,email,phone,role,availability FROM users WHERE id=:id", {"id": user_id})[0]
    if body.role == "driver":
        notify(user_id, "Driver account created", "Complete your driver profile and vehicle setup.", "driver")
    return {"message": "Registration successful", "token": token_for(user), "user": user_view(user)}


@app.post("/api/login")
def login(body: LoginBody):
    found = rows("SELECT id,name,email,phone,password,role,availability FROM users WHERE email=:email LIMIT 1",
                 {"email": str(body.email).strip().lower()})
    if not found:
        fail(401, "Invalid email or password")
    user = found[0]
    stored = str(user["password"] or "")
    valid = False
    if stored.startswith("$argon2"):
        try:
            valid = password_hash.verify(body.password, stored)
        except Exception:
            valid = False
    elif stored.startswith(("$2a$", "$2b$", "$2y$")):
        try:
            import bcrypt
            valid = bcrypt.checkpw(body.password.encode(), stored.encode())
        except Exception:
            valid = False
        if valid:
            execute("UPDATE users SET password=:password WHERE id=:id",
                    {"password": password_hash.hash(body.password), "id": user["id"]})
    else:
        # One-time compatibility with legacy accounts from the original demo.
        valid = hmac.compare_digest(stored, body.password)
        if valid:
            execute("UPDATE users SET password=:password WHERE id=:id",
                    {"password": password_hash.hash(body.password), "id": user["id"]})
    if not valid:
        fail(401, "Invalid email or password")
    return {"message": "Login successful", "token": token_for(user), "user": user_view(user)}


@app.get("/api/profile")
def get_profile(user=Depends(jwt_subject)):
    return user_view(user)


@app.put("/api/profile")
def update_profile(body: ProfileBody, user=Depends(jwt_subject)):
    execute("UPDATE users SET name=:name,phone=:phone WHERE id=:id",
            {"name": body.name.strip(), "phone": body.phone.strip(), "id": user["id"]})
    return user_view(rows("SELECT id,name,email,phone,role,availability FROM users WHERE id=:id",
                          {"id": user["id"]})[0])


@app.get("/api/users")
def list_users(_: dict = Depends(require_role("admin"))):
    return rows("SELECT id,name,email,phone,role,created_at FROM users ORDER BY id DESC")


@app.put("/api/users/{user_id}")
def admin_update_user(user_id: int, body: dict[str, Any], admin=Depends(require_role("admin"))):
    found = rows("SELECT id,role FROM users WHERE id=:id", {"id": user_id})
    if not found:
        fail(404, "User not found")
    role = body.get("role", found[0]["role"])
    if role not in ("admin", "rider", "driver"):
        fail(422, "Invalid role")
    if user_id == admin["id"] and role != "admin":
        fail(400, "You cannot remove your own admin role")
    sets = ["name=:name", "email=:email", "phone=:phone", "role=:role"]
    values: dict[str, Any] = {"id": user_id, "name": str(body.get("name", "")).strip(),
                              "email": str(body.get("email", "")).strip().lower(),
                              "phone": str(body.get("phone", "")), "role": role}
    if not values["name"] or not values["email"]:
        fail(422, "Name and email are required")
    if body.get("password"):
        sets.append("password=:password")
        values["password"] = password_hash.hash(str(body["password"]))
    execute(f"UPDATE users SET {','.join(sets)} WHERE id=:id", values)
    return {"message": "User updated successfully"}


@app.delete("/api/users/{user_id}")
def delete_user(user_id: int, admin=Depends(require_role("admin"))):
    if user_id == admin["id"]:
        fail(400, "You cannot delete the logged-in admin")
    count, _ = execute("DELETE FROM users WHERE id=:id", {"id": user_id})
    if not count:
        fail(404, "User not found")
    return {"message": "User deleted successfully"}


@app.get("/api/drivers")
def list_drivers(_: dict = Depends(require_role("admin"))):
    return rows("""SELECT u.id,u.name,u.email,u.phone,
      CASE u.availability WHEN 'available' THEN 'online' WHEN 'on_ride' THEN 'busy'
      ELSE COALESCE(u.availability,'offline') END AS availability,
      v.id AS vehicle_id,v.vehicle_type,v.vehicle_model,v.plate_number
      FROM users u LEFT JOIN vehicles v ON v.driver_id=u.id
      WHERE u.role='driver' ORDER BY u.id DESC""")


@app.post("/api/drivers", status_code=201)
def admin_create_driver(body: RegisterBody, _: dict = Depends(require_role("admin"))):
    if body.role != "driver":
        body = body.model_copy(update={"role": "driver"})
    return register(body)


@app.put("/api/drivers/{driver_id}")
def admin_update_driver(driver_id: int, body: dict[str, Any], _: dict = Depends(require_role("admin"))):
    driver = rows("SELECT id FROM users WHERE id=:id AND role='driver'", {"id": driver_id})
    if not driver:
        fail(404, "Driver not found")
    availability = body.get("availability", "offline")
    availability = {"online": "available", "busy": "on_ride"}.get(availability, availability)
    if availability not in ("offline", "available", "on_ride"):
        fail(422, "Invalid availability")
    values = {"id": driver_id, "name": str(body.get("name", "")).strip(),
              "email": str(body.get("email", "")).strip().lower(), "phone": str(body.get("phone", "")),
              "availability": availability}
    assignments = ["name=:name", "email=:email", "phone=:phone", "availability=:availability"]
    if body.get("password"):
        assignments.append("password=:password")
        values["password"] = password_hash.hash(str(body["password"]))
    execute(f"UPDATE users SET {','.join(assignments)} WHERE id=:id", values)
    return {"message": "Driver updated successfully"}


@app.delete("/api/drivers/{driver_id}")
def delete_driver(driver_id: int, _: dict = Depends(require_role("admin"))):
    count, _ = execute("DELETE FROM users WHERE id=:id AND role='driver'", {"id": driver_id})
    if not count:
        fail(404, "Driver not found")
    return {"message": "Driver deleted successfully"}


@app.put("/api/drivers/{driver_id}/availability")
def update_availability(driver_id: int, body: AvailabilityBody, user=Depends(jwt_subject)):
    if user["role"] not in ("admin", "driver"):
        fail(403, "Driver access required")
    if user["role"] == "driver" and driver_id != user["id"]:
        fail(403, "You can only change your own availability")
    value = {"online": "available", "busy": "on_ride"}.get(body.availability, body.availability)
    if user["role"] == "driver" and value not in ("offline", "available"):
        fail(422, "Drivers can only switch between online and offline")
    if user["role"] == "driver" and rows(
        "SELECT id FROM rides WHERE driver_id=:id AND status IN ('accepted','ongoing') LIMIT 1",
        {"id": driver_id},
    ):
        fail(409, "Finish or cancel your active ride before changing availability")
    if value == "available" and not rows(
        "SELECT id FROM vehicles WHERE driver_id=:id LIMIT 1", {"id": driver_id}
    ):
        fail(409, "Register a vehicle before going online")
    count, _ = execute("UPDATE users SET availability=:availability WHERE id=:id AND role='driver'",
                       {"id": driver_id, "availability": value})
    if not count:
        fail(404, "Driver not found")
    if value == "available":
        offer_pending_rides_to_driver(driver_id)
    return {"message": "Availability updated", "availability": body.availability}


@app.get("/api/my-vehicle")
def my_vehicle(driver=Depends(require_role("driver"))):
    found = rows("SELECT id,driver_id,vehicle_type,vehicle_model,plate_number FROM vehicles WHERE driver_id=:id",
                 {"id": driver["id"]})
    return found[0] if found else None


@app.post("/api/my-vehicle", status_code=201)
def set_my_vehicle(body: VehicleBody, driver=Depends(require_role("driver"))):
    existing = rows("SELECT id FROM vehicles WHERE driver_id=:id", {"id": driver["id"]})
    values = {"driver": driver["id"], "type": body.vehicle_type.strip(),
              "model": body.vehicle_model.strip(), "plate": body.plate_number.strip().upper()}
    if existing:
        execute("UPDATE vehicles SET vehicle_type=:type,vehicle_model=:model,plate_number=:plate WHERE id=:id",
                {**values, "id": existing[0]["id"]})
        return {"id": existing[0]["id"], "message": "Vehicle updated"}
    _, vehicle_id = execute("INSERT INTO vehicles(driver_id,vehicle_type,vehicle_model,plate_number) "
                            "VALUES(:driver,:type,:model,:plate)", values)
    return {"id": vehicle_id, "message": "Vehicle registered"}


@app.get("/api/vehicles")
def list_vehicles(_: dict = Depends(require_role("admin"))):
    return rows("SELECT v.id,v.driver_id,u.name AS driver_name,v.vehicle_type,v.vehicle_model,v.plate_number "
                "FROM vehicles v LEFT JOIN users u ON u.id=v.driver_id ORDER BY v.id DESC")


@app.post("/api/vehicles", status_code=201)
def create_vehicle(body: dict[str, Any], _: dict = Depends(require_role("admin"))):
    try:
        model = VehicleBody.model_validate(body)
        driver_id = int(body["driver_id"])
    except (KeyError, ValueError):
        fail(422, "Driver, vehicle type, model and plate number are required")
    if not rows("SELECT id FROM users WHERE id=:id AND role='driver'", {"id": driver_id}):
        fail(400, "Selected driver does not exist")
    _, vehicle_id = execute("INSERT INTO vehicles(driver_id,vehicle_type,vehicle_model,plate_number) "
                            "VALUES(:driver,:type,:model,:plate)",
                            {"driver": driver_id, "type": model.vehicle_type,
                             "model": model.vehicle_model, "plate": model.plate_number.upper()})
    return {"id": vehicle_id, "message": "Vehicle added successfully"}


@app.put("/api/vehicles/{vehicle_id}")
def update_vehicle(vehicle_id: int, body: dict[str, Any], _: dict = Depends(require_role("admin"))):
    try:
        model = VehicleBody.model_validate(body)
        driver_id = int(body["driver_id"])
    except (KeyError, ValueError):
        fail(422, "Driver, vehicle type, model and plate number are required")
    if not rows("SELECT id FROM users WHERE id=:id AND role='driver'", {"id": driver_id}):
        fail(400, "Selected driver does not exist")
    count, _ = execute("UPDATE vehicles SET driver_id=:driver,vehicle_type=:type,vehicle_model=:model,"
                       "plate_number=:plate WHERE id=:id",
                       {"id": vehicle_id, "driver": driver_id, "type": model.vehicle_type,
                        "model": model.vehicle_model, "plate": model.plate_number.upper()})
    if not count:
        fail(404, "Vehicle not found")
    return {"message": "Vehicle updated successfully"}


@app.delete("/api/vehicles/{vehicle_id}")
def delete_vehicle(vehicle_id: int, _: dict = Depends(require_role("admin"))):
    count, _ = execute("DELETE FROM vehicles WHERE id=:id", {"id": vehicle_id})
    if not count:
        fail(404, "Vehicle not found")
    return {"message": "Vehicle deleted successfully"}


@app.post("/api/fare/estimate")
async def estimate_fare(body: FareBody, _: dict = Depends(require_role("rider"))):
    ride_type = normalize_ride_type(body.ride_type)
    if ride_type == "Direct Ride":
        return {"ride_type": ride_type, "estimated_fare": None, "direct": True,
                "message": "Final fare will be set when the ride is completed."}
    distance = body.distance_km
    if distance is None:
        pickup = ((body.pickup_lat, body.pickup_lng)
                  if body.pickup_lat is not None and body.pickup_lng is not None
                  else await geocode(body.pickup or ""))
        destination = ((body.destination_lat, body.destination_lng)
                       if body.destination_lat is not None and body.destination_lng is not None
                       else await geocode(body.destination or ""))
        if pickup is None or destination is None:
            fail(422, "We could not locate both places. Add coordinates or try a clearer address.")
        # Road distance is estimated from straight-line distance for this demo; production should use routing.
        distance = round(distance_between(*pickup, *destination) * 1.25, 2)
    if not math.isfinite(distance) or distance < 0:
        fail(422, "A valid distance is required")
    return {"ride_type": ride_type, "distance_km": distance,
            "estimated_fare": fare_for(ride_type, distance)}


@app.post("/api/rides", status_code=201)
async def request_ride(body: RideBody, rider=Depends(require_role("rider"))):
    ride_type = normalize_ride_type(body.ride_type)
    direct = ride_type == "Direct Ride"
    if not direct and not body.destination:
        fail(422, "Destination is required")
    distance = body.distance_km
    pickup = ((body.pickup_lat, body.pickup_lng)
              if body.pickup_lat is not None and body.pickup_lng is not None
              else await geocode(body.pickup_location))
    destination = ((body.destination_lat, body.destination_lng)
                   if body.destination_lat is not None and body.destination_lng is not None
                   else await geocode(body.destination or "")) if not direct else None
    if not direct and distance is None:
        if pickup is None or destination is None:
            fail(422, "Could not estimate the route. Set a distance or use locatable pickup and destination.")
        distance = round(distance_between(*pickup, *destination) * 1.25, 2)
    fare = None if direct else fare_for(ride_type, distance or 0)
    params = {
        "rider": rider["id"], "pickup": body.pickup_location.strip(),
        "destination": (body.destination or "").strip(), "type": ride_type,
        "distance": distance, "pickup_lat": pickup[0] if pickup else None,
        "pickup_lng": pickup[1] if pickup else None,
        "dest_lat": destination[0] if destination else None,
        "dest_lng": destination[1] if destination else None, "fare": fare,
    }
    _, ride_id = execute("INSERT INTO rides(rider_id,pickup_location,destination,ride_type,distance_km,"
                         "pickup_lat,pickup_lng,destination_lat,destination_lng,estimated_fare,fare,status) "
                         "VALUES(:rider,:pickup,:destination,:type,:distance,:pickup_lat,:pickup_lng,"
                         ":dest_lat,:dest_lng,:fare,:fare,'requested')", params)
    event(ride_id, rider["id"], "requested")
    offer_ride_to_available_drivers(ride_id, ride_type)
    return {"message": "Ride requested successfully", "ride_id": ride_id,
            "ride": {"id": ride_id, "status": "requested", "fare": fare},
            "estimated_fare": fare, "direct": direct}


@app.get("/api/my-rides")
def my_rides(rider=Depends(require_role("rider"))):
    items = rows("SELECT r.id,r.driver_id,r.pickup_location,r.destination,r.ride_type,r.distance_km,r.fare,"
                 "r.estimated_fare,r.status,r.created_at,d.name AS driver_name,"
                 "EXISTS(SELECT 1 FROM payments p WHERE p.ride_id=r.id AND p.status='paid') AS paid,"
                 "EXISTS(SELECT 1 FROM ratings rt WHERE rt.ride_id=r.id AND rt.rater_id=:id) AS rated "
                 "FROM rides r LEFT JOIN users d ON d.id=r.driver_id WHERE r.rider_id=:id ORDER BY r.id DESC",
                 {"id": rider["id"]})
    return {"rides": items}


@app.get("/api/rides")
def admin_rides(_: dict = Depends(require_role("admin"))):
    return rows("SELECT r.id,r.rider_id,ru.name AS rider_name,r.driver_id,du.name AS driver_name,"
                "r.pickup_location,r.destination,r.ride_type,r.distance_km,r.pickup_lat,r.pickup_lng,"
                "r.destination_lat,r.destination_lng,r.fare,r.status,r.created_at "
                "FROM rides r LEFT JOIN users ru ON ru.id=r.rider_id LEFT JOIN users du ON du.id=r.driver_id "
                "ORDER BY r.id DESC")


@app.get("/api/driver-rides")
def driver_rides(driver=Depends(require_role("driver"))):
    return rows("SELECT r.id,r.rider_id,r.driver_id,u.name AS rider_name,u.phone AS rider_phone,"
                "r.pickup_location,r.destination,r.ride_type,r.distance_km,r.fare,r.estimated_fare,"
                "r.status,r.created_at FROM rides r JOIN users u ON u.id=r.rider_id "
                "LEFT JOIN ride_offers o ON o.ride_id=r.id AND o.driver_id=:driver "
                "WHERE r.driver_id=:driver OR (r.status='requested' AND r.driver_id IS NULL "
                "AND o.status='offered' AND (r.ride_type='Direct Ride' OR EXISTS "
                "(SELECT 1 FROM vehicles v WHERE v.driver_id=:driver AND "
                "LOWER(REPLACE(REPLACE(TRIM(v.vehicle_type),' ',''),'-',''))="
                "LOWER(REPLACE(REPLACE(TRIM(r.ride_type),' ',''),'-',''))))) "
                "ORDER BY r.id DESC", {"driver": driver["id"]})


@app.put("/api/driver-rides/{ride_id}")
def driver_ride_action(ride_id: int, body: DriverRideAction, driver=Depends(require_role("driver"))):
    found = rows("SELECT id,rider_id,driver_id,ride_type,status FROM rides WHERE id=:id", {"id": ride_id})
    if not found:
        fail(404, "Ride not found")
    ride = found[0]
    if body.status == "rejected":
        if ride["status"] != "requested" or ride["driver_id"] is not None:
            fail(409, "This ride is no longer available")
        set_ride_offer(ride_id, driver["id"], "rejected")
        return {"message": "Ride declined"}
    if body.status == "accepted":
        if driver.get("availability") != "available":
            fail(409, "Go online before accepting a ride")
        compatible_vehicles = rows("SELECT vehicle_type FROM vehicles WHERE driver_id=:driver",
                                    {"driver": driver["id"]})
        if not any(vehicle_matches_ride(ride["ride_type"], vehicle["vehicle_type"])
                   for vehicle in compatible_vehicles):
            fail(409, "Register a vehicle that matches this ride type before accepting")
        vehicle_filter = ""
        claim_params = {"driver": driver["id"], "ride": ride_id}
        if ride["ride_type"] != "Direct Ride":
            vehicle_filter = " AND LOWER(REPLACE(REPLACE(TRIM(v.vehicle_type),' ',''),'-',''))=:vehicle_type"
            claim_params["vehicle_type"] = normalize_vehicle_type(ride["ride_type"])
        # Reserve the driver and claim the ride in one transaction so parallel
        # accept requests cannot assign two rides to the same driver.
        with engine.begin() as conn:
            available = conn.execute(
                text("UPDATE users SET availability='on_ride' "
                     "WHERE id=:driver AND role='driver' AND availability='available' "
                     "AND EXISTS (SELECT 1 FROM vehicles v WHERE v.driver_id=users.id"
                     f"{vehicle_filter})"),
                claim_params,
            )
            if not available.rowcount:
                fail(409, "You are no longer available to accept a ride")
            claimed = conn.execute(
                text("UPDATE rides SET driver_id=:driver,status='accepted' "
                     "WHERE id=:ride AND status='requested' AND driver_id IS NULL"),
                claim_params,
            )
            if not claimed.rowcount:
                fail(409, "This ride has already been accepted")
        set_ride_offer(ride_id, driver["id"], "accepted")
    else:
        if ride["driver_id"] != driver["id"]:
            fail(403, "This ride is not assigned to you")
        allowed_previous = {"ongoing": ("accepted",), "completed": ("ongoing",),
                            "cancelled": ("accepted", "ongoing")}
        if body.status not in allowed_previous or ride["status"] not in allowed_previous[body.status]:
            fail(409, f"Cannot change ride from {ride['status']} to {body.status}")
        if body.status == "completed" and ride["ride_type"] == "Direct Ride" and body.final_fare is None:
            fail(422, "Final fare is required to complete a Direct Ride")
        if body.status == "completed" and ride["ride_type"] != "Direct Ride" and body.final_fare is not None:
            fail(422, "Fare for this ride is calculated when it is requested")
        if body.status == "completed" and ride["ride_type"] == "Direct Ride":
            execute("UPDATE rides SET status=:status,fare=:fare WHERE id=:ride AND driver_id=:driver",
                    {"status": body.status, "fare": body.final_fare, "ride": ride_id, "driver": driver["id"]})
        else:
            execute("UPDATE rides SET status=:status WHERE id=:ride AND driver_id=:driver",
                    {"status": body.status, "ride": ride_id, "driver": driver["id"]})
        if body.status in ("completed", "cancelled"):
            execute("UPDATE users SET availability='available' WHERE id=:id AND availability='on_ride'",
                    {"id": driver["id"]})
    event(ride_id, driver["id"], body.status)
    updated = rows("SELECT status,fare FROM rides WHERE id=:id", {"id": ride_id})[0]
    notify(ride["rider_id"], "Ride updated", f"Ride #{ride_id} is now {updated['status']}.", "ride")
    return {"message": "Ride updated successfully", **updated}


@app.put("/api/rides/{ride_id}/cancel")
def cancel_ride(ride_id: int, rider=Depends(require_role("rider"))):
    count, _ = execute("UPDATE rides SET status='cancelled' WHERE id=:id AND rider_id=:rider "
                       "AND status='requested' AND driver_id IS NULL",
                       {"id": ride_id, "rider": rider["id"]})
    if not count:
        fail(409, "Only an unassigned requested ride can be cancelled")
    event(ride_id, rider["id"], "cancelled")
    return {"message": "Ride cancelled"}


@app.post("/api/driver-location")
def update_driver_location(body: LocationBody, ride_id: int = Query(gt=0),
                           driver=Depends(require_role("driver"))):
    if driver.get("availability") not in ("on_ride", "busy"):
        fail(409, "Location sharing is available during an active ride")
    if not rows("SELECT id FROM rides WHERE id=:ride AND driver_id=:driver "
                "AND status='ongoing'", {"ride": ride_id, "driver": driver["id"]}):
        fail(403, "The active ride does not belong to you")
    save_driver_location(driver["id"], ride_id, body)
    return {"message": "Location updated"}


@app.get("/api/rides/{ride_id}/track")
def track_ride(ride_id: int, user=Depends(jwt_subject)):
    found = rows(
        "SELECT id,rider_id,driver_id,status,pickup_location,destination,"
        "pickup_lat,pickup_lng,destination_lat,destination_lng "
        "FROM rides WHERE id=:id",
        {"id": ride_id},
    )
    if not found:
        fail(404, "Ride not found")
    ride = found[0]
    if user["role"] == "rider" and user["id"] != ride["rider_id"]:
        fail(403, "You cannot track this ride")
    if user["role"] == "driver" and user["id"] != ride["driver_id"]:
        fail(403, "You cannot track this ride")
    if user["role"] not in ("rider", "driver", "admin"):
        fail(403, "Access denied")
    location = rows("SELECT latitude,longitude,heading,updated_at FROM driver_locations "
                    "WHERE driver_id=:driver AND ride_id=:ride",
                    {"driver": ride["driver_id"], "ride": ride_id}) if ride["driver_id"] else []
    return {
        "ride_id": ride_id,
        "status": ride["status"],
        "location": location[0] if location else None,
        "pickup": {
            "label": ride["pickup_location"],
            "latitude": ride["pickup_lat"],
            "longitude": ride["pickup_lng"],
        },
        "destination": {
            "label": ride["destination"],
            "latitude": ride["destination_lat"],
            "longitude": ride["destination_lng"],
        },
    }


@app.get("/api/notifications")
def admin_notifications(_: dict = Depends(require_role("admin"))):
    return rows("SELECT id,user_id,title,message,type,is_read,created_at FROM notifications ORDER BY id DESC")


@app.get("/api/my-notifications")
def my_notifications(user=Depends(jwt_subject)):
    return {"notifications": rows("SELECT id,title,message,type,is_read,created_at FROM notifications "
                                   "WHERE user_id=:id ORDER BY id DESC LIMIT 100", {"id": user["id"]})}


@app.put("/api/my-notifications/{notification_id}/read")
def mark_notification_read(notification_id: int, user=Depends(jwt_subject)):
    count, _ = execute("UPDATE notifications SET is_read=1 WHERE id=:id AND user_id=:user",
                       {"id": notification_id, "user": user["id"]})
    if not count:
        fail(404, "Notification not found")
    return {"message": "Notification marked as read"}


@app.get("/api/payments")
def admin_payments(_: dict = Depends(require_role("admin"))):
    return rows("SELECT p.id,p.ride_id,u.name AS rider_name,p.amount,p.payment_method,p.status,p.created_at "
                "FROM payments p JOIN rides r ON r.id=p.ride_id JOIN users u ON u.id=r.rider_id ORDER BY p.id DESC")


@app.post("/api/payments", status_code=201)
def create_payment(body: PaymentBody, rider=Depends(require_role("rider"))):
    ride_rows = rows("SELECT id,fare,status FROM rides WHERE id=:ride AND rider_id=:rider",
                     {"ride": body.ride_id, "rider": rider["id"]})
    if not ride_rows:
        fail(404, "Ride not found")
    ride = ride_rows[0]
    if ride["status"] != "completed" or ride["fare"] is None:
        fail(409, "Payment is available after the final fare is recorded")
    if body.payment_method == "card":
        fail(501, "Card payments need a payment-provider account and are not configured")
    if rows("SELECT id FROM payments WHERE ride_id=:ride", {"ride": body.ride_id}):
        fail(409, "This ride has already been paid")
    try:
        _, payment_id = execute("INSERT INTO payments(ride_id,amount,payment_method,status) "
                                "VALUES(:ride,:amount,'cash','paid')",
                                {"ride": body.ride_id, "amount": ride["fare"]})
    except IntegrityError:
        fail(409, "This ride has already been paid")
    return {"message": "Cash payment recorded", "payment_id": payment_id, "amount": ride["fare"]}


@app.get("/api/rides/{ride_id}/receipt")
def ride_receipt(ride_id: int, rider=Depends(require_role("rider"))):
    receipt = rows(
        "SELECT p.id AS receipt_id,p.ride_id,p.amount,p.payment_method,p.created_at AS paid_at,"
        "r.pickup_location,r.destination,r.ride_type,r.distance_km,u.name AS rider_name,"
        "d.name AS driver_name FROM payments p JOIN rides r ON r.id=p.ride_id "
        "JOIN users u ON u.id=r.rider_id LEFT JOIN users d ON d.id=r.driver_id "
        "WHERE p.ride_id=:ride AND r.rider_id=:rider AND p.status='paid'",
        {"ride": ride_id, "rider": rider["id"]},
    )
    if not receipt:
        fail(404, "Paid receipt not found")
    return receipt[0]


@app.post("/api/ratings", status_code=201)
def rate_ride(body: RatingBody, user=Depends(jwt_subject)):
    found = rows("SELECT id,rider_id,driver_id,status FROM rides WHERE id=:id", {"id": body.ride_id})
    if not found or found[0]["status"] != "completed":
        fail(409, "Only completed rides can be rated")
    ride = found[0]
    if user["id"] == ride["rider_id"] and ride["driver_id"]:
        ratee = ride["driver_id"]
    elif user["id"] == ride["driver_id"]:
        ratee = ride["rider_id"]
    else:
        fail(403, "You were not part of this ride")
    try:
        _, rating_id = execute("INSERT INTO ratings(ride_id,rater_id,ratee_id,score,comment) "
                               "VALUES(:ride,:rater,:ratee,:score,:comment)",
                               {"ride": body.ride_id, "rater": user["id"], "ratee": ratee,
                                "score": body.score, "comment": body.comment})
    except IntegrityError:
        fail(409, "You have already rated this ride")
    return {"id": rating_id, "message": "Rating saved"}


@app.get("/api/ratings")
def admin_ratings(_: dict = Depends(require_role("admin"))):
    return rows("SELECT r.id,r.ride_id,r.rater_id,a.name AS rater_name,r.ratee_id,b.name AS ratee_name,"
                "r.score,r.comment,r.created_at FROM ratings r LEFT JOIN users a ON a.id=r.rater_id "
                "LEFT JOIN users b ON b.id=r.ratee_id ORDER BY r.id DESC")


@app.post("/api/push-tokens", status_code=201)
def register_push_token(token: str = Query(min_length=20, max_length=512),
                        platform: str = Query(default="android"), user=Depends(jwt_subject)):
    if platform not in ("android", "ios"):
        fail(422, "Platform must be android or ios")
    statement = (
        "INSERT INTO push_tokens(user_id,token,platform) VALUES(:user,:token,:platform) "
        "ON CONFLICT(token) DO UPDATE SET user_id=excluded.user_id,platform=excluded.platform"
        if engine.dialect.name == "sqlite"
        else "INSERT INTO push_tokens(user_id,token,platform) VALUES(:user,:token,:platform) "
        "ON DUPLICATE KEY UPDATE user_id=VALUES(user_id),platform=VALUES(platform)"
    )
    execute(statement, {"user": user["id"], "token": token, "platform": platform})
    return {"message": "Push token registered"}


@app.delete("/api/push-tokens", status_code=204)
def delete_my_push_tokens(user=Depends(jwt_subject)):
    execute("DELETE FROM push_tokens WHERE user_id=:user", {"user": user["id"]})


@app.exception_handler(HTTPException)
async def json_error(_, exc: HTTPException):
    # The Flutter client and existing admin panel both read an `error` property.
    from fastapi.responses import JSONResponse
    return JSONResponse(status_code=exc.status_code,
                        content={"error": exc.detail}, headers=exc.headers)


@app.exception_handler(RequestValidationError)
async def validation_error(_, exc: RequestValidationError):
    from fastapi.responses import JSONResponse
    error = exc.errors()[0] if exc.errors() else {}
    field = ".".join(str(part) for part in error.get("loc", ())[1:])
    message = error.get("msg", "Invalid request")
    detail = f"{field}: {message}" if field else message
    return JSONResponse(status_code=422, content={"error": detail})

