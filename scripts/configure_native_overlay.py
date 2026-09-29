"""Install the reviewed Android bridge in the generated Flutter project."""
from pathlib import Path
import shutil
root = Path('buildapp')
target = root / 'android/app/src/main/kotlin/com/pdfmateapp/pdfmate/MainActivity.kt'
target.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile('android_native/MainActivity.kt', target)
gradle = root / 'android/app/build.gradle.kts'
s = gradle.read_text()
s += '\ndependencies { implementation("com.tom-roush:pdfbox-android:2.0.27.0") }\n'
gradle.write_text(s)

# Flutter 3.47+/AGP 9: use Android's built-in Kotlin. Current FlutterFire
# and pdfx releases explicitly honor this property; do not suppress warnings.
import re
s = gradle.read_text()
s = re.sub(r'^\s*id\("(?:kotlin-android|org.jetbrains.kotlin.android)"\)\s*$', '', s, flags=re.M)
s = re.sub(r'\n\s*kotlinOptions\s*\{[^{}]*\}', '', s)
gradle.write_text(s)
properties = root / 'android/gradle.properties'
p = properties.read_text()
p = re.sub(r'^android.builtInKotlin=.*\n?', '', p, flags=re.M)
properties.write_text(p + '\nandroid.builtInKotlin=true\n')

# Audit actual configured plugins. Flutter 3.47's source-text detector also
# warns about conditional legacy fallbacks that are never applied in this mode.
with gradle.open('a') as out:
    out.write('''
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
gradle.projectsEvaluated {
    val legacy = rootProject.allprojects.filter {
        it.plugins.hasPlugin("org.jetbrains.kotlin.android") || it.plugins.hasPlugin("kotlin-android")
    }
    check(legacy.isEmpty()) { "Legacy Kotlin Android plugin still applied: ${legacy.map { it.path }}" }
    logger.lifecycle("PDFMate: verified built-in Kotlin; no legacy Kotlin Android plugin applied")
}
''')
