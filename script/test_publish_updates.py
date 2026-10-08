import tempfile
import subprocess
import base64
import unittest
from pathlib import Path
from publish_updates import make_feed
import xml.etree.ElementTree as ET

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'

class FeedTests(unittest.TestCase):
    def test_stable_version_architecture_signature_and_length(self):
        signature = 'A' * 86 + '=='
        xml = make_feed('0.1.7', 'arm64', signature, 123)
        root = ET.fromstring(xml)
        enclosure = root.find('./channel/item/enclosure')
        self.assertEqual(enclosure.attrib[SPARKLE + 'edSignature'], signature)
        self.assertEqual(enclosure.attrib[SPARKLE + 'version'], '0.1.7')
        self.assertEqual(enclosure.attrib['length'], '123')
        self.assertEqual(enclosure.attrib['url'], 'https://github.com/tamia6/AppDuo/releases/download/v0.1.7/AppDuo-arm64.dmg')
        self.assertNotIn('x86_64', xml)
    def test_crypto_verifier_accepts_rfc8032_vector_and_rejects_modified_data(self):
        public = base64.b64encode(bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')).decode()
        signature = base64.b64encode(bytes.fromhex('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b')).decode()
        verifier = Path(__file__).with_name('verify_update.swift')
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / 'archive'
            archive.write_bytes(b'')
            command = ['swift', str(verifier), public, str(archive), signature]
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            archive.write_bytes(b'tampered')
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)

    def test_mismatched_embedded_key_blocks_feed_publication(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'update-public-key-arm64.txt').write_text('one-key')
            (root / 'update-public-key-x86_64.txt').write_text('another-key')
            result = subprocess.run(['python3', str(Path(__file__).with_name('publish_updates.py')), '--version', '0.1.7', '--directory', folder, '--output', folder, '--public-key', 'one-key', '--private-key-file', 'not-used', '--sign-update', 'not-used'], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('embedded public key differs', result.stderr)
            self.assertFalse(list(root.glob('appcast-*.xml')))

    def test_rejects_prerelease_bad_signature_architecture_and_size(self):
        for values in [('0.1.7-beta', 'arm64', 'A' * 86 + '==', 1), ('0.1.7', 'arm64', 'bad', 1), ('0.1.7', 'unknown', 'A' * 86 + '==', 1), ('0.1.7', 'arm64', 'A' * 86 + '==', 0)]:
            with self.assertRaises(ValueError):
                make_feed(*values)

if __name__ == '__main__':
    unittest.main()
