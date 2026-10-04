import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('production_config', ROOT / 'scripts/check_production_config.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)

class ProductionConfigTest(unittest.TestCase):
    def valid(self):
        fields = config.SIGNING + config.ADS + config.FIREBASE + config.PUBLIC
        env = {name: 'sensitive_test_value' for name in fields}
        env.update(ANDROID_KEYSTORE_BASE64='Ynl0ZXM=', ANDROID_UPLOAD_CERT_SHA256='ab' * 32,
                   PDFMATE_PRIVACY_EMAIL='support@example.com', PDFMATE_PRIVACY_URL='https://example.com/privacy')
        for name in config.ADS:
            env[name] = 'ca-app-pub-1234567890123456' + ('~' if name == 'ADMOB_APP_ID' else '/') + '1234567890'
        return env
    def test_missing_secrets_are_named_without_values(self):
        result = config.inspect({})
        self.assertFalse(result['ready'])
        self.assertIn('ANDROID_KEYSTORE_BASE64', result['missing'])
    def test_valid_configuration_passes_and_values_are_redacted(self):
        env = self.valid()
        result = config.inspect(env)
        self.assertTrue(result['ready'])
        encoded = json.dumps(result)
        for value in env.values():
            self.assertNotIn(value, encoded)
    def test_test_ads_invalid_pin_contact_and_url_are_rejected(self):
        env = self.valid()
        env.update(ADMOB_APP_ID='ca-app-pub-3940256099942544~3347511713',
                   ANDROID_UPLOAD_CERT_SHA256='bad', PDFMATE_PRIVACY_EMAIL='bad',
                   PDFMATE_PRIVACY_URL='http://example.com/privacy')
        self.assertEqual(set(config.inspect(env)['invalid']),
                         {'ADMOB_APP_ID', 'ANDROID_UPLOAD_CERT_SHA256', 'PDFMATE_PRIVACY_EMAIL', 'PDFMATE_PRIVACY_URL'})

if __name__ == '__main__': unittest.main()
