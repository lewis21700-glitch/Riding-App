# RideApp Mobile (Flutter)

Cross-platform Flutter application for passengers and drivers in Phnom Penh.

## Features
- **Passenger Flow**: Instant upfront fare calculation across 5 vehicle types (Car, Comfort, Premium, Tuk Tuk, Motorbike), interactive Phnom Penh map, location search, and trip history.
- **Driver Flow**: Interactive lifecycle stepper (`Accept Booking` ➔ `Going to Pickup` ➔ `Arrived at Pickup` ➔ `Start Trip` ➔ `Complete Trip`), passenger phone launcher, cash collection, and passenger rating.
- **Payments**: Cash on arrival and Bakong KHQR dynamic payment code verification.
- **Account & Settings**: Saved places (Home/Work), language selection (English/Khmer), currency display (USD/KHR), safety SOS emergency center, and notification preferences.

## Running the App

```powershell
flutter pub get
flutter run
```

For Android Emulator connecting to local host backend:
```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

For Web testing in Edge/Chrome:
```powershell
flutter run -d edge --web-port=57496
```

## Testing
Run unit and widget tests:
```powershell
flutter test
```
