"""Generate platform icon sizes from the approved artwork using macOS sips."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/weekpact-icon.png'

def resize(destination, size, source=SOURCE):
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['sips', '-z', str(size), str(size), str(source), '--out', str(destination)], check=True, stdout=subprocess.DEVNULL)

catalog = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
outputs = {}
for item in json.loads((catalog / 'Contents.json').read_text())['images']:
    size = round(float(item['size'].split('x')[0]) * float(item['scale'][:-1]))
    outputs[catalog / item['filename']] = size
for density, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    outputs[ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'] = size
outputs[ROOT / 'web/favicon.png'] = 32
outputs[ROOT / 'website/public/app-icon.png'] = 1024
outputs[ROOT / 'website/public/favicon.png'] = 32
for size in (192,512):
    outputs[ROOT / f'web/icons/Icon-{size}.png'] = size
for destination, size in outputs.items():
    resize(destination, size)
# Give browser maskable icons extra space to preserve the mark in circular masks.
with tempfile.TemporaryDirectory() as temporary:
    padded = Path(temporary) / 'maskable.png'
    resize(padded, 768)
    subprocess.run(['sips', '-p', '1024', '1024', '--padColor', '163228', str(padded)], check=True, stdout=subprocess.DEVNULL)
    for size in (192,512):
        destination = ROOT / f'web/icons/Icon-maskable-{size}.png'
        resize(destination, size, padded)
        outputs[destination] = size
for destination, size in outputs.items():
    result = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', '-g', 'hasAlpha', str(destination)], text=True)
    assert f'pixelWidth: {size}' in result and f'pixelHeight: {size}' in result, destination
    assert 'hasAlpha: no' in result, destination
print(f'Generated and verified {len(outputs)} opaque platform icons.')
