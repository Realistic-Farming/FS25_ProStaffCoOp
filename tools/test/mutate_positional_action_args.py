# PLAYER-REPORTS row 199 mutation battery: the three NetworkSync action senders send a positional
# array (src/ProStaffManager.lua buyLevel, src/ProStaffDiseaseFlush.lua requestFarmFlush and
# requestAdminClear) and the three handlers read args[1] as a positive number. Rows live in
# PR-199-positional_action_args_test.lua; the other bars run with it.
#
# Each mutation restores one piece of the defect and must be KILLED by a named row. For each:
# assert the edit LANDED (exact occurrence count), run the suite, record KILLED/SURVIVED with
# the named rows, restore byte-for-byte and PROVE the restore with a hash. "DID NOT APPLY"
# never counts as a kill. KILLED* means killed only by a Lua error: a weak kill, a failure.
#
# Not run, and why:
# - the transport itself (the fixture copies of NetworkSync): not this repo's code.
# - the ownership equality (farm.farmId ~= farmId): unchanged by this PR and pinned by the
#   existing rows; only the read of the farm and the > 0 test moved.
#
# Anchors are written with "\n"; in a CRLF file they are matched as "\r\n".
#
# Usage (from the repo root): py tools/test/mutate_positional_action_args.py [id-prefix ...]
import hashlib, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def p(rel): return os.path.join(ROOT, rel)

MGR = "src/ProStaffManager.lua"
FLUSH = "src/ProStaffDiseaseFlush.lua"

MUTATIONS = [
 # ── the senders: the keyed literal restored ─────────────────────────────────
 ("K1-buy-sends-keyed", MGR,
  [("        ns:requestAction(ProStaffConstants.ACTION_BUY, { farmId })\n",
    "        ns:requestAction(ProStaffConstants.ACTION_BUY, { farmId = farmId })\n", 1)],
  "the purchase request arrives empty on the server: J. Duke's report"),
 ("K2-flush-sends-keyed", FLUSH,
  [("        ns:requestAction(ProStaffConstants.ACTION_FLUSH, { farmId })\n",
    "        ns:requestAction(ProStaffConstants.ACTION_FLUSH, { farmId = farmId })\n", 1)],
  "the flush request arrives empty"),
 ("K3-clear-sends-keyed", FLUSH,
  [("        ns:requestAction(ProStaffConstants.ACTION_CLEAR, { farmId })\n",
    "        ns:requestAction(ProStaffConstants.ACTION_CLEAR, { farmId = farmId })\n", 1)],
  "the admin clear request arrives empty"),
 # ── the handlers: the keyed read restored ───────────────────────────────────
 ("H1-buy-reads-keyed", MGR,
  [("                    local farmId = type(args) == \"table\" and args[1] or nil\n                    if type(farmId) ~= \"number\" or farmId <= 0 then return end\n",
    "                    local farmId = type(args) == \"table\" and args.farmId or nil\n                    if type(farmId) ~= \"number\" or farmId <= 0 then return end\n", 1)],
  "the purchase handler looks for a key the wire cannot carry"),
 ("H2-flush-reads-keyed", FLUSH,
  [("            local farmId = type(args) == \"table\" and args[1] or nil\n            if type(farmId) ~= \"number\" or farmId <= 0 then return end\n            -- Ownership: a client may only flush",
    "            local farmId = type(args) == \"table\" and args.farmId or nil\n            if type(farmId) ~= \"number\" or farmId <= 0 then return end\n            -- Ownership: a client may only flush", 1)],
  "the flush handler looks for a key the wire cannot carry"),
 ("H3-clear-reads-keyed", FLUSH,
  [("            local farmId = type(args) == \"table\" and args[1] or nil\n            if type(farmId) ~= \"number\" or farmId <= 0 then return end\n            self:_doAdminClear(farmId)",
    "            local farmId = type(args) == \"table\" and args.farmId or nil\n            if type(farmId) ~= \"number\" or farmId <= 0 then return end\n            self:_doAdminClear(farmId)", 1)],
  "the clear handler looks for a key the wire cannot carry"),
 # ── the spectator's zero ────────────────────────────────────────────────────
 ("Z1-buy-accepts-farm-zero", MGR,
  [("                    if type(farmId) ~= \"number\" or farmId <= 0 then return end\n",
    "                    if type(farmId) ~= \"number\" then return end\n", 1)],
  "a spectator's 0 passes the ownership equality (getFarmByUserId answers farm 0) and buys for farm 0"),
 ("Z2-flush-accepts-farm-zero", FLUSH,
  [("            if type(farmId) ~= \"number\" or farmId <= 0 then return end\n            -- Ownership: a client may only flush",
    "            if type(farmId) ~= \"number\" then return end\n            -- Ownership: a client may only flush", 1)],
  "a spectator's 0 reaches the flush"),
]

