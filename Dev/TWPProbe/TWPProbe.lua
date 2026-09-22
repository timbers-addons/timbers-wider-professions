local ADDON_NAME = ...

-- Dev-only probe for the Forever (camelot) client. Records what the profession
-- API looks like there so the Forever backend is built on facts. Everything is
-- pcall-wrapped and written to TWPProbeDB; /reload flushes it to
-- WTF\Account\<account>\SavedVariables\TWPProbe.lua.

local frame = CreateFrame("Frame")
local db
local registered = {}

local function say(msg)
    print("|cff33ff99TWPProbe|r: " .. msg)
end

local function results(ok, ...)
    if ok then return ... end
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return results(pcall(fn, ...))
end

-- Secret values error on any comparison or conversion, and would likely break
-- the SavedVariables write too, so everything stored goes through here.
local function clean(v)
    local ok, out = pcall(function()
        if v == nil then return nil end
        local t = type(v)
        if (t == "number" or t == "string" or t == "boolean") and v == v then return v end
        return tostring(v)
    end)
    if ok then return out end
    return "<unreadable>"
end

local function copy(v, depth)
    if type(v) ~= "table" then return clean(v) end
    if depth <= 0 then return "<table>" end
    local out = {}
    for k, val in pairs(v) do
        local key = clean(k)
        if key ~= nil and type(val) ~= "function" and type(val) ~= "userdata" then
            out[key] = copy(val, depth - 1)
        end
    end
    return out
end

local function snap(v, depth)
    local ok, out = pcall(copy, v, depth or 3)
    if ok then return out end
    return "<error: " .. tostring(out) .. ">"
end

