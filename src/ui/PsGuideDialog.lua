-- =========================================================
-- Pro Staff Field Guide - Field Guide
-- =========================================================
-- BUILD 19:15 (George CLOSED DESIGN 18:55 item 5): every Realistic Farming Esc page gets its own
-- guide, in its own mod, opened from the shared Help footer through this guest's onOpenHelp. The
-- chrome is SoilGuideDialog's so all of them read as one family; only the words differ.
-- Rows are { t = "H" | "B" | "S" | "COL", v = "text" }: header, body, spacer, column break.
-- =========================================================

---@class PsGuideDialog
PsGuideDialog = PsGuideDialog or {}
local PsGuideDialog_mt = Class(PsGuideDialog, ScreenElement)

local GUIDE_MOD_DIR = (ProStaffCoOpModDirectory or g_currentModDirectory)

PsGuideDialog.INSTANCE = nil
PsGuideDialog.GUI_NAME = "PsGuideDialog"

PsGuideDialog.SUBTITLES = {
    "Overview - what Pro Staff does and the Esc page",
    "The Ladder - all twenty rungs and what they give",
    "Buy and Run - buying rungs, the flush, the money",
    "Settings - the options and common questions",
}

PsGuideDialog.PAGE1 = {
    { t="H", v="WHAT PRO STAFF CO-OP IS" },
    { t="B", v="Pro Staff Co-Op is a farm membership with" },
    { t="B", v="twenty levels. Your farm buys its way up the" },
    { t="B", v="ladder one rung at a time." },
    { t="S", v=" " },
    { t="B", v="Each rung you reach makes some part of the" },
    { t="B", v="farm cheaper or better: lower wages, cheaper" },
    { t="B", v="fertilizer and fungicide, less tired" },
    { t="B", v="workers, cheaper vet supplies, better dairy" },
    { t="B", v="hauling, and access to reports." },
    { t="S", v=" " },
    { t="B", v="The membership belongs to the farm, not to" },
    { t="B", v="one player. Everyone on the farm shares it." },
    { t="S", v=" " },
    { t="H", v="WHERE TO FIND IT" },
    { t="B", v="Open the in game menu and pick the" },
    { t="B", v="Realistic Farming tab. In the list of" },
    { t="B", v="modules choose Pro Staff." },
    { t="S", v=" " },
    { t="B", v="Progress is saved with your game." },
    { t="COL", v="" },
    { t="H", v="WHAT THE PAGE SHOWS" },
    { t="B", v="The top line names the rung you are on, how" },
    { t="B", v="much the farm has invested so far, and the" },
    { t="B", v="name and price of the next rung." },
    { t="S", v=" " },
    { t="B", v="Below that are all twenty rungs as cards," },
    { t="B", v="four across and five down, in buying order." },
    { t="B", v="Each card gives the rung number, its name," },
    { t="B", v="what buying it adds, and what it would cost" },
    { t="B", v="you right now." },
    { t="S", v=" " },
    { t="B", v="A green bar and a lit card mark the rung you" },
    { t="B", v="are on. Cards below it are reached. Dim" },
    { t="B", v="cards are still ahead of you." },
    { t="S", v=" " },
    { t="B", v="The bottom line shows the monthly agronomy" },
    { t="B", v="report fee, the fleet rebate and the price" },
    { t="B", v="of a disease flush on your fields." },
    { t="S", v=" " },
    { t="B", v="The box on the right explains the page and" },
    { t="B", v="lists any notes that apply to your farm." },
}

