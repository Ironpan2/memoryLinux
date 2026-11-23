#!/usr/bin/env python3
"""
Patch Proton's kernelbase.dll to export SetProcessValidCallTargets{,Ex}
as stubs that return TRUE. Byfron's fake RobloxPlayerBeta.dll calls them
to CFG-whitelist its own trampolines after unpacking; Wine has no CFG
bitmap so the call is a no-op on this side. Without the stub the loader
aborts with 'unimplemented function api-ms-win-core-memory-l1-1-3.dll.
SetProcessValidCallTargets'.
"""
import sys, lief

SRC = sys.argv[1]
DST = sys.argv[2]

# mov eax, 1 ; ret
STUB = bytes.fromhex("b801000000c3")
PAYLOAD = STUB + b"\xcc\xcc" + STUB + b"\xcc" * 8

pe = lief.PE.parse(SRC)
section = lief.PE.Section(".stub")
section.content = list(PAYLOAD)
C = lief.PE.Section.CHARACTERISTICS
section.characteristics = C.MEM_EXECUTE.value | C.MEM_READ.value | C.CNT_CODE.value
added = pe.add_section(section)
rva_main = added.virtual_address
rva_ex   = added.virtual_address + len(STUB) + 2

exp = pe.get_export()
if exp.find_entry("SetProcessValidCallTargets") is None:
    exp.add_entry("SetProcessValidCallTargets", rva_main)
if exp.find_entry("SetProcessValidCallTargetsEx") is None:
    exp.add_entry("SetProcessValidCallTargetsEx", rva_ex)

cfg = lief.PE.Builder.config_t()
cfg.exports = True
b = lief.PE.Builder(pe, cfg)
b.build()
b.write(DST)

verify = lief.PE.parse(DST)
names = {e.name for e in verify.get_export().entries}
assert "SetProcessValidCallTargets" in names
assert "SetProcessValidCallTargetsEx" in names
print("patched: SetProcessValidCallTargets @ 0x%x, Ex @ 0x%x" % (rva_main, rva_ex))
