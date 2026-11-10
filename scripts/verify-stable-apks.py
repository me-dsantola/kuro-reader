"""Reject wrong-identity/debug APKs and package checksummed release assets."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


ABI_CODES = {'armeabi-v7a': 1, 'arm64-v8a': 2, 'x86_64': 4}
APP_ID = 'com.kuroreader.kuro_reader'


def verify_metadata(badging, signature, version, build, fingerprint, abi):
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
    if not package or package.groups() != (APP_ID, str(ABI_CODES[abi] * 1000 + int(build)), version):
        raise ValueError('APK application ID or version does not match the stable source.')
    if not re.search(r"^application-label:'YOMI'$", badging, re.M):
        raise ValueError('Stable APK must display the YOMI app label.')
    if re.search(r'^application-debuggable', badging, re.M):
        raise ValueError('Stable APK must not be debuggable.')
    native = re.search(r"^native-code: '([^']+)'", badging, re.M)
    if not native or native.group(1) != abi:
        raise ValueError('APK native architecture does not match the filename.')
    digests = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9:]+)', signature, re.M)
    normalized = [value.replace(':', '').lower() for value in digests]
    if normalized != [fingerprint.lower()] or 'android debug' in signature.lower():
        raise ValueError('APK does not use the expected permanent production certificate.')


def main():
    version_match = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)\s*$', Path('pubspec.yaml').read_text(), re.M)
    if not version_match:
        raise ValueError('Stable version must have a numeric version and build number.')
    version, build = version_match.groups()
    sdk = Path(os.environ.get('ANDROID_HOME') or os.environ['ANDROID_SDK_ROOT'])
    candidates = [p for p in (sdk / 'build-tools').iterdir() if re.fullmatch(r'\d+(\.\d+)*', p.name)]
    tools = max(candidates, key=lambda p: tuple(map(int, p.name.split('.'))))
    output = Path('release-assets')
    output.mkdir(exist_ok=True)
    manifest = {'version': version, 'build': int(build), 'commit': os.environ['GITHUB_SHA'],
                'applicationId': APP_ID, 'certificateSha256': os.environ['YOMI_CERT_SHA256'], 'apks': []}
    for abi in ABI_CODES:
        apk = Path(f'build/app/outputs/flutter-apk/app-{abi}-release.apk')
        badging = subprocess.check_output([str(tools / 'aapt'), 'dump', 'badging', str(apk)], text=True)
        signature = subprocess.check_output([str(tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
        verify_metadata(badging, signature, version, build, manifest['certificateSha256'], abi)
        name = f'YOMI-{version}-{abi}.apk'
        shutil.copyfile(apk, output / name)
        manifest['apks'].append({'file': name, 'abi': abi, 'androidVersionCode': ABI_CODES[abi] * 1000 + int(build), 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest()})
    (output / 'release.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (output / 'SHA256SUMS.txt').write_text(''.join(f"{entry['sha256']}  {entry['file']}\n" for entry in manifest['apks']))
    with open(os.environ['GITHUB_OUTPUT'], 'a') as values:
        values.write(f'version={version}\n')
    print(f'Verified YOMI {version} (build {build}): three stable APKs with the expected certificate.')


if __name__ == '__main__':
    main()
