"""Run against one explicitly selected, authorized USB phone; never an emulator."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True, help='Authorized adb USB device ID')
args = parser.parse_args()
if shutil.which('adb') is None or shutil.which('flutter') is None:
    raise SystemExit('Physical QA BLOCKED: install Android platform-tools and Flutter, then attach an authorized test phone.')
adb = ['adb', '-s', args.serial]
state = subprocess.run(adb + ['get-state'], capture_output=True, text=True)
if state.returncode != 0 or state.stdout.strip() != 'device':
    raise SystemExit('Physical QA BLOCKED: selected phone is missing, offline or unauthorized.')
def prop(name):
    return subprocess.check_output(adb + ['shell', 'getprop', name], text=True).strip()
if prop('ro.kernel.qemu') == '1' or prop('ro.boot.qemu') == '1':
    raise SystemExit('Physical QA rejects emulators.')
report = {'manufacturer': prop('ro.product.manufacturer'), 'model': prop('ro.product.model'),
          'android': prop('ro.build.version.release'), 'sdk': prop('ro.build.version.sdk'),
          'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
          'manual_checks': 'PENDING: rotation, visible torch, capture alignment, real background/resume, open exports'}
if not Path('buildapp/integration_test/app_smoke_test.dart').exists():
    raise SystemExit('Run python3 scripts/prepare_device_qa.py first.')
folder = Path('device-qa-results') / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
folder.mkdir(parents=True)
try:
    with (folder / 'flutter-test.log').open('w') as log:
        result = subprocess.run(['flutter', 'test', 'integration_test/app_smoke_test.dart',
            '-d', args.serial, '--dart-define=PDFMATE_PHYSICAL_QA=true', '--reporter', 'expanded'],
            cwd='buildapp', stdout=log, stderr=subprocess.STDOUT, timeout=1800)
    report['automated_result'] = 'passed' if result.returncode == 0 else 'failed'
except subprocess.TimeoutExpired:
    report['automated_result'] = 'timeout'
finally:
    # Scope diagnostics to this app where possible; do not dump unrelated app logs.
    pid = subprocess.run(adb + ['shell', 'pidof', 'com.pdfmateapp.pdfmate'], text=True, capture_output=True).stdout.strip()
    if pid.isdigit():
        with (folder / 'app-logcat.txt').open('w') as log:
            subprocess.run(adb + ['logcat', '-d', '--pid', pid], stdout=log, stderr=subprocess.STDOUT)
    with (folder / 'memory.txt').open('w') as log:
        subprocess.run(adb + ['shell', 'dumpsys', 'meminfo', 'com.pdfmateapp.pdfmate'], stdout=log)
    (folder / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
print(f"Automated tests: {report['automated_result']}. Manual checks still pending. Evidence: {folder}")
raise SystemExit(0 if report['automated_result'] == 'passed' else 1)