def sha(b): return hashlib.sha256(b).hexdigest()


def run_suite():
    r = subprocess.run(["node", "run-tests.mjs"], cwd=os.path.join(ROOT, "tools", "test"),
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = r.stdout + r.stderr
    strip = lambda l: (re.sub(r"\x1b\[[0-9;]*m", "", l).strip()
                       .encode("ascii", "replace").decode("ascii"))
    fails = [strip(l) for l in out.splitlines() if "FAIL" in l and "assertions passed" not in l]
    crashes = [strip(l) for l in out.splitlines() if "Lua error while loading/running" in l]
    return r.returncode, fails, crashes


only = sys.argv[1:]
rc, fails, crashes = run_suite()
if rc != 0:
    print("BASELINE IS NOT GREEN; fix that before trusting any mutation result.")
    for l in fails[:10]:
        print("   " + l)
    sys.exit(2)
print("baseline green")

killed, crashkills, survived, badedit = [], [], [], []

for mid, rel, edits, why in MUTATIONS:
    if only and not any(mid.startswith(o) for o in only):
        continue
    path = p(rel)
    with open(path, "rb") as f:
        original = f.read()
    crlf = b"\r\n" in original
    enc = lambda s: (s.replace("\n", "\r\n") if crlf else s).encode("utf-8")

    ok, mutated = True, original
    for old, new, want in edits:
        ob, nb = enc(old), enc(new)
        n = mutated.count(ob)
        if n != want:
            badedit.append((mid, "anchor matched %dx, expected %d" % (n, want)))
            print("  !! %s: ANCHOR MISMATCH (%d != %d), mutation NOT applied" % (mid, n, want))
            ok = False
            break
        mutated = mutated.replace(ob, nb, want)
    if not ok:
        continue

    with open(path, "wb") as f:
        f.write(mutated)
    with open(path, "rb") as f:
        landed = f.read()
    if landed == original or landed != mutated:
        with open(path, "wb") as f:
            f.write(original)
        badedit.append((mid, "edit did not land"))
        print("  !! %s: EDIT DID NOT LAND" % mid)
        continue

    try:
        rc, fails, crashes = run_suite()
    finally:
        with open(path, "wb") as f:
            f.write(original)
    with open(path, "rb") as f:
        if sha(f.read()) != sha(original):
            print("  !! %s: RESTORE FAILED, stopping" % mid)
            sys.exit(3)

    named = [l for l in fails if l.startswith("FAIL ")]
    if rc != 0:
        killed.append(mid)
        tag = "KILLED  "
        if crashes and not named:
            crashkills.append(mid)
            tag = "KILLED* "
    else:
        survived.append((mid, why))
        tag = "SURVIVED"
    print("  %s %s  [%s]" % (tag, mid, rel))
    print("        (%s)" % why)
    for l in named[:4]:
        print("        " + l[:170])
    for l in crashes[:2]:
        print("        CRASH " + l[:170])

print("\n==== MUTATION RESULT ====")
print("killed   %d (of which %d only by a Lua error, marked KILLED*)" % (len(killed), len(crashkills)))
print("survived %d" % len(survived))
for mid, why in survived:
    print("   SURVIVED %s: %s" % (mid, why))
print("bad edit %d" % len(badedit))
for mid, why in badedit:
    print("   BAD EDIT %s: %s" % (mid, why))
print("all files restored byte-identical (hash-checked per mutation)")
sys.exit(1 if (survived or badedit or crashkills) else 0)
