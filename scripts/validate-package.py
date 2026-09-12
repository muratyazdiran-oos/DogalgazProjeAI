#!/usr/bin/env python3
from pathlib import Path
import re, plistlib, subprocess, sys
root=Path(__file__).resolve().parents[1]
pbx=(root/'DogalgazProjeAI.xcodeproj/project.pbxproj').read_text()
ids=re.findall(r'^\s*([A-F0-9]{24}) /\* .*? \*/ = \{isa =',pbx,re.M)
dups=sorted({x for x in ids if ids.count(x)>1})
if dups: raise SystemExit(f'duplicate PBX ids: {dups}')
refs=re.findall(r'/\* ([A-Za-z0-9_+.-]+\.swift) \*/ = \{isa = PBXFileReference;',pbx)
missing=[x for x in refs if not (root/'DogalgazProjeAI'/x).exists()]
if missing: raise SystemExit(f'missing swift refs: {missing}')
for name in ['Info.plist','PrivacyInfo.xcprivacy']:
    with (root/'DogalgazProjeAI'/name).open('rb') as f: plistlib.load(f)
subprocess.run(['/usr/local/swift/usr/bin/swiftc','-parse',*map(str,(root/'DogalgazProjeAI').glob('*.swift'))],check=True)
subprocess.run(['node','--check',str(root/'backend/server.js')],check=True)
print(f'OK: {len(refs)} Swift refs, plists, Swift parser, Node syntax')
