// l10n-esc-page-check.mjs: the Pro Staff Esc page's text and the 20 level names in all 25 locales
// (MAINTENANCE row 142, parts 1 and 2).
//
// The page (src/ui/ProStaffRfPdaGuest.lua) draws every text through its own tr(key, fallback)
// (:54), which asks this mod's i18n. Until row 142 the 25 non-English files carried English
// copies of every key, so the page read English in every language. This bar holds the page's
// keys to the locale files:
//
//   R   the reader set: every ps_rf_pda_* / ps_tab_title string literal in src/ (plus the
//       ps_rf_pda_unlock_1..20 keys the "ps_rf_pda_unlock_" .. level call builds, :372) is
//       exactly KEYS. A key the code reads that the bar does not check, or a checked key
//       nothing reads, fails. NO_READER lists the page keys nothing reads, with the reason;
//       they are not translated (Bob's intake).
//   T   text rows: each key in each locale exists, is not empty, carries no em dash, and is
//       not the English text unless OWN names it (a product or mod name).
//   F   placeholders: the %d/%s sequence equals English's, in order (string.format has no
//       positional arguments, so a reordered value would print the wrong argument).
//   C   script: in ct, cs, jp, kr, ru and uk every checked value carries a letter of that
//       locale's script unless OWN names it (FarmTablet's rule, Bob's MAJOR on #177).
//   X1  the lookup, executed: ProStaff's OWN tr, cut from the real file by luaparse, runs in
//       fengari against each real locale file (an i18n that answers the engine's "Missing"
//       text for an absent key), and must return the file's text for every key, never the
//       fallback.
//
// Exit 0 on PASS; exit 1 listing each failure. Usage: node tools/test/l10n-esc-page-check.mjs
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const req = createRequire(import.meta.url);

const NO_READER = {
  ps_rf_pda_col_item: "no reader anywhere in src/ (Bob's intake, row 142): not translated",
  ps_rf_pda_col_note: "no reader anywhere in src/ (Bob's intake, row 142): not translated",
  ps_rf_pda_col_status: "no reader anywhere in src/ (Bob's intake, row 142): not translated",
  ps_rf_pda_col_value: "no reader anywhere in src/ (Bob's intake, row 142): not translated",
  ps_rf_pda_page_next: "no reader anywhere in src/ (Bob's intake, row 142): not translated",
  ps_rf_pda_page_prev: "no reader anywhere in src/ (Bob's intake, row 142): not translated",
  ps_rf_pda_showing_range: "no reader anywhere in src/ (Bob's intake, row 142): not translated",
};
// ps_rf_pda_grp_wc left OWN in part 2: it now carries FarmTablet's own translated name for the
// WorkerCosts app (ft_ui_app_worker_costs), Bob's MINOR on part 1.
const OWN = new Set(["ps_tab_title"]); // the product's name
const ALLOW_SAME = { "ps_rf_pda_max": "MAX (L20)" };       // the level mark where a language keeps L and MAX

function xmlTexts(file) {
  const xml = readFileSync(file, "utf8");
  const out = new Map();
  for (const m of xml.matchAll(/<text\s+name="([^"]+)"\s+text="([^"]*)"/g)) {
    const v = m[2].replace(/&#10;/g, "\n").replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
    out.set(m[1], v);
  }
  return out;
}
function luaFiles(dir) {
  const out = [];
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) out.push(...luaFiles(p));
    else if (n.endsWith(".lua")) out.push(p);
  }
  return out;
}

const tdir = join(root, "translations");
const en = xmlTexts(join(tdir, "translation_en.xml"));
const KEYS = [...en.keys()].filter((k) => (k.startsWith("ps_rf_pda_") || k.startsWith("ps_level_") || k === "ps_tab_title") && !(k in NO_READER));
const locales = readdirSync(tdir).map((n) => n.match(/^translation_([a-z]{2})\.xml$/)).filter(Boolean).map((m) => m[1]).filter((l) => l !== "en").sort();
const failures = [];

// R: the reader set.
const read = new Set();
let dynamicUnlock = false, dynamicLevel = false;
for (const f of luaFiles(join(root, "src"))) {
  const src = readFileSync(f, "utf8");
  for (const m of src.matchAll(/"(ps_rf_pda_[a-z0-9_]+|ps_tab_title)"/g)) {
    if (m[1] === "ps_rf_pda_unlock_") dynamicUnlock = true; else read.add(m[1]);
  }
  // The level names: the page's rungName builds "ps_level_" .. level (ProStaffRfPdaGuest.lua),
  // the getter string.format("ps_level_%d", level) (ProStaffAPI.lua getLevelDisplayName).
  if (/"ps_level_"|"ps_level_%d"/.test(src)) dynamicLevel = true;
}
if (dynamicUnlock) for (let i = 1; i <= 20; i++) read.add("ps_rf_pda_unlock_" + i);
if (dynamicLevel) for (let i = 1; i <= 20; i++) read.add("ps_level_" + i);
for (const k of KEYS) if (!read.has(k)) failures.push(`R ${k}: checked but nothing in src/ reads it (move it to NO_READER with a reason)`);
for (const k of read) if (!KEYS.includes(k) && !(k in NO_READER)) failures.push(`R ${k}: read in src/ but not checked (not in the en file?)`);
for (const k of Object.keys(NO_READER)) if (read.has(k)) failures.push(`R ${k}: in NO_READER but src/ reads it`);

