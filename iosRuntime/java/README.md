# Vendored Java runtime

`src/` holds the J2ME API layer of the iOS runtime (279 files), derived from
J2ME-Decade's `J2ME Emulator iOS` (Apache-2.0), whose API layer was ported
from J2ME-Loader. Every file carries a derivation header written by
`scripts/add-provenance-headers.sh`; see `THIRD_PARTY_NOTICES.md` at the
repository root for attribution.

Packages present: `javax.microedition.{lcdui,midlet,rms,media,messaging,io}`
plus the OEM extension packages kept for game compatibility (Nokia, Samsung,
Siemens, Sony Ericsson, Sprint, KDDI, Motorola, Vodafone).

**This tree is read-only.** Do not reshape these classes to suit the host.
If a game needs different behaviour, add it in the host or in
`native/bridge/`, or record a patch under `patches/`. The only accepted edits
are fixes required by the miniJVM build (documented in the file) or engine
differences, and they must keep the compile-clean guarantee:

```
javac --release 8 -nowarn -cp <minijvm_rt.jar> -d /tmp/jr-classes $(find src -name '*.java')
```

`javax.microedition.io` deliberately does **not** live here: the miniJVM
runtime jar ships its own implementation (including TLS) and bootclasspath
classes win, so a second copy would be dead code. See
`../README.md` (Networking).