PsGuideDialog.PAGE2 = {
    { t="H", v="THE TWENTY RUNGS" },
    { t="B", v="You buy rungs in order, one at a time. A" },
    { t="B", v="rung you have reached stays reached." },
    { t="S", v=" " },
    { t="B", v="L1 Office Access. Nothing live yet." },
    { t="B", v="L2 Procurement Access. Fertilizer, fungicide" },
    { t="B", v="   and vet supplies all cost a little less." },
    { t="B", v="L3 Scheduling Optimization. Dairy hauling" },
    { t="B", v="   works better." },
    { t="B", v="L4 Comms Relay. Workers tire more slowly." },
    { t="B", v="L5 Labor Welfare. Wages drop a step." },
    { t="B", v="L6 Loading Automation. Nothing live yet." },
    { t="B", v="L7 Bulk Silo Admin. More off fertilizer and" },
    { t="B", v="   weather forecasts arrive. The monthly" },
    { t="B", v="   agronomy report fee starts here." },
    { t="B", v="L8 Regional Mesh. Workers tire less again." },
    { t="B", v="L9 Personnel Records. Wages drop again." },
    { t="B", v="L10 Academic Liaison. A soil test kit, and" },
    { t="B", v="   prices start to follow your net worth." },
    { t="COL", v="" },
    { t="H", v="RUNGS ELEVEN TO TWENTY" },
    { t="B", v="L11 Labor Recovery. Workers recover faster." },
    { t="B", v="L12 Precision Agronomy. More off fertilizer" },
    { t="B", v="   and vet supplies. Fungicide works better." },
    { t="B", v="L13 Global Comms. Spraying costs less and" },
    { t="B", v="   workers tire much less." },
    { t="B", v="L14 Fleet Logistics. A fleet rebate is paid" },
    { t="B", v="   into the farm every month." },
    { t="B", v="L15 Syndicate Board. The best fertilizer" },
    { t="B", v="   discount, better bulk buying and market" },
    { t="B", v="   intelligence." },
    { t="B", v="L16 Curriculum Admin. Nothing live yet." },
    { t="B", v="L17 Payroll Oversight. Wages drop a step." },
    { t="B", v="L18 Predictive Control. Fastest recovery" },
    { t="B", v="   and predictive control." },
    { t="B", v="L19 System Overdrive. All work is a little" },
    { t="B", v="   more effective." },
    { t="B", v="L20 Sovereign Admin. Top effectiveness." },
    { t="S", v=" " },
    { t="B", v="A few rungs are named on the ladder but do" },
    { t="B", v="not change anything yet. Their card says so." },
}

PsGuideDialog.PAGE3 = {
    { t="H", v="BUYING THE NEXT RUNG" },
    { t="B", v="The Buy button sits under the ladder. It" },
    { t="B", v="names the rung it will buy, and it reads At" },
    { t="B", v="MAX once the ladder is finished." },
    { t="S", v=" " },
    { t="B", v="Buying takes the price from the farm" },
    { t="B", v="account. If the farm cannot afford it the" },
    { t="B", v="page says so and nothing is bought." },
    { t="S", v=" " },
    { t="B", v="In multiplayer the server does the buying." },
    { t="B", v="The page tells you the request was sent." },
    { t="S", v=" " },
    { t="H", v="HOW THE PRICE IS SET" },
    { t="B", v="Each rung costs a good deal more than the" },
    { t="B", v="one below it. From rung ten up the price" },
    { t="B", v="follows your farm's net worth, not the cash" },
    { t="B", v="in hand, and it stops rising at a top band." },
    { t="S", v=" " },
    { t="B", v="Invested is what you really paid. The figure" },
    { t="B", v="on each card is what that rung would cost" },
    { t="B", v="you today." },
    { t="COL", v="" },
    { t="H", v="THE DISEASE FLUSH" },
    { t="B", v="Run pays for a farm wide disease treatment," },
    { t="B", v="and reads No flush needed when none is due." },
    { t="S", v=" " },
    { t="B", v="The quote counts every diseased field and" },
    { t="B", v="adds a fee for each one. A worse infection" },
    { t="B", v="costs more. The Economy setting scales it." },
    { t="S", v=" " },
    { t="B", v="The money is taken first, then each diseased" },
    { t="B", v="field is treated with the right product. On" },
    { t="B", v="the gentlest difficulty they are cleared." },
    { t="S", v=" " },
    { t="B", v="Only one flush runs at a time per farm, and" },
    { t="B", v="the quote needs the Soil Fertilizer disease" },
    { t="B", v="system to be present." },
    { t="S", v=" " },
    { t="H", v="MONEY THAT REPEATS" },
    { t="B", v="From rung seven a monthly agronomy report" },
    { t="B", v="fee can be charged, if it is turned on." },
    { t="S", v=" " },
    { t="B", v="From rung fourteen a fleet rebate is paid" },
    { t="B", v="into the farm each month." },
}

