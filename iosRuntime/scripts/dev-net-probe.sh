#!/bin/bash
# Device-side network check: bundle the probe pointed at this Mac's LAN address,
# install on the real iPhone, run it and print the [NET] lines.
set -e
cd "$(dirname "$0")/.."
export JAVA_HOME=~/.sdkman/candidates/java/25.0.5.0+8-tem
export PATH="$JAVA_HOME/bin:$PATH"

LAN=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1)
UDID=00008140-000139890187001C
echo "lan=$LAN"

bash scripts/net-fixtures.sh start >/dev/null 2>&1 || true

rm -rf /tmp/lanprobe && mkdir -p /tmp/lanprobe/classes
sed "s/127\\.0\\.0\\.1/$LAN/g" test/NetworkProbe.java > /tmp/lanprobe/NetworkProbe.java
javac --release 8 -nowarn \
    -cp "build/RuntimeApp.app/jars/minijvm_rt.jar:build/RuntimeApp.app/jars/j2me_api.jar" \
    -d /tmp/lanprobe/classes /tmp/lanprobe/NetworkProbe.java
jar cfm build/net-lan-probe.jar test/network-probe.mf -C /tmp/lanprobe/classes .

MIDLET_JAR=build/net-lan-probe.jar ./scripts/build-device.sh | tail -2

xcrun devicectl device install app --device "$UDID" --json-output /tmp/inst.json \
    build/device/RuntimeApp.app >/dev/null
URL=$(python3 - <<'PY'
import json
d = json.load(open('/tmp/inst.json'))
print(d['result']['installedApplications'][0]['installationURL'])
PY
)
JAR="${URL#file://}/jars/game.jar"
echo "jar=$JAR"

( xcrun devicectl device process launch --device "$UDID" --terminate-existing --console \
    -e "{\"RT_MIDLET_JAR\":\"$JAR\"}" io.github.h3nb.jlmodplus.runtime \
    > build/device/net.log 2>&1 & echo $! > /tmp/devnet.pid )
sleep 30
kill "$(cat /tmp/devnet.pid)" 2>/dev/null || true
grep -E '\[NET\]|\[RT\]|Exception|Error' build/device/net.log | head -20
