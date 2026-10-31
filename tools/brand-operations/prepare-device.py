"""승인된 version2 HTTPS 중계의 읽기 확인과 전용 빌드/런타임 파일 준비. 서버는 변경하지 않는다."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
from datetime import datetime, timezone, timedelta


def sha(data):
    return hashlib.sha256(data).hexdigest()


def prepare(pointer_path, output, stage=None):
    pointer = json.loads(pointer_path.read_bytes())
    ready_path = Path(pointer['readyPath'])
    raw = ready_path.read_bytes()
    assert sha(raw) == pointer['readySHA256'], '중계 pointer SHA 불일치'
    relay = json.loads(raw)
    assert not (ready_path.parent / 'shutdown.json').exists(), '중계 종료 기록 있음'
    assert relay['status'] == 'ready' and relay['scope'] == 'ios-single-device-read-relay'
    assert relay['projectID'] == 'outpick-test' and relay['region'] == 'asia-northeast3'
    assert relay['tenantID'] is None and relay['timeLimit'] is None
    assert relay['allowedPeerIP'] == '192.168.123.169'
    assert relay['roundID'] == '49fd2792-eca0-45b8-b711-e72b9124add4'
    assert relay['stopsOnQAComplete'] is True and relay['expiresOnUSBDisconnect'] is False
    assert relay['automaticallyRestarts'] is False and relay['credentialsIncluded'] is False
    assert relay['userUID'] == 'fixture-user'
    assert relay['groupID'] == 'ba0b02d1d3f1c0a889226d2060165c63'
    assert relay['brandID'] == '668fefda94c3ac1055720b1823256703a38a3966de214f5a7989683c199d189c'
    assert relay['seasonID'] == 'local-l159-first-season'
    os.kill(relay['pid'], 0)
    assert set(relay['endpoints']) == {'auth', 'functions', 'firestore', 'storage'}
    ports = []
    for address in relay['endpoints'].values():
        host, port = address.split(':')
        assert host == '192.168.123.110' and str(int(port)) == port and 1024 <= int(port) <= 65535
        ports.append(port)
        listener = subprocess.run(['lsof', '-nP', '-iTCP:' + port, '-sTCP:LISTEN', '-t'],
                                  capture_output=True, text=True, check=True)
        assert set(listener.stdout.split()) == {str(relay['pid'])}, '중계 리스너 소유 불일치'
    assert len(set(ports)) == 4
    assert relay['connectionVersion'] == 2, '실기기는 HTTPS version2만 허용한다'
    assert relay['functionsBaseURL'] == 'https://' + relay['endpoints']['functions'] + '/outpick-test/asia-northeast3'
    tls = relay['functionsTLS']
    certificate_path = Path(tls['publicRootCertificatePath'])
    assert certificate_path.suffix == '.cer'
    certificate_raw = certificate_path.read_bytes()
    assert sha(certificate_raw) == tls['publicRootSHA256']
    assert tls['rootFingerprint256'].replace(':', '').lower() == tls['publicRootSHA256']
    certificate = subprocess.run(['openssl', 'x509', '-inform', 'DER', '-in', str(certificate_path),
                                  '-noout', '-enddate', '-fingerprint', '-sha256'],
                                 capture_output=True, text=True, check=True).stdout.splitlines()
    actual_expiry = datetime.strptime(certificate[0].split('=', 1)[1], '%b %d %H:%M:%S %Y GMT').replace(tzinfo=timezone.utc)
    expected_expiry = datetime.fromisoformat(tls['validUntil'].replace('Z', '+00:00'))
    assert actual_expiry == expected_expiry and datetime.now(timezone.utc) < actual_expiry <= datetime.now(timezone.utc) + timedelta(days=31)
    assert certificate[1].split('=', 1)[1] == tls['rootFingerprint256']
    target_raw = Path(relay['targetPath']).read_bytes()
    assert sha(target_raw) == relay['targetSHA256'] == 'da65cb05b578dc48e71508b56b8a51f8537fe9572cf2ce43e706d7a00e336484'
    target = json.loads(target_raw)
    assert target['projectID'] == 'outpick-test' and target['region'] == 'asia-northeast3'
    assert target['allRequiredServicesLocal'] is True and target['inheritedCredentials'] is False
    assert Path(target['directory']).name == relay['roundID']
    storage_raw = Path(relay['sourceStorageTargetPath']).read_bytes()
    storage = json.loads(storage_raw)
    assert storage['targetSHA256'] == relay['targetSHA256'] and storage['roundID'] == relay['roundID']
    assert storage['firestoreHost'] == target['firestoreHost']
    login_path = Path(relay['generalUserLoginPath'])
    assert login_path.stat().st_mode & 0o777 == 0o600
    login_raw = login_path.read_bytes()
    login = json.loads(login_raw)
    assert set(login) == {'projectID', 'user', 'password', 'tenantID', 'syntheticLocalOnly'}
    assert login['syntheticLocalOnly'] is True and login['projectID'] == 'outpick-test' and login['tenantID'] is None
    assert login['user']['uid'] == relay['userUID'] and login['user']['email'] and login['password']
    output.mkdir(parents=True, exist_ok=True)
    info = plistlib.loads(Path('OutPick/Info.plist').read_bytes())
    # HTTP 예외는 ignored 검사 plist에만 생성한다. 제품 plist/타깃에는 저장하지 않는다.
    info['NSAppTransportSecurity'] = {'NSAllowsArbitraryLoads': True}
    info['OutPickBrandLocalDeviceBuild'] = True
    (output / 'DeviceQA-Info.plist').write_bytes(plistlib.dumps(info))
    observation = {'roundID': relay['roundID'], 'relayPID': relay['pid'], 'readyPath': str(ready_path),
                   'readySHA256': sha(raw), 'targetSHA256': sha(target_raw), 'endpoints': relay['endpoints'],
                   'allowedPeerIP': relay['allowedPeerIP'], 'listenerOwnershipVerified': True,
                   'shutdownAbsent': True, 'loginMode600': True, 'credentialsIncluded': False,
                   'connectionVersion': 2, 'functionsBaseURL': relay['functionsBaseURL'],
                   'publicRootSHA256': sha(certificate_raw), 'certificateValidUntil': tls['validUntil'],
                   'runtimeStaged': stage is not None}
    (output / 'relay-observation.json').write_text(json.dumps(observation, indent=2) + '\n')
    if stage is not None:
        stage = stage.resolve()
        assert str(stage).startswith('/private/tmp/outpick-device-'), '런타임 자료는 전용 임시 폴더에만 준비한다'
        stage.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(stage, 0o700)
        for name, data in [('target.json', target_raw), ('storage-target.json', storage_raw),
                           ('device-target.json', raw), ('accepted-relay-sha256.txt', sha(raw).encode()),
                           ('login.private.json', login_raw), ('public-root.cer', certificate_raw)]:
            path = stage / name
            path.write_bytes(data)
            os.chmod(path, 0o600)
    print(json.dumps(observation, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--pointer', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--stage', type=Path)
    args = parser.parse_args()
    prepare(args.pointer, args.output, args.stage)
