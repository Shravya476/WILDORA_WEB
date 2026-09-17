# HWC Alert — Setup Guide

## Extract this zip to C:\hwc_app\

## MANDATORY BEFORE RUNNING

### 1. Firebase (for OTP login)
- Go to https://console.firebase.google.com
- New Project → name: HWC Alert
- Add Android app → Package: com.hwc.hwc_app
- Download google-services.json
- Place it at: android/app/google-services.json

### 2. Google Maps API Key (for map)
- Go to https://console.cloud.google.com
- Enable "Maps SDK for Android"
- Create API Key → copy it
- Open android/app/src/main/AndroidManifest.xml
- Replace: YOUR_GOOGLE_MAPS_API_KEY
- With your actual key

## RUN COMMANDS

Open Command Prompt in this folder (C:\hwc_app\hwc_final):

  flutter pub get
  flutter run -d chrome

For Android phone:
  flutter run

## BACKEND
Already connected to: https://hwc-backend-fixed.onrender.com
No changes needed.

## HIGH RISK TEST COORDINATES
Nagarhole: lat=11.93, lon=76.13
Bandipur:  lat=11.67, lon=76.63
Wayanad:   lat=11.61, lon=76.13


## Shared Community Reports

Community reports are stored in Firebase Cloud Firestore so that reports submitted by one WILDORA user can appear in the Community Reports feed and the Predict Risk page for other signed-in users.

Enable **Cloud Firestore** in the Firebase project used by this app. The included `firestore.rules` allows signed-in users (including the app's anonymous Firebase-authenticated session) to read and create community reports. If you use the Firebase CLI, deploy the rules with `firebase deploy --only firestore:rules`.

Images are stored as compressed-size data in the report document and the app accepts images up to 650 KB to stay within Firestore document limits.
