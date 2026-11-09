#!/usr/bin/env bash
set -euo pipefail

APK="build/app/outputs/flutter-apk/app-release.apk"
PACKAGE="com.example.batipro_dz"
ACTIVITY="$PACKAGE/.MainActivity"

echo "Waiting for Android emulator device"
adb wait-for-device

boot_wait=0
while true; do
  boot_state="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  if [[ "$boot_state" == "1" ]]; then
    break
  fi
  if (( boot_wait >= 600 )); then
    echo "ERROR: Android emulator did not finish booting within 600 seconds"
    adb devices -l || true
    exit 1
  fi
  sleep 3
  boot_wait=$((boot_wait + 3))
done

echo "Emulator boot completed; installing APK"
if [[ ! -s "$APK" ]]; then
  echo "ERROR: APK not found or empty: $APK"
  exit 1
fi

install_ok=0
for attempt in 1 2 3; do
  if adb install -r "$APK"; then
    install_ok=1
    break
  fi
  echo "ADB install attempt $attempt failed; restarting ADB connection"
  adb reconnect || true
  adb wait-for-device || true
  sleep 5
done
if [[ "$install_ok" != "1" ]]; then
  echo "ERROR: APK installation failed after 3 attempts"
  exit 1
fi

echo "Starting BatiPro DZ"
adb shell am force-stop "$PACKAGE"
adb shell am start -W -n "$ACTIVITY"

app_wait=0
app_pid=""
while [[ -z "$app_pid" ]]; do
  app_pid="$(adb shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r' || true)"
  if [[ -n "$app_pid" ]]; then
    break
  fi
  if (( app_wait >= 30 )); then
    echo "ERROR: BatiPro DZ process did not remain alive after launch"
    adb logcat -d -t 300 || true
    exit 1
  fi
  sleep 2
  app_wait=$((app_wait + 2))
done

echo "PASS: BatiPro DZ installed and launched successfully; PID=$app_pid"
