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
| Camera and rotation | Test manual and automatic capture of a printed page upright and after rotating the phone through 90/180/270°. Preview, detected corners, crop and exported page agree; no mirrored or sideways crop. The app UI stays portrait. |
| Torch | Light physically switches on and off, including after opening the camera again. |
| Background/resume | Press Home while scanning, return after 30 seconds, repeat five times; also lock/unlock. Preview and shutter recover; no camera-in-use error or spontaneous capture. |
| Crop cancellation | Take a page, cancel manual crop, reopen scanner. No abandoned camera photos remain in app temporary storage. |
| Downloads/Gallery | Open exported PDF/JPEG in the system Files/Gallery app; verify complete contents and retry after a denied permission. Test scoped storage and an Android 24–28 phone if supported. |
| OCR layout | Hindi samples with rotated lines, two columns, tables and mixed existing text: search each word and inspect selection placement/order. Arabic/Hebrew recognition is unsupported by the current ML Kit recognizer. |
| Large OCR | Run a representative 300+ page Hindi scan with adequate disk space. Record source/output sizes, free space and peak memory. Cancel once and retry; no partial output should be shown. |

Keep failed devices as failures. Do not turn a pending observation into a pass based on a successful build. Share only app diagnostics from a test phone; review logs before uploading.

## Real document corpus (separate from generated fixtures)
Prepare a debug test installation, then run:

```
python3 scripts/run_document_corpus.py --serial DEVICE_ID --corpus /path/to/consented-test-documents
```

The folder must contain real PDFs and `corpus.json`, for example:

```json
[{"file":"hindi-columns.pdf","script":"devanagiri","pages":300,"tableRows":false,
  "checks":[{"page":0,"orderedText":["पहला","दूसरा"]},
            {"page":299,"orderedText":["अंतिम"]}]}]
```

Page indices are zero based. Use independently checked expected words, not output
from the OCR under test. Include 300, 500 and 1000-page scans, columns, tables,
90/180/270-degree scans and mixed scripts. This runner checks page count and
expected reading order; manually inspect selection bounding boxes. It does not
claim character-error accuracy or physical-device coverage from synthetic tests.
Arabic/Hebrew are explicitly rejected until a capable recognizer is integrated.

Low-space: the Hindi native writer now checks free space before processing. Verify
on an isolated low-storage emulator, then free space and retry. Do not fill a
personal phone to test this. A preflight reserve cannot guarantee success if
another application consumes disk space concurrently.

Process death: kill the test application during OCR, relaunch, and inspect private
cache for abandoned `pdfmate_overlay_*` and `pdfmate_secure_tmp_*` files. Confirm
original document opens and no partial new document is listed. Interrupted jobs
are not resumable; rerun the job. Record actual observations before marking pass.

## Native-save cancellation gate
While saving a large Hindi searchable copy, tap Cancel. Confirm the source remains
unchanged, no output is listed, and native scratch is removed. The writer checks
cancellation between 16 KiB writes, including PDFBox's incremental source copy;
verification also checks during text-position processing. A pending OS write or
PDF parser work between checkpoints can still take time; this is not a hard
wall-clock cancellation deadline. Repeat and confirm a subsequent save succeeds.
