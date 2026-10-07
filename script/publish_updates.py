#!/usr/bin/env python3
"""Produce separate authenticated Sparkle appcasts for a stable release."""
import argparse
import base64
import re
import subprocess
from pathlib import Path
import xml.etree.ElementTree as ET

NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)


def make_feed(version, arch, signature, length):
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        raise ValueError('A stable major.minor.patch version is required')
    if arch not in ('arm64', 'x86_64') or length <= 0:
        raise ValueError('Invalid architecture or archive size')
    try:
        if len(base64.b64decode(signature, validate=True)) != 64:
            raise ValueError('Invalid Ed25519 signature length')
    except Exception as error:
        raise ValueError('Invalid Ed25519 signature') from error
    root = ET.Element('rss', version='2.0')
    channel = ET.SubElement(root, 'channel')
    ET.SubElement(channel, 'title').text = 'AppDuo updates'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = 'AppDuo ' + version
    ET.SubElement(item, '{' + NS + '}minimumSystemVersion').text = '14.0'
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/tamia6/AppDuo/releases/download/v{version}/AppDuo-{arch}.dmg',
        'length': str(length), 'type': 'application/octet-stream',
        '{' + NS + '}version': version, '{' + NS + '}shortVersionString': version,
        '{' + NS + '}edSignature': signature,
    })
    return ET.tostring(root, encoding='unicode', xml_declaration=True) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sign-update', required=True)
    parser.add_argument('--private-key-file', required=True)
    parser.add_argument('--public-key', required=True)
    args = parser.parse_args()
    # Compare keys extracted from both built DMGs, not just mutable CI variables.
    for arch in ("arm64", "x86_64"):
        embedded = (args.directory / f"update-public-key-{arch}.txt").read_text().strip()
        if embedded != args.public_key:
            raise ValueError(f"{arch} embedded public key differs from release signing configuration")
    # Produce both feeds before writing either: an incomplete release is not published.
    feeds = {}
    for arch in ('arm64', 'x86_64'):
        archive = args.directory / f'AppDuo-{arch}.dmg'
        result = subprocess.run([args.sign_update, '--ed-key-file', args.private_key_file, '-p', str(archive)], check=True, capture_output=True, text=True)
        signature = result.stdout.strip()
        subprocess.run(["swift", str(Path(__file__).with_name("verify_update.swift")), args.public_key, str(archive), signature], check=True)
        feeds[arch] = make_feed(args.version, arch, signature, archive.stat().st_size)
    args.output.mkdir(parents=True, exist_ok=True)
    for arch, text in feeds.items():
        (args.output / f'appcast-{arch}.xml').write_text(text)


if __name__ == '__main__':
    main()