local function resolve(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return v
end

-- Static facts ----------------------------------------------------------------

local GLOBALS = {
    -- old trade skill / craft API
    "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillLine", "SelectTradeSkill", "DoTradeSkill",
    "GetNumCrafts", "GetCraftInfo", "CraftIsEnchanting", "GetCraftDisplaySkillLine",
    "GetPetTrainingPoints", "C_PetInfo.GetPetTrainingPoints",
    "TradeSkillFrame", "CraftFrame", "ProfessionsFrame",
    -- skills
    "GetNumSkillLines", "GetSkillLineInfo", "GetProfessions", "GetProfessionInfo",
    -- spells and items
    "GetSpellInfo", "C_Spell.GetSpellInfo", "C_Spell.GetSpellName", "C_Spell.GetSpellTexture",
    "C_Spell.GetSpellDescription",
    "IsSpellKnown", "IsPlayerSpell", "C_SpellBook.IsSpellKnown", "C_SpellBook.IsSpellInSpellBook",
    "GetItemInfo", "C_Item.GetItemInfo", "GetItemCount", "C_Item.GetItemCount",
    "GetItemQualityColor", "C_Item.GetItemQualityColor",
    -- chat links and clicks
    "ChatEdit_InsertLink", "ChatFrameUtil.InsertLink", "HandleModifiedItemClick", "IsModifiedClick",
    "DressUpItemLink", "StackSplitCancelButton", "StackSplitFrame", "ChatFrame1EditBox", "MerchantFrame",
    -- panels and loading
    "UIParentLoadAddOn", "C_AddOns.LoadAddOn", "C_AddOns.IsAddOnLoaded", "ShowUIPanel", "HideUIPanel",
    "UIPanelWindows", "UISpecialFrames", "Settings.OpenToCategory", "Settings.RegisterCanvasLayoutCategory",
    "Settings.RegisterAddOnCategory", "InterfaceOptions_AddCategory",
    -- tooltips
    "GameTooltip.SetSpellByID", "GameTooltip.SetHyperlink", "GameTooltip.SetCraftSpell",
    "GameTooltip.SetRecipeResultItem", "GameTooltip.SetRecipeReagentItem",
    -- misc used by the addon
    "C_CreatureInfo.GetCreatureFamilyInfo", "C_CVar.GetCVarBool", "C_Timer.After", "SOUNDKIT",
    "issecretvalue", "hooksecurefunc",
    "FAVORITES", "BINDING_HEADER_MISC", "PET_PASSIVE", "CRAFT_IS_MAKEABLE", "CRAFT_IS_MAKEABLE_TOOLTIP",
    "MINIMAP_TRACKING_VENDOR_REAGENT", "BATTLE_PET_FAVORITE", "SPELL_FAILED_NO_PET", "SETTINGS", "SEARCH",
}

local TEMPLATES = {
    { "Frame", "PortraitFrameTemplate", { "TitleText", "TitleContainer", "CloseButton", "SetPortraitTextureRaw", "SetPortraitToAsset", "SetTitle" } },
    { "Frame", "InsetFrameTemplate", {} },
    { "Slider", "UIPanelScrollBarTemplate", { "ScrollUpButton", "ScrollDownButton" } },
    { "EditBox", "SearchBoxTemplate", { "Instructions", "clearButton" } },
    { "CheckButton", "UICheckButtonTemplate", {} },
    { "Button", "UIPanelButtonTemplate", {} },
}

local SPELLS = {
    beastTraining = 5149, beastLore = 1462, poisons = 2842,
    alchemy = 2259, cooking = 2550, firstAid = 3273, enchanting = 7411,
}

local function probeStatic()
    local out = {}

    local version, build, date, interface = call(GetBuildInfo)
    out.client = {
        version = clean(version), build = clean(build), date = clean(date), interface = clean(interface),
        projectID = clean(WOW_PROJECT_ID), locale = clean(call(GetLocale)),
        class = clean(select(2, call(UnitClass, "player"))), level = clean(call(UnitLevel, "player")),
    }
    out.tocLoaded = clean(call(C_AddOns and C_AddOns.GetAddOnMetadata, ADDON_NAME, "X-TWPProbe-TOC"))
    out.loadDeprecationFallbacks = clean(call(C_CVar and C_CVar.GetCVar, "loadDeprecationFallbacks"))

    out.globals, out.missing = {}, {}
    for _, path in ipairs(GLOBALS) do
        local v = resolve(path)
        out.globals[path] = type(v)
        if v == nil then out.missing[#out.missing + 1] = path end
    end

    out.templates = {}
    for _, spec in ipairs(TEMPLATES) do
        local widget, template, keys = spec[1], spec[2], spec[3]
        local ok, f = pcall(CreateFrame, widget, nil, UIParent, template)
        local rec = { ok = ok, err = (not ok) and clean(f) or nil, keys = {} }
        if ok and f then
            f:Hide()
            for _, key in ipairs(keys) do rec.keys[key] = type(f[key]) end
        end
        out.templates[template] = rec
    end

    out.addons = {}
    for _, name in ipairs({ "Blizzard_Professions", "Blizzard_ProfessionsBook", "Blizzard_TradeSkillUI", "Blizzard_CraftUI" }) do
        out.addons[name] = {
            exists = clean(call(C_AddOns and C_AddOns.DoesAddOnExist, name)),
            loaded = clean(call(C_AddOns and C_AddOns.IsAddOnLoaded, name)),
        }
    end

    out.tradeSkillFunctions = {}
    if type(C_TradeSkillUI) == "table" then
        for name, fn in pairs(C_TradeSkillUI) do
            if type(fn) == "function" then out.tradeSkillFunctions[#out.tradeSkillFunctions + 1] = name end
        end
        table.sort(out.tradeSkillFunctions)
    end
    out.difficultyEnum = snap(Enum and Enum.TradeskillRelativeDifficulty)

    out.spells = {}
    for key, spellID in pairs(SPELLS) do
        local info = call(C_Spell and C_Spell.GetSpellInfo, spellID)
        out.spells[key] = {
            spellID = spellID,
            name = type(info) == "table" and clean(info.name) or nil,
            icon = type(info) == "table" and clean(info.iconID) or nil,
            isPlayerSpell = clean(call(IsPlayerSpell, spellID)),
            spellBookKnown = clean(call(C_SpellBook and C_SpellBook.IsSpellKnown, spellID)),
        }
    end

    out.professions = {}
    local function walk(...)
        for i = 1, select("#", ...) do
            local index = select(i, ...)
            if index then
                local name, icon, rank, maxRank, _, spellOffset, skillLine = call(GetProfessionInfo, index)
                -- The opening spell sits first in the profession's spellbook range (Blizzard's tabs read it the same way).
                local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
                local book = spellOffset and call(C_SpellBook and C_SpellBook.GetSpellBookItemInfo, spellOffset + 1, bank)
                out.professions[#out.professions + 1] = {
                    slot = i, name = clean(name), icon = clean(icon),
                    rank = clean(rank), maxRank = clean(maxRank), skillLine = clean(skillLine),
                    spellID = type(book) == "table" and clean(book.spellID) or nil,
                    spellName = type(book) == "table" and clean(book.name) or nil,
                }
            end
        end
    end
    walk(call(GetProfessions))

    db.static = out
end

-- Open profession window --------------------------------------------------------

local MAX_SAMPLES = 5
local lastScanLine

local function sampleRecipe(T, recipeID, info)
    local rec = { recipeID = recipeID, info = snap(info, 2) }
    rec.category = snap(call(T.GetCategoryInfo, info.categoryID), 2)
    rec.itemLink = clean(call(T.GetRecipeItemLink, recipeID))
    rec.recipeLink = clean(call(T.GetRecipeLink, recipeID))
    rec.description = clean(call(T.GetRecipeDescription, recipeID, {}))
    rec.cooldown = clean(call(T.GetRecipeCooldown, recipeID))
    rec.requirements = snap(call(T.GetRecipeRequirements, recipeID), 3)
    rec.sourceText = clean(call(T.GetRecipeSourceText, recipeID))

    local schematic = call(T.GetRecipeSchematic, recipeID, false)
    if type(schematic) == "table" then
        rec.schematic = {
            name = clean(schematic.name), icon = clean(schematic.icon), recipeType = clean(schematic.recipeType),
            quantityMin = clean(schematic.quantityMin), quantityMax = clean(schematic.quantityMax),
            outputItemID = clean(schematic.outputItemID), slots = {},
        }
        for i, slot in ipairs(schematic.reagentSlotSchematics or {}) do
            local reagent = type(slot.reagents) == "table" and slot.reagents[1] or nil
            local itemID = reagent and reagent.itemID or nil
            rec.schematic.slots[i] = {
                reagentType = clean(slot.reagentType), required = clean(slot.required),
                quantityRequired = clean(slot.quantityRequired), numChoices = type(slot.reagents) == "table" and #slot.reagents or 0,
                itemID = clean(itemID),
                itemName = itemID and clean(call(C_Item and C_Item.GetItemInfo, itemID)) or nil,
                playerCount = itemID and clean(call(C_Item and C_Item.GetItemCount, itemID)) or nil,
            }
        end
    end
    return rec
end

local function frameFacts()
    local pf = ProfessionsFrame
    local out = { exists = pf ~= nil }
    if not pf then return out end
    out.shown = clean(call(pf.IsShown, pf))
    out.alpha = clean(call(pf.GetAlpha, pf))
    out.width, out.height = clean(call(pf.GetWidth, pf)), clean(call(pf.GetHeight, pf))
    out.panelArea = clean(call(pf.GetAttribute, pf, "UIPanelLayout-area"))
    out.inUIPanelWindows = UIPanelWindows and UIPanelWindows["ProfessionsFrame"] ~= nil or false
    local page = pf.CraftingPage
    out.craftingPage = {}
    if type(page) == "table" then
        for _, key in ipairs({ "CreateButton", "CreateAllButton", "CreateMultipleInputBox", "RecipeList", "SchematicForm", "RankBar" }) do
            out.craftingPage[key] = type(page[key])
        end
    end
    return out
end

local function scanTradeSkill()
    local T = C_TradeSkillUI
    if type(T) ~= "table" then
        db.tradeskill = { error = "no C_TradeSkillUI" }
        return
    end

    local out = { scannedAt = clean(call(GetTime)) }
    out.ready = clean(call(T.IsTradeSkillReady))
    -- LIST_UPDATE also fires after the window closes, when there is nothing to read.
    if out.ready ~= true then return end
    out.linked = clean(call(T.IsTradeSkillLinked))
    out.base = snap(call(T.GetBaseProfessionInfo), 2)
    out.child = snap(call(T.GetChildProfessionInfo), 2)
    out.frame = frameFacts()

    local ids = call(T.GetAllRecipeIDs)
    if type(ids) ~= "table" then ids = {} end
    out.numRecipeIDs = #ids
    out.numLearned, out.numUnlearned, out.numCraftable = 0, 0, 0
    out.difficulty = {}
    out.samples, out.unlearnedSamples = {}, {}

    local candidate, enchantCandidate
    for _, recipeID in ipairs(ids) do
        local info = call(T.GetRecipeInfo, recipeID)
        if type(info) == "table" then
            if clean(info.learned) == true then
                out.numLearned = out.numLearned + 1
                local key = tostring(clean(info.relativeDifficulty))
                out.difficulty[key] = (out.difficulty[key] or 0) + 1
                -- Recipe info has no numAvailable on this client; Blizzard's list asks for it per recipe.
                local available = clean(call(T.GetCraftableCount, recipeID))
                local craftable = type(available) == "number" and available > 0
                if craftable then
                    out.numCraftable = out.numCraftable + 1
                    if clean(info.isEnchantingRecipe) == true and not enchantCandidate then
                        enchantCandidate = { recipeID = recipeID, name = clean(info.name) }
                        out.enchantSample = sampleRecipe(T, recipeID, info)
                    end
                    if not candidate then
                        candidate = { recipeID = recipeID, name = clean(info.name) }
                        table.insert(out.samples, 1, sampleRecipe(T, recipeID, info))
                    end
                end
                if #out.samples < MAX_SAMPLES and not (candidate and candidate.recipeID == recipeID) then
                    out.samples[#out.samples + 1] = sampleRecipe(T, recipeID, info)
                end
            else
                out.numUnlearned = out.numUnlearned + 1
                if #out.unlearnedSamples < 3 then out.unlearnedSamples[#out.unlearnedSamples + 1] = sampleRecipe(T, recipeID, info) end
            end
        end
    end
    while #out.samples > MAX_SAMPLES do table.remove(out.samples) end

    db.craftCandidate = candidate
    db.enchantCandidate = enchantCandidate
    local name = type(out.base) == "table" and out.base.professionName or nil
    db.tradeskill[type(name) == "string" and name or "unknown"] = out
    local line = ("scanned %s: %d recipe ids, %d learned, %d unlearned, %d craftable."):format(
        tostring(name), out.numRecipeIDs, out.numLearned, out.numUnlearned, out.numCraftable)
    if line ~= lastScanLine then say(line) end
    lastScanLine = line
end

-- Events ------------------------------------------------------------------------

local WATCHED = {
    "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_DATA_SOURCE_CHANGING", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_DETAILS_UPDATE",
    "TRADE_SKILL_NAME_UPDATE", "TRADE_SKILL_ITEM_CRAFTED_RESULT", "NEW_RECIPE_LEARNED",
    "CRAFT_SHOW", "CRAFT_CLOSE", "CRAFT_UPDATE", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL",
    "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED",
    "REPLACE_ENCHANT", "REPLACE_TRADESKILL_ENCHANT", "TRADE_REPLACE_ENCHANT", "OPEN_RECIPE_RESPONSE",
}

-- Only listened to for a few seconds after a test craft; they are too noisy otherwise.
local CRAFT_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UPDATE_TRADESKILL_CAST_STOPPED", "UPDATE_TRADESKILL_RECAST", "UI_ERROR_MESSAGE",
}

local RESCAN = {
    TRADE_SKILL_SHOW = true, TRADE_SKILL_LIST_UPDATE = true, TRADE_SKILL_DATA_SOURCE_CHANGED = true,
}

local MAX_EVENT_LOG = 120
local scanPending = false

local function logEvent(event, ...)
    db.eventCounts[event] = (db.eventCounts[event] or 0) + 1
    if #db.eventLog < MAX_EVENT_LOG then
        db.eventLog[#db.eventLog + 1] = { t = clean(call(GetTime)), event = event, args = snap({ ... }, 2) }
    end
end

-- Test buttons -------------------------------------------------------------------
-- Each test runs from a real click so it goes through the same path a button in
-- the addon would.

local buttons = {}

local function testButton(index, text, onClick)
    local b = buttons[index]
    if not b then
        b = CreateFrame("Button", "TWPProbeButton" .. index, UIParent, "UIPanelButtonTemplate")
        b:SetSize(460, 30)
        b:SetPoint("TOP", UIParent, "TOP", 0, -120 - 34 * (index - 1))
        b:SetFrameStrata("DIALOG")
        buttons[index] = b
    end
    b:SetText(text)
    b:SetScript("OnClick", function(self)
        self:Hide()
        onClick()
    end)
    b:Show()
end

local craftWatching = false

local function watchCraftEvents(seconds, done)
    craftWatching = true
    for _, event in ipairs(CRAFT_EVENTS) do
        if event:find("^UNIT_") then
            pcall(frame.RegisterUnitEvent, frame, event, "player")
        else
            pcall(frame.RegisterEvent, frame, event)
        end
    end
    C_Timer.After(seconds, function()
        for _, event in ipairs(CRAFT_EVENTS) do pcall(frame.UnregisterEvent, frame, event) end
        craftWatching = false
        pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
        done()
    end)
end

local function showCraftButton()
    local target = db.craftCandidate
    if not target then
        say("no craftable recipe recorded. Open a profession with something you can make, wait for the scan line, then try again.")
        return
    end
    testButton(1, "TWPProbe: craft 1x " .. tostring(target.name), function()
        local rec = { recipeID = target.recipeID, name = target.name, t = clean(call(GetTime)) }
        rec.countBefore = clean(call(C_TradeSkillUI.GetCraftableCount, target.recipeID))
        local ok, err = pcall(C_TradeSkillUI.CraftRecipe, target.recipeID, 1)
        rec.callOk, rec.callError = ok, (not ok) and clean(err) or nil
        db.craftTests[#db.craftTests + 1] = rec
        say(("CraftRecipe(%d) returned %s. Watching events for 8 seconds."):format(target.recipeID, ok and "without error" or ("an error: " .. tostring(rec.callError))))
        watchCraftEvents(8, function()
            rec.countAfter = clean(call(C_TradeSkillUI.GetCraftableCount, target.recipeID))
            say(("craft test done: craftable count %s -> %s. /reload to save."):format(tostring(rec.countBefore), tostring(rec.countAfter)))
        end)
    end)
    say("click the button at the top of the screen. It crafts one " .. tostring(target.name) .. " and uses the materials.")
end

-- Wrong-profession bug -------------------------------------------------------------
-- Every window open records what was cast, what the API says is open and what
-- Blizzard's frame believes it is showing, so a misfire shows which layer lied.

local lastCast
local MAX_OPENS = 60

-- UNIT_SPELLCAST_SENT never fired for action bar profession opens (2026-09-21),
-- so the action bar and the cast-succeeded event are watched as well and each
-- record says which source saw it.
local function noteCast(spellID, source)
    local info = call(C_Spell and C_Spell.GetSpellInfo, spellID)
    lastCast = { spellID = clean(spellID), name = type(info) == "table" and clean(info.name) or nil, t = call(GetTime) or 0, source = source }
end

if type(hooksecurefunc) == "function" and type(UseAction) == "function" then
    hooksecurefunc("UseAction", function(slot)
        local kind, id = call(GetActionInfo, slot)
        if kind == "spell" then noteCast(id, "UseAction") end
    end)
end

local function frameBelief()
    local pf = ProfessionsFrame
    if not pf then return nil end
    local info = pf.professionInfo
    local title = call(pf.GetTitleText, pf)
    if type(title) == "table" then title = call(title.GetText, title) end
    return {
        shown = clean(call(pf.IsShown, pf)),
        professionID = type(info) == "table" and clean(info.professionID) or nil,
        professionName = type(info) == "table" and clean(info.professionName) or nil,
        title = clean(title),
    }
end

local function recordOpen(stage)
    local base = call(C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo)
    local now = call(GetTime) or 0
    local rec = {
        t = clean(now), stage = stage,
        cast = lastCast and { spellID = lastCast.spellID, name = lastCast.name, secondsAgo = clean(now - lastCast.t), source = lastCast.source } or nil,
        api = type(base) == "table" and { professionID = clean(base.professionID), name = clean(base.professionName), sourceCounter = clean(base.sourceCounter) } or nil,
        frame = frameBelief(),
    }
    local castName = rec.cast and rec.cast.name or "?"
    local apiName = rec.api and rec.api.name or "?"
    local frameName = rec.frame and (rec.frame.professionName or rec.frame.title) or "?"
    -- Only compare sides we actually know; an unknown cast is not a misfire.
    rec.mismatch = (castName ~= "?" and castName ~= apiName) or (frameName ~= "?" and apiName ~= frameName)
    db.opens = db.opens or {}
    if #db.opens >= MAX_OPENS then table.remove(db.opens, 1) end
    db.opens[#db.opens + 1] = rec
    if stage == "settled" then
        say(("open: cast=%s%s api=%s frame=%s%s"):format(castName, rec.cast and (" via " .. tostring(rec.cast.source)) or "",
            apiName, frameName, rec.mismatch and " |cffff0000MISMATCH|r" or ""))
    end
end

local function printOpens()
    local opens = db.opens or {}
    if #opens == 0 then
        say("no window opens recorded yet.")
        return
    end
    for i = math.max(1, #opens - 7), #opens do
        local r = opens[i]
        say(("%s %s: cast=%s api=%s(%s) frame=%s/%s%s"):format(
            tostring(r.t), r.stage, r.cast and tostring(r.cast.name) or "?",
            r.api and tostring(r.api.name) or "?", r.api and tostring(r.api.sourceCounter) or "?",
            r.frame and tostring(r.frame.professionName) or "?", r.frame and tostring(r.frame.title) or "?",
            r.mismatch and " MISMATCH" or ""))
    end
end

-- OpenTradeSkill from an addon click, the way a profession tab would.
local function showOpenButton(arg)
    local current = call(C_TradeSkillUI.GetBaseProfessionInfo)
    local currentID = type(current) == "table" and clean(current.professionID) or nil
    local pick
    for _, p in ipairs(db.static and db.static.professions or {}) do
        local matches = arg ~= "" and type(p.name) == "string" and p.name:lower():find(arg, 1, true) == 1
        if (arg == "" and p.skillLine ~= currentID) or matches then
            pick = p
            break
        end
    end
    if not pick then
        say("no profession matched. Usage: /twpprobe open [name]")
        return
    end
    testButton(1, "TWPProbe: OpenTradeSkill(" .. tostring(pick.name) .. ")", function()
        local rec = { name = pick.name, skillLine = pick.skillLine, t = clean(call(GetTime)) }
        local ok, err = pcall(C_TradeSkillUI.OpenTradeSkill, pick.skillLine)
        rec.callOk, rec.callError = ok, (not ok) and clean(err) or nil
        C_Timer.After(1.5, function()
            local base = call(C_TradeSkillUI.GetBaseProfessionInfo)
            rec.apiAfter = type(base) == "table" and clean(base.professionName) or nil
            rec.frameAfter = frameBelief()
            db.openTests = db.openTests or {}
            db.openTests[#db.openTests + 1] = rec
            say(("OpenTradeSkill test: call %s, api now %s, frame shows %s."):format(
                ok and "ok" or ("error: " .. tostring(rec.callError)), tostring(rec.apiAfter),
                rec.frameAfter and tostring(rec.frameAfter.professionName) or "?"))
        end)
    end)
    say("click the button at the top of the screen.")
end

-- OpenTradeSkill is blocked for addons (ADDON_ACTION_BLOCKED, 2026-09-21), so a
-- profession tab has to cast the profession spell from a secure button instead.
local function showCastButton(arg)
    local pick
    for _, p in ipairs(db.static and db.static.professions or {}) do
        if type(p.name) == "string" and p.spellID and (arg == "" or p.name:lower():find(arg, 1, true) == 1) then
            pick = p
            break
        end
    end
    if not pick then
        say("no profession with a known spell matched. Usage: /twpprobe cast [name]")
        return
    end
    local b = _G.TWPProbeSecureButton
    if not b then
        b = CreateFrame("Button", "TWPProbeSecureButton", UIParent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
        b:SetSize(460, 30)
        b:SetPoint("TOP", UIParent, "TOP", 0, -120)
        b:SetFrameStrata("DIALOG")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "spell")
        b:HookScript("OnClick", function(self)
            local rec = { name = self.pick.name, spellID = self.pick.spellID, t = clean(call(GetTime)) }
            db.castTests = db.castTests or {}
            db.castTests[#db.castTests + 1] = rec
            C_Timer.After(1.5, function()
                local base = call(C_TradeSkillUI.GetBaseProfessionInfo)
                rec.apiAfter = type(base) == "table" and clean(base.professionName) or nil
                rec.frameAfter = frameBelief()
                say(("secure cast test: api now %s, frame shows %s."):format(tostring(rec.apiAfter),
                    rec.frameAfter and tostring(rec.frameAfter.professionName) or "?"))
                self:Hide()
            end)
        end)
    end
    b.pick = pick
    b:SetAttribute("spell", pick.spellID)
    b:SetText(("TWPProbe: secure cast %s (spell %s)"):format(tostring(pick.name), tostring(pick.spellID)))
    b:Show()
    say("click the button at the top of the screen.")
end

-- Enchanting: does a plain CraftRecipe give the targeting cursor, and does
-- CraftEnchant with an item location apply straight to a bag or equipped item?
local function itemNameFromGUID(guid)
    local itemID = call(C_Item and C_Item.GetItemIDByGUID, guid)
    return itemID and clean(call(C_Item.GetItemNameByID, itemID)) or nil, clean(itemID)
end

-- /twpprobe enchant [recipe words] [> item words]: picks the learned enchant whose
-- name contains the words, and the valid target whose name contains the item words.
-- Every word must appear in the name, so "bracer inferior" does not pick the chest enchant.
local function matchesWords(name, words)
    if type(name) ~= "string" then return false end
    name = name:lower()
    for word in words:gmatch("%S+") do
        if not name:find(word, 1, true) then return false end
    end
    return true
end

local function findEnchant(words)
    if words == "" then return db.enchantCandidate end
    local T = C_TradeSkillUI
    for _, recipeID in ipairs(call(T.GetAllRecipeIDs) or {}) do
        local info = call(T.GetRecipeInfo, recipeID)
        if type(info) == "table" and clean(info.learned) == true and clean(info.isEnchantingRecipe) == true then
            local name = clean(info.name)
            if matchesWords(name, words) then
                return { recipeID = recipeID, name = name }
            end
        end
    end
end

local function showEnchantButtons(arg)
    local recipeWords, itemWords = arg:match("^(.-)%s*>%s*(.-)$")
    recipeWords = recipeWords or arg
    local target = findEnchant(recipeWords)
    if not target then
        say("no learned enchant matched. Open Enchanting, wait for the scan line, then /twpprobe enchant [name] [> item name].")
        return
    end
    local guids = call(C_TradeSkillUI.GetEnchantItems, target.recipeID) or {}
    local items, chosen = {}, nil
    for i = 1, #guids do
        local name, itemID = itemNameFromGUID(guids[i])
        if i <= 8 then items[i] = { guid = clean(guids[i]), itemID = itemID, name = name } end
        if not chosen and (not itemWords or matchesWords(name, itemWords)) then
            chosen = { guid = guids[i], name = name }
        end
    end
    db.enchantItems = { recipeID = target.recipeID, name = target.name, count = #guids, items = items,
        craftable = clean(call(C_TradeSkillUI.GetCraftableCount, target.recipeID)) }
    say(("enchant %s (%s craftable): GetEnchantItems returned %d valid targets%s."):format(tostring(target.name),
        tostring(db.enchantItems.craftable), #guids, chosen and (", B will use " .. tostring(chosen.name)) or ""))
    if itemWords and not chosen then
        local names = {}
        for _, it in ipairs(items) do names[#names + 1] = tostring(it.name) end
        say(("no valid target matched '%s'. Valid: %s"):format(itemWords, #names > 0 and table.concat(names, ", ") or "none"))
    end
    if buttons[2] then buttons[2]:Hide() end

    testButton(1, "TWPProbe A: CraftRecipe " .. tostring(target.name) .. " (expect a targeting cursor)", function()
        local rec = { kind = "CraftRecipe", recipeID = target.recipeID, t = clean(call(GetTime)) }
        local ok, err = pcall(C_TradeSkillUI.CraftRecipe, target.recipeID, 1)
        rec.callOk, rec.callError = ok, (not ok) and clean(err) or nil
        db.enchantTests = db.enchantTests or {}
        db.enchantTests[#db.enchantTests + 1] = rec
        C_Timer.After(0.5, function()
            rec.targeting = clean(call(SpellIsTargeting))
            rec.canTargetItem = clean(call(SpellCanTargetItem))
            say(("A: call %s, SpellIsTargeting=%s SpellCanTargetItem=%s. Press Escape or click an item."):format(
                ok and "ok" or ("error: " .. tostring(rec.callError)), tostring(rec.targeting), tostring(rec.canTargetItem)))
        end)
        watchCraftEvents(10, function() say("A: done watching. /reload to save.") end)
    end)

    if chosen then
        testButton(2, "TWPProbe B: CraftEnchant onto " .. tostring(chosen.name) .. " (applies the enchant)", function()
            local rec = { kind = "CraftEnchant", recipeID = target.recipeID, targetItem = { guid = clean(chosen.guid), name = chosen.name }, t = clean(call(GetTime)) }
            local location = call(C_Item.GetItemLocation, chosen.guid)
            rec.hasLocation = location ~= nil
            local ok, err = pcall(C_TradeSkillUI.CraftEnchant, target.recipeID, 1, nil, location)
            rec.callOk, rec.callError = ok, (not ok) and clean(err) or nil
            db.enchantTests = db.enchantTests or {}
            db.enchantTests[#db.enchantTests + 1] = rec
            say(("B: CraftEnchant call %s. Watching events for 10 seconds."):format(ok and "ok" or ("error: " .. tostring(rec.callError))))
            watchCraftEvents(10, function()
                rec.targeting = clean(call(SpellIsTargeting))
                say("B: done watching. /reload to save.")
            end)
        end)
    end
    say("two buttons at the top of the screen: A tests the cursor, B enchants your item and uses the materials.")
end

-- The replace-enchant confirmation: record it, and auto-accept it when opted in.
local REPLACE_EVENTS = {
    REPLACE_ENCHANT = "ReplaceEnchant",
    REPLACE_TRADESKILL_ENCHANT = "ReplaceTradeskillEnchant",
    TRADE_REPLACE_ENCHANT = "ReplaceTradeEnchant",
}

local function onReplaceEvent(event, existing, replacement)
    local rec = { event = event, existing = clean(existing), replacement = clean(replacement), t = clean(call(GetTime)), auto = db.autoReplace and true or false }
    if db.autoReplace then
        local ok, err = pcall(C_Item and C_Item[REPLACE_EVENTS[event]])
        rec.callOk, rec.callError = ok, (not ok) and clean(err) or nil
        pcall(StaticPopup_Hide, event)
        say(("%s auto-accepted: %s"):format(event, ok and "ok" or ("error: " .. tostring(rec.callError))))
    else
        say(event .. " fired; popup left alone. /twpprobe autoreplace to auto-accept next time.")
    end
    db.replaceEvents = db.replaceEvents or {}
    db.replaceEvents[#db.replaceEvents + 1] = rec
end

-- Hiding ProfessionsFrame runs its OnHide, which closes the trade skill, so the
-- addon can only ghost it. This checks the data survives that.
local function toggleGhost()
    local pf = ProfessionsFrame
    if not pf or not pf:IsShown() then
        say("open a profession window first.")
        return
    end
    local ghosted = pf:GetAlpha() == 0
    pf:SetAlpha(ghosted and 1 or 0)
    pf:EnableMouse(ghosted)
    if ghosted then
        say("ProfessionsFrame restored.")
        return
    end
    C_Timer.After(1, function()
        local ids = call(C_TradeSkillUI.GetAllRecipeIDs)
        local rec = {
            shown = clean(call(pf.IsShown, pf)),
            ready = clean(call(C_TradeSkillUI.IsTradeSkillReady)),
            numRecipeIDs = type(ids) == "table" and #ids or nil,
        }
        db.ghostTest = rec
        say(("ghosted: shown=%s ready=%s recipes=%s. Run /twpprobe craft now to test crafting while ghosted, /twpprobe ghost to restore."):format(
            tostring(rec.shown), tostring(rec.ready), tostring(rec.numRecipeIDs)))
    end)
end

-- Report ----------------------------------------------------------------------------

local function report()
    local s = db.static or {}
    say(("toc=%s interface=%s deprecationFallbacks=%s"):format(
        tostring(s.tocLoaded), tostring(s.client and s.client.interface), tostring(s.loadDeprecationFallbacks)))
    say(("missing globals (%d): %s"):format(#(s.missing or {}), table.concat(s.missing or {}, ", ")))
    local unregistered = {}
    for _, event in ipairs(WATCHED) do
        if not registered[event] then unregistered[#unregistered + 1] = event end
    end
    say("events the client refused: " .. (#unregistered > 0 and table.concat(unregistered, ", ") or "none"))
    local seen = {}
    for event, count in pairs(db.eventCounts) do seen[#seen + 1] = event .. "=" .. count end
    table.sort(seen)
    say("events seen: " .. (#seen > 0 and table.concat(seen, ", ") or "none yet"))
    for name, scan in pairs(db.tradeskill) do
        if type(scan) == "table" and scan.difficulty then
            local parts = {}
            for key, count in pairs(scan.difficulty) do parts[#parts + 1] = key .. "=" .. count end
            table.sort(parts)
            say(("%s: learned=%s unlearned=%s difficulty{%s}"):format(name, tostring(scan.numLearned), tostring(scan.numUnlearned), table.concat(parts, " ")))
        end
    end
    say("commands: /twpprobe scan | craft | ghost | opens | open [name] | cast [name] | enchant | autoreplace. /reload saves.")
end

-- Wiring ----------------------------------------------------------------------------

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        TWPProbeDB = { tradeskill = {}, eventCounts = {}, eventLog = {}, craftTests = {}, registered = registered }
        db = TWPProbeDB
        return
    end
    if not db then return end
    if event == "PLAYER_LOGIN" then
        local ok, err = pcall(probeStatic)
        if not ok then db.staticError = clean(err) end
        say("static probe " .. (ok and "done" or "failed: " .. tostring(err)) .. ". Open each profession window, then /twpprobe.")
        return
    end

    if event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Only while no craft test is watching; the craft tests log these themselves.
        if event == "UNIT_SPELLCAST_SUCCEEDED" and craftWatching then logEvent(event, ...) return end
        local spellID = select(event == "UNIT_SPELLCAST_SENT" and 4 or 3, ...)
        noteCast(spellID, event)
        return
    end
    logEvent(event, ...)
    if REPLACE_EVENTS[event] then onReplaceEvent(event, ...) end
    if event == "TRADE_SKILL_SHOW" then
        recordOpen("show")
        C_Timer.After(1.5, function() recordOpen("settled") end)
    end
    if RESCAN[event] and not scanPending then
        scanPending = true
        C_Timer.After(1, function()
            scanPending = false
            local ok, err = pcall(scanTradeSkill)
            if not ok then
                db.scanError = clean(err)
                say("scan failed: " .. tostring(err))
            end
        end)
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
-- Registering an event the client does not know throws, so each goes through pcall.
for _, event in ipairs(WATCHED) do
    registered[event] = pcall(frame.RegisterEvent, frame, event)
end
registered.UNIT_SPELLCAST_SENT = pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SENT", "player")
registered.UNIT_SPELLCAST_SUCCEEDED = pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", "player")

SLASH_TWPPROBE1 = "/twpprobe"
SlashCmdList["TWPPROBE"] = function(msg)
    local arg
    msg, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if not db then return end
    if msg == "scan" then
        local ok, err = pcall(scanTradeSkill)
        if not ok then say("scan failed: " .. tostring(err)) end
    elseif msg == "craft" then
        showCraftButton()
    elseif msg == "ghost" then
        toggleGhost()
    elseif msg == "opens" then
        printOpens()
    elseif msg == "open" then
        showOpenButton(arg or "")
    elseif msg == "cast" then
        showCastButton(arg or "")
    elseif msg == "enchant" then
        showEnchantButtons(arg or "")
    elseif msg == "autoreplace" then
        db.autoReplace = not db.autoReplace
        say("auto-accept the replace-enchant popup: " .. (db.autoReplace and "ON" or "OFF"))
    else
        report()
    end
end
