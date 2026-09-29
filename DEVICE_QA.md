# Physical Android release gate

No Samsung, Xiaomi, Pixel or OnePlus physical device has been exercised by this change. Emulator results do not complete this gate.

On a trusted workstation with Java 17, Flutter 3.47.5+, Android SDK 36 and USB debugging authorized on a **test phone**, check out the PR commit and run:

```sh
python3 scripts/prepare_device_qa.py
adb devices
python3 scripts/run_physical_qa.py --serial DEVICE_ID
```

Grant camera/storage permission when prompted. The runner rejects emulators, records the device model, Android version and tested commit, and saves integration logs and app memory diagnostics. It tests camera initialization, lifecycle callbacks, torch API on/off, Downloads/Gallery exports and PDF preservation. Passing these automated checks leaves the manual checks explicitly pending.

For each OEM, record model, OS, commit, pass/fail and evidence for:

| Check | Required observation |
| --- | --- |
| Camera and rotation | Capture a printed page upright and after rotating the phone through 90/180/270°. Preview, detected corners, crop and exported page agree; no mirrored or sideways crop. The app UI stays portrait. |
| Torch | Light physically switches on and off, including after opening the camera again. |
| Background/resume | Press Home while scanning, return after 30 seconds, repeat five times; also lock/unlock. Preview and shutter recover; no camera-in-use error or spontaneous capture. |
| Crop cancellation | Take a page, cancel manual crop, reopen scanner. No abandoned camera photos remain in app temporary storage. |
| Downloads/Gallery | Open exported PDF/JPEG in the system Files/Gallery app; verify complete contents and retry after a denied permission. Test scoped storage and an Android 24–28 phone if supported. |
| OCR layout | Hindi samples with rotated lines, two columns, tables and mixed existing text: search each word and inspect selection placement/order. Arabic/Hebrew recognition is unsupported by the current ML Kit recognizer. |
| Large OCR | Run a representative 300+ page Hindi scan with adequate disk space. Record source/output sizes, free space and peak memory. Cancel once and retry; no partial output should be shown. |

Keep failed devices as failures. Do not turn a pending observation into a pass based on a successful build. Share only app diagnostics from a test phone; review logs before uploading.
