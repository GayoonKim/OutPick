"""정상 Development 실기기 산출물의 공개 환경·기존 서명만 확인한다."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--app', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
app = Path(args.app)
output = Path(args.output)
try:
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    firebase = plistlib.loads((app / 'GoogleService-Info.plist').read_bytes())
    signed = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True)
    cms = subprocess.run(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')], capture_output=True, check=True)
    profile = plistlib.loads(cms.stdout)
    device = os.environ['OUTPICK_QA_DEVICE_UDID']
    checks = {
        'codesignValid': signed.returncode == 0,
        'developmentBundle': info.get('CFBundleIdentifier') == 'GayoonKim.OutPick.dev',
        'developmentEnvironment': info.get('OUTPICK_ENVIRONMENT') == 'development',
        'expectedProject': info.get('OUTPICK_EXPECTED_FIREBASE_PROJECT_ID') == 'outpick-test',
        'firebaseProject': firebase.get('PROJECT_ID') == 'outpick-test',
        'expectedStorageBucket': firebase.get('STORAGE_BUCKET') == 'outpick-test.firebasestorage.app',
        'noLocalDeviceMarker': info.get('OutPickBrandLocalDeviceBuild') is not True,
        'noATSExceptions': not info.get('NSAppTransportSecurity', {}).get('NSExceptionDomains'),
        'deviceInExistingProfile': device in profile.get('ProvisionedDevices', []),
        'profileNotExpired': profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
    }
    sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    report = {'schemaVersion': 1, 'checks': checks, 'checksCount': len(checks),
              'allPassed': all(checks.values()), 'executableSHA256': sha(app / info['CFBundleExecutable']),
              'profileSHA256': sha(app / 'embedded.mobileprovision'),
              'profileContentsOrCredentialsRecorded': False, 'newProfileIssued': False,
              'deviceExecutableDirectlyHashed': False}
    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    output.write_text(json.dumps(report, indent=2) + '\n')
    output.chmod(0o600)
    print(json.dumps({'verdict': 'passed' if report['allPassed'] else 'failed', 'checksCount': len(checks),
                      'failedChecks': [key for key, value in checks.items() if not value]}))
    raise SystemExit(0 if report['allPassed'] else 2)
except (OSError, ValueError, KeyError, subprocess.SubprocessError):
    print('실기기 산출물·서명·지정 환경 근거를 확인하지 못했습니다.')
    raise SystemExit(2)
