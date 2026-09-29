"""Generate the same Android app for attached-device QA (Flutter 3.47+)."""
from pathlib import Path
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
if Path.cwd() != root:
    raise SystemExit('Run this script from the repository root.')
subprocess.run(['flutter', 'create', '--platforms=android', '--org', 'com.pdfmateapp',
                '--project-name', 'pdfmate', 'buildapp'], check=True)
shutil.copyfile('src/pubspec.yaml', 'buildapp/pubspec.yaml')
for file in Path('src').glob('*.dart'):
    shutil.copyfile(file, Path('buildapp/lib') / file.name)
for directory in ['integration_test', 'test']:
    shutil.copytree(directory, Path('buildapp') / directory, dirs_exist_ok=True)
shutil.copytree('src/assets', 'buildapp/assets', dirs_exist_ok=True)
Path('buildapp/test/widget_test.dart').unlink(missing_ok=True)
subprocess.run([sys.executable, 'scripts/configure_native_overlay.py'], check=True)
android = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', android)
manifest = Path('buildapp/android/app/src/main/AndroidManifest.xml')
tree = ET.parse(manifest)
element = tree.getroot()
for name, limit in [('CAMERA', None), ('WRITE_EXTERNAL_STORAGE', '28'), ('READ_EXTERNAL_STORAGE', '32')]:
    attributes = {f'{{{android}}}name': f'android.permission.{name}'}
    if limit:
        attributes[f'{{{android}}}maxSdkVersion'] = limit
    if not any(p.get(f'{{{android}}}name') == attributes[f'{{{android}}}name'] for p in element.findall('uses-permission')):
        ET.SubElement(element, 'uses-permission', attributes)
app = element.find('application')
ET.SubElement(app, 'meta-data', {f'{{{android}}}name': 'com.google.android.gms.ads.APPLICATION_ID',
    f'{{{android}}}value': 'ca-app-pub-3940256099942544~3347511713'})
tree.write(manifest, encoding='unicode')
gradle = Path('buildapp/android/app/build.gradle.kts')
s = gradle.read_text().replace('compileSdk = flutter.compileSdkVersion', 'compileSdk = 36')
s = s.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
s = s.replace('targetSdk = flutter.targetSdkVersion', 'targetSdk = 36')
s += '\ndependencies {\n' + ''.join(f'    implementation("com.google.mlkit:text-recognition-{language}:16.0.1")\n'
    for language in ['chinese', 'devanagari', 'japanese', 'korean']) + '}\n'
gradle.write_text(s)
subprocess.run(['flutter', 'pub', 'get'], cwd='buildapp', check=True)
