"""Prepare owner-supplied production signing material without logging values."""
import base64
import hashlib
import os
from pathlib import Path
import subprocess
import sys


def main():
    names = ('YOMI_KEYSTORE_BASE64', 'YOMI_STORE_PASSWORD', 'YOMI_KEY_ALIAS', 'YOMI_KEY_PASSWORD')
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        sys.exit('Production signing settings unavailable: ' + ', '.join(missing))
    folder = Path(os.environ['RUNNER_TEMP']) / 'yomi-signing'
    folder.mkdir(mode=0o700, exist_ok=True)
    key = folder / 'release.jks'
    try:
        payload = base64.b64decode(''.join(os.environ['YOMI_KEYSTORE_BASE64'].split()), validate=True)
        key.write_bytes(payload)
        key.chmod(0o600)
        certificate = folder / 'certificate.der'
        result = subprocess.run([
            'keytool', '-exportcert', '-keystore', str(key),
            '-alias', os.environ['YOMI_KEY_ALIAS'],
            '-storepass:env', 'YOMI_STORE_PASSWORD', '-file', str(certificate),
        ], capture_output=True)
        if result.returncode:
            raise ValueError('Invalid keystore, alias or store password.')
        subject = subprocess.check_output([
            'openssl', 'x509', '-inform', 'DER', '-in', str(certificate),
            '-noout', '-subject', '-nameopt', 'RFC2253',
        ], text=True)
        if 'android debug' in subject.lower():
            raise ValueError('Android debug certificates cannot sign stable releases.')
        fingerprint = hashlib.sha256(certificate.read_bytes()).hexdigest()
        with open(os.environ['GITHUB_ENV'], 'a') as env:
            env.write(f'YOMI_KEYSTORE_PATH={key}\nYOMI_CERT_SHA256={fingerprint}\n')
        print('Production certificate SHA-256:', fingerprint)
    except Exception as error:
        # Never include subprocess output, passwords or key bytes in errors.
        key.unlink(missing_ok=True)
        sys.exit(f'Unable to prepare production signing: {type(error).__name__}. Check the four signing secrets.')


if __name__ == '__main__':
    main()
