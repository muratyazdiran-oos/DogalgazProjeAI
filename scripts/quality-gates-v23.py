#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
checks=[]
def req(path,needle):
    text=(root/path).read_text(errors='ignore')
    checks.append((f'{path}: {needle}',needle in text))
req(Path('DogalgazProjeAI/Info.plist'),'<string>2.3.0</string>')
req(Path('DogalgazProjeAI/Info.plist'),'<string>23</string>')
req(Path('DogalgazProjeAI.xcodeproj/project.pbxproj'),'V23Enhancements.swift in Sources')
req(Path('DogalgazProjeAI.xcodeproj/project.pbxproj'),'MARKETING_VERSION = 2.3.0;')
req(Path('backend/server.js'),'const apiVersion = "2.3.0"')
req(Path('DogalgazProjeAI/V23Enhancements.swift'),'MultiPointARRoomAlignmentView')
req(Path('DogalgazProjeAI/V23Enhancements.swift'),'ObstacleAwareRouter3D')
req(Path('DogalgazProjeAI/V23Enhancements.swift'),'evidenceManifestForApproval')
req(Path('DogalgazProjeAI/ProjectStore.swift'),'approvalHashMismatch')
req(Path('backend/server.js'),'S3_ARTIFACT_BUCKET')
req(Path('backend/server.js'),'deduplicated:true')
failed=[n for n,o in checks if not o]
for n,o in checks: print(('PASS ' if o else 'FAIL ')+n)
if failed: sys.exit(1)
