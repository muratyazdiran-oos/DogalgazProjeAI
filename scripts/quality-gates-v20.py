#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
checks=[]
def require(path, needle):
    text=(root/path).read_text(errors='ignore'); checks.append((f'{path}: {needle}', needle in text))
require(Path('DogalgazProjeAI/Info.plist'), '<string>2.0.0</string>')
require(Path('DogalgazProjeAI/Info.plist'), '<string>20</string>')
require(Path('DogalgazProjeAI.xcodeproj/project.pbxproj'), 'V20Enhancements.swift in Sources')
require(Path('DogalgazProjeAI.xcodeproj/project.pbxproj'), 'MARKETING_VERSION = 2.0.0;')
require(Path('backend/server.js'), 'const apiVersion = "2.0.0"')
require(Path('.github/workflows/ci.yml'), 'workflow_dispatch:')
require(Path('DogalgazProjeAI/V20Enhancements.swift'), 'ARCaptureDiagnosticsView')
failed=[name for name,ok in checks if not ok]
for name,ok in checks: print(('PASS ' if ok else 'FAIL ')+name)
if failed: sys.exit(1)
