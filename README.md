# 🩺 DiaCare — Barangay Diabetes Monitoring App

A Flutter-based mobile application for Barangay Health Workers (BHW) to monitor Type 2 Diabetes patients in their assigned Purok. Built with an offline-first architecture and Material Design 3 UI.

---

## 📱 Features

| Module | Description |
|---|---|
| **Dashboard** | Summary cards, high-risk alerts, quick actions, recent records |
| **Patient List** | Search, filter by risk level, full patient profiles |
| **Health Records** | Log vitals per visit with automatic risk classification |
| **Notifications** | High-risk and no-visit alerts with read/unread state |
| **Profile** | BHW info, change password, manual sync, app settings |

### Risk Classification Logic
| Risk Level | Triggers |
|---|---|
| **High Risk** | Glucose ≥ 200 mg/dL **OR** Systolic BP ≥ 140 mmHg **OR** BMI ≥ 35 **OR** Medication missed |
| **Moderate Risk** | Glucose 140–199 **OR** Systolic BP 130–139 **OR** BMI 30–34.9 |
| **Normal** | All values within normal range + medication taken |

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) **≥ 3.0.0**
- [Android Studio](https://developer.android.com/studio) or VS Code with Flutter extension
- Android device or emulator (API 21+)
- Java JDK 11 or higher

### Setup

```bash
# 1. Clone or extract the project
cd diacare

# 2. Install dependencies
flutter pub get

# 3. Create assets directory (required by pubspec)
mkdir -p assets/images

# 4. Verify setup
flutter doctor

# 5. Run on connected device / emulator
flutter run

# 6. Build release APK
flutter build apk --release
```

### VS Code Setup

1. Install extensions: **Flutter** and **Dart**
2. Open folder: `File → Open Folder → diacare/`
3. Press `F5` or use `Run → Start Debugging`
4. Select your connected Android device

---

## 🔑 Demo Credentials

```
Username:  bhw.santos
Password:  bhw1234
```

The demo account (BHW Maria Santos) comes pre-loaded with:
- 3 approved patients (Purok 3)
- 4 health records
- 2 unread notifications (high-risk alert + overdue visit)

---

## 📁 Project Structure

```
lib/
├── main.dart                   # App entry point with session restore
├── models/
│   ├── patient.dart            # Patient data model
│   ├── health_record.dart      # Health record model
│   ├── user_model.dart         # BHW user model
│   └── notification_model.dart # Notification model
├── database/
│   └── database_helper.dart    # SQLite CRUD operations (sqflite)
├── services/
│   ├── auth_service.dart       # Login / session / password
│   ├── risk_classifier.dart    # Risk logic + input validators
│   └── sync_service.dart       # Offline-first sync management
├── providers/
│   └── app_provider.dart       # Global state (ChangeNotifier)
├── screens/
│   ├── login_screen.dart
│   ├── main_screen.dart        # Bottom navigation controller
│   ├── dashboard/              # Home dashboard
│   ├── patients/               # Patient list, profile, add patient
│   ├── records/                # Records list, add record
│   ├── notifications/          # Alerts screen
│   └── profile/                # BHW profile & settings
├── widgets/
│   └── shared_widgets.dart     # RiskBadge, SummaryCard, PatientCard, etc.
└── utils/
    ├── theme.dart              # Material Design 3 theme
    └── constants.dart          # App-wide constants & thresholds
```

---

## 🔒 Security & Privacy

- **No self-registration** — accounts are created by BHN/Admin only
- **Role-based access** — BHW can only view patients in their assigned Purok
- **Password hashing** — MD5 hashing (upgrade to bcrypt for production)
- **Local-first** — all data stored on-device via SQLite (sqflite)
- **Pending approval** — new patients added by BHW require Admin approval

---

## 📦 Key Dependencies

| Package | Purpose |
|---|---|
| `sqflite` | SQLite local database |
| `provider` | State management |
| `connectivity_plus` | Network detection for sync |
| `fl_chart` | Blood glucose & BP trend charts |
| `shared_preferences` | Session persistence |
| `crypto` | Password hashing |
| `uuid` | Unique record IDs |
| `intl` | Date formatting |

---

## 🌐 Offline-First Architecture

1. All reads/writes go to **local SQLite** first
2. On network restore → `SyncService.syncIfOnline()` runs automatically
3. **Unique IDs** prevent duplicate sync
4. **Timestamp-based conflict resolution** (latest record wins)
5. Records marked `isSynced = false` until confirmed by backend

> **Note:** The current sync implementation simulates the API call. In production, replace `_performSync()` in `sync_service.dart` with your actual REST API calls.

---

## ⚠️ Disclaimer

DiaCare is designed for community health monitoring and decision-support only. It does not provide medical diagnosis or treatment. All clinical decisions must be made by qualified healthcare professionals.

---

## 🛠️ Production Checklist

- [ ] Replace MD5 password hashing with `bcrypt`
- [ ] Connect `SyncService` to real REST API endpoint
- [ ] Set up remote backend (Firebase / Supabase / custom)
- [ ] Enable BHN/Admin web panel for patient approvals
- [ ] Add biometric authentication
- [ ] Implement proper SSL certificate pinning
- [ ] Add crash analytics (Firebase Crashlytics)
- [ ] Enable ProGuard for release APK
