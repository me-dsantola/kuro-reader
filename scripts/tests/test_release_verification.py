import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('verification', Path(__file__).resolve().parents[1] / 'verify-stable-apks.py')
verification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verification)


class StableArtifactTests(unittest.TestCase):
    def setUp(self):
        self.badging = "package: name='com.kuroreader.kuro_reader' versionCode='2008' versionName='1.2.0'\napplication-label:'YOMI'\nnative-code: 'arm64-v8a'\n"
        self.fingerprint = 'a' * 64
        self.signature = f'Signer #1 certificate DN: CN=YOMI Release\nSigner #1 certificate SHA-256 digest: {self.fingerprint}\n'

    def verify(self, badging=None, signature=None):
        verification.verify_metadata(badging or self.badging, signature or self.signature, '1.2.0', '8', self.fingerprint, 'arm64-v8a')

    def test_matching_production_apk_passes(self):
        self.verify()

    def test_v31_sdk_range_format_passes_with_exact_production_certificate(self):
        self.verify(signature=self.signature.replace('Signer #1', 'Signer (minSdkVersion=33, maxSdkVersion=2147483647)'))

    def test_v31_development_sdk_range_format_passes(self):
        self.verify(signature=self.signature.replace('Signer #1', 'Signer (minSdkVersion=33 (dev release=true), maxSdkVersion=2147483647)'))

    def test_multiple_sdk_ranges_must_all_use_the_same_production_certificate(self):
        newer = self.signature.replace('Signer #1', 'Signer (minSdkVersion=33, maxSdkVersion=2147483647)')
        older = self.signature.replace('Signer #1', 'Signer (minSdkVersion=24, maxSdkVersion=32)')
        self.verify(signature=newer + older)
        with self.assertRaises(ValueError):
            self.verify(signature=newer + older.replace(self.fingerprint, 'b' * 64))

    def test_unknown_signer_format_cannot_be_ignored(self):
        with self.assertRaises(ValueError):
            self.verify(signature=self.signature + self.signature.replace('Signer #1', 'Signer unsupported'))

    def test_mixed_signer_formats_are_rejected(self):
        with self.assertRaises(ValueError):
            self.verify(signature=self.signature + self.signature.replace('Signer #1', 'Signer (minSdkVersion=33, maxSdkVersion=2147483647)'))

    def test_missing_certificate_output_is_rejected(self):
        with self.assertRaises(ValueError):
            self.verify(signature='Verifies\n')

    def test_beta_identity_is_rejected(self):
        with self.assertRaises(ValueError):
            self.verify(self.badging.replace("kuro_reader'", "kuro_reader.beta'"))

    def test_beta_label_is_rejected(self):
        with self.assertRaises(ValueError):
            self.verify(self.badging.replace("application-label:'YOMI'", "application-label:'YOMI Beta'"))

    def test_wrong_version_or_build_is_rejected(self):
        for badging in (self.badging.replace('1.2.0', '1.1.5'), self.badging.replace('2008', '2007')):
            with self.assertRaises(ValueError):
                self.verify(badging)

    def test_debuggable_apk_is_rejected(self):
        with self.assertRaises(ValueError):
            self.verify(self.badging + 'application-debuggable\n')

    def test_debug_certificate_is_rejected_even_if_fingerprint_matches(self):
        with self.assertRaises(ValueError):
            self.verify(signature=self.signature.replace('YOMI Release', 'Android Debug'))

    def test_wrong_or_extra_certificate_is_rejected(self):
        for signature in (self.signature.replace('a' * 64, 'b' * 64), self.signature + f'Signer #2 certificate SHA-256 digest: {self.fingerprint}\n'):
            with self.assertRaises(ValueError):
                self.verify(signature=signature)

    def test_mislabeled_architecture_is_rejected(self):
        with self.assertRaises(ValueError):
            self.verify(self.badging.replace('arm64-v8a', 'x86_64'))


if __name__ == '__main__':
    unittest.main()
