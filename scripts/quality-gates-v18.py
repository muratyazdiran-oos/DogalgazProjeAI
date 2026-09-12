#!/usr/bin/env python3
from pathlib import Path
import json, plistlib
root=Path(__file__).resolve().parents[1]
with (root/'DogalgazProjeAI/Info.plist').open('rb') as f: info=plistlib.load(f)
assert info['CFBundleShortVersionString']=='1.8.0'
assert info['CFBundleVersion']=='18'
pbx=(root/'DogalgazProjeAI.xcodeproj/project.pbxproj').read_text()
assert pbx.count('V18Enhancements.swift in Sources')>=1
assert 'MARKETING_VERSION = 1.8.0' in pbx and 'CURRENT_PROJECT_VERSION = 18' in pbx
server=(root/'backend/server.js').read_text(); assert 'const apiVersion = "1.8.0"' in server
pkg=json.loads((root/'backend/package.json').read_text()); assert pkg['version']=='1.8.0'
prof=(root/'DogalgazProjeAI/ProfessionalFeatures.swift').read_text(); assert 'AutoCAD-GasLine-mm-v1.8.dxf' in prof
v18=(root/'DogalgazProjeAI/V18Enhancements.swift').read_text()
for marker in ['ApplianceLabelOCR','FieldChecklistView','SpatialCaptureStatusView','ImprovementCenterView','VNRecognizeTextRequest']:
    assert marker in v18
print('OK: v1.8 semantic quality gates')
