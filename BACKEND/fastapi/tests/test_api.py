from __future__ import annotations

import itertools

import bcrypt
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.pool import StaticPool

import app.main as api


_ids = itertools.count(1)


@pytest.fixture
def client(monkeypatch):
    test_engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    schema = [
        """CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, email TEXT UNIQUE NOT NULL,
          phone TEXT DEFAULT '', password TEXT NOT NULL, role TEXT NOT NULL,
          availability TEXT DEFAULT 'offline', created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )""",
        """CREATE TABLE vehicles (
          id INTEGER PRIMARY KEY AUTOINCREMENT, driver_id INTEGER NOT NULL, vehicle_type TEXT,
          vehicle_model TEXT, plate_number TEXT UNIQUE
        )""",
        """CREATE TABLE rides (
          id INTEGER PRIMARY KEY AUTOINCREMENT, rider_id INTEGER NOT NULL, driver_id INTEGER,
          pickup_location TEXT NOT NULL, destination TEXT DEFAULT '', ride_type TEXT,
          distance_km NUMERIC, estimated_fare NUMERIC, fare NUMERIC,
          pickup_lat NUMERIC, pickup_lng NUMERIC, destination_lat NUMERIC, destination_lng NUMERIC,
          status TEXT DEFAULT 'requested', created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )""",
        """CREATE TABLE notifications (
          id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, title TEXT, message TEXT,
          type TEXT, is_read INTEGER DEFAULT 0, created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )""",
        """CREATE TABLE ride_offers (
          ride_id INTEGER, driver_id INTEGER, status TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (ride_id,driver_id)
        )""",
        """CREATE TABLE ride_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT, ride_id INTEGER, actor_id INTEGER,
          event_type TEXT, details JSON, created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )""",
        """CREATE TABLE driver_locations (
          driver_id INTEGER PRIMARY KEY, ride_id INTEGER, latitude NUMERIC, longitude NUMERIC,
          heading NUMERIC, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )""",
        """CREATE TABLE payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT, ride_id INTEGER UNIQUE, amount NUMERIC,
          payment_method TEXT, status TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )""",
        """CREATE TABLE ratings (
          id INTEGER PRIMARY KEY AUTOINCREMENT, ride_id INTEGER, rater_id INTEGER,
          ratee_id INTEGER, score INTEGER, comment TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          UNIQUE (ride_id,rater_id)
        )""",
        """CREATE TABLE push_tokens (
          id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, token TEXT UNIQUE,
          platform TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )""",
    ]
    with test_engine.begin() as connection:
        for statement in schema:
            connection.execute(text(statement))
    monkeypatch.setattr(api, "engine", test_engine)
    monkeypatch.setattr(api, "ensure_schema", lambda: None)
    with TestClient(api.app) as test_client:
        yield test_client
    test_engine.dispose()


def register(client: TestClient, role: str, label: str):
    response = client.post(
        "/api/register",
        json={
            "name": f"Test {label}",
            "email": f"rideapp-test-{next(_ids)}@example.com",
            "phone": "01234567",
            "password": "test-password-123",
            "role": role,
        },
    )
    assert response.status_code == 201, response.text
    data = response.json()
    return data["user"], data["token"]


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_authentication_role_checks_and_password_hash(client):
    user, token = register(client, "rider", "rider")
    assert user["role"] == "rider"
    assert client.get("/api/profile", headers=auth(token)).json()["email"] == user["email"]
    assert client.get("/api/users", headers=auth(token)).status_code == 403
    assert client.get("/api/users").status_code == 401
    login = client.post("/api/login", json={"email": user["email"], "password": "test-password-123"})
    assert login.status_code == 200
    assert client.post("/api/login", json={"email": user["email"], "password": "incorrect"}).status_code == 401


def test_production_rejects_weak_jwt_secret(monkeypatch):
    monkeypatch.setattr(api, "APP_ENV", "production")
    monkeypatch.setattr(api, "JWT_SECRET", "local-development-only-change-before-deploy-32chars")
    with pytest.raises(RuntimeError, match="private JWT_SECRET"):
        api.validate_security_configuration()


