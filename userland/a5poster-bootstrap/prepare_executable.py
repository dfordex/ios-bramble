#!/usr/bin/env python3
"""Privately add a mandatory startup shim to the exact lab PosterBoard image.
Only Mach-O header padding changes; executable text and entitlements are retained.
Apple executable bytes are inputs/outputs, never included in this source file.
"""
import argparse,hashlib,json,plistlib,struct,subprocess,tempfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
p.add_argument('--expected-sha256',required=True);p.add_argument('--receipt',type=Path,required=True);a=p.parse_args()
assert a.output.name=='PosterBoard' and a.output.parent.name=='PosterBoard.app'
assert plistlib.loads((a.output.parent/'Info.plist').read_bytes())['CFBundleIdentifier']=='com.apple.PosterBoard'
assert not a.receipt.resolve().is_relative_to(a.output.parent.resolve()), 'receipt must be outside signed app'
b=bytearray(a.input.read_bytes());assert hashlib.sha256(b).hexdigest()==a.expected_sha256
assert struct.unpack_from('<II',b)==(0xfeedfacf,0x100000c)
assert not a.output.exists();count,size=struct.unpack_from('<II',b,16);off=32;texts=[];first=len(b);loads=[]
for _ in range(count):
 cmd,n=struct.unpack_from('<II',b,off);assert n>=8 and off+n<=32+size
 if cmd==0x19:
  for i in range(struct.unpack_from('<I',b,off+64)[0]):
   q=off+72+i*80;name=bytes(b[q:q+16]).rstrip(b'\0');length=struct.unpack_from('<Q',b,q+40)[0];start=struct.unpack_from('<I',b,q+48)[0]
   if start and length:first=min(first,start)
   if name==b'__text':texts.append(bytes(b[start:start+length]))
 if cmd in (0xc,0x80000018,0x8000001f):
  start=struct.unpack_from('<I',b,off+8)[0];loads.append(bytes(b[off+start:off+n]).split(b'\0')[0].decode())
 off+=n
name=b'/usr/libexec/a5poster-bootstrap.dylib\0';n=(24+len(name)+7)&~7
assert off==32+size and off+n<=first and not any(b[off:off+n])
assert name[:-1].decode() not in loads
lc=struct.pack('<6I',0xc,n,24,2,0x10000,0x10000)+name
b[off:off+n]=lc.ljust(n,b'\0');struct.pack_into('<II',b,16,count+1,size+n)
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_bytes(b);a.output.chmod(0o755)
e=subprocess.run(['codesign','-d','--entitlements',':-',str(a.input)],capture_output=True,check=True).stdout
ent=plistlib.loads(e)
with tempfile.TemporaryDirectory(prefix='a5poster-sign-') as folder:
 entpath=Path(folder)/'entitlements.plist';entpath.write_bytes(e)
 subprocess.run(['codesign','--force','--sign','-','--pagesize','4096','--identifier','com.apple.PosterBoard','--entitlements',str(entpath),str(a.output)],check=True)
subprocess.run(['codesign','--verify','--strict',str(a.output)],check=True)
e2=subprocess.run(['codesign','-d','--entitlements',':-',str(a.output)],capture_output=True,check=True).stdout
assert plistlib.loads(e2)==ent
new=a.output.read_bytes();off=32;after=[]
for _ in range(struct.unpack_from('<I',new,16)[0]):
 cmd,n=struct.unpack_from('<II',new,off)
 if cmd==0x19:
  for i in range(struct.unpack_from('<I',new,off+64)[0]):
   q=off+72+i*80
   if new[q:q+16].rstrip(b'\0')==b'__text':
    length=struct.unpack_from('<Q',new,q+40)[0];start=struct.unpack_from('<I',new,q+48)[0];after.append(new[start:start+length])
 off+=n
assert after==texts and len(texts)==1
receipt={'original_sha256':a.expected_sha256,'output_sha256':hashlib.sha256(new).hexdigest(),'output_bytes':len(new),'text_bytes_exact':True,'entitlements_exact':True,'added_load':name[:-1].decode(),'new_ncmds':count+1,'header_padding_used':n}

# Check the complete application after creating the external receipt, not only
# its executable: no temporary signing metadata may become an omitted resource.
subprocess.run(['codesign','--verify','--strict',str(a.output.parent)],check=True)
resources=plistlib.loads((a.output.parent/'_CodeSignature/CodeResources').read_bytes())
for name,entry in resources.get('files2',{}).items():
 q=a.output.parent/name
 assert q.is_file() and not q.is_symlink(),name
 if isinstance(entry,dict) and 'hash2' in entry:assert hashlib.sha256(q.read_bytes()).digest()==entry['hash2'],name

receipt.update(bundle_resources_verified=True,resource_files=sorted(resources.get('files2',{})))
a.receipt.write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt,indent=2))
