#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
checks=[]
def req(path,needle):
    text=(root/path).read_text(errors='ignore');checks.append((f'{path}: {needle}',needle in text))
req(Path('DogalgazProjeAI/Info.plist'),'<string>2.2.0</string>')
req(Path('DogalgazProjeAI/Info.plist'),'<string>22</string>')
req(Path('DogalgazProjeAI.xcodeproj/project.pbxproj'),'MARKETING_VERSION = 2.2.0;')
req(Path('backend/server.js'),'const apiVersion = "2.2.0"')
req(Path('DogalgazProjeAI/V21Enhancements.swift'),'ARRoomAlignment')
req(Path('DogalgazProjeAI/V21Enhancements.swift'),'CloudArtifactService')
req(Path('DogalgazProjeAI/Models.swift'),'internalDiameterMM')
req(Path('DogalgazProjeAI/EngineeringSettings.swift'),'PipeDimensionCatalog')
req(Path('backend/server.js'),'project_artifacts')
req(Path('backend/server.js'),'team membership required')
failed=[n for n,o in checks if not o]
for n,o in checks: print(('PASS ' if o else 'FAIL ')+n)
if failed: sys.exit(1)
