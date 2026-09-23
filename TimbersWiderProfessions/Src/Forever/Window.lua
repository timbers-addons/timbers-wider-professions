local ADDON_NAME = ...
local main = TimbersWiderProfessionsAddon
local Compat = main.Compat
local Recipes = main.Recipes

-- The Forever (Midnight engine) window. Blizzard's ProfessionsFrame still
-- owns the trade skill session and the UI panel slot; this frame sits on top
-- of it, anchored to it, and Blizzard's is made invisible while ours shows.
-- Closing either closes the trade skill, which closes both.

local FRAME_WIDTH = 673 -- same as ProfessionsFrame, so nothing of it peeks out
local LIST_WIDTH = 340
local ROW_HEIGHT = 20
local MAX_ROWS = 40 -- enough for the tallest window height the options allow
local MAX_REAGENTS = 8
local REAGENTS_PER_LINE = 2

local L -- locale table, set on load

local textColors = {
    optimal = { 1.0, 0.5, 0.25 },
    medium = { 1.0, 1.0, 0.0 },
    easy = { 0.25, 0.75, 0.25 },
    trivial = { 0.5, 0.5, 0.5 },
}
local highlightColors = {
    optimal = { 0.569, 0.282, 0.141 },
    medium = { 0.612, 0.604, 0.0 },
    easy = { 0.153, 0.451, 0.153 },
    trivial = { 0.306, 0.302, 0.306 },
}

local frame -- TimbersWiderProfessionsFrame
local rows = {}
local reagentFrames = {}
local headers = {}
local collapsed = {}
local selectedID = nil
local refreshPending = false
local active = false -- our window is handling the current trade skill
local enchantTargets = {} -- recipeID -> item GUID chosen in the enchant slot this session
local tabs = {} -- side tab buttons, one per profession
local overviewTab -- the Skills tab that hands over to Blizzard's overview page
local requested = nil -- { spellID, t }: the profession the player last asked for

local MODES = { Recipes.MODE_BLIZZARD, Recipes.MODE_LEVEL, Recipes.MODE_ALPHA }

-- Remembers which profession the player asked for, to catch the client
-- opening a different one (see warnIfWrongProfession).
local function noteRequest(spellID)
    requested = { spellID = spellID, t = GetTime() }
end

local function modeLabel(mode)
    if mode == Recipes.MODE_LEVEL then return L.ListByLevel end
    if mode == Recipes.MODE_ALPHA then return L.ListAlphabetical end
    return L.ListBlizzard
end

local function levelsText(recipe, separator)
    if recipe.levels then
        return ("|cffff8000%d|r%s|cffffff00%d|r%s|cff00ff00%d|r%s|cff808080%d|r"):format(
            recipe.levels[1], separator, recipe.levels[2], separator, recipe.levels[3], separator, recipe.levels[4])
    elseif recipe.grayLevel then
        return ("|cff808080%d|r"):format(recipe.grayLevel)
    end
    return ""
end

local function currentFilters()
    return {
        search = frame.searchBar:GetText(),
        showUnlearned = frame.showUnlearned:GetChecked(),
        onlySkillUp = frame.onlySkillUp:GetChecked(),
        onlyMakeable = frame.onlyMakeable:GetChecked(),
    }
end

local function visibleRows()
    return math.floor((frame:GetHeight() - 101) / ROW_HEIGHT)
end

-- Details pane --------------------------------------------------------------

local function updateCraftControls(recipe)
    local count = recipe and recipe.numAvailable or 0
    local maxCount = math.max(1, count)
    frame.createCount:SetMinMaxValues(1, maxCount)
    if frame.createCount:GetValue() > maxCount then frame.createCount:SetValue(maxCount) end
    local canCraft = recipe ~= nil and recipe.learned and count > 0
    if recipe and recipe.isEnchant then
        canCraft = canCraft and enchantTargets[recipe.id] ~= nil
        frame.createAll:Hide()
        frame.createCount:Hide()
    else
        frame.createAll:SetShown(recipe ~= nil and recipe.learned)
        frame.createCount:SetShown(recipe ~= nil and recipe.learned)
    end
    frame.create:SetShown(recipe ~= nil and recipe.learned)
    frame.create:SetEnabled(canCraft)
    frame.createAll:SetEnabled(canCraft and count > 1)
end

local function enchantTargetName(guid)
    local itemID = guid and C_Item.GetItemIDByGUID(guid)
    if not itemID then return nil end
    local name, _, quality, _, _, _, _, _, _, icon = Compat.GetItemInfo(itemID)
    return name, icon, quality
end

-- Drops a remembered target the client no longer lists as valid (enchanted,
-- moved, or the recipe changed).
local function validEnchantTarget(recipe)
    local guid = enchantTargets[recipe.id]
    if not guid then return nil end
    for _, valid in ipairs(C_TradeSkillUI.GetEnchantItems(recipe.id) or {}) do
        if valid == guid then return guid end
    end
    enchantTargets[recipe.id] = nil
    return nil
end

local function updateEnchantSlot(recipe)
    if not (recipe and recipe.isEnchant and recipe.learned) then
        frame.enchantSlot:Hide()
        frame.enchantPicker:Hide()
        return
    end
    local guid = validEnchantTarget(recipe)
    local name, icon = enchantTargetName(guid)
    frame.enchantSlot.guid = guid
    frame.enchantSlot.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    frame.enchantSlot.icon:SetDesaturated(guid == nil)
    frame.enchantSlot.label:SetText(name or L.EnchantTargetNone)
    frame.enchantSlot:Show()
end

local function clearDetails()
    selectedID = nil
    updateCraftControls(nil)
    updateEnchantSlot(nil)
    frame.detailIcon:Hide()
    frame.detailCount:SetText("")
    frame.detailName:SetText("")
    frame.detailLevels:SetText("")
    frame.detailDescription:SetText("")
    frame.reagentsLabel:Hide()
    frame.favorite:Hide()
    for _, reagent in ipairs(reagentFrames) do reagent:Hide() end
    frame.highlight:Hide()
end

