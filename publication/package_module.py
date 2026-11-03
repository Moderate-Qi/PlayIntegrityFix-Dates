"""Package the current module tree after the frontend and native builds."""
from pathlib import Path
import argparse
import zipfile
import zlib

root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser()
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
module=root/'module'
required=['module.prop','classes.dex','webroot/index.html','patch_mode.sh']
for name in required:
    if not (module/name).is_file():raise SystemExit('Build input missing: '+name)
if not any((module/n).is_file() for n in ('webroot/patch-mode.js','webroot/assets/patch-mode.js')):
    raise SystemExit('Build input missing: date UI')
expected=f'{zlib.crc32((module/"module.prop").read_bytes()):x}'.encode()+b'\0'
for abi in ('arm64-v8a','armeabi-v7a','x86_64'):
    lib=module/'zygisk'/f'{abi}.so'
    if expected not in lib.read_bytes():raise SystemExit('Rebuild native metadata for '+abi)
args.output.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(args.output,'x',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(module.rglob('*')):
        if not p.is_file():continue
        name=p.relative_to(module).as_posix()
        info=zipfile.ZipInfo(name)
        info.create_system=3
        info.external_attr=(0o100755 if p.suffix=='.sh' or p.name=='update-binary' else 0o100644)<<16
        info.compress_type=zipfile.ZIP_DEFLATED
        z.writestr(info,p.read_bytes())
print(args.output)
