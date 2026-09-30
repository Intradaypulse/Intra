"""Install a corpus into a test app's private directory and run actual OCR.
Requires prepare_device_qa.py and an installed DEBUG PDFMate on an authorized
Android test device. Existing app documents are not touched.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--corpus', type=Path, required=True)
args = parser.parse_args()
cases = json.loads((args.corpus / 'corpus.json').read_text())
if not cases:
    raise SystemExit('Corpus is empty; QA cannot pass.')
files = ['corpus.json']
for case in cases:
    name = case['file']
    if not re.fullmatch(r'[A-Za-z0-9_.-]+\.pdf', name):
        raise SystemExit('Invalid corpus filename')
    if case['script'] not in ('latin', 'devanagiri', 'chinese', 'japanese', 'korean'):
        raise SystemExit('Unsupported OCR script. Arabic/Hebrew require another engine.')
    if not case.get('checks'):
        raise SystemExit('Every document needs expected-text checks.')
    files.append(name)
adb = ['adb', '-s', args.serial]
package = 'com.pdfmateapp.pdfmate'
subprocess.run(adb + ['shell', 'run-as', package, 'mkdir', '-p', 'app_flutter/qa'], check=True)
for name in set(files):
    with (args.corpus / name).open('rb') as source:
        subprocess.run(adb + ['shell', 'run-as', package, 'sh', '-c',
            f'"cat > app_flutter/qa/{name}"'], stdin=source, check=True)
try:
    subprocess.run(['flutter', 'test', 'integration_test/document_corpus_test.dart',
        '-d', args.serial, '--reporter', 'expanded'], cwd='buildapp', check=True)
finally:
    # Delete only the dedicated corpus files, never user documents.
    for name in set(files):
        subprocess.run(adb + ['shell', 'run-as', package, 'rm', '-f', f'app_flutter/qa/{name}'], check=True)