local function setDetails(recipe)
    selectedID = recipe.id
    if not recipe.detailsLoaded then Recipes.LoadDetails(recipe) end

    frame.detailIcon:SetTexture(recipe.icon)
    frame.detailIcon:Show()
    if recipe.quantityMin and recipe.quantityMax and recipe.quantityMax > 1 then
        if recipe.quantityMin == recipe.quantityMax then
            frame.detailCount:SetText(recipe.quantityMin)
        else
            frame.detailCount:SetText(recipe.quantityMin .. "-" .. recipe.quantityMax)
        end
    else
        frame.detailCount:SetText("")
    end
    frame.detailName:SetText(recipe.name)
    frame.detailLevels:SetText(levelsText(recipe, " / "))
    frame.detailDescription:SetText(recipe.description or "")
    frame.favorite:SetAlpha(recipe.favorite and 1 or 0.5)
    frame.favorite:SetShown(recipe.learned)

    frame.reagentsLabel:ClearAllPoints()
    frame.reagentsLabel:SetPoint("TOPLEFT", frame.detailDescription, "TOPLEFT", 0, -frame.detailDescription:GetStringHeight() - 15)
    frame.reagentsLabel:SetShown(#recipe.reagents > 0)

    for i, reagentFrame in ipairs(reagentFrames) do
        local reagent = recipe.reagents[i]
        if reagent then
            reagentFrame.icon:SetTexture(reagent.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            reagentFrame.name:SetText(reagent.name or "")
            reagentFrame.count:SetText((reagent.playerCount or 0) .. "/" .. reagent.count)
            local shade = (reagent.playerCount or 0) < reagent.count and 0.5 or 1
            reagentFrame.icon:SetVertexColor(shade, shade, shade)
            reagentFrame.name:SetTextColor(shade, shade, shade)
            reagentFrame.link = reagent.link
            reagentFrame.itemName = reagent.name
            reagentFrame:Show()
        else
            reagentFrame:Hide()
        end
    end

    updateEnchantSlot(recipe)
    updateCraftControls(recipe)
end

-- List ---------------------------------------------------------------------

local function refreshList()
    if #rows == 0 then return end -- scroll bar events during window creation
    local shown = visibleRows()
    local total = 0
    for _, header in ipairs(headers) do
        total = total + 1
        if not collapsed[header.key] then total = total + #header.recipes end
    end
    frame.scrollBar:SetMinMaxValues(0, math.max(0, total - shown))
    local offset = math.floor(frame.scrollBar:GetValue() + 0.5)
    frame.highlight:Hide()

    local lineIndex, drawn = 0, 0
    for _, header in ipairs(headers) do
        lineIndex = lineIndex + 1
        if lineIndex > offset and drawn < shown then
            drawn = drawn + 1
            rows[drawn]:SetHeader(header)
        end
        if not collapsed[header.key] then
            for _, recipe in ipairs(header.recipes) do
                lineIndex = lineIndex + 1
                if lineIndex > offset and drawn < shown then
                    drawn = drawn + 1
                    rows[drawn]:SetRecipe(recipe)
                end
            end
        end
    end
    for i = drawn + 1, MAX_ROWS do rows[i]:Hide() end
end

local function rebuild()
    headers = Recipes.Build(TimbersWiderProfessions_DB.listMode, currentFilters())
    for _, header in ipairs(headers) do
        if collapsed[header.key] == nil then collapsed[header.key] = false end
    end

    -- Keep the selection when it survived the filters, otherwise pick the first.
    local selected = selectedID and Recipes.byID[selectedID]
    local stillListed = false
    if selected then
        for _, header in ipairs(headers) do
            for _, recipe in ipairs(header.recipes) do
                if recipe.id == selectedID then stillListed = true end
            end
        end
    end
    if stillListed then
        setDetails(selected)
    else
        clearDetails()
        for _, header in ipairs(headers) do
            if header.recipes[1] then
                setDetails(header.recipes[1])
                break
            end
        end
    end
    refreshList()
end

local function refreshProfessionHeader()
    local profession = Recipes.profession
    if not profession then return end
    Compat.SetWindowTitle(frame, profession.name)
    if profession.icon then
        frame:SetPortraitTextureRaw(profession.icon)
    else
        frame:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09")
    end
    local previous = frame.rankBar:GetValue()
    frame.rankBar:SetMinMaxValues(0, profession.maxRank)
    frame.rankBar:SetValue(profession.rank)
    frame.rankBar.text:SetText(profession.rank .. "/" .. profession.maxRank)
    if previous > 0 and profession.rank > previous then frame.rankBar:Flash() end

    -- Blizzard paints the details pane per profession; fall back to their generic art.
    local atlas = "Professions-Recipe-Background-" .. (profession.name or "")
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then
        atlas = "Professions-Recipe-Background"
    end
    frame.detailsBackground:SetAtlas(atlas, false)
end

local function reload()
    if not Recipes.IsReady() then return end
    Recipes.Load()
    refreshProfessionHeader()
    rebuild()
end

-- Several list updates arrive per craft; one refresh per frame is enough.
local function scheduleRefresh(full)
    if full then frame.fullRefresh = true end
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        if not active or not frame:IsShown() then return end
        if frame.fullRefresh then
            frame.fullRefresh = false
            reload()
        else
            Recipes.RefreshCounts()
            refreshProfessionHeader()
            rebuild()
        end
    end)
end

-- Rows ---------------------------------------------------------------------

local function createRow(index)
    local row = CreateFrame("Button", nil, frame.listContent)
    row:SetSize(LIST_WIDTH - 33, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame.listInset, "TOPLEFT", 8, -ROW_HEIGHT * index - 5)
    -- An explicit label: a Button only grows a font string once it has text.
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.label:SetSize(LIST_WIDTH - 58, ROW_HEIGHT)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row:SetFontString(row.label)
    row:SetNormalFontObject("GameFontNormal")
    row:SetHighlightFontObject("GameFontHighlight")
    row:RegisterForClicks("LeftButtonUp")

    row.headerBackground = row:CreateTexture(nil, "BACKGROUND")
    row.headerBackground:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    row.headerBackground:SetSize(LIST_WIDTH - 15, ROW_HEIGHT)
    row.headerBackground:SetPoint("TOPLEFT", 0, 0)
    row.headerBackground:SetVertexColor(0.3, 0.3, 0.35, 0.4)

    row.toggle = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.toggle:SetPoint("RIGHT", -8, 0)
    row.toggle:SetTextColor(1, 1, 1)

    row.levels = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.levels:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    row.levels:SetJustifyH("RIGHT")

    row:SetScript("OnMouseDown", function(self)
        if IsModifiedClick("CHATLINK") and self.link then Compat.InsertLink(self.link) end
    end)

    function row:SetHeader(header)
        self.recipe, self.link = nil, nil
        self.headerBackground:Show()
        self.toggle:SetText(collapsed[header.key] and "+" or "-")
        self.toggle:Show()
        self.levels:Hide()
        self:SetText(header.name)
        self:SetNormalFontObject("GameFontHighlight")
        self.label:SetPoint("LEFT", 13, 0)
        self:SetScript("OnClick", function()
            frame.searchBar:ClearFocus()
            if IsModifiedClick("CHATLINK") then
                local goal = not collapsed[header.key]
                for key in pairs(collapsed) do collapsed[key] = goal end
            else
                collapsed[header.key] = not collapsed[header.key]
            end
            refreshList()
        end)
        self:Show()
    end

    function row:SetRecipe(recipe)
        self.recipe, self.link = recipe, recipe.link
        self.headerBackground:Hide()
        self.toggle:Hide()
        if recipe.numAvailable > 0 then
            self:SetText(recipe.name .. " [" .. recipe.numAvailable .. "]")
        else
            self:SetText(recipe.name)
        end
        self.label:SetPoint("LEFT", 20, 0)

        local color
        if not recipe.learned then
            color = { 0.5, 0.5, 0.5, 0.5 }
        elseif TimbersWiderProfessions_DB.skillColorMode == "rarity" and recipe.rarityColor then
            local hex = recipe.rarityColor:sub(5)
            color = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
        else
            color = textColors[recipe.difficulty] or textColors.trivial
        end
        self:SetNormalFontObject(recipe.id == selectedID and "GameFontHighlight" or "GameFontNormal")
        self.label:SetTextColor(color[1], color[2], color[3], color[4] or 1)

        if recipe.learned and TimbersWiderProfessions_DB.showSkillLevelsInList then
            self.levels:SetText(levelsText(recipe, " "))
            self.levels:Show()
            self.label:SetWidth(LIST_WIDTH - 58 - self.levels:GetStringWidth() - 8)
        else
            self.levels:Hide()
            self.label:SetWidth(LIST_WIDTH - 58)
        end

        if recipe.id == selectedID then
            local highlight = highlightColors[recipe.difficulty] or highlightColors.trivial
            frame.highlight:ClearAllPoints()
            frame.highlight:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
            frame.highlight:SetVertexColor(highlight[1], highlight[2], highlight[3])
            frame.highlight:Show()
        end

        self:SetScript("OnClick", function()
            if IsModifiedClick("CHATLINK") then return end
            frame.searchBar:ClearFocus()
            setDetails(recipe)
            refreshList()
        end)
        self:Show()
    end

    return row
end

local function createReagent(index)
    local x = (index - 1) % REAGENTS_PER_LINE
    local y = math.floor((index - 1) / REAGENTS_PER_LINE)
    local reagent = CreateFrame("Frame", nil, frame.detailsContent)
    reagent:SetSize(150, 45)
    reagent:SetPoint("TOPLEFT", frame.reagentsLabel, "BOTTOMLEFT", x * 148, -50 * y - 10)
    reagent:Hide()

    local background = reagent:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("136796")
    background:SetSize(122, 65)
    background:SetPoint("TOPLEFT", 31, 10)

    reagent.icon = reagent:CreateTexture(nil, "OVERLAY")
    reagent.icon:SetSize(40, 40)
    reagent.icon:SetPoint("TOPLEFT", 0, -2.5)

    reagent.count = reagent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reagent.count:SetPoint("BOTTOMRIGHT", reagent.icon, "BOTTOMRIGHT", -3, 2)
    reagent.count:SetTextColor(1, 1, 1)

    reagent.name = reagent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reagent.name:SetPoint("LEFT", reagent.icon, "RIGHT", 8, 0)
    reagent.name:SetSize(90, 30)
    reagent.name:SetJustifyH("LEFT")

    reagent:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self.icon, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    reagent:SetScript("OnLeave", function() GameTooltip:Hide() end)
    reagent:SetScript("OnMouseDown", function(self)
        if IsModifiedClick("CHATLINK") and self.link then
            if frame.searchBar:HasFocus() then
                frame.searchBar:SetText(self.itemName or "")
            else
                Compat.InsertLink(self.link)
            end
        end
    end)
    return reagent
end

-- Frame --------------------------------------------------------------------

local function createCheckBox(name, text, tooltip)
    local checkbox = CreateFrame("CheckButton", name, frame, "UICheckButtonTemplate")
    checkbox:SetSize(20, 20)
    checkbox.text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    checkbox.text:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
    checkbox.text:SetText(text)
    checkbox:SetChecked(false)
    checkbox:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        rebuild()
    end)
    checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(text, 1, 1, 1)
        if tooltip then GameTooltip:AddLine(tooltip, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return checkbox
end

-- Crafting ------------------------------------------------------------------

local function selectedRecipe()
    return selectedID and Recipes.byID[selectedID] or nil
end

local function craft(count)
    local recipe = selectedRecipe()
    if not recipe or not recipe.learned then return end
    if recipe.isEnchant then
        local guid = validEnchantTarget(recipe)
        local location = guid and C_Item.GetItemLocation(guid)
        if not location then return end
        C_TradeSkillUI.CraftEnchant(recipe.id, 1, nil, location)
    else
        C_TradeSkillUI.CraftRecipe(recipe.id, count)
    end
end

local function createCraftControls()
    local content = frame.detailsContent
    frame.create = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    frame.create:SetSize(90, 22)
    frame.create:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -8, 8)
    frame.create:SetText(CREATE_PROFESSION or "Create")
    frame.create:SetScript("OnClick", function()
        craft(frame.createCount:GetValue())
    end)

    frame.createCount = CreateFrame("EditBox", nil, content, "NumericInputSpinnerTemplate")
    frame.createCount:SetPoint("RIGHT", frame.create, "LEFT", -28, 0)
    frame.createCount:SetMinMaxValues(1, 1)
    frame.createCount:SetValue(1)

    frame.createAll = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    frame.createAll:SetSize(90, 22)
    frame.createAll:SetPoint("RIGHT", frame.createCount, "LEFT", -34, 0)
    frame.createAll:SetText(PROFESSIONS_CREATE_ALL or "Create All")
    frame.createAll:SetScript("OnClick", function()
        local recipe = selectedRecipe()
        if recipe then craft(recipe.numAvailable) end
    end)
