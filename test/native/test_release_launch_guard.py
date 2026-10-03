import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('guard', Path(__file__).parents[2] / 'scripts/verify_release_launch_logs.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class ReleaseLaunchGuardTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for attempt in (1, 2):
            (self.root / f'pid-{attempt}.txt').write_text('1234\n')
            (self.root / f'start-{attempt}.txt').write_text('Status: ok\nLaunchState: COLD\n')
            (self.root / f'logcat-{attempt}.txt').write_text('Displayed com.pdfmateapp.pdfmate/.MainActivity\n')

    def test_valid_launches(self):
        guard.verify(self.root)

    def test_fatal_in_second_launch_is_rejected(self):
        with (self.root / 'logcat-2.txt').open('a') as out:
            out.write('FATAL EXCEPTION: main\n')
        with self.assertRaises(ValueError):
            guard.verify(self.root)

    def test_missing_log_is_rejected(self):
        (self.root / 'logcat-1.txt').unlink()
        with self.assertRaises(OSError):
            guard.verify(self.root)

    def test_alive_process_without_display_is_rejected(self):
        (self.root / 'logcat-2.txt').write_text('starting but no first frame\n')
        with self.assertRaises(ValueError):
            guard.verify(self.root)


if __name__ == '__main__':
    unittest.main()
