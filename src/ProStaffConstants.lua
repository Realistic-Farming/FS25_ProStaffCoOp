-- =========================================================
-- FS25_ProStaffCoOp - Constants (all tunables + the 20-level effect tables)
-- =========================================================
-- Author: TisonK
-- Global: ProStaffConstants. The effect tables drive ProStaffAPI: each is a
-- {level = value} map. "STEP" effects return the value of the highest level
-- reached; WAGE is the multiplicative product of every reached step (per the
-- brief: L5 x L9 x L17 = 0.833). All numbers ride the balance pass.
-- =========================================================

ProStaffConstants = {}

ProStaffConstants.MAX_LEVEL = 20
ProStaffConstants.COST_EXPONENT = 2.2

-- baseCost presets (SettingsHub). Default = Standard.
ProStaffConstants.PRESETS = {
    cooperative = 100,
    standard    = 260,
    hardcore    = 550,
}
ProStaffConstants.DEFAULT_BASE_COST = 260

-- Wealth-bracket escalator (F5-F): activates on L10+ rungs only, keyed on farm
-- NET WORTH read at purchase time, CAPPED at the top bracket. Premium (above 1.0)
-- rides the Economy dial (neutral here). Thresholds/magnitudes are indicative.
ProStaffConstants.WEALTH_BRACKET = {
    ACTIVATES_AT_LEVEL = 10,
    -- ascending thresholds on net worth; the first row whose max the worth is under wins
    TIERS = {
        { max = 500000,   mult = 1.00 },
        { max = 2000000,  mult = 1.10 },
        { max = 5000000,  mult = 1.20 },
        { max = math.huge, mult = 1.35 },  -- CAPPED ceiling
    },
}

-- The recurring report subscription (agronomyFee) + defaults per preset.
ProStaffConstants.AGRONOMY_FEE = {
    DEFAULT = 800,
    CADENCE = "month",   -- Time Guard calendar tick (rule 10; no "week")
    LABEL = "Co-Op Agronomy Report Sub",
}

-- Rebate labels (audit lines).
ProStaffConstants.LABELS = {
    INVESTMENT = "Co-Op Membership Investment",
    HERDSMAN_REBATE = "Co-Op Herdsman Rebate",
    FLEET_REBATE = "Co-Op Fleet Rebate",
}
ProStaffConstants.L9_HERDSMAN_REBATE_RATE = 0.03
ProStaffConstants.L14_FLEET_REBATE = 2500   -- indicative per-cadence credit (balance pass)

-- =========================================================
-- Effect tables (level -> value)
-- =========================================================
ProStaffConstants.EFFECTS = {
    -- Wage modifier: MULTIPLICATIVE product of every reached step (< 1 = cheaper).
    WAGE = { steps = { [5] = 0.975, [9] = 0.95, [17] = 0.90 }, mode = "product", neutral = 1.0 },

    -- Fertilizer discount: highest reached (totals per the level table).
    FERTILIZER = { steps = { [2] = 0.985, [7] = 0.96, [12] = 0.94, [15] = 0.925 }, mode = "step", neutral = 1.0 },

    FUNGICIDE_DISCOUNT = { steps = { [2] = 0.95 }, mode = "step", neutral = 1.0 },
    FUNGICIDE_EFFECT   = { steps = { [12] = 1.10 }, mode = "step", neutral = 1.0 },
    SPRAY_COST         = { steps = { [13] = 0.92 }, mode = "step", neutral = 1.0 },

    FATIGUE_MITIGATION = { steps = { [4] = 0.90, [8] = 0.80, [13] = 0.65 }, mode = "step", neutral = 1.0 },
    FATIGUE_RECOVERY   = { steps = { [11] = 1.75, [18] = 1.85 }, mode = "step", neutral = 1.0 },

    VET_SUPPLY   = { steps = { [2] = 0.95, [12] = 0.90 }, mode = "step", neutral = 1.0 },   -- L12 supersedes L2
    DAIRY_LOGISTICS = { steps = { [3] = 1.05 }, mode = "step", neutral = 1.0 },
    BULK_PROCUREMENT = { steps = { [15] = 1.05 }, mode = "step", neutral = 1.0 },
    BULK_TRANSPORT   = { steps = { [14] = 0.925 }, mode = "step", neutral = 1.0 },  -- DESIGNED-NOT-BUILT: no confirmed apply site

    GLOBAL_EFFECTIVENESS = { steps = { [19] = 1.05, [20] = 1.15 }, mode = "step", neutral = 1.0 },
}

-- Boolean feature unlocks (first active at level).
ProStaffConstants.FLAGS = {
    hasMarketIntel      = 15,
    hasForecastAccess   = 7,
    hasPredictiveControl = 18,
    hasEarlyWarning     = 20,
}

-- Level names for display.
ProStaffConstants.LEVEL_NAMES = {
    "Office Access", "Procurement Access", "Scheduling Optimization", "Comms Relay", "Labor Welfare",
    "Loading Automation", "Bulk Silo Admin", "Regional Mesh", "Personnel Records", "Academic Liaison",
    "Labor Recovery", "Precision Agronomy", "Global Comms", "Fleet Logistics", "Syndicate Board",
    "Curriculum Admin", "Payroll Oversight", "Predictive Control", "System Overdrive", "Sovereign Admin",
}

ProStaffConstants.LEDGER_STATE = "ProStaffCoOp_State"
ProStaffConstants.NETWORK_CHANNEL = "ProStaffCoOp_Level"
ProStaffConstants.ACTION_BUY = "ProStaffCoOp_buyLevel"
ProStaffConstants.SETTLE_PRIORITY = 30
