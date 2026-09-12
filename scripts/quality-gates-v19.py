from pathlib import Path
import re, plistlib, sys

root = Path(__file__).resolve().parents[1]
app = root / 'DogalgazProjeAI'
pbx = (root / 'DogalgazProjeAI.xcodeproj/project.pbxproj').read_text()
errors = []

swift_files = sorted(app.glob('*.swift'))
for f in swift_files:
    if f.name not in pbx:
        errors.append(f'{f.name} Xcode targetında yok')

for required in ['V19Enhancements.swift', 'ARFieldCaptureView', 'Project3DViewer', 'EnterpriseDashboardView']:
    if required not in (app / 'V19Enhancements.swift').read_text() and required != 'V19Enhancements.swift':
        errors.append(f'v1.9 özelliği eksik: {required}')

with open(app / 'Info.plist', 'rb') as fh:
    info = plistlib.load(fh)
if info.get('CFBundleShortVersionString') != '1.9.0': errors.append('Info.plist sürümü 1.9.0 değil')
if info.get('CFBundleVersion') != '19': errors.append('Info.plist build 19 değil')
if info.get('NSCameraUsageDescription') is None: errors.append('Kamera izin açıklaması yok')
if 'MARKETING_VERSION = 1.9.0;' not in pbx: errors.append('Xcode marketing version uyumsuz')
if 'CURRENT_PROJECT_VERSION = 19;' not in pbx: errors.append('Xcode build uyumsuz')

backend = (root / 'backend/server.js').read_text()
for marker in ['const apiVersion = "1.9.0"', '/v1/teams/:id/dashboard', '/v1/team-projects/sync-batch']:
    if marker not in backend: errors.append(f'Backend marker eksik: {marker}')

# PBX 24-char IDs duplicate definitions check
ids = re.findall(r'^\s*([A-F0-9]{24})\s+/\*.*?\*/\s*=\s*\{', pbx, re.M)
if len(ids) != len(set(ids)): errors.append('Duplicate PBX object ID var')

if errors:
    print('v1.9 quality gate FAILED')
    for e in errors: print('-', e)
    sys.exit(1)
print(f'v1.9 quality gate OK • {len(swift_files)} Swift file')
