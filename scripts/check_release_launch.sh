#!/usr/bin/env bash
set -euo pipefail
apk="$1"
package=com.pdfmateapp.pdfmate
mkdir -p release-launch-logs
adb install -r -g "$apk"
for attempt in 1 2; do
  adb logcat -c
  adb shell am force-stop "$package"
  adb shell am start -W -n "$package/.MainActivity" > "release-launch-logs/start-$attempt.txt"
  # Wait past native/plugin initialization and first-frame rendering.
  sleep 15
  adb logcat -d -v threadtime > "release-launch-logs/logcat-$attempt.txt"
  if ! adb shell pidof "$package" | tr -d '\r' > "release-launch-logs/pid-$attempt.txt"; then
    cat "release-launch-logs/logcat-$attempt.txt"
    exit 1
  fi
  test -s "release-launch-logs/pid-$attempt.txt"
  adb shell dumpsys activity activities > "release-launch-logs/activities-$attempt.txt"
  adb exec-out screencap -p > "release-launch-logs/screen-$attempt.png"
done
python3 scripts/verify_release_launch_logs.py release-launch-logs
