from __future__ import annotations

import hmac
import logging
import math
import os
import re
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Literal

import httpx
import jwt
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field, field_validator
from fastapi.exceptions import RequestValidationError
from pwdlib import PasswordHash
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.engine import Engine

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("rideapp")

# Ensure .env is resolved from backend directory as well as current working directory
_backend_env = Path(__file__).resolve().parent.parent / ".env"
if _backend_env.exists():
    load_dotenv(dotenv_path=_backend_env)
load_dotenv()

APP_ENV = os.getenv("APP_ENV", "development").strip().lower()
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "mysql+pymysql://root:sinoeun2026@127.0.0.1:3306/ride_app?charset=utf8mb4",
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
MAP_REVERSE_PROXY_URL = os.getenv(
    "MAP_REVERSE_PROXY_URL", "http://127.0.0.1:3001/reverse"
).strip()
FIREBASE_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID", "").strip()
BAKONG_ACCOUNT_ID = os.getenv("BAKONG_ACCOUNT_ID", "").strip()
BAKONG_MERCHANT_NAME = os.getenv("BAKONG_MERCHANT_NAME", "").strip()
BAKONG_MERCHANT_CITY = os.getenv("BAKONG_MERCHANT_CITY", "").strip()
BAKONG_PHONE_NUMBER = os.getenv("BAKONG_PHONE_NUMBER", "").strip()
BAKONG_API_TOKEN = os.getenv("BAKONG_API_TOKEN", "").strip()
BAKONG_API_BASE_URL = os.getenv(
    "BAKONG_API_BASE_URL", "https://api-bakong.nbc.gov.kh/v1"
).strip().rstrip("/")
BAKONG_QR_EXPIRY_MINUTES = int(os.getenv("BAKONG_QR_EXPIRY_MINUTES", "5"))
RIDE_MATCH_RADIUS_KM = float(os.getenv("RIDE_MATCH_RADIUS_KM", "10"))
DRIVER_LOCATION_MAX_AGE_MINUTES = 5
engine: Engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_recycle=1800)
password_hash = PasswordHash.recommended()
_firebase_app = None