def test_bcrypt_legacy_password_is_upgraded_on_successful_login(client):
    password = b"legacy-password-123"
    _, user_id = api.execute(
        "INSERT INTO users(name,email,phone,password,role,availability) "
        "VALUES(:name,:email,'',:password,'rider',NULL)",
        {"name": "Legacy Rider", "email": "legacy-bcrypt@example.com",
         "password": bcrypt.hashpw(password, bcrypt.gensalt()).decode()},
    )
    result = client.post("/api/login", json={
        "email": "legacy-bcrypt@example.com", "password": password.decode()
    })
    assert result.status_code == 200
    migrated = api.rows("SELECT password FROM users WHERE id=:id", {"id": user_id})[0]["password"]
    assert migrated.startswith("$argon2")


def test_ride_booking_matching_trip_completion_payment_and_rating(client):
    rider, rider_token = register(client, "rider", "passenger")
    driver, driver_token = register(client, "driver", "driver")
    driver_auth = auth(driver_token)
    rider_auth = auth(rider_token)

    vehicle = client.post("/api/my-vehicle", headers=driver_auth, json={
        "vehicle_type": "Tuk Tuk", "vehicle_model": "Demo vehicle", "plate_number": "TEST-001"
    })
    assert vehicle.status_code == 201
    assert client.put(f"/api/drivers/{driver['id']}/availability", headers=driver_auth,
                      json={"availability": "online"}).status_code == 200

    estimate = client.post("/api/fare/estimate", headers=rider_auth, json={
        "ride_type": "tukTuk", "distance_km": 10
    })
    assert estimate.status_code == 200
    assert estimate.json()["estimated_fare"] == 6.5

    booking = client.post("/api/rides", headers=rider_auth, json={
        "pickup_location": "Phnom Penh",
        "destination": "Central Market",
        "ride_type": "tukTuk",
        "distance_km": 10,
        "pickup_lat": 11.56,
        "pickup_lng": 104.92,
        "destination_lat": 11.57,
        "destination_lng": 104.93,
    })
    assert booking.status_code == 201, booking.text
    ride_id = booking.json()["ride_id"]

    driver_notifications = client.get("/api/my-notifications", headers=driver_auth).json()["notifications"]
    ride_notification = next(item for item in driver_notifications if item["title"] == "New ride request")
    rider_notifications = client.get("/api/my-notifications", headers=rider_auth).json()["notifications"]
    assert all(item["id"] != ride_notification["id"] for item in rider_notifications)
    assert client.put(f"/api/my-notifications/{ride_notification['id']}/read",
                      headers=rider_auth).status_code == 404
    assert client.put(f"/api/my-notifications/{ride_notification['id']}/read",
                      headers=driver_auth).status_code == 200

    offers = client.get("/api/driver-rides", headers=driver_auth).json()
    assert any(ride["id"] == ride_id for ride in offers)
    assert client.put(f"/api/driver-rides/{ride_id}", headers=driver_auth,
                      json={"status": "accepted"}).status_code == 200
    second_booking = client.post("/api/rides", headers=rider_auth, json={
        "pickup_location": "Phnom Penh Riverside",
        "destination": "Central Market",
        "ride_type": "tukTuk",
        "distance_km": 4,
    })
    assert second_booking.status_code == 201
    second_ride_id = second_booking.json()["ride_id"]
    assert client.put(f"/api/driver-rides/{second_ride_id}", headers=driver_auth,
                      json={"status": "accepted"}).status_code == 409
    second_ride = api.rows("SELECT driver_id,status FROM rides WHERE id=:id",
                           {"id": second_ride_id})[0]
    assert second_ride["driver_id"] is None and second_ride["status"] == "requested"
    other_driver, other_token = register(client, "driver", "rollback-driver")
    other_auth = auth(other_token)
    assert client.post("/api/my-vehicle", headers=other_auth, json={
        "vehicle_type": "Car", "vehicle_model": "Rollback test car", "plate_number": "TEST-003"
    }).status_code == 201
    assert client.put(f"/api/drivers/{other_driver['id']}/availability", headers=other_auth,
                      json={"availability": "online"}).status_code == 200
    assert client.put(f"/api/driver-rides/{ride_id}", headers=other_auth,
                      json={"status": "accepted"}).status_code == 409
    assert client.get("/api/profile", headers=other_auth).json()["availability"] == "available"
    assert client.put(f"/api/drivers/{driver['id']}/availability", headers=driver_auth,
                      json={"availability": "offline"}).status_code == 409
    assert client.put(f"/api/driver-rides/{ride_id}", headers=driver_auth,
                      json={"status": "ongoing"}).status_code == 200
    assert client.post("/api/driver-location", headers=driver_auth,
                       json={"latitude": 11.56, "longitude": 104.92}).status_code == 422
    assert client.post("/api/driver-location?ride_id=9999", headers=driver_auth,
                       json={"latitude": 11.56, "longitude": 104.92}).status_code == 403
    assert client.post(f"/api/driver-location?ride_id={ride_id}", headers=driver_auth,
                       json={"latitude": 11.56, "longitude": 104.92}).status_code == 200
    tracking = client.get(f"/api/rides/{ride_id}/track", headers=rider_auth)
    assert tracking.status_code == 200 and tracking.json()["location"]["latitude"] == 11.56
    assert client.put(f"/api/driver-rides/{ride_id}", headers=driver_auth,
                      json={"status": "completed"}).status_code == 200
    assert client.post("/api/payments", headers=rider_auth,
                       json={"ride_id": ride_id, "payment_method": "cash"}).status_code == 201
    assert client.post("/api/payments", headers=rider_auth,
                       json={"ride_id": ride_id, "payment_method": "cash"}).status_code == 409
    assert client.post("/api/ratings", headers=rider_auth,
                       json={"ride_id": ride_id, "score": 5, "comment": "Great ride"}).status_code == 201
    assert client.post("/api/ratings", headers=rider_auth,
                       json={"ride_id": ride_id, "score": 5}).status_code == 409