PsGuideDialog.PAGE4 = {
    { t="H", v="SETTINGS" },
    { t="B", v="These sit with the shared Realistic Farming" },
    { t="B", v="settings, under Pro Staff Co-Op. In" },
    { t="B", v="multiplayer only an admin may change them." },
    { t="S", v=" " },
    { t="B", v="Pro Staff Co-Op Enabled. On by default. Off" },
    { t="B", v="means nothing on the page is live." },
    { t="S", v=" " },
    { t="B", v="Level Base Cost. The whole ladder scales" },
    { t="B", v="with this. It starts at 260 and can be set" },
    { t="B", v="from 50 to 2000." },
    { t="S", v=" " },
    { t="B", v="Agronomy Report Sub Fee. Off by default." },
    { t="B", v="Turn it on to charge the monthly report fee" },
    { t="B", v="to farms at rung seven or above." },
    { t="S", v=" " },
    { t="B", v="Agronomy Fee (per month). The size of that" },
    { t="B", v="fee. It starts at 800 and runs to 10000." },
    { t="S", v=" " },
    { t="B", v="Experimental Systems. Off by default. It" },
    { t="B", v="allows unfinished features, at your own risk." },
    { t="COL", v="" },
    { t="H", v="COMMON QUESTIONS" },
    { t="B", v="I bought a rung and see no difference." },
    { t="B", v="Each benefit is used by another Realistic" },
    { t="B", v="Farming mod. Without that mod the rung" },
    { t="B", v="still counts but nothing changes." },
    { t="S", v=" " },
    { t="B", v="Some cards say a benefit is not applied." },
    { t="B", v="Those rungs are unlocked but do not pay" },
    { t="B", v="out yet. The card says so." },
    { t="S", v=" " },
    { t="B", v="Spectator. Join a farm to see membership." },
    { t="B", v="You cannot buy or flush from that seat." },
    { t="S", v=" " },
    { t="B", v="Precision Farming installed. The fertilizer" },
    { t="B", v="and fungicide discounts stand down while it" },
    { t="B", v="is loaded. Every other rung keeps working." },
    { t="S", v=" " },
    { t="B", v="The soil test kit at rung ten is still" },
    { t="B", v="experimental and stays off until" },
    { t="B", v="Experimental Systems is turned on." },
    { t="S", v=" " },
    { t="B", v="There is no key for this page. Open it from" },
    { t="B", v="the game menu." },
}

PsGuideDialog.PAGE_CONTENT = { PsGuideDialog.PAGE1, PsGuideDialog.PAGE2, PsGuideDialog.PAGE3, PsGuideDialog.PAGE4 }

-- -- Constructor ------------------------------------------

function PsGuideDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or PsGuideDialog_mt)
    self._contentLineEls = {}
    self._currentPage = 1
    return self
end

--- Loads the dialog into g_gui once. Safe to call twice, and safe to call when some other path has
--- already registered the same name.
function PsGuideDialog.register(modDirectory)
    if g_gui == nil then return end
    if g_gui.guis ~= nil and g_gui.guis[PsGuideDialog.GUI_NAME] ~= nil then return end
    if modDirectory ~= nil then GUIDE_MOD_DIR = modDirectory end
    if GUIDE_MOD_DIR == nil then return end
    PsGuideDialog.INSTANCE = PsGuideDialog.new()
    local ok, err = pcall(function()
        g_gui:loadGui(GUIDE_MOD_DIR .. "xml/gui/PsGuideDialog.xml", PsGuideDialog.GUI_NAME, PsGuideDialog.INSTANCE)
    end)
    if not ok then
        print("[ProStaff] PsGuideDialog: loadGui failed: " .. tostring(err))
        PsGuideDialog.INSTANCE = nil
    end
