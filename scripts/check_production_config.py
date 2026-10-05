"""Report configuration names only; never print values or credential material."""
import argparse
import base64
import json
import os
import re
from urllib.parse import urlsplit

SIGNING = ['ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD', 'ANDROID_UPLOAD_CERT_SHA256']
ADS = ['ADMOB_APP_ID', 'ADMOB_BANNER_ID', 'ADMOB_INTERSTITIAL_ID', 'ADMOB_REWARDED_ID', 'ADMOB_APP_OPEN_ID']
FIREBASE = ['FIREBASE_API_KEY', 'FIREBASE_APP_ID', 'FIREBASE_PROJECT_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_STORAGE_BUCKET']
PUBLIC = ['PDFMATE_OPERATOR_NAME', 'PDFMATE_PRIVACY_EMAIL', 'PDFMATE_PRIVACY_URL']

def inspect(env):
    fields = SIGNING + ADS + FIREBASE + PUBLIC
    missing = [name for name in fields if not env.get(name, '').strip()]
    invalid = []
    for name in ADS:
        value = env.get(name, '')
        pattern = r'ca-app-pub-[0-9]+~[0-9]+' if name == 'ADMOB_APP_ID' else r'ca-app-pub-[0-9]+/[0-9]+'
        if value and (not re.fullmatch(pattern, value) or '3940256099942544' in value):
            invalid.append(name)
    value = env.get('ANDROID_UPLOAD_CERT_SHA256', '')
    if value and not re.fullmatch(r'[0-9a-fA-F]{64}', value.replace(':', '')):
        invalid.append('ANDROID_UPLOAD_CERT_SHA256')
    value = env.get('ANDROID_KEYSTORE_BASE64', '')
    if value:
        try:
            if not base64.b64decode(value, validate=True):
                invalid.append('ANDROID_KEYSTORE_BASE64')
        except ValueError:
            invalid.append('ANDROID_KEYSTORE_BASE64')
    value = env.get('PDFMATE_PRIVACY_EMAIL', '')
    if value and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', value):
        invalid.append('PDFMATE_PRIVACY_EMAIL')
    value = env.get('PDFMATE_PRIVACY_URL', '')
    if value:
        try:
            url = urlsplit(value)
            if url.scheme != 'https' or not url.hostname or url.username or url.password:
                invalid.append('PDFMATE_PRIVACY_URL')
        except ValueError:
            invalid.append('PDFMATE_PRIVACY_URL')
    return {'ready': not missing and not invalid, 'missing': missing, 'invalid': invalid,
            'configured': [name for name in fields if name not in missing and name not in invalid]}

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--report-only', action='store_true')
    args = parser.parse_args()
    result = inspect(os.environ)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if args.report_only or result['ready'] else 1)
