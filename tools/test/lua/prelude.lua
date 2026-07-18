-- prelude.lua - minimal FS25 engine mock + tiny test framework for ProStaff.
-- Loaded first by run-tests.mjs, before any src module and the test file itself.
-- Only stubs what module load + the functions under test actually touch.

-- Lua 5.1 <-> fengari (5.3) shims
unpack = unpack or table.unpack

-- Class(base): FS25's OO helper. Returns a metatable whose __index chains to base,
-- enough for `setmetatable({}, Class(Foo))` and method dispatch in tests.
function Class(base)
  local mt = {}
  mt.__index = base or mt
  return mt
end

-- ProStaff's logger (src/Logger.lua defines PSLogger in-game; stub it here so the
-- Manager's PSLogger.info/warning calls are harmless no-ops under test).
PSLogger = PSLogger or {
  info = function() end,
  warning = function() end,
  error = function() end,
  debug = function() end,
  print = function() end,
}

-- Engine globals the pure getters may brush against. g_farmManager is left nil by
-- default; a test assigns it when exercising the net-worth / wealth-bracket path.
g_currentMission = {
  getFarmId = function() return 1 end,
  getIsServer = function() return true end,
}
g_farmManager = nil
g_modIsLoaded = {}
MoneyType = { OTHER = 1 }

-- tiny test framework - results emitted as ##TEST_ lines run-tests.mjs parses.
T = { _pass = 0, _fail = 0 }

local function _pass(name)
  T._pass = T._pass + 1
  print("##TEST_PASS " .. name)
end
local function _fail(name, msg)
  T._fail = T._fail + 1
  print("##TEST_FAIL " .. name .. " :: " .. tostring(msg))
end

function T.ok(name, cond, msg)
  if cond then _pass(name) else _fail(name, msg or "expected truthy, got " .. tostring(cond)) end
end

function T.eq(name, got, want)
  if got == want then _pass(name)
  else _fail(name, "got " .. tostring(got) .. " want " .. tostring(want)) end
end

function T.near(name, got, want, tol)
  tol = tol or 1e-6
  if type(got) == "number" and math.abs(got - want) <= tol then _pass(name)
  else _fail(name, "got " .. tostring(got) .. " want ~" .. tostring(want) .. " (tol " .. tostring(tol) .. ")") end
end

function T.summary()
  print("##TEST_SUMMARY " .. T._pass .. " " .. T._fail)
end
