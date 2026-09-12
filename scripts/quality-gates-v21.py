#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
checks=[]
def require(path, needle):
    text=(root/path).read_text(errors='ignore')
    checks.append((f'{path}: {needle}', needle in text))
require(Path('DogalgazProjeAI/Info.plist'), '<string>2.1.0</string>')
require(Path('DogalgazProjeAI/Info.plist'), '<string>21</string>')
require(Path('DogalgazProjeAI.xcodeproj/project.pbxproj'), 'V21Enhancements.swift in Sources')
require(Path('DogalgazProjeAI.xcodeproj/project.pbxproj'), 'MARKETING_VERSION = 2.1.0;')
require(Path('backend/server.js'), 'const apiVersion = "2.1.0"')
require(Path('DogalgazProjeAI/V19Enhancements.swift'), 'ARDepthSample')
require(Path('DogalgazProjeAI/V21Enhancements.swift'), 'ARWorldProjection')
require(Path('DogalgazProjeAI/V21Enhancements.swift'), 'PipeDiameterAdvisor')
require(Path('DogalgazProjeAI/V17Enhancements.swift'), 'nearManualObstacle')
require(Path('.github/workflows/ci.yml'), 'workflow_dispatch:')
failed=[name for name,ok in checks if not ok]
for name,ok in checks: print(('PASS ' if ok else 'FAIL ')+name)
if failed: sys.exit(1)