end

function PsGuideDialog.show()
    if g_gui == nil then return end
    local loaded = g_gui.guis ~= nil and g_gui.guis[PsGuideDialog.GUI_NAME] ~= nil
    if not loaded then
        PsGuideDialog.register(GUIDE_MOD_DIR)
        loaded = g_gui.guis ~= nil and g_gui.guis[PsGuideDialog.GUI_NAME] ~= nil
    end
    if not loaded then return end
    g_gui:showDialog(PsGuideDialog.GUI_NAME)
end

-- -- Lifecycle --------------------------------------------

function PsGuideDialog:onGuiSetupFinished()
    PsGuideDialog:superClass().onGuiSetupFinished(self)
    self._elCol1 = self:getDescendantById("psGuide_col1")
    self._elCol2 = self:getDescendantById("psGuide_col2")
    self._elSubtitle = self:getDescendantById("psGuide_subtitle")
end

function PsGuideDialog:onOpen()
    PsGuideDialog:superClass().onOpen(self)
    self._currentPage = 1
    self:_selectPage(1)
end

function PsGuideDialog:onClose()
    PsGuideDialog:superClass().onClose(self)
    self:_clearContent()
    self._currentPage = 1
end

-- -- Tabs -------------------------------------------------

function PsGuideDialog:onClickTab1() self:_selectPage(1) end
function PsGuideDialog:onClickTab2() self:_selectPage(2) end
function PsGuideDialog:onClickTab3() self:_selectPage(3) end
function PsGuideDialog:onClickTab4() self:_selectPage(4) end

function PsGuideDialog:_selectPage(pageNum)
    if self._currentPage == pageNum and #self._contentLineEls > 0 then return end
    self:_clearContent()
    self._currentPage = pageNum
    if self._elSubtitle ~= nil then
        self._elSubtitle:setText(PsGuideDialog.SUBTITLES[pageNum] or "")
    end
    self:_buildContent(pageNum)
end

-- -- Content ----------------------------------------------

function PsGuideDialog:_buildContent(pageNum)
    local profileH = g_gui:getProfile("psGuide_colHeader")
    local profileB = g_gui:getProfile("psGuide_colBody")
    local profileS = g_gui:getProfile("psGuide_colSpacer")
    if not profileH or not profileB then
        print("[ProStaff] PsGuideDialog: column profiles not found")
        return
    end
    local content = PsGuideDialog.PAGE_CONTENT[pageNum]
    if content == nil then return end
    local currentBox = self._elCol1
    for _, row in ipairs(content) do
        if row.t == "COL" then
            if self._elCol1 ~= nil then self._elCol1:invalidateLayout() end
            currentBox = self._elCol2
        elseif currentBox ~= nil then
            local profile = (row.t == "H") and profileH
                         or (row.t == "S") and profileS
                         or profileB
            if profile ~= nil then
                local el = TextElement.new()
                el:loadProfile(profile, true)
                el:setText(row.v or "")
                currentBox:addElement(el)
                el:onGuiSetupFinished()
                table.insert(self._contentLineEls, { box = currentBox, el = el })
            end
        end
    end
    if self._elCol2 ~= nil then self._elCol2:invalidateLayout() end
end

function PsGuideDialog:_clearContent()
    for _, entry in ipairs(self._contentLineEls or {}) do
        if entry.box ~= nil then
            entry.box:removeElement(entry.el)
        end
    end
    self._contentLineEls = {}
    if self._elCol1 ~= nil then self._elCol1:invalidateLayout() end
    if self._elCol2 ~= nil then self._elCol2:invalidateLayout() end
end

-- -- Button -----------------------------------------------

function PsGuideDialog:onClickClose()
    g_gui:closeDialogByName(PsGuideDialog.GUI_NAME)
end
