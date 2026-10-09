"""Notify IndexNow after Pages deployment. --dry-run validates without submitting."""
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

site = Path(__file__).resolve().parents[1] / 'website'
base = 'https://tamia6.github.io/AppDuo/'
keys = [p for p in site.glob('*.txt') if re.fullmatch(r'[a-f0-9]{32}', p.stem)]
assert len(keys) == 1, 'Expected one IndexNow ownership file'
key_file = keys[0]
key = key_file.read_text().strip()
assert key == key_file.stem
urls = [e.text for e in ET.parse(site / 'sitemap.xml').iter('{http://www.sitemaps.org/schemas/sitemap/0.9}loc')]
assert urls and len(urls) == len(set(urls))
assert all(url.startswith(base) for url in urls), 'Only submit this project site'
payload = {'host': 'tamia6.github.io', 'key': key,
           'keyLocation': base + key_file.name, 'urlList': urls}
if '--dry-run' in sys.argv:
    print(f'Validated {len(urls)} URLs; no submission made.')
else:
    with urllib.request.urlopen(payload['keyLocation'], timeout=30) as response:
        assert response.read().decode().strip() == key, 'Ownership file is not deployed'
    request = urllib.request.Request('https://api.indexnow.org/indexnow',
        data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=30) as response:
        assert response.status in (200, 202)
        print(f'IndexNow HTTP {response.status}: {len(urls)} URLs received; indexing is not guaranteed.')