RIDE_ALIASES = {
    "car": "Car",
    "standard": "Car",
    "comfort": "Comfort",
    "premium": "Premium",
    "economy": "Car",
    "standard xl": "Comfort",
    "tuktuk": "Tuk Tuk",
    "tuk tuk": "Tuk Tuk",
    "rickshaw": "Tuk Tuk",
    "passapp": "Tuk Tuk",
    "motorbike": "Motorbike",
    "rormork": "Motorbike",
    "direct": "Direct Ride",
    "direct ride": "Direct Ride",
}
FARE_RULES = {
    "Car": (1.50, 0.75, 2.50),
    "Comfort": (2.00, 0.95, 3.50),
    "Premium": (3.00, 1.40, 5.00),
    "Tuk Tuk": (1.00, 0.55, 2.00),
    "Motorbike": (0.75, 0.40, 1.50),
    "Direct Ride": (1.50, 0.75, 2.50),
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
        """CREATE TABLE IF NOT EXISTS payment_intents (
          id INT AUTO_INCREMENT PRIMARY KEY, ride_id INT NOT NULL, rider_id INT NOT NULL,
          provider VARCHAR(30) NOT NULL DEFAULT 'bakong', amount DECIMAL(10,2) NOT NULL,
          currency CHAR(3) NOT NULL DEFAULT 'USD', qr_payload TEXT NOT NULL,
          qr_md5 CHAR(32) NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'pending',
          expires_at DATETIME NOT NULL, provider_transaction_hash VARCHAR(128) NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE KEY uq_payment_qr_md5 (qr_md5), UNIQUE KEY uq_payment_intent_ride (ride_id),
          CONSTRAINT fk_payment_intent_ride FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
          CONSTRAINT fk_payment_intent_rider FOREIGN KEY (rider_id) REFERENCES users(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""",
    ]
    with engine.begin() as conn:
        for statement in statements:
            conn.execute(text(statement))
        user_columns = {
            row["COLUMN_NAME"]
            for row in conn.execute(
                text("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS "
                     "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users'")
            ).mappings()
        }
        if "is_deleted" not in user_columns:
            conn.execute(text(
                "ALTER TABLE users ADD COLUMN is_deleted TINYINT(1) NOT NULL DEFAULT 0"
            ))
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
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1|0\.0\.0\.0|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[0-1])\.\d+\.\d+|\[::1\])(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class RegisterBody(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    email: EmailStr
    phone: str = Field(default="", max_length=30)
    password: str = Field(min_length=8, max_length=128)
    role: str = "rider"

    @field_validator("role", mode="before")
    @classmethod
    def normalize_role(cls, v: Any) -> str:
        s = str(v or "rider").strip().lower()
        if s in ("driver", "admin"):
            return s
        return "rider"


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
    status: Literal["accepted", "rejected", "arrived", "ongoing", "completed", "cancelled"]
    final_fare: float | None = Field(default=None, ge=0, le=100000)
    final_distance_km: float | None = Field(default=None, ge=0, le=500)


class PaymentBody(BaseModel):
    ride_id: int = Field(gt=0)
    payment_method: Literal["cash", "card"] = "cash"


class KhqrPaymentBody(BaseModel):
    ride_id: int = Field(gt=0)


def database_datetime(value: datetime | str) -> datetime:
    return value if isinstance(value, datetime) else datetime.fromisoformat(value)


def db_now() -> datetime:
    """Current timestamp aligned with database engine timezone (MySQL local datetime vs SQLite UTC)."""
    if engine.dialect.name == "mysql":
        return datetime.now()
    return datetime.now(timezone.utc).replace(tzinfo=None)


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
    if not math.isfinite(RIDE_MATCH_RADIUS_KM) or RIDE_MATCH_RADIUS_KM <= 0:
        raise RuntimeError("RIDE_MATCH_RADIUS_KM must be a positive finite number")
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
        found = rows("SELECT id,name,email,phone,role,availability FROM users "
                     "WHERE id=:id AND is_deleted=0", {"id": user_id})
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
    r_norm = normalize_vehicle_type(ride_type)
    v_norm = normalize_vehicle_type(vehicle_type)
    if r_norm == v_norm:
        return True
    if v_norm == "car" and r_norm in ("car", "standard", "comfort"):
        return True
    return False


def distance_between(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6371.0088
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lam = math.radians(lon2 - lon1)
    a = math.sin(delta_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lam / 2) ** 2
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


PHNOM_PENH_LANDMARKS = [
    {"label": "Aeon Mall 1 (Samdach Sothearos Blvd)", "latitude": 11.5475, "longitude": 104.9351, "category": "mall"},
    {"label": "Aeon Mall 2 Sen Sok", "latitude": 11.5976, "longitude": 104.8860, "category": "mall"},
    {"label": "Aeon Mall 3 Mean Chey", "latitude": 11.4883, "longitude": 104.9189, "category": "mall"},
    {"label": "Independence Monument", "latitude": 11.5564, "longitude": 104.9282, "category": "monument"},
    {"label": "Royal Palace Phnom Penh", "latitude": 11.5638, "longitude": 104.9317, "category": "palace"},
    {"label": "Central Market (Phsar Thmey)", "latitude": 11.5696, "longitude": 104.9213, "category": "market"},
    {"label": "Wat Phnom Historical Park", "latitude": 11.5762, "longitude": 104.9230, "category": "temple"},
    {"label": "Russian Market (Toul Tom Poung)", "latitude": 11.5408, "longitude": 104.9142, "category": "market"},
    {"label": "Phnom Penh International Airport (PNH)", "latitude": 11.5466, "longitude": 104.8441, "category": "airport"},
    {"label": "Tuol Sleng Genocide Museum (S-21)", "latitude": 11.5494, "longitude": 104.9174, "category": "museum"},
    {"label": "Phnom Penh Railway Station", "latitude": 11.5739, "longitude": 104.9169, "category": "station"},
    {"label": "Riverside (Sisowath Quay)", "latitude": 11.5682, "longitude": 104.9312, "category": "park"},
    {"label": "Olympic Stadium Phnom Penh", "latitude": 11.5578, "longitude": 104.9126, "category": "stadium"},
    {"label": "Calmette Hospital", "latitude": 11.5833, "longitude": 104.9167, "category": "hospital"},
    {"label": "NagaWorld Resort & Casino", "latitude": 11.5528, "longitude": 104.9392, "category": "hotel"},
    {"label": "Koh Pich (Diamond Island)", "latitude": 11.5478, "longitude": 104.9431, "category": "area"},
    {"label": "BKK1 (Boeung Keng Kang 1)", "latitude": 11.5510, "longitude": 104.9248, "category": "area"},
    {"label": "Toul Kork (Phnom Penh)", "latitude": 11.5802, "longitude": 104.8972, "category": "area"},
    {"label": "Royal University of Phnom Penh (RUPP)", "latitude": 11.5689, "longitude": 104.8906, "category": "university"},
    {"label": "Institute of Technology of Cambodia (ITC)", "latitude": 11.5714, "longitude": 104.8986, "category": "university"},
    {"label": "Choeung Ek Genocidal Center", "latitude": 11.4844, "longitude": 104.9020, "category": "museum"},
]


async def geocode(place: str) -> tuple[float, float] | None:
    # Coordinates and GPS strings work offline; named places use OpenStreetMap's public geocoder.
    match = re.search(r"(-?\d{1,3}(?:\.\d+)?)\s*[, ]\s*(-?\d{1,3}(?:\.\d+)?)", place)
    if match:
        lat, lng = float(match.group(1)), float(match.group(2))
        if -90 <= lat <= 90 and -180 <= lng <= 180:
            return lat, lng
    clean = place.strip().lower()
    if not clean:
        return None
    # Check known Phnom Penh landmarks
    for item in PHNOM_PENH_LANDMARKS:
        label = item["label"].lower()
        if clean in label or label in clean or any(w in label for w in clean.split() if len(w) > 3):
            return item["latitude"], item["longitude"]
    if len(clean) < 3 or "replace-with-your-contact" in GEOCODER_USER_AGENT:
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


_ROUTE_CACHE: dict[tuple[float, float, float, float], tuple[float, int, list[dict[str, float]]]] = {}


async def fetch_driving_route(from_lat: float, from_lng: float, to_lat: float, to_lng: float) -> tuple[float, int, list[dict[str, float]]]:
    """
    Fetches real road-following driving polyline, road distance, and travel duration from OSRM.
    Returns: (distance_km, duration_minutes, route_points)
    where route_points is a list of {'latitude': float, 'longitude': float}.
    """
    cache_key = (round(from_lat, 4), round(from_lng, 4), round(to_lat, 4), round(to_lng, 4))
    if cache_key in _ROUTE_CACHE:
        return _ROUTE_CACHE[cache_key]

    straight_km = distance_between(from_lat, from_lng, to_lat, to_lng)
    if straight_km < 0.01:
        res = 0.1, 1, [{"latitude": from_lat, "longitude": from_lng}, {"latitude": to_lat, "longitude": to_lng}]
        _ROUTE_CACHE[cache_key] = res
        return res

    if engine.dialect.name == "sqlite":
        fallback_km = round(straight_km * 1.25, 2)
        fallback_dur = max(1, round(fallback_km / 25.0 * 60.0))
        steps = 6
        points = []
        for i in range(steps + 1):
            t = i / steps
            lat = from_lat + (to_lat - from_lat) * t
            lng = from_lng + (to_lng - from_lng) * t
            offset = math.sin(t * math.pi) * 0.0008
            points.append({"latitude": round(lat + offset, 6), "longitude": round(lng - offset, 6)})
        res = fallback_km, fallback_dur, points
        _ROUTE_CACHE[cache_key] = res
        return res

    osrm_url = (
        f"https://router.project-osrm.org/route/v1/driving/"
        f"{from_lng:.6f},{from_lat:.6f};{to_lng:.6f},{to_lat:.6f}"
        "?overview=full&geometries=geojson"
    )
    try:
        async with httpx.AsyncClient(timeout=4.0, headers={"User-Agent": GEOCODER_USER_AGENT}) as client:
            resp = await client.get(osrm_url)
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == "Ok" and data.get("routes"):
                    primary = data["routes"][0]
                    dist_km = round(primary.get("distance", straight_km * 1000.0) / 1000.0, 2)
                    dur_min = max(1, round(primary.get("duration", (dist_km / 25.0) * 3600.0) / 60.0))
                    coords = primary.get("geometry", {}).get("coordinates", [])
                    points = [
                        {"latitude": round(pt[1], 6), "longitude": round(pt[0], 6)}
                        for pt in coords
                    ]
                    if points:
                        if len(_ROUTE_CACHE) > 500:
                            _ROUTE_CACHE.clear()
                        res = dist_km, dur_min, points
                        _ROUTE_CACHE[cache_key] = res
                        return res
    except Exception as exc:
        logger.warning("OSRM driving route lookup failed: %s", exc)

    fallback_km = round(straight_km * 1.25, 2)
    fallback_dur = max(1, round(fallback_km / 25.0 * 60.0))
    steps = 6
    points = []
    for i in range(steps + 1):
        t = i / steps
        lat = from_lat + (to_lat - from_lat) * t
        lng = from_lng + (to_lng - from_lng) * t
        offset = math.sin(t * math.pi) * 0.0008
        points.append({"latitude": round(lat + offset, 6), "longitude": round(lng - offset, 6)})
    res = fallback_km, fallback_dur, points
    _ROUTE_CACHE[cache_key] = res
    return res


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


def driver_is_near_ride(ride: dict[str, Any], driver_id: int) -> bool:
    pickup_lat = ride.get("pickup_lat")
    pickup_lng = ride.get("pickup_lng")
    if pickup_lat is None or pickup_lng is None:
        # Keep the demo usable for manually entered rides that could not be geocoded.
        return True
    locations = rows(
        "SELECT latitude,longitude,updated_at FROM driver_locations "
        "WHERE driver_id=:driver AND ride_id IS NULL",
        {"driver": driver_id},
    )
    if not locations:
        return False
    location = locations[0]
    updated_at = database_datetime(location["updated_at"])
    now = db_now()
    if abs((now - updated_at).total_seconds()) > DRIVER_LOCATION_MAX_AGE_MINUTES * 60:
        return False
    return distance_between(
        float(pickup_lat), float(pickup_lng),
        float(location["latitude"]), float(location["longitude"]),
    ) <= RIDE_MATCH_RADIUS_KM


def notify_ride_offer(ride_id: int, driver_id: int) -> None:
    if add_ride_offer(ride_id, driver_id):
        notify(driver_id, "New ride request", f"Ride #{ride_id} is waiting for a driver.", "ride")


def offer_ride_to_available_drivers(ride_id: int, ride_type: str) -> None:
    ride_rows = rows("SELECT pickup_lat,pickup_lng FROM rides WHERE id=:ride", {"ride": ride_id})
    if not ride_rows:
        return
    ride = ride_rows[0]
    candidates = rows(
        "SELECT DISTINCT u.id,v.vehicle_type FROM users u JOIN vehicles v ON v.driver_id=u.id "
        "WHERE u.role='driver' AND u.availability='available' AND u.is_deleted=0"
    )
    for candidate in candidates:
        if (vehicle_matches_ride(ride_type, candidate["vehicle_type"])
                and driver_is_near_ride(ride, candidate["id"])):
            notify_ride_offer(ride_id, candidate["id"])


def offer_pending_rides_to_driver(driver_id: int) -> None:
    vehicle_types = [item["vehicle_type"] for item in rows(
        "SELECT vehicle_type FROM vehicles WHERE driver_id=:driver", {"driver": driver_id}
    )]
    if not vehicle_types:
        return
    pending = rows("SELECT id,ride_type,pickup_lat,pickup_lng FROM rides "
                   "WHERE status='requested' AND driver_id IS NULL")
    for ride in pending:
        if (any(vehicle_matches_ride(ride["ride_type"], vehicle_type)
                for vehicle_type in vehicle_types)
                and driver_is_near_ride(ride, driver_id)):
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
@app.get("/api/health")
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
    found = rows("SELECT id,name,email,phone,password,role,availability FROM users "
                 "WHERE email=:email AND is_deleted=0 LIMIT 1",
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
    return rows("SELECT id,name,email,phone,role,created_at FROM users "
                "WHERE is_deleted=0 ORDER BY id DESC")


@app.put("/api/users/{user_id}")
def admin_update_user(user_id: int, body: dict[str, Any], admin=Depends(require_role("admin"))):
    found = rows("SELECT id,role FROM users WHERE id=:id AND is_deleted=0", {"id": user_id})
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


def remove_account(user_id: int, admin_id: int, expected_role: str | None = None) -> None:
    if user_id == admin_id:
        fail(400, "You cannot delete the logged-in admin")
    role_filter = " AND role=:role" if expected_role else ""
    params: dict[str, Any] = {"id": user_id}
    if expected_role:
        params["role"] = expected_role
    found = rows(f"SELECT id,role FROM users WHERE id=:id AND is_deleted=0{role_filter}", params)
    if not found:
        fail(404, "User not found" if expected_role is None else "Driver not found")

    # Keep ride/payment history valid while removing the account's personal details.
    execute(
        "UPDATE users SET is_deleted=1,name='Deleted user',email=:email,phone='',"
        "password=:password,availability='offline' WHERE id=:id",
        {"id": user_id, "email": f"deleted-user-{user_id}@deleted.invalid",
         "password": password_hash.hash(uuid.uuid4().hex + uuid.uuid4().hex)},
    )
    execute("DELETE FROM push_tokens WHERE user_id=:id", {"id": user_id})
    execute("DELETE FROM notifications WHERE user_id=:id", {"id": user_id})
    execute("DELETE FROM driver_locations WHERE driver_id=:id", {"id": user_id})
    if found[0]["role"] == "driver":
        execute("DELETE FROM vehicles WHERE driver_id=:id", {"id": user_id})


@app.delete("/api/users/{user_id}")
def delete_user(user_id: int, admin=Depends(require_role("admin"))):
    remove_account(user_id, admin["id"])
    return {"message": "User removed; personal details cleared and ride history retained"}


@app.get("/api/drivers")
def list_drivers(_: dict = Depends(require_role("admin"))):
    return rows("""SELECT u.id,u.name,u.email,u.phone,
      CASE u.availability WHEN 'available' THEN 'online' WHEN 'on_ride' THEN 'busy'
      ELSE COALESCE(u.availability,'offline') END AS availability,
      v.id AS vehicle_id,v.vehicle_type,v.vehicle_model,v.plate_number
      FROM users u LEFT JOIN vehicles v ON v.driver_id=u.id
      WHERE u.role='driver' AND u.is_deleted=0 ORDER BY u.id DESC""")


@app.post("/api/drivers", status_code=201)
def admin_create_driver(body: RegisterBody, _: dict = Depends(require_role("admin"))):
    if body.role != "driver":
        body = body.model_copy(update={"role": "driver"})
    return register(body)


@app.put("/api/drivers/{driver_id}")
def admin_update_driver(driver_id: int, body: dict[str, Any], _: dict = Depends(require_role("admin"))):
    driver = rows("SELECT id FROM users WHERE id=:id AND role='driver' AND is_deleted=0", {"id": driver_id})
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
def delete_driver(driver_id: int, admin: dict = Depends(require_role("admin"))):
    remove_account(driver_id, admin["id"], expected_role="driver")
    return {"message": "Driver removed; personal details cleared and ride history retained"}


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


@app.get("/api/places/search")
async def search_places(q: str = ""):
    query = q.strip().lower()
    matches = []
    if not query:
        return {"places": PHNOM_PENH_LANDMARKS[:8]}
    for item in PHNOM_PENH_LANDMARKS:
        if query in item["label"].lower() or query in item.get("category", ""):
            matches.append(item)
    if not matches and len(query) >= 3:
        try:
            async with httpx.AsyncClient(timeout=4, headers={"User-Agent": GEOCODER_USER_AGENT}) as client:
                res = await client.get(
                    "https://nominatim.openstreetmap.org/search",
                    params={"q": f"{q}, Phnom Penh, Cambodia", "format": "jsonv2", "limit": 5},
                )
                if res.status_code == 200:
                    for c in res.json():
                        matches.append({
                            "label": c.get("display_name", q),
                            "latitude": float(c["lat"]),
                            "longitude": float(c["lon"]),
                            "category": "place",
                        })
        except Exception:
            pass
    if not matches:
        words = [w for w in query.split() if len(w) > 2]
        matches = [item for item in PHNOM_PENH_LANDMARKS if any(w in item["label"].lower() for w in words)]
    if not matches:
        matches = PHNOM_PENH_LANDMARKS[:5]
    return {"places": matches}


@app.get("/api/places/reverse")
async def reverse_places(lat: float, lon: float):
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        fail(422, "Invalid coordinates")
    best_item = None
    min_dist = float("inf")
    for item in PHNOM_PENH_LANDMARKS:
        d = distance_between(lat, lon, item["latitude"], item["longitude"])
        if d < min_dist:
            min_dist = d
            best_item = item
    if best_item and min_dist < 0.08:  # within about 80 meters; otherwise resolve the actual address
        return {"label": best_item["label"], "latitude": lat, "longitude": lon}

    result = None
    try:
        async with httpx.AsyncClient(timeout=6.0) as client:
            response = await client.get(
                MAP_REVERSE_PROXY_URL,
                params={"lat": lat, "lon": lon},
            )
            response.raise_for_status()
            result = response.json()
    except (httpx.HTTPError, ValueError):
        # If the local development proxy is unavailable, try the geocoder directly.
        try:
            async with httpx.AsyncClient(
                timeout=6.0, headers={"User-Agent": GEOCODER_USER_AGENT}
            ) as client:
                response = await client.get(
                    "https://nominatim.openstreetmap.org/reverse",
                    params={
                        "format": "jsonv2", "lat": lat, "lon": lon,
                        "zoom": 18, "addressdetails": 1,
                    },
                )
                response.raise_for_status()
                result = response.json()
        except (httpx.HTTPError, ValueError):
            logger.info("Reverse geocoding unavailable for current location")

    if isinstance(result, dict):
        address = result.get("address") or {}
        road = " ".join(
            part for part in (address.get("house_number"), address.get("road")) if part
        )
        area = next((address.get(key) for key in (
            "neighbourhood", "suburb", "quarter", "hamlet", "village"
        ) if address.get(key)), None)
        district = next((address.get(key) for key in (
            "city_district", "county", "district"
        ) if address.get(key)), None)
        city = next((address.get(key) for key in (
            "city", "town", "municipality", "state"
        ) if address.get(key)), None)
        parts = list(dict.fromkeys(part for part in (road, area, district, city) if part))
        label = ", ".join(parts) or result.get("display_name")
        if label:
            return {"label": label, "latitude": lat, "longitude": lon}

    return {
        "label": f"Current location ({lat:.5f}, {lon:.5f})",
        "latitude": lat,
        "longitude": lon,
    }


@app.get("/api/route")
async def get_route(
    pickup_lat: float = Query(...),
    pickup_lng: float = Query(...),
    destination_lat: float = Query(...),
    destination_lng: float = Query(...),
):
    dist_km, dur_min, points = await fetch_driving_route(
        pickup_lat, pickup_lng, destination_lat, destination_lng
    )
    return {
        "distance_km": dist_km,
        "estimated_duration_minutes": dur_min,
        "route_points": points,
    }


@app.post("/api/fare/estimate")
async def estimate_fare(body: FareBody):
    ride_type = normalize_ride_type(body.ride_type)
    distance = body.distance_km
    pickup = ((body.pickup_lat, body.pickup_lng)
              if body.pickup_lat is not None and body.pickup_lng is not None
              else None)
    destination = ((body.destination_lat, body.destination_lng)
                   if body.destination_lat is not None and body.destination_lng is not None
                   else None)
    if pickup is None and body.pickup:
        pickup = await geocode(body.pickup)
    if destination is None and body.destination:
        destination = await geocode(body.destination)

    route_points: list[dict[str, float]] = []
    if pickup and destination:
        road_km, road_dur, pts = await fetch_driving_route(pickup[0], pickup[1], destination[0], destination[1])
        route_points = pts
        if distance is None:
            distance = road_km
            estimated_duration_minutes = road_dur
        else:
            estimated_duration_minutes = max(1, round(distance / 25 * 60))
    else:
        if pickup is None and destination is not None:
            pickup = (11.5564, 104.9282)
        elif destination is None and pickup is not None:
            destination = (11.5696, 104.9213)
        elif pickup is None and destination is None:
            pickup = (11.5564, 104.9282)
            destination = (11.5696, 104.9213)
        if distance is None:
            distance = round(distance_between(*pickup, *destination) * 1.25, 2)
        estimated_duration_minutes = max(1, round(distance / 25 * 60))

    if not math.isfinite(distance) or distance < 0:
        distance = 3.5

    if ride_type == "Direct Ride":
        base_estimate = fare_for("Car", distance)
        return {
            "ride_type": ride_type,
            "distance_km": distance,
            "estimated_duration_minutes": estimated_duration_minutes,
            "estimated_fare": None,
            "direct": True,
            "pickup_lat": pickup[0] if pickup else None,
            "pickup_lng": pickup[1] if pickup else None,
            "destination_lat": destination[0] if destination else None,
            "destination_lng": destination[1] if destination else None,
            "route_points": route_points,
            "message": f"Direct Ride: Metered trip. Final fare calculated upon completion (~{base_estimate:.2f} USD).",
        }

    type_fares = {}
    for r_type in ["Car", "Comfort", "Premium", "Tuk Tuk", "Motorbike"]:
        f_val = fare_for(r_type, distance)
        type_fares[r_type] = {
            "usd": f_val,
            "khr": int(round(f_val * 4100 / 100) * 100),
        }

    current_fare = fare_for(ride_type, distance)
    fare_khr = int(round(current_fare * 4100 / 100) * 100)
    base, per_km, minimum = FARE_RULES.get(ride_type, (1.50, 0.75, 2.50))

    return {
        "ride_type": ride_type,
        "distance_km": distance,
        "estimated_duration_minutes": estimated_duration_minutes,
        "pickup_lat": pickup[0] if pickup else None,
        "pickup_lng": pickup[1] if pickup else None,
        "destination_lat": destination[0] if destination else None,
        "destination_lng": destination[1] if destination else None,
        "route_points": route_points,
        "estimated_fare": current_fare,
        "estimated_fare_khr": fare_khr,
        "type_fares": type_fares,
        "breakdown": {
            "base_fare": base,
            "per_km_rate": per_km,
            "minimum_fare": minimum,
            "distance_charge": round(distance * per_km, 2),
            "currency": "USD",
            "khr_exchange_rate": 4100,
        },
    }

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


@app.put("/api/rides/{ride_id}/status")
def admin_set_ride_status(ride_id: int, body: dict[str, Any], _: dict = Depends(require_role("admin"))):
    new_status = body.get("status")
    if new_status not in ("requested", "accepted", "arrived", "ongoing", "completed", "cancelled"):
        fail(422, f"Invalid status: {new_status}")
    found = rows("SELECT id, status, driver_id FROM rides WHERE id=:id", {"id": ride_id})
    if not found:
        fail(404, "Ride not found")
    driver_id = body.get("driver_id", found[0]["driver_id"])
    execute("UPDATE rides SET status=:status, driver_id=:driver WHERE id=:id",
            {"status": new_status, "driver": driver_id, "id": ride_id})
    if new_status in ("completed", "cancelled") and driver_id:
        execute("UPDATE users SET availability='available' WHERE id=:id", {"id": driver_id})
    elif new_status in ("accepted", "ongoing", "arrived") and driver_id:
        execute("UPDATE users SET availability='on_ride' WHERE id=:id", {"id": driver_id})
    event(ride_id, None, new_status, {"admin_override": True})
    return {"message": f"Ride #{ride_id} status updated to {new_status}", "status": new_status}


@app.get("/api/admin/stats")
def admin_stats(_: dict = Depends(require_role("admin"))):
    rev_res = rows("SELECT COALESCE(SUM(amount), 0) as total_rev, COUNT(*) as pay_count FROM payments WHERE status='paid'")
    total_rev = float(rev_res[0]["total_rev"]) if rev_res else 0.0
    if total_rev == 0:
        fare_res = rows("SELECT COALESCE(SUM(fare), 0) as total_fare FROM rides WHERE status='completed'")
        total_rev = float(fare_res[0]["total_fare"]) if fare_res else 0.0

    ride_counts = rows("SELECT status, COUNT(*) as cnt FROM rides GROUP BY status")
    rides_by_status = {r["status"]: r["cnt"] for r in ride_counts}
    total_rides = sum(rides_by_status.values())

    driver_counts = rows("SELECT availability, COUNT(*) as cnt FROM users WHERE role='driver' GROUP BY availability")
    drivers_by_status = {d["availability"]: d["cnt"] for d in driver_counts}
    total_drivers = sum(drivers_by_status.values())

    total_riders = rows("SELECT COUNT(*) as cnt FROM users WHERE role='rider'")[0]["cnt"]
    total_vehicles = rows("SELECT COUNT(*) as cnt FROM vehicles")[0]["cnt"]

    commission_rate = 0.15
    platform_net_income = round(total_rev * commission_rate, 2)
    driver_payouts_due = round(total_rev * (1 - commission_rate), 2)

    methods = rows("SELECT payment_method, COALESCE(SUM(amount),0) as sum_amt, COUNT(*) as cnt FROM payments WHERE status='paid' GROUP BY payment_method")
    payment_breakdown = [{"method": m["payment_method"], "amount": float(m["sum_amt"]), "count": m["cnt"]} for m in methods]

    driver_stats = rows("""
        SELECT u.id, u.name, u.phone, u.availability,
               COALESCE(v.vehicle_model, 'Standard Car') as vehicle_model,
               COALESCE(v.plate_number, '—') as plate_number,
               COUNT(r.id) as completed_trips,
               COALESCE(SUM(r.fare), 0) as gross_fare
        FROM users u
        LEFT JOIN vehicles v ON v.driver_id = u.id
        LEFT JOIN rides r ON r.driver_id = u.id AND r.status = 'completed'
        WHERE u.role = 'driver'
        GROUP BY u.id, u.name, u.phone, u.availability, v.vehicle_model, v.plate_number
        ORDER BY gross_fare DESC
    """)
    driver_finance = []
    for d in driver_stats:
        gross = float(d["gross_fare"])
        fee = round(gross * commission_rate, 2)
        net = round(gross - fee, 2)
        driver_finance.append({
            "id": d["id"],
            "name": d["name"],
            "phone": d["phone"],
            "availability": d["availability"],
            "vehicle": f"{d['vehicle_model']} ({d['plate_number']})",
            "completed_trips": d["completed_trips"],
            "gross_fare": gross,
            "platform_fee": fee,
            "net_earnings": net,
            "payout_status": "Settled" if gross == 0 else "Pending Payout",
        })

    return {
        "total_revenue": total_rev,
        "commission_rate": commission_rate,
        "platform_net_income": platform_net_income,
        "driver_payouts_due": driver_payouts_due,
        "total_rides": total_rides,
        "rides_by_status": rides_by_status,
        "total_drivers": total_drivers,
        "drivers_by_status": drivers_by_status,
        "total_riders": total_riders,
        "total_vehicles": total_vehicles,
        "payment_breakdown": payment_breakdown,
        "driver_finance": driver_finance,
    }


@app.get("/api/driver-rides")
def driver_rides(driver=Depends(require_role("driver"))):
    return rows("SELECT r.id,r.rider_id,r.driver_id,u.name AS rider_name,u.phone AS rider_phone,"
                "r.pickup_location,r.destination,r.ride_type,r.distance_km,r.fare,r.estimated_fare,"
                "r.status,r.created_at,EXISTS(SELECT 1 FROM ratings rt WHERE rt.ride_id=r.id "
                "AND rt.rater_id=:driver) AS rated FROM rides r JOIN users u ON u.id=r.rider_id "
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
        allowed_previous = {
            "accepted": ("requested",),
            "arrived": ("accepted",),
            "ongoing": ("accepted", "arrived"),
            "completed": ("ongoing", "arrived"),
            "cancelled": ("accepted", "arrived", "ongoing"),
        }
        if body.status not in allowed_previous or ride["status"] not in allowed_previous[body.status]:
            fail(409, f"Cannot change ride from {ride['status']} to {body.status}")
        if body.status == "completed" and ride["ride_type"] == "Direct Ride":
            if body.final_fare is None and body.final_distance_km is not None:
                body.final_fare = fare_for("Car", body.final_distance_km)
            if body.final_fare is None:
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
    status_messages = {
        "accepted": ("Driver on the way", f"Your driver has accepted ride #{ride_id} and is heading to your pickup location."),
        "arrived": ("Driver arrived", f"Your driver has arrived at the pickup location! Please meet your driver."),
        "ongoing": ("Trip in progress", f"Your trip #{ride_id} has started. Have a safe journey!"),
        "completed": ("Trip completed", f"Trip #{ride_id} is completed. Thank you for riding with RideApp!"),
        "cancelled": ("Trip cancelled", f"Ride #{ride_id} has been cancelled."),
    }
    title, msg = status_messages.get(body.status, ("Ride updated", f"Ride #{ride_id} is now {updated['status']}."))
    notify(ride["rider_id"], title, msg, "ride")
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
def update_driver_location(body: LocationBody, ride_id: int | None = Query(default=None, gt=0),
                           driver=Depends(require_role("driver"))):
    if ride_id is None:
        if driver.get("availability") != "available":
            fail(409, "Go online before sharing your location for nearby ride requests")
    else:
        if driver.get("availability") not in ("on_ride", "busy"):
            fail(409, "Trip location sharing is available during an active ride")
        if not rows("SELECT id FROM rides WHERE id=:ride AND driver_id=:driver "
                    "AND status='ongoing'", {"ride": ride_id, "driver": driver["id"]}):
            fail(403, "The active ride does not belong to you")
    save_driver_location(driver["id"], ride_id, body)
    if ride_id is None:
        offer_pending_rides_to_driver(driver["id"])
    return {"message": "Location updated"}


@app.get("/api/rides/{ride_id}/track")
async def track_ride(ride_id: int, user=Depends(jwt_subject)):
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

    route_points = []
    p_lat, p_lng = ride["pickup_lat"], ride["pickup_lng"]
    d_lat, d_lng = ride["destination_lat"], ride["destination_lng"]
    if p_lat is not None and p_lng is not None and d_lat is not None and d_lng is not None:
        try:
            _, _, route_points = await fetch_driving_route(float(p_lat), float(p_lng), float(d_lat), float(d_lng))
        except Exception:
            route_points = []

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
        "route_points": route_points,
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
def create_payment(body: PaymentBody, user=Depends(jwt_subject)):
    if body.payment_method == "card":
        fail(422, "Card payments are not offered. Use cash or KHQR.")
    try:
        with engine.begin() as conn:
            lock = " FOR UPDATE" if engine.dialect.name == "mysql" else ""
            ride = conn.execute(
                text("SELECT id,fare,status,rider_id,driver_id FROM rides WHERE id=:ride" + lock),
                {"ride": body.ride_id},
            ).mappings().first()
            if ride:
                if user.get("role") == "rider" and user.get("id") != ride["rider_id"]:
                    fail(403, "You cannot record payment for another passenger's ride")
                if user.get("role") == "driver" and user.get("id") != ride["driver_id"]:
                    fail(403, "You cannot record payment for another driver's ride")
            if not ride:
                fail(404, "Ride not found")
            if ride["status"] != "completed" or ride["fare"] is None:
                fail(409, "Payment is available after the final fare is recorded")
            now = db_now()
            active_intent = conn.execute(
                text("SELECT id FROM payment_intents WHERE ride_id=:ride AND status='pending' "
                     "AND expires_at>:now LIMIT 1" + lock),
                {"ride": body.ride_id, "now": now},
            ).first()
            if active_intent:
                fail(409, "A KHQR payment is already waiting for confirmation")
            if conn.execute(text("SELECT id FROM payments WHERE ride_id=:ride"),
                            {"ride": body.ride_id}).first():
                fail(409, "This ride has already been paid")
            inserted = conn.execute(
                text("INSERT INTO payments(ride_id,amount,payment_method,status) "
                     "VALUES(:ride,:amount,'cash','paid')"),
                {"ride": body.ride_id, "amount": ride["fare"]},
            )
            payment_id = inserted.lastrowid
    except IntegrityError:
        fail(409, "This ride has already been paid")
    return {"message": "Cash payment recorded", "payment_id": payment_id, "amount": ride["fare"]}


def create_bakong_qr(amount: Decimal) -> tuple[str, str]:
    """Generate a dynamic KHQR locally; the payment status is always verified server-side."""
    if not all((BAKONG_ACCOUNT_ID, BAKONG_MERCHANT_NAME, BAKONG_MERCHANT_CITY,
                BAKONG_PHONE_NUMBER, BAKONG_API_TOKEN)):
        fail(503, "Real KHQR payments need the registered merchant account and Bakong verification credentials")
    if not 1 <= BAKONG_QR_EXPIRY_MINUTES <= 10:
        fail(503, "KHQR expiry must be between 1 and 10 minutes")
    try:
        from bakong_khqr import KHQR

        generator = KHQR()
        qr = generator.create_qr(
            account_id=BAKONG_ACCOUNT_ID,
            merchant_name=BAKONG_MERCHANT_NAME,
            merchant_city=BAKONG_MERCHANT_CITY,
            amount=float(amount),
            currency="USD",
            store_label="RideApp",
            phone_number=BAKONG_PHONE_NUMBER,
            bill_number=f"RA{uuid.uuid4().hex[:14].upper()}",
            terminal_label="RideApp",
            static=False,
            expiration=BAKONG_QR_EXPIRY_MINUTES,
        )
        return str(qr.qr), str(qr.md5)
    except HTTPException:
        raise
    except Exception as exc:
        logger.warning("KHQR creation failed: %s", type(exc).__name__)
        fail(503, "Could not create a KHQR payment. Please try again.")


async def fetch_bakong_payment(md5: str) -> dict[str, Any] | None:
    if not BAKONG_API_TOKEN:
        fail(503, "KHQR transaction verification is not configured")
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            response = await client.post(
                f"{BAKONG_API_BASE_URL}/check_transaction_by_md5",
                headers={"Authorization": f"Bearer {BAKONG_API_TOKEN}"},
                json={"md5": md5},
            )
            response.raise_for_status()
            result = response.json()
    except (httpx.HTTPError, ValueError):
        logger.warning("Bakong transaction status lookup failed")
        fail(503, "Could not verify payment yet. Please try again.")
    if not isinstance(result, dict):
        fail(502, "Bakong returned an invalid payment response")
    if result.get("responseCode") == 0 and isinstance(result.get("data"), dict):
        return result["data"]
    # NBC returns responseCode 1 when the dynamic QR has not been paid yet.
    if result.get("responseCode") == 1:
        return None
    fail(502, "Bakong could not verify this payment")


@app.post("/api/payments/khqr", status_code=201)
def create_khqr_payment(body: KhqrPaymentBody, rider=Depends(require_role("rider"))):
    if not all((BAKONG_ACCOUNT_ID, BAKONG_MERCHANT_NAME, BAKONG_MERCHANT_CITY,
                BAKONG_PHONE_NUMBER, BAKONG_API_TOKEN)):
        fail(
            503,
            "ACLEDA/KHQR payments are not configured. Set the registered merchant details and Bakong verification token first.",
        )
    now = db_now()
    lock = " FOR UPDATE" if engine.dialect.name == "mysql" else ""
    with engine.begin() as conn:
        ride = conn.execute(
            text("SELECT id,fare,status FROM rides WHERE id=:ride AND rider_id=:rider" + lock),
            {"ride": body.ride_id, "rider": rider["id"]},
        ).mappings().first()
        if not ride:
            fail(404, "Ride not found")
        if ride["status"] != "completed" or ride["fare"] is None:
            fail(409, "KHQR payment is available after the final fare is recorded")
        if conn.execute(text("SELECT id FROM payments WHERE ride_id=:ride"),
                        {"ride": body.ride_id}).first():
            fail(409, "This ride has already been paid")
        existing = conn.execute(
            text("SELECT id,amount,currency,qr_payload,expires_at,status FROM payment_intents "
                 "WHERE ride_id=:ride AND rider_id=:rider" + lock),
            {"ride": body.ride_id, "rider": rider["id"]},
        ).mappings().first()
        if existing and existing["status"] == "pending" and database_datetime(existing["expires_at"]) > now:
            return {
                "intent_id": existing["id"], "qr": existing["qr_payload"],
                "amount": existing["amount"], "currency": existing["currency"],
                "expires_at": database_datetime(existing["expires_at"]).isoformat(),
            }
        amount = Decimal(str(ride["fare"])).quantize(Decimal("0.01"))
        qr_payload, qr_md5 = create_bakong_qr(amount)
        expires_at = now + timedelta(minutes=BAKONG_QR_EXPIRY_MINUTES)
        if existing:
            conn.execute(
                text("UPDATE payment_intents SET amount=:amount,currency='USD',qr_payload=:qr,"
                     "qr_md5=:md5,status='pending',expires_at=:expires,"
                     "provider_transaction_hash=NULL WHERE id=:id"),
                {"id": existing["id"], "amount": str(amount), "qr": qr_payload,
                 "md5": qr_md5, "expires": expires_at},
            )
            intent_id = existing["id"]
        else:
            inserted = conn.execute(
                text("INSERT INTO payment_intents(ride_id,rider_id,amount,currency,qr_payload,"
                     "qr_md5,status,expires_at) VALUES(:ride,:rider,:amount,'USD',:qr,:md5,"
                     "'pending',:expires)"),
                {"ride": body.ride_id, "rider": rider["id"], "amount": str(amount),
                 "qr": qr_payload, "md5": qr_md5, "expires": expires_at},
            )
            intent_id = inserted.lastrowid
    return {
        "intent_id": intent_id, "qr": qr_payload, "amount": amount,
        "currency": "USD", "expires_at": expires_at.isoformat(),
    }


@app.get("/api/payments/khqr/{intent_id}")
async def check_khqr_payment(intent_id: int, rider=Depends(require_role("rider"))):
    intent_rows = rows(
        "SELECT id,ride_id,rider_id,amount,currency,qr_md5,status,expires_at "
        "FROM payment_intents WHERE id=:id AND rider_id=:rider",
        {"id": intent_id, "rider": rider["id"]},
    )
    if not intent_rows:
        fail(404, "KHQR payment not found")
    intent = intent_rows[0]
    paid_rows = rows("SELECT id FROM payments WHERE ride_id=:ride", {"ride": intent["ride_id"]})
    if paid_rows:
        return {"intent_id": intent_id, "status": "paid", "payment_id": paid_rows[0]["id"]}
    if intent["status"] == "paid":
        fail(409, "Payment state needs reconciliation")
    if intent["status"] != "pending":
        return {"intent_id": intent_id, "status": intent["status"]}
    expires_at = database_datetime(intent["expires_at"])
    if expires_at <= db_now():
        execute("UPDATE payment_intents SET status='expired' WHERE id=:id AND status='pending'",
                {"id": intent_id})
        return {"intent_id": intent_id, "status": "expired"}

    transaction = await fetch_bakong_payment(str(intent["qr_md5"]))
    if transaction is None:
        return {"intent_id": intent_id, "status": "pending"}
    try:
        amount = Decimal(str(transaction.get("amount", "NaN"))).quantize(Decimal("0.01"))
    except InvalidOperation:
        fail(502, "Bakong returned an invalid transaction amount")
    if (amount != Decimal(str(intent["amount"]))
            or str(transaction.get("currency", "")).upper() != intent["currency"]
            or str(transaction.get("toAccountId", "")).casefold()
            != BAKONG_ACCOUNT_ID.casefold()
            or not transaction.get("hash")):
        logger.error("Bakong payment details did not match payment intent %s", intent_id)
        fail(409, "Bakong payment details do not match this ride fare")

    with engine.begin() as conn:
        lock = " FOR UPDATE" if engine.dialect.name == "mysql" else ""
        conn.execute(text("SELECT id FROM rides WHERE id=:ride" + lock),
                     {"ride": intent["ride_id"]}).first()
        existing_payment = conn.execute(
            text("SELECT id FROM payments WHERE ride_id=:ride"),
            {"ride": intent["ride_id"]},
        ).mappings().first()
        if existing_payment:
            conn.execute(
                text("UPDATE payment_intents SET status='reconciliation',"
                     "provider_transaction_hash=:hash WHERE id=:id AND status='pending'"),
                {"hash": str(transaction["hash"]), "id": intent_id},
            )
            return {"intent_id": intent_id, "status": "reconciliation"}
        updated = conn.execute(
            text("UPDATE payment_intents SET status='paid',provider_transaction_hash=:hash "
                 "WHERE id=:id AND status='pending'"),
            {"hash": str(transaction["hash"]), "id": intent_id},
        )
        if updated.rowcount:
            inserted = conn.execute(
                text("INSERT INTO payments(ride_id,amount,payment_method,status) "
                     "VALUES(:ride,:amount,'khqr','paid')"),
                {"ride": intent["ride_id"], "amount": intent["amount"]},
            )
            payment_id = inserted.lastrowid
        else:
            payment = conn.execute(
                text("SELECT id FROM payments WHERE ride_id=:ride"),
                {"ride": intent["ride_id"]},
            ).mappings().first()
            payment_id = payment["id"] if payment else None
    if payment_id is None:
        fail(409, "Payment state needs reconciliation")
    return {"intent_id": intent_id, "status": "paid", "payment_id": payment_id}


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

