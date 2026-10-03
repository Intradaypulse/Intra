"""Fail closed when release launch diagnostics are missing or show a crash."""
from pathlib import Path
import re
import sys


def verify(root):
    root = Path(root)
    for attempt in (1, 2):
        pid = (root / f'pid-{attempt}.txt').read_text().strip()
        start = (root / f'start-{attempt}.txt').read_text()
        log = (root / f'logcat-{attempt}.txt').read_text(errors='replace')
        if not pid.isdigit() or 'Status: ok' not in start or 'LaunchState: COLD' not in start:
            raise ValueError(f'Release cold launch {attempt} did not complete')
        if re.search(r'FATAL EXCEPTION|Fatal signal|Unable to start activity|Unable to instantiate activity', log):
            raise ValueError(f'Fatal startup log in launch {attempt}')
        if 'Displayed com.pdfmateapp.pdfmate/.MainActivity' not in log:
            raise ValueError(f'No displayed PDFMate activity in launch {attempt}')
    print('Verified two cold launches, live processes, displayed activities and no fatal logs')


if __name__ == '__main__':
    try:
        verify(sys.argv[1])
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
