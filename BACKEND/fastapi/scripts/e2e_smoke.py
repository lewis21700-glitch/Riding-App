"""Opt-in HTTP smoke test for the complete local passenger/driver ride flow."""

from __future__ import annotations

import argparse
import secrets
import sys
import uuid
from urllib.parse import urlsplit

import httpx


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--api-url",
        default="http://127.0.0.1:3000",
        help="FastAPI origin, without the /api suffix (default: %(default)s)",
    )
    parser.add_argument(
        "--allow-nonlocal",
        action="store_true",
        help="Also permit writes when --api-url points outside this computer",
    )
    parser.add_argument(
        "--allow-writes",
        action="store_true",
        help="Create test accounts, a ride, payment, and rating in the configured database",
    )
    args = parser.parse_args()
    if not args.allow_writes:
        parser.error("This test writes database records; pass --allow-writes against a dev/test database")

    base_url = args.api_url.rstrip("/")
    host = urlsplit(base_url).hostname
    if host not in {"localhost", "127.0.0.1", "::1"} and not args.allow_nonlocal:
        parser.error("Remote targets need --allow-nonlocal in addition to --allow-writes")
    run_id = uuid.uuid4().hex[:12]
    password = f"RideSmoke-{secrets.token_urlsafe(18)}"

    with httpx.Client(base_url=base_url, timeout=20.0) as client:
        health = client.get("/health")
        require(health.status_code == 200, f"API health failed: HTTP {health.status_code}")
        health_data = health.json()
        require(health_data.get("database") == "connected", "API database is not connected")
        print("PASS API and database health")
        docs = client.get("/docs")
        openapi = client.get("/openapi.json")
        require(docs.status_code == 200 and openapi.status_code == 200,
                "Swagger UI or OpenAPI schema is unavailable")
        paths = openapi.json().get("paths", {})
        require("/api/register" in paths and "/api/rides/{ride_id}/track" in paths,
                "OpenAPI schema is missing core authentication or tracking routes")
        print("PASS Swagger UI and generated OpenAPI schema")

        passenger_response = client.post(
            "/api/register",
            json={
                "name": f"Smoke Passenger {run_id}",
                "email": f"ride-smoke-passenger-{run_id}@example.com",
                "phone": "010000000",
                "password": password,
                "role": "rider",
            },
        )
        require(passenger_response.status_code == 201,
                f"Passenger registration failed: {passenger_response.text}")
        passenger = passenger_response.json()["user"]
        print("PASS passenger registration")

        login = client.post("/api/login", json={"email": passenger["email"], "password": password})
        require(login.status_code == 200, f"Passenger login failed: {login.text}")
        passenger_token = login.json()["token"]
        passenger_headers = {"Authorization": f"Bearer {passenger_token}"}
        profile = client.get("/api/profile", headers=passenger_headers)
        require(profile.status_code == 200 and profile.json()["role"] == "rider",
                "Passenger JWT/profile check failed")
        require(client.get("/api/users", headers=passenger_headers).status_code == 403,
                "Passenger was not denied admin-only access")
        print("PASS login, JWT profile, and passenger role restriction")

        driver_response = client.post(
            "/api/register",
            json={
                "name": f"Smoke Driver {run_id}",
                "email": f"ride-smoke-driver-{run_id}@example.com",
                "phone": "010000001",
                "password": password,
                "role": "driver",
            },
        )
        require(driver_response.status_code == 201,
                f"Driver registration failed: {driver_response.text}")
        driver = driver_response.json()["user"]
        driver_login = client.post("/api/login", json={"email": driver["email"], "password": password})
        require(driver_login.status_code == 200, f"Driver login failed: {driver_login.text}")
        driver_headers = {"Authorization": f"Bearer {driver_login.json()['token']}"}
        require(client.get("/api/users", headers=driver_headers).status_code == 403,
                "Driver was not denied admin-only access")
        vehicle = client.post(
            "/api/my-vehicle",
            headers=driver_headers,
            json={
                "vehicle_type": "Car",
                "vehicle_model": "RideApp smoke test",
                "plate_number": f"SMK-{run_id[:8].upper()}",
            },
        )
        require(vehicle.status_code == 201, f"Driver vehicle setup failed: {vehicle.text}")
        availability = client.put(
            f"/api/drivers/{driver['id']}/availability",
            headers=driver_headers,
            json={"availability": "online"},
        )
        require(availability.status_code == 200, f"Driver onboarding failed: {availability.text}")
        print("PASS driver onboarding, vehicle, and availability")

        estimate = client.post(
            "/api/fare/estimate",
            headers=passenger_headers,
            json={"ride_type": "Car", "distance_km": 5},
        )
        require(estimate.status_code == 200 and estimate.json().get("estimated_fare") is not None,
                f"Fare estimate failed: {estimate.text}")
        ride_response = client.post(
            "/api/rides",
            headers=passenger_headers,
            json={
                "pickup_location": f"Smoke pickup {run_id}",
                "destination": "Central Market",
                "ride_type": "Car",
                "distance_km": 5,
                "pickup_lat": 11.56,
                "pickup_lng": 104.92,
                "destination_lat": 11.57,
                "destination_lng": 104.93,
            },
        )
        require(ride_response.status_code == 201, f"Ride request failed: {ride_response.text}")
        ride_id = ride_response.json()["ride_id"]
        driver_requests = client.get("/api/driver-rides", headers=driver_headers)
        require(driver_requests.status_code == 200 and any(
            ride["id"] == ride_id for ride in driver_requests.json()
        ), "New ride was not offered to the available driver")
        driver_notifications = client.get("/api/my-notifications", headers=driver_headers)
        require(driver_notifications.status_code == 200 and any(
            item["title"] == "New ride request"
            for item in driver_notifications.json()["notifications"]
        ), "The driver did not receive the ride-request notification")
        print("PASS fare estimate, ride request, matching, and notification delivery to inbox")

        for status, label in (("accepted", "accept ride"), ("ongoing", "start trip")):
            response = client.put(
                f"/api/driver-rides/{ride_id}",
                headers=driver_headers,
                json={"status": status},
            )
            require(response.status_code == 200, f"Driver could not {label}: {response.text}")
        location = client.post(
            f"/api/driver-location?ride_id={ride_id}",
            headers=driver_headers,
            json={"latitude": 11.56, "longitude": 104.92, "heading": 90},
        )
        require(location.status_code == 200, f"Driver location update failed: {location.text}")
        tracking = client.get(f"/api/rides/{ride_id}/track", headers=passenger_headers)
        require(tracking.status_code == 200 and tracking.json().get("location") is not None,
                f"Passenger tracking failed: {tracking.text}")
        require(client.put(f"/api/driver-rides/{ride_id}", headers=driver_headers,
                           json={"status": "completed"}).status_code == 200,
                "Trip completion failed")
        print("PASS accept, start, location tracking, and trip completion")

        payment = client.post("/api/payments", headers=passenger_headers,
                              json={"ride_id": ride_id, "payment_method": "cash"})
        require(payment.status_code == 201, f"Cash payment failed: {payment.text}")
        rating = client.post("/api/ratings", headers=passenger_headers,
                             json={"ride_id": ride_id, "score": 5, "comment": "Smoke test"})
        require(rating.status_code == 201, f"Ride rating failed: {rating.text}")
        passenger_rides = client.get("/api/my-rides", headers=passenger_headers)
        require(passenger_rides.status_code == 200 and any(
            ride["id"] == ride_id and ride["paid"] and ride["rated"]
            for ride in passenger_rides.json()["rides"]
        ), "Ride history does not show payment and rating")
        print("PASS cash payment, rating, and passenger ride history")

    print(f"Smoke test passed. Test records were created for run {run_id}.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (httpx.HTTPError, RuntimeError, KeyError, ValueError) as error:
        print(f"FAIL {error}", file=sys.stderr)
        raise SystemExit(1) from error