end

-- The enchant target: a slot the player fills from a picker of every bag or
-- equipped item the enchant accepts, so the bags can stay closed.
local PICKER_ROWS = 12

local function fillEnchantPicker(recipe)
    local picker = frame.enchantPicker
    local guids = C_TradeSkillUI.GetEnchantItems(recipe.id) or {}
    local shown = 0
    for i = 1, PICKER_ROWS do
        local row = picker.rows[i]
        local guid = guids[i]
        if guid then
            local name, icon, quality = enchantTargetName(guid)
            row.guid = guid
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.label:SetText(name or "")
            local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if color then row.label:SetTextColor(color.r, color.g, color.b) else row.label:SetTextColor(1, 1, 1) end
            row:Show()
            shown = shown + 1
        else
            row:Hide()
        end
    end
    picker.empty:SetShown(shown == 0)
    picker.more:SetShown(#guids > PICKER_ROWS)
    if #guids > PICKER_ROWS then picker.more:SetText(("+%d"):format(#guids - PICKER_ROWS)) end
    picker:SetHeight(12 + math.max(1, shown) * 22 + (#guids > PICKER_ROWS and 16 or 0))
end

local function createEnchantSlot()
    local content = frame.detailsContent
    local slot = CreateFrame("Button", nil, content)
    frame.enchantSlot = slot
    slot:SetSize(40, 40)
    slot:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 14, 40)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:Hide()

    slot.border = slot:CreateTexture(nil, "BACKGROUND")
    slot.border:SetTexture("136796")
    slot.border:SetSize(64, 64)
    slot.border:SetPoint("CENTER", 11, -11)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints()
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    slot.title = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    slot.title:SetPoint("BOTTOMLEFT", slot, "TOPLEFT", 0, 4)
    slot.title:SetText(L.EnchantTarget)

    slot.label = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    slot.label:SetPoint("LEFT", slot, "RIGHT", 8, 0)
    slot.label:SetSize(180, 40)
    slot.label:SetJustifyH("LEFT")

    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.guid and GameTooltip.SetItemByGUID then
            GameTooltip:SetItemByGUID(self.guid)
            GameTooltip:AddLine(" ")
        else
            GameTooltip:SetText(L.EnchantTarget, 1, 1, 1)
        end
        GameTooltip:AddLine(L.EnchantTargetTooltip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slot:SetScript("OnClick", function(self, button)
        local recipe = selectedRecipe()
        if not recipe then return end
        if button == "RightButton" then
            enchantTargets[recipe.id] = nil
            frame.enchantPicker:Hide()
            setDetails(recipe)
        elseif frame.enchantPicker:IsShown() then
            frame.enchantPicker:Hide()
        else
            fillEnchantPicker(recipe)
            frame.enchantPicker:Show()
        end
    end)

    local picker = CreateFrame("Frame", nil, frame, "TooltipBackdropTemplate")
    frame.enchantPicker = picker
    picker:SetFrameStrata("DIALOG")
    picker:SetSize(240, 40)
    picker:SetPoint("BOTTOMLEFT", slot, "TOPRIGHT", 4, 4)
    picker:EnableMouse(true)
    picker:Hide()
    picker.rows = {}
    for i = 1, PICKER_ROWS do
        local row = CreateFrame("Button", nil, picker)
        row:SetSize(228, 22)
        row:SetPoint("TOPLEFT", picker, "TOPLEFT", 6, -6 - (i - 1) * 22)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 2, 0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnEnter", function(self)
            if not self.guid or not GameTooltip.SetItemByGUID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByGUID(self.guid)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            local recipe = selectedRecipe()
            if recipe and self.guid then
                enchantTargets[recipe.id] = self.guid
                picker:Hide()
                setDetails(recipe)
            end
        end)
        picker.rows[i] = row
    end
    picker.empty = picker:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    picker.empty:SetPoint("TOPLEFT", 8, -8)
    picker.empty:SetText(L.EnchantTargetNoItems)
    picker.more = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    picker.more:SetPoint("BOTTOMRIGHT", -8, 4)
end

-- The inset template's border is a child frame with a filled center, which
-- draws over anything placed directly on the inset. Content goes on a frame
-- above it.
local function contentFrame(inset)
    local content = CreateFrame("Frame", nil, inset)
    content:SetAllPoints()
    content:SetFrameLevel(inset:GetFrameLevel() + 1)
    return content
end

local function createWindow()
    local height = TimbersWiderProfessions_DB.windowHeight or 426
    frame = CreateFrame("Frame", "TimbersWiderProfessionsFrame", UIParent, "PortraitFrameTemplate")
    main.window = frame
    frame:SetSize(FRAME_WIDTH, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetScale((TimbersWiderProfessions_DB.windowScale or 100) / 100)
    frame.waitingForData = false -- set when TRADE_SKILL_SHOW arrives before the recipe list is readable
    frame.fullRefresh = false
    frame.onOverview = false -- ours stepped aside for Blizzard's overview page
    frame:Hide()
    Compat.SetWindowTitle(frame, "")
    tinsert(UISpecialFrames, "TimbersWiderProfessionsFrame")

    -- The template's own backdrop sits at the frame's level, so the painted art
    -- goes on a child frame above it and the insets above that.
    local art = CreateFrame("Frame", nil, frame)
    art:SetFrameLevel(frame:GetFrameLevel() + 1)
    art:SetPoint("TOPLEFT", 3, -21)
    art:SetPoint("BOTTOMRIGHT", -3, 3)
    frame.background = art:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAtlas("Profession-Background-Template2", false)
    frame.background:SetAllPoints()

    -- Rank bar with link button
    local rankBar = CreateFrame("StatusBar", nil, frame)
    frame.rankBar = rankBar
    rankBar:SetSize(300, 18)
    rankBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, -30)
    rankBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    rankBar:SetStatusBarColor(0, 0.2, 0.6)
    rankBar:SetMinMaxValues(0, 100)
    rankBar.border = rankBar:CreateTexture(nil, "OVERLAY")
    rankBar.border:SetPoint("LEFT", rankBar, -8, 0)
    rankBar.border:SetSize(315, 35)
    rankBar.border:SetTexture(136571)
    rankBar.text = rankBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rankBar.text:SetPoint("CENTER", rankBar, 0, 0.5)
    function rankBar:Flash()
        if self.flashing then return end
        self.flashing = true
        self:SetStatusBarColor(0, 0.3, 0.9)
        C_Timer.After(0.4, function()
            self:SetStatusBarColor(0, 0.2, 0.6)
            self.flashing = false
        end)
    end

    local linkButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.linkButton = linkButton
    linkButton:SetSize(60, 20)
    linkButton:SetPoint("LEFT", rankBar, "RIGHT", 12, 0)
    linkButton:SetText(L.Link)
    linkButton:SetScript("OnClick", function()
        local link = C_TradeSkillUI.GetTradeSkillListLink()
        if link then Compat.InsertLink(link) end
    end)

    -- Settings button below the close button
    local settingsButton = CreateFrame("Button", nil, frame)
    settingsButton:SetSize(20, 20)
    settingsButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -24)
    settingsButton:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    settingsButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    settingsButton:SetFrameLevel(frame:GetFrameLevel() + 10)
    settingsButton:SetScript("OnClick", function()
        if main.settingsCategory and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(main.settingsCategory:GetID())
        end
    end)
    settingsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(SETTINGS, 1, 1, 1)
        GameTooltip:Show()
    end)
    settingsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Left: list inset
    frame.listInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    frame.listInset:SetFrameLevel(frame:GetFrameLevel() + 2)
    frame.listInset:SetSize(LIST_WIDTH, height - 76)
    frame.listInset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 3, 0)
    frame.listContent = contentFrame(frame.listInset)

    frame.highlight = frame.listContent:CreateTexture(nil, "ARTWORK")
    frame.highlight:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    frame.highlight:SetSize(LIST_WIDTH - 15, ROW_HEIGHT)
    frame.highlight:SetBlendMode("BLEND")
    frame.highlight:Hide()

    -- Filters above the list
    frame.onlyMakeable = createCheckBox("TimbersWiderProfessionsMakeable", CRAFT_IS_MAKEABLE, CRAFT_IS_MAKEABLE_TOOLTIP)
    frame.onlyMakeable:SetPoint("BOTTOMLEFT", frame.listInset, "TOPLEFT", 4, 2)
    frame.onlySkillUp = createCheckBox("TimbersWiderProfessionsSkillUp", L.CanRankUp, L.CanRankUpTooltip)
    frame.onlySkillUp:SetPoint("LEFT", frame.onlyMakeable.text, "RIGHT", 10, 0)
    frame.showUnlearned = createCheckBox("TimbersWiderProfessionsUnlearned", L.ShowUnlearned, L.ShowUnlearnedTooltip)
    frame.showUnlearned:SetPoint("LEFT", frame.onlySkillUp.text, "RIGHT", 10, 0)

    -- List mode button: cycles through the three lists
    local modeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.modeButton = modeButton
    modeButton:SetSize(150, 20)
    modeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -55)
    modeButton:SetScript("OnClick", function(self)
        local current = TimbersWiderProfessions_DB.listMode
        local nextMode = MODES[1]
        for i, mode in ipairs(MODES) do
            if mode == current then nextMode = MODES[i % #MODES + 1] end
        end
        main:SetListMode(nextMode)
    end)
    modeButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.ListMode, 1, 1, 1)
        GameTooltip:AddLine(L.ListModeTooltip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    modeButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Search bar
    frame.searchBar = CreateFrame("EditBox", "TimbersWiderProfessionsSearch", frame, "SearchBoxTemplate")
    frame.searchBar:SetSize(LIST_WIDTH - 44, 20)
    frame.searchBar:SetPoint("TOPLEFT", frame.listInset, "TOPLEFT", 10, -3)
    frame.searchBar:SetAutoFocus(false)
    frame.searchBar.Instructions:SetText(SEARCH)
    frame.searchBar:SetScript("OnTextChanged", function(self)
        self.clearButton:SetShown(self:GetText() ~= "")
        rebuild()
    end)
    frame.searchBar:SetScript("OnEscapePressed", frame.searchBar.ClearFocus)
    frame.searchBar:SetScript("OnEnterPressed", frame.searchBar.ClearFocus)
    frame.searchBar:SetScript("OnEditFocusLost", function(self)
        if self:GetText():match("^%s*$") then
            self:SetText("")
            self.Instructions:Show()
        end
        self:HighlightText(0, 0)
    end)
    frame.searchBar:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        self.Instructions:Hide()
    end)
    frame:SetScript("OnMouseDown", function() frame.searchBar:ClearFocus() end)

    -- Scroll bar
    local scrollBar = CreateFrame("Slider", nil, frame.listContent, "UIPanelScrollBarTemplate")
    frame.scrollBar = scrollBar
    scrollBar:SetPoint("TOPRIGHT", frame.listInset, "TOPRIGHT", -8, -24)
    scrollBar:SetPoint("BOTTOMRIGHT", frame.listInset, "BOTTOMRIGHT", -8, 18)
    scrollBar:SetWidth(16)
    -- The template has no track, only thumb and buttons.
    scrollBar.track = scrollBar:CreateTexture(nil, "BACKGROUND")
    scrollBar.track:SetTexture("Interface\\Buttons\\WHITE8X8")
    scrollBar.track:SetVertexColor(0, 0, 0, 0.35)
    scrollBar.track:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
    scrollBar.track:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    -- The template's own OnValueChanged expects a scroll frame parent, so ours
    -- goes in before the first SetValue.
    scrollBar:SetScript("OnValueChanged", function(self, value)
        refreshList()
        local minValue, maxValue = self:GetMinMaxValues()
        self.ScrollUpButton:SetEnabled(value > minValue)
        self.ScrollDownButton:SetEnabled(value < maxValue)
    end)
    scrollBar:SetScript("OnMinMaxChanged", function(self, minValue, maxValue)
        self:SetShown(maxValue > 0)
        if self:GetValue() > maxValue then self:SetValue(maxValue) end
    end)
    scrollBar:SetValue(0)
    scrollBar.ScrollUpButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        scrollBar:SetValue(scrollBar:GetValue() - 1)
    end)
    scrollBar.ScrollDownButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        scrollBar:SetValue(scrollBar:GetValue() + 1)
    end)
    frame.listInset:SetScript("OnMouseWheel", function(_, delta)
        scrollBar:SetValue(scrollBar:GetValue() - delta)
    end)

    for i = 1, MAX_ROWS do rows[i] = createRow(i) end

    -- Right: details inset
    frame.detailsInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    frame.detailsInset:SetFrameLevel(frame:GetFrameLevel() + 2)
    frame.detailsInset:SetSize(FRAME_WIDTH - LIST_WIDTH - 6, height - 76)
    frame.detailsInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 0)
    frame.detailsContent = contentFrame(frame.detailsInset)

    -- Blizzard's painted art replaces the inset's marble, as on their frame.
    if frame.detailsInset.Bg then frame.detailsInset.Bg:Hide() end
    frame.detailsBackground = frame.detailsContent:CreateTexture(nil, "BACKGROUND")
    frame.detailsBackground:SetPoint("TOPLEFT", 2, -2)
    frame.detailsBackground:SetPoint("BOTTOMRIGHT", -2, 2)

    frame.detailIcon = frame.detailsContent:CreateTexture(nil, "OVERLAY")
    frame.detailIcon:SetSize(45, 45)
    frame.detailIcon:SetPoint("TOPLEFT", 14, -9)
    frame.detailIcon:Hide()
    local iconButton = CreateFrame("Button", nil, frame.detailsContent)
    iconButton:SetAllPoints(frame.detailIcon)
    iconButton:SetScript("OnEnter", function(self)
        local recipe = selectedID and Recipes.byID[selectedID]
        if not recipe or not recipe.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(recipe.link)
        GameTooltip:Show()
    end)
    iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    iconButton:SetScript("OnMouseDown", function()
        local recipe = selectedID and Recipes.byID[selectedID]
        if not recipe or not recipe.link then return end
        if IsModifiedClick("CHATLINK") then
            Compat.InsertLink(recipe.link)
        elseif IsModifiedClick("DRESSUP") and DressUpItemLink then
            DressUpItemLink(recipe.link)
        end
    end)

    frame.detailCount = frame.detailsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.detailCount:SetPoint("BOTTOMRIGHT", frame.detailIcon, "BOTTOMRIGHT", -4, 2)
    frame.detailCount:SetTextColor(1, 1, 1)

    frame.detailName = frame.detailsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.detailName:SetPoint("TOPLEFT", 70, -15)
    frame.detailName:SetSize(220, 10)
    frame.detailName:SetJustifyH("LEFT")

    frame.detailLevels = frame.detailsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.detailLevels:SetPoint("TOPLEFT", frame.detailName, "BOTTOMLEFT", 0, -3)
    frame.detailLevels:SetSize(220, 12)
    frame.detailLevels:SetJustifyH("LEFT")

    frame.detailDescription = frame.detailsContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.detailDescription:SetPoint("TOPLEFT", frame.detailsInset, "TOPLEFT", 15, -70)
    frame.detailDescription:SetSize(frame.detailsInset:GetWidth() - 25, 60)
    frame.detailDescription:SetJustifyH("LEFT")
    frame.detailDescription:SetJustifyV("TOP")

    frame.favorite = CreateFrame("Button", nil, frame.detailsContent)
    frame.favorite:SetSize(30, 30)
    frame.favorite:SetPoint("TOPRIGHT", frame.detailsInset, "TOPRIGHT", -10, -8)
    frame.favorite:SetNormalTexture("Interface\\Common\\FavoritesIcon")
    frame.favorite:SetAlpha(0.5)
    frame.favorite:Hide()
    frame.favorite:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(BATTLE_PET_FAVORITE, 1, 1, 1)
        GameTooltip:Show()
        self:SetAlpha(1)
    end)
    frame.favorite:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        local recipe = selectedID and Recipes.byID[selectedID]
        self:SetAlpha(recipe and recipe.favorite and 1 or 0.5)
    end)
    frame.favorite:SetScript("OnClick", function()
        local recipe = selectedID and Recipes.byID[selectedID]
        if not recipe then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Recipes.SetFavorite(recipe, not recipe.favorite)
        rebuild()
    end)

    frame.reagentsLabel = frame.detailsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.reagentsLabel:SetPoint("TOPLEFT", frame.detailDescription, "BOTTOMLEFT", 0, 20)
    frame.reagentsLabel:SetText(MINIMAP_TRACKING_VENDOR_REAGENT .. ":")
    frame.reagentsLabel:SetJustifyH("LEFT")
    frame.reagentsLabel:Hide()
    for i = 1, MAX_REAGENTS do reagentFrames[i] = createReagent(i) end

    createCraftControls()
    createEnchantSlot()

    frame.fixButton = CreateFrame("Button", "TimbersWiderProfessionsFixButton", frame.detailsContent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    frame.fixButton:SetSize(220, 22)
    frame.fixButton:SetPoint("BOTTOMRIGHT", frame.detailsContent, "BOTTOMRIGHT", -8, 36)
    frame.fixButton:RegisterForClicks("AnyUp", "AnyDown")
    frame.fixButton:SetAttribute("type", "spell")
    frame.fixButton:HookScript("OnClick", function(self)
        local spellID = self:GetAttribute("spell")
        if spellID then noteRequest(spellID) end
        self:Hide()
    end)
    frame.fixButton:Hide()

    -- Closing ours closes the trade skill; Blizzard's frame follows on TRADE_SKILL_CLOSE.
    frame:SetScript("OnHide", function()
        frame.enchantPicker:Hide()
        frame.searchBar:ClearFocus()
        frame.searchBar:SetText("")
        if active then
            active = false
            C_TradeSkillUI.CloseTradeSkill()
        end
        if ProfessionsFrame then
            ProfessionsFrame:SetAlpha(1)
            ProfessionsFrame:EnableMouse(true)
        end
    end)

    main:ApplyDragOption()
end

-- Public --------------------------------------------------------------------

function main:SetListMode(mode)
    TimbersWiderProfessions_DB.listMode = mode
    if frame then
        frame.modeButton:SetText(modeLabel(mode))
        if frame:IsShown() then rebuild() end
    end
end

function main:SetWindowHeight(height)
    if not frame then return end
    frame:SetHeight(height)
    frame.listInset:SetHeight(height - 76)
    frame.detailsInset:SetHeight(height - 76)
    if frame:IsShown() then refreshList() end
end

function main:ApplyDragOption()
    if not frame then return end
    local container = frame.TitleContainer or frame
    if TimbersWiderProfessions_DB.canDragFrame then
        container:EnableMouse(true)
        container:RegisterForDrag("LeftButton")
        container:SetScript("OnDragStart", function() frame:StartMoving() end)
        container:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    else
        container:SetScript("OnDragStart", nil)
        container:SetScript("OnDragStop", nil)
    end
end

-- Profession tabs ------------------------------------------------------------
-- C_TradeSkillUI.OpenTradeSkill is blocked for addons, so each tab is a secure
-- button that casts the profession's own spell, like the action bar does.

local TAB_WIDTH, TAB_HEIGHT = 40, 44

local function createTab(index, template)
    local tab = CreateFrame("Button", "TimbersWiderProfessionsTab" .. index, frame, template)
    tab:SetSize(TAB_WIDTH, TAB_HEIGHT)
    tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -60 - (index - 1) * (TAB_HEIGHT + 2))

    tab.background = tab:CreateTexture(nil, "BACKGROUND")
    tab.background:SetAtlas("common-sidetab", true)
    tab.background:SetPoint("CENTER")

    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetSize(30, 30)
    tab.icon:SetPoint("CENTER", 2, 0)
    if tab.CreateMaskTexture then
        tab.mask = tab:CreateMaskTexture()
        tab.mask:SetAtlas("common-sidetab-mask", true)
        tab.mask:SetPoint("CENTER")
        tab.icon:AddMaskTexture(tab.mask)
    end

    tab.selected = tab:CreateTexture(nil, "OVERLAY")
    tab.selected:SetAtlas("common-sidetab-selected", true)
    tab.selected:SetPoint("CENTER")
    tab.selected:Hide()

    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -4, -4)
        GameTooltip:SetText(self.profession and self.profession.name or "", 1, 1, 1)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return tab
