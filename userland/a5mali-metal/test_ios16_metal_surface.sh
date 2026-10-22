#!/bin/sh
# A local iOS 16 Metal ObjC dump is required; no Apple-derived metadata ships
# with this repository.  This test also verifies the regression gate fails.
set -eu
if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/ios16-metal-objc-verbose.txt" >&2
  exit 2
fi
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dump=$1
python3 "$here/audit_ios16_metal_surface.py" --ios16-objc-dump "$dump"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
python3 - "$dump" "$here/ios16_metal_surface_baseline.json" \
  "$scratch/dump.txt" "$scratch/baseline.json" <<'PY'
import hashlib,json,sys
source=open(sys.argv[1]).read()
start=source.index('@protocol MTLSamplerState <NSObject>')
end=source.index('@end',start)
part=source[start:end]
assert '/* required instance methods */' in part
part=part.replace('@optional','- (void)a5SyntheticMissingSelector;\n\n@optional',1)
mutated=source[:start]+part+source[end:]
open(sys.argv[3],'w').write(mutated)
data=json.load(open(sys.argv[2]))
data['ios16_objc_dump_sha256']=hashlib.sha256(mutated.encode()).hexdigest()
json.dump(data,open(sys.argv[4],'w'))
PY
if python3 "$here/audit_ios16_metal_surface.py" --ios16-objc-dump "$scratch/dump.txt" \
  --baseline "$scratch/baseline.json" >"$scratch/output" 2>&1; then
  echo 'audit accepted an unclassified required selector' >&2
  exit 1
fi
if ! grep -q 'unclassified required selectors' "$scratch/output"; then
  cat "$scratch/output" >&2
  exit 1
fi
echo 'PASS: unclassified selector regression rejected'
