#!/usr/bin/env python3
from pathlib import Path
import json, plistlib, re
root=Path(__file__).resolve().parents[1]
with (root/'DogalgazProjeAI/Info.plist').open('rb') as f: info=plistlib.load(f)
assert info['CFBundleShortVersionString']=='1.7.0'
assert info['CFBundleVersion']=='17'
pbx=(root/'DogalgazProjeAI.xcodeproj/project.pbxproj').read_text()
assert pbx.count('V17Enhancements.swift in Sources')>=1
assert 'MARKETING_VERSION = 1.7.0' in pbx and 'CURRENT_PROJECT_VERSION = 17' in pbx
server=(root/'backend/server.js').read_text()
assert 'const apiVersion = "1.7.0"' in server
pkg=json.loads((root/'backend/package.json').read_text())
assert pkg['version']=='1.7.0'
adv=(root/'DogalgazProjeAI/AdvancedFeatures.swift').read_text()
assert 'applicationSupportDirectory' in adv and 'offlineProjectSyncQueue.v1' not in adv
prof=(root/'DogalgazProjeAI/ProfessionalFeatures.swift').read_text()
assert 'AutoCAD-GasLine-mm-v1.7.dxf' in prof
assert 'ProjectQualityView' in prof and 'RevisionComparisonView' in prof
print('OK: v1.7 semantic quality gates')
