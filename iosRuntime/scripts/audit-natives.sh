#!/bin/bash
# Audit: every `native` method declared in the J2ME API classes must have a C
# implementation registered in a java_native_method table, otherwise calling it
# throws UnsatisfiedLinkError (an Error a MIDlet cannot catch).
#
#   ./audit-natives.sh [jar]
# jar defaults to build/j2me_api.jar (built by build-sim.sh).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
: "${JAVA_HOME:?set JAVA_HOME to a JDK 17+ install}"
export PATH="$JAVA_HOME/bin:$PATH"

JAR="${1:-$ROOT/build/j2me_api.jar}"
[ -f "$JAR" ] || { echo "missing $JAR (run build-sim.sh first)" >&2; exit 1; }

CLASSES=$(unzip -Z1 "$JAR" | grep '\.class$' | sed 's|\.class$||; s|/|.|g' | grep -v '\$')
javap -p -s -cp "$JAR" $CLASSES > "$ROOT/build/audit-javap.txt"

python3 - "$ROOT" <<'PYEOF'
import re, sys, glob, os
root = sys.argv[1]
txt = open(os.path.join(root, 'build/audit-javap.txt'), encoding='utf-8', errors='replace').read()

declared, cur_class, pending = [], None, None
for line in txt.splitlines():
    cm = re.search(r'\b(?:class|interface)\s+([\w.$]+)', line)
    if cm and 'descriptor:' not in line:
        cur_class = cm.group(1)
    nm = re.match(r'^\s+(?:public |protected |private |static |final |synchronized |native |abstract )*.*\bnative\b.*?\s(\w+)\(', line)
    if nm:
        pending = nm.group(1)
        continue
    dm = re.match(r'^\s+descriptor:\s*(\S+)', line)
    if dm and pending and cur_class:
        declared.append((cur_class, pending, dm.group(1)))
        pending = None

impl = set()
for path in glob.glob(os.path.join(root, 'native', '*.[cm]')):
    src = open(path, encoding='utf-8', errors='replace').read()
    defines = dict(re.findall(r'#define\s+(\w+)\s+"([^"]+)"', src))
    for c, n, d in re.findall(r'\{\s*(\w+|"[\w/$]+")\s*,\s*"(\w+)"\s*,\s*"([^"]+)"', src):
        if c.startswith('"'):
            c = c.strip('"')
        else:
            c = defines.get(c, c)
        impl.add((c.replace('/', '.'), n, d))

missing = [t for t in declared if t not in impl]
print(f"declared natives: {len(declared)}")
print(f"native table entries: {len(impl)}")
print(f"missing implementations: {len(missing)}")
for c, n, d in sorted(missing):
    print(f"  MISSING {c}.{n}{d}")
PYEOF
