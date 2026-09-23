RIDEAPP SPRINT 3 MOBILE

This is the Flutter Rider App for Android Studio.

Backend for Android emulator:
http://10.0.2.2:3000/api

Sprint 3 flow:
Login/Register -> Pickup/current location -> Destination -> Ride type -> Fare estimate -> Request ride -> Ride history.

Direct Ride:
Pickup -> Direct Ride -> Request -> no destination -> final fare after driver completes the ride.

Expected backend endpoints:
POST /api/login
POST /api/users
POST /api/fare/estimate
POST /api/rides
GET /api/my-rides

Commands:
flutter pub get
flutter run