end

-- The first tab is Blizzard's overview (what K shows): ours steps aside and
-- theirs comes back; picking a profession there brings ours back.
-- Blizzard's Camelot side tabs each cast their profession spell whenever
-- ProfessionsFrame shows (ProfessionsLargeRightTabMixin:OnLoad registers it on
-- "ProfessionsFrame.Show"), so opening one profession from a closed window can
-- end on whichever cast the server handled last, and K reopens the last
-- profession. Dropping those callbacks leaves the tabs' own clicks intact.
local blizzardTabsDisarmed = false

local function disarmBlizzardTabs()
    if blizzardTabsDisarmed or not ProfessionsFrame or not EventRegistry then return end
    blizzardTabsDisarmed = true
    local list = { ProfessionsFrame.ProfessionsOverviewTab }
    for _, tab in ipairs(ProfessionsFrame.rightProfessionTabs or {}) do list[#list + 1] = tab end
    for _, tab in ipairs(list) do
        if tab then pcall(EventRegistry.UnregisterCallback, EventRegistry, "ProfessionsFrame.Show", tab) end
    end
    -- Without the auto-cast, K would show an empty crafting page; send it to the overview.
    ProfessionsFrame:HookScript("OnShow", function(self)
        if not Recipes.IsReady() and self.SelectBookPage then pcall(self.SelectBookPage, self) end
    end)
end

local function showOverview()
    if not ProfessionsFrame then return end
    active = false
    frame.onOverview = true
    frame:Hide()
    if ProfessionsFrame.SelectBookPage then pcall(ProfessionsFrame.SelectBookPage, ProfessionsFrame) end
end

local function createProfessionTab(index)
    local tab = createTab(index, "SecureActionButtonTemplate")
    tab:RegisterForClicks("AnyUp", "AnyDown")
    tab:SetAttribute("type", "spell")
    -- Records the request before the cast resolves, so a misfire can be told apart.
    tab:HookScript("OnClick", function(self)
        if self.profession then noteRequest(self.profession.spellID) end
    end)
    return tab
end

-- Secure attributes cannot change in combat; the tabs are rebuilt once it ends.
local function refreshTabs()
    if InCombatLockdown() then
        frame.tabsDirty = true
        return
    end
    frame.tabsDirty = false
    if not overviewTab then
        overviewTab = createTab(1)
        overviewTab.profession = { name = TRADE_SKILLS }
        overviewTab.icon:SetTexture("Interface\\ICONS\\INV_SideTab_Professions_c60")
        overviewTab:SetScript("OnClick", showOverview)
    end
    local professions = Compat.GetProfessionTabs()
    local current = Recipes.profession and Recipes.profession.id
    for i, profession in ipairs(professions) do
        local tab = tabs[i] or createProfessionTab(i + 1)
        tabs[i] = tab
        tab.profession = profession
        tab:SetAttribute("spell", profession.spellID)
        tab.icon:SetTexture(profession.icon)
        local isCurrent = profession.skillLine == current
        tab.selected:SetShown(isCurrent)
        -- Casting the open profession's spell closes it, so the current tab is inert.
        tab:SetEnabled(not isCurrent)
        tab:Show()
    end
    for i = #professions + 1, #tabs do tabs[i]:Hide() end
end

-- Wrong-profession detection: the client sometimes opens a different
-- profession than the one cast (engine bug, seen 2026-09-22 with no addons).
-- The action bar goes through UseAction; direct casts fire the succeeded event.
if type(hooksecurefunc) == "function" and type(UseAction) == "function" then
    hooksecurefunc("UseAction", function(slot)
        local kind, id = GetActionInfo(slot)
        if kind == "spell" then noteRequest(id) end
    end)
end

-- When the game opened the wrong profession, a secure button offers the one
-- that was asked for; a click on it is the only way to cast from an addon.
local function warnIfWrongProfession()
    frame.fixButton:Hide()
    if not requested or GetTime() - requested.t > 5 or not Recipes.profession then return end
    local wantedName = Compat.GetSpellName(requested.spellID)
    local wanted
    for _, tab in ipairs(tabs) do
        if tab.profession and wantedName and tab.profession.spellName == wantedName then wanted = tab.profession end
    end
    requested = nil
    local opened = Recipes.profession
    if wanted and wanted.skillLine ~= opened.id and wanted.skillLine ~= opened.parentID then
        print(("|cff33ff99TWP|r: " .. L.WrongProfession):format(wanted.name, Recipes.profession.name))
        if not InCombatLockdown() then
            frame.fixButton:SetAttribute("spell", wanted.spellID)
            frame.fixButton:SetText((L.OpenInstead):format(wanted.name))
            frame.fixButton:Show()
        end
    end
end

-- Showing ---------------------------------------------------------------------

local function ghostBlizzardFrame()
    if not ProfessionsFrame then return end
    ProfessionsFrame:SetAlpha(0)
    ProfessionsFrame:EnableMouse(false)
end

local function showWindow()
    if not Recipes.IsReady() then return end
    if Recipes.IsForeign() then
        -- Someone else's profession: leave it to Blizzard's window.
        if frame:IsShown() then
            active = false
            frame:Hide()
        end
        return
    end
    active = true
    ghostBlizzardFrame()
    if ProfessionsFrame and not TimbersWiderProfessions_DB.canDragFrame then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPLEFT", 0, 0)
    end
    frame.modeButton:SetText(modeLabel(TimbersWiderProfessions_DB.listMode))
    collapsed = {}
    selectedID = nil
    frame.scrollBar:SetValue(0)
    frame:Show()
    reload()
    refreshTabs()
    warnIfWrongProfession()
end

-- Events ------------------------------------------------------------------------

main.ADDON_LOADED = function(self, event, addon)
    if addon == "Blizzard_Professions" then
        disarmBlizzardTabs()
        return
    end
    if addon ~= ADDON_NAME then return end
    local defaultVariables = main:GetDefaultVariables()
    if TimbersWiderProfessions_DB == nil then
        TimbersWiderProfessions_DB = {}
    end
    for key, value in pairs(defaultVariables) do
        if TimbersWiderProfessions_DB[key] == nil then
            TimbersWiderProfessions_DB[key] = value
        end
    end

    L = main.Locales[GetLocale()] or main.Locales["enUS"]
    if L ~= main.Locales["enUS"] then setmetatable(L, { __index = main.Locales["enUS"] }) end
    main.ClientLocale = L
    main:CreateSettingsFrame()
    createWindow()
    disarmBlizzardTabs() -- in case Blizzard_Professions loaded before us
end

main.TRADE_SKILL_SHOW = function()
    -- Blizzard's frame is load-on-demand and shows itself on this event; ours
    -- waits until the recipe list is readable.
    disarmBlizzardTabs()
    frame.onOverview = false
    if Recipes.IsReady() then
        showWindow()
    else
        frame.waitingForData = true
    end
end

main.TRADE_SKILL_DATA_SOURCE_CHANGED = function()
    if frame.waitingForData or frame.onOverview or frame:IsShown() then
        frame.waitingForData = false
        frame.onOverview = false
        showWindow()
    end
end

main.TRADE_SKILL_LIST_UPDATE = function()
    if frame.waitingForData and Recipes.IsReady() then
        frame.waitingForData = false
        showWindow()
    elseif frame:IsShown() then
        scheduleRefresh(false)
    end
end

main.TRADE_SKILL_CLOSE = function()
    frame.waitingForData = false
    frame.onOverview = false
    if frame:IsShown() then
        active = false
        frame:Hide()
    end
end

main.NEW_RECIPE_LEARNED = function()
    if frame:IsShown() then scheduleRefresh(true) end
end

main.TRADE_SKILL_ITEM_CRAFTED_RESULT = main.TRADE_SKILL_LIST_UPDATE
main.BAG_UPDATE_DELAYED = function()
    if frame:IsShown() then scheduleRefresh(false) end
end

main.SKILL_LINES_CHANGED = function()
    refreshTabs()
end

main.PLAYER_REGEN_ENABLED = function()
    if frame.tabsDirty then refreshTabs() end
end

function main.OnEvent(self, event, ...)
    self[event](self, event, ...)
end

main:RegisterEvent("ADDON_LOADED")
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "TRADE_SKILL_ITEM_CRAFTED_RESULT", "NEW_RECIPE_LEARNED", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "PLAYER_REGEN_ENABLED" }) do
    main:RegisterEvent(event)
end
main:SetScript("OnEvent", main.OnEvent)