def test_push_tokens_upsert_across_accounts(client):
    _, rider_token = register(client, "rider", "token-owner")
    _, driver_token = register(client, "driver", "token-owner-change")
    token = "device-registration-token-00000001"
    assert client.post(f"/api/push-tokens?token={token}", headers=auth(rider_token)).status_code == 201
    assert client.post(f"/api/push-tokens?token={token}&platform=android",
                       headers=auth(driver_token)).status_code == 201
    assert api.rows("SELECT COUNT(*) AS count FROM push_tokens WHERE token=:token",
                    {"token": token})[0]["count"] == 1


def test_direct_ride_needs_driver_set_fare_and_rejects_invalid_transition(client):
    rider, token = register(client, "rider", "direct-rider")
    response = client.post("/api/rides", headers=auth(token), json={
        "pickup_location": "GPS: 11.56, 104.92", "ride_type": "direct"
    })
    assert response.status_code == 201
    ride_id = response.json()["ride_id"]
    driver, driver_token = register(client, "driver", "direct-driver")
    driver_auth = auth(driver_token)
    client.post("/api/my-vehicle", headers=driver_auth, json={
        "vehicle_type": "Car", "vehicle_model": "Demo car", "plate_number": "TEST-002"
    })
    client.put(f"/api/drivers/{driver['id']}/availability", headers=driver_auth,
               json={"availability": "online"})
    assert client.put(f"/api/driver-rides/{ride_id}", headers=driver_auth,
                      json={"status": "accepted"}).status_code == 200
    assert client.put(f"/api/driver-rides/{ride_id}", headers=driver_auth,
                      json={"status": "completed", "final_fare": 4.25}).status_code == 409
    assert client.put(f"/api/driver-rides/{ride_id}", headers=driver_auth,
                      json={"status": "ongoing"}).status_code == 200
    result = client.put(f"/api/driver-rides/{ride_id}", headers=driver_auth,
                        json={"status": "completed", "final_fare": 4.25})
    assert result.status_code == 200 and float(result.json()["fare"]) == 4.25