// T, F, C.
const SCRIPT = {
  cs: /\p{Script=Han}/u, ct: /\p{Script=Han}/u,
  jp: /[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}]/u,
  kr: /\p{Script=Hangul}/u, ru: /\p{Script=Cyrillic}/u, uk: /\p{Script=Cyrillic}/u,
};
const ph = (s) => (s.match(/%[-0-9.]*[a-zA-Z]/g) || []).join(" ");
const files = {};
let scriptChecked = 0;
for (const loc of locales) {
  const t = xmlTexts(join(tdir, `translation_${loc}.xml`));
  files[loc] = t;
  for (const k of KEYS) {
    const v = t.get(k);
    if (v === undefined) { failures.push(`T ${loc}: ${k} missing`); continue; }
    if (!v.trim()) failures.push(`T ${loc}: ${k} is empty`);
    if (v.includes("\u2014")) failures.push(`T ${loc}: ${k} holds an em dash`);
    if (v === en.get(k) && !OWN.has(k) && ALLOW_SAME[k] !== v) failures.push(`T ${loc}: ${k} is the English text`);
    if (ph(v) !== ph(en.get(k))) failures.push(`F ${loc}: ${k} placeholders [${ph(v)}] differ from English [${ph(en.get(k))}]`);
    if (SCRIPT[loc] && !OWN.has(k)) {
      scriptChecked++;
      if (!SCRIPT[loc].test(v)) failures.push(`C ${loc}: ${k} carries no ${loc} letter: "${v.slice(0, 40)}"`);
    }
  }
}

// X1: ProStaff's own tr, executed.
let x1 = 0;
{
  const luaparse = req("luaparse");
  const fengari = req("fengari");
  const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
  const guest = readFileSync(join(root, "src", "ui", "ProStaffRfPdaGuest.lua"), "utf8");
  const ast = luaparse.parse(guest, { ranges: true, luaVersion: "5.1" });
  const decl = ast.body.find((s) => s.type === "FunctionDeclaration" && s.isLocal && s.identifier && s.identifier.name === "tr");
  if (!decl) {
    failures.push("X1 ProStaffRfPdaGuest.lua: no local function tr found; the bar cannot run the page's helper");
  } else {
    const trSrc = guest.slice(decl.range[0], decl.range[1]);
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    const prog = `
      MOD_NAME = "FS25_ProStaffCoOp"
      X1_TEXT = {}
      local I = {}
      function I:getText(key)
        local v = X1_TEXT[key]
        if v == nil then return "Missing '" .. tostring(key) .. "' in l10n_" .. X1_LANG .. ".xml" end
        return v
      end
      g_modEnvironments = { [MOD_NAME] = { i18n = I } }
      g_i18n = nil
      ${trSrc}
      X1_TR = tr`;
    if (lauxlib.luaL_loadbuffer(L, to_luastring(prog), null, to_luastring("@ProStaffRfPdaGuest.tr")) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
      failures.push("X1 the page's tr does not load in fengari: " + to_jsstring(lua.lua_tostring(L, -1)));
    } else {
      const setGlobalStr = (name, s) => { lua.lua_pushstring(L, to_luastring(s)); lua.lua_setglobal(L, to_luastring(name)); };
      for (const loc of locales) {
        setGlobalStr("X1_LANG", loc);
        lua.lua_newtable(L);
        for (const [k, v] of files[loc]) { lua.lua_pushstring(L, to_luastring(v)); lua.lua_setfield(L, -2, to_luastring(k)); }
        lua.lua_setglobal(L, to_luastring("X1_TEXT"));
        for (const k of KEYS) {
          lua.lua_getglobal(L, to_luastring("X1_TR"));
          lua.lua_pushstring(L, to_luastring(k));
          lua.lua_pushstring(L, to_luastring("\u0001FALLBACK"));
          if (lua.lua_pcall(L, 2, 1, 0) !== lua.LUA_OK) { failures.push(`X1 ${loc}: tr("${k}") raised ${to_jsstring(lua.lua_tostring(L, -1))}`); lua.lua_pop(L, 1); continue; }
          const got = to_jsstring(lua.lua_tostring(L, -1));
          lua.lua_pop(L, 1);
          x1++;
          if (got !== files[loc].get(k)) failures.push(`X1 ${loc}: tr("${k}") returned "${String(got).slice(0, 40)}", not the file's text`);
        }
      }
    }
  }
}

if (failures.length) {
  const shown = failures.slice(0, 60);
  for (const f of shown) console.log("FAIL " + f);
  if (failures.length > shown.length) console.log(`... and ${failures.length - shown.length} more`);
  console.log(`l10n-esc-page: ${failures.length} failure(s) over ${KEYS.length * locales.length} entries (${KEYS.length} keys x ${locales.length} locales)`);
  process.exit(1);
}
console.log(`l10n-esc-page: PASS - ${KEYS.length * locales.length} entries checked (${KEYS.length} keys x ${locales.length} locales), ` +
  `${read.size} keys read in src/, ${Object.keys(NO_READER).length} page keys with no reader, script rule: ${scriptChecked} values ` +
  `in ${Object.keys(SCRIPT).filter((l) => locales.includes(l)).join(", ")}${existsSync(join(tdir, "translation_cs.xml")) ? "" : " (no translation_cs.xml)"}, ` +
  `X1 ${x1} lookups executed through the page's own tr`);
