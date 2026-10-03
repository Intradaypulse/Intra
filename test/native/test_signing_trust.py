"""Check the release verifier accepts the configured signer and rejects others."""
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


@unittest.skipUnless(shutil.which('keytool') and shutil.which('jarsigner'), 'JDK signing tools required')
class SigningTrustTest(unittest.TestCase):
    def test_expected_self_signed_upload_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def run(*args, success=True):
                result = subprocess.run(args, cwd=root, capture_output=True, text=True)
                if success:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result

            for alias in ('expected', 'different'):
                run('keytool', '-genkeypair', '-keystore', f'{alias}.p12', '-storepass', 'test-password',
                    '-alias', alias, '-dname', f'CN={alias}', '-keyalg', 'RSA', '-validity', '3650')
                with zipfile.ZipFile(root / f'{alias}.jar', 'w') as jar:
                    jar.writestr('fixture.txt', 'PDFMate signing fixture')
                run('jarsigner', '-keystore', f'{alias}.p12', '-storepass', 'test-password', f'{alias}.jar', alias)
            run('keytool', '-exportcert', '-keystore', 'expected.p12', '-storepass', 'test-password',
                '-alias', 'expected', '-file', 'expected.cer')
            run('keytool', '-importcert', '-noprompt', '-keystore', 'trust.p12', '-storepass', 'test-password',
                '-alias', 'expected-upload', '-file', 'expected.cer')
            self.assertNotEqual(run('jarsigner', '-verify', '-strict', 'expected.jar', success=False).returncode, 0)
            verifier = ('jarsigner', '-verify', '-strict', '-certs', '-keystore', 'trust.p12', '-storepass', 'test-password')
            run(*verifier, 'expected.jar', 'expected-upload')
            self.assertNotEqual(run(*verifier, 'different.jar', 'expected-upload', success=False).returncode, 0)


if __name__ == '__main__':
    unittest.main()
