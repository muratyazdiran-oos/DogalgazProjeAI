#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
checks=[]
def req(path,needle):
    text=(root/path).read_text(errors='ignore');checks.append((f'{path}: {needle}',needle in text))
req(Path('DogalgazProjeAI/Info.plist'),'<string>2.4.0</string>')
req(Path('DogalgazProjeAI/Info.plist'),'<string>24</string>')
req(Path('DogalgazProjeAI.xcodeproj/project.pbxproj'),'MARKETING_VERSION = 2.4.0;')
req(Path('backend/server.js'),'const apiVersion = "2.4.0"')
req(Path('DogalgazProjeAI/V23Enhancements.swift'),'calibrationIsAcceptable')
req(Path('DogalgazProjeAI/V23Enhancements.swift'),'pointInPolygon')
req(Path('DogalgazProjeAI/V23Enhancements.swift'),'approvalEvidenceBlockingReasons')
req(Path('DogalgazProjeAI/HydraulicCalculator.swift'),'criticalPathPipeIDs')
req(Path('DogalgazProjeAI/V19Enhancements.swift'),'confidence: [UInt8]?')
req(Path('backend/server.js'),'artifact_upload_sessions')
req(Path('backend/server.js'),'artifacts/presign')
req(Path('backend/server.js'),'runArtifactGC')
req(Path('backend/server.js'),'artifacts/:remoteID/verify')
req(Path('backend/server.js'),'overdueCount')
req(Path('DogalgazProjeAI/V21Enhancements.swift'),'recentlyVerified')
req(Path('DogalgazProjeAI/ProductionReadinessView.swift'),'Hidrolik ağ bütünlüğü')
failed=[n for n,o in checks if not o]
for n,o in checks: print(('PASS ' if o else 'FAIL ')+n)
if failed: sys.exit(1)
