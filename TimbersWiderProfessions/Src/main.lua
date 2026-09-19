local ADDON_NAME = ...
local main = CreateFrame("Frame", "TimbersWiderProfessionsAddon")
local closedHeaders = {}
main.selectedSkill = nil
main.canRankUp = true
main.windowType = nil

local MAX_SKILLS_SHOWN = 16
local MAX_SKILLS_CREATABLE = 35 -- Enough buttons for max window height (800)
local MAX_CRAFT_REAGENTS = 8
local MAX_REAGENTS_PER_LINE = 2
local MAX_PETS_SHOWN = 14
local buildVersion = select(4, GetBuildInfo())
if buildVersion >= 20000 then
    MAX_PETS_SHOWN = 19
end

local VANILLA_SKILL_RANKS_PER_LEVEL = 5
local BEAST_TRAINING_SPELL_ID = 5149
local POISONS_SPELL_ID = 2842
local MINIMUM_SCROLLBAR_INCREMENT = 0.5
local BEAST_LORE_SPELL_ID = 1462

local skillDescriptionDict = {}
local isHunter = false

local function ColorCodeToRGB(code)
    -- expects something like "|cffaabbcc"
    local hex = code:sub(3) -- strip "|c"
    local a = tonumber(hex:sub(1, 2), 16) / 255
    local r = tonumber(hex:sub(3, 4), 16) / 255
    local g = tonumber(hex:sub(5, 6), 16) / 255
    local b = tonumber(hex:sub(7, 8), 16) / 255
    return r, g, b, a
end

-- Bright colors for text
local difficultyTextColors = {
    ["optimal"] = {1.0, 0.5, 0.25},       -- Orange (bright)
    ["medium"]  = {1.0, 1.0, 0.0},        -- Yellow (bright)
    ["easy"]    = {0.25, 0.75, 0.25},     -- Green (bright)
    ["trivial"] = {0.5, 0.5, 0.5},        -- Gray (bright)
}

-- Dark colors for highlight backgrounds
local difficultyHighlightColors = {
    ["optimal"] = {0.569, 0.282, 0.141},  -- Orange #914824
    ["medium"]  = {0.612, 0.604, 0.0},    -- Yellow #9C9A00
    ["easy"]    = {0.153, 0.451, 0.153},  -- Green #277327
    ["trivial"] = {0.306, 0.302, 0.306},  -- Gray #4E4D4E
}

local function GetDifficultyTextColor(rankEfficiency)
    return difficultyTextColors[rankEfficiency] or difficultyTextColors["trivial"]
end

local function GetDifficultyHighlightColor(rankEfficiency)
    return difficultyHighlightColors[rankEfficiency] or difficultyHighlightColors["trivial"]
end

local function linkItemInTextBar(name, link)
    -- Searchbar focus has priority.
    if CraftTradeSkillFrame.searchBar:HasFocus() then
        CraftTradeSkillFrame.searchBar:SetText(name)
        CraftTradeSkillFrame.searchBar.Instructions:Hide()
        return
    end

    -- Attempt to insert (chat, auction, ?) and see if it worked.
    local hasSuceededInserting = ChatEdit_InsertLink(link)
    if hasSuceededInserting then
        return
    end

    CraftTradeSkillFrame.searchBar:SetText(name)
    CraftTradeSkillFrame.searchBar.Instructions:Hide()
end

main.ADDON_LOADED = function(self, event, addon)
    if addon ~= ADDON_NAME then return end
    local defaultVariables = main:GetDefaultVariables()
    -- Initializes saved variables and creates any missing entries.
    if TimbersWiderProfessions_DB == nil then
        TimbersWiderProfessions_DB = defaultVariables
    end
    for key, value in pairs(defaultVariables) do
        if TimbersWiderProfessions_DB[key] == nil then
            TimbersWiderProfessions_DB[key] = value
        end
    end
    defaultVariables = nil

    -- Setup the frame
    main.ClientLocale = main.Locales[GetLocale()] or main.Locales["enUS"] -- The default locale is English.
    -- TODO: Load these only when needed.
    main:createAlchemyCategoryMap()
    main:createCookingCategoryMap()
    main:createEnchantingCategoryMap()
    local playerClass_InEnglish = select(2, UnitClass("player"))
    isHunter = playerClass_InEnglish == "HUNTER" and buildVersion < 40000
    main.hasBeastLore = false
    if isHunter then
        main.hasBeastLore = IsSpellKnown(BEAST_LORE_SPELL_ID)
        main:createPetSkillsCategoryMap()
    end
    main:CreateSettingsFrame()

    MAX_SKILLS_SHOWN = math.floor(((TimbersWiderProfessions_DB.windowHeight or 426) - 101) / 20)
    main:CraftTradeSkillFrame()
    HideUIPanel(CraftTradeSkillFrame)

    UIParentLoadAddOn("Blizzard_TradeSkillUI")
    main:HideOriginalCraftFrame("TradeSkillFrame")
    if buildVersion <= 40000 then
        UIParentLoadAddOn("Blizzard_CraftUI")
        main:HideOriginalCraftFrame("CraftFrame")
    end

    CraftTradeSkillFrame:SetScript("OnHide", function(self)
        if CraftFrame and CraftFrame:IsVisible() then HideUIPanel(CraftFrame) end
        if TradeSkillFrame and TradeSkillFrame:IsVisible() then HideUIPanel(TradeSkillFrame) end

        main.windowType = nil

        -- Reset the search bar when hiding the frame.
        CraftTradeSkillFrame.searchBar:ClearFocus()
        CraftTradeSkillFrame.searchBar:SetText("")
        CraftTradeSkillFrame.searchBar.Instructions:Show()
    end)

    main:UnregisterEvent("ADDON_LOADED")
end

function main:ReadSkillDescriptions()
    local lastHeader = nil

    for skillIndex = 1, GetNumSkillLines() do
        local skillName, header, isExpanded, skillRank, numTempPoints, skillModifier, skillMaxRank, isAbandonable, stepCost, rankCost, minLevel, skillCostType, skillDescription = GetSkillLineInfo(skillIndex);
        -- We can filter most of the skills, but we still also save the "weapon skills" on non-English clients.
        if header then
            lastHeader = skillName
        end

        if skillDescription ~= nil and skillDescription ~= "" and skillMaxRank > 1 and lastHeader ~= "Weapon Skills" then
            skillDescriptionDict[skillName] = skillDescription
        end
    end
end

function main:HideOriginalCraftFrame(frameName)
    local frame = _G[frameName]
    frame:SetAlpha(0)

    -- These allow us to disable the pushing behavior of the frame to open with auction house.
    UIPanelWindows[frameName] = nil
    frame:SetAttribute("UIPanelLayout-enabled", false)
    frame:SetAttribute("UIPanelLayout-area", nil)
    frame:SetAttribute("UIPanelLayout-pushable", nil)
end

function main:AddRankBar()
    local RankBar = CreateFrame("StatusBar", "TradeSkillRankBar", CraftTradeSkillFrame)
    RankBar:SetSize(295, 18)
    RankBar:SetPoint("TOPLEFT", CraftTradeSkillFrame, "TOPLEFT", 178, -30)
    RankBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    RankBar:SetStatusBarColor(0, 0.2, 0.6)
    RankBar:SetMinMaxValues(0, 100)
    RankBar:Show()

    RankBar.Border = RankBar:CreateTexture(nil, "OVERLAY")
    RankBar.Border:SetPoint("LEFT", RankBar, -8, 0)
    RankBar.Border:SetSize(310, 35)
    RankBar.Border:SetTexture(136571)

    RankBar.Text = RankBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    RankBar.Text:SetPoint("CENTER", RankBar, 0, 0.5)
    RankBar.Text:SetFont("Fonts\\FRIZQT__.TTF", 10)

    RankBar.isFlashing = false
    function RankBar.Flash(self)
        -- make the bar flash whiter for a second.
        if self.isFlashing then return end
        self.isFlashing = true

        self:SetStatusBarColor(0, 0.3, 0.9)

        C_Timer.After(0.4, function()
            self:SetStatusBarColor(0, 0.2, 0.6)
            self.isFlashing = false
        end)
    end

    -- If we hover the bar show a tooltip
    RankBar:SetScript("OnEnter", function(self)
        -- Check for pet training.
        if main.windowType == "Craft" and not CraftIsEnchanting() then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetSpellByID(BEAST_TRAINING_SPELL_ID)
            GameTooltip:Show()
            return
        end

        local professionName = CraftTradeSkillFrame.TitleText:GetText() -- It won't work for pets, but pets have no description anyway.
        if professionName == nil then return end

        -- Check for poisons.
        if professionName == GetSpellInfo(POISONS_SPELL_ID) then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetSpellByID(POISONS_SPELL_ID)
            GameTooltip:Show()
            return
        end

        -- The rest show from cached descriptions.
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(professionName, 1, 1, 1)
        if skillDescriptionDict[professionName] ~= nil then
            GameTooltip:AddLine(skillDescriptionDict[professionName], nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    RankBar:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

function main:FetchSkillData()
    local filterWord = CraftTradeSkillFrame.searchBar:GetText()
    if filterWord == "" then
        filterWord = nil
    else
        filterWord = string.lower(filterWord)
    end

    if main.windowType == "Craft" then
        skillInfoDict, headersList = main:FetchCrafts(filterWord)
    else
        skillInfoDict, headersList = main:FetchTradeSkills(filterWord)
    end

    if #headersList == 0 then
        main:CleanSkillDetails()
        main.skillInfoDict, main.headersList = {}, {}
        return
    end

    if main.windowType == "TradeSkill" then
        main:StealButton(TradeSkillCreateButton)
    else
        main:StealButton(CraftCreateButton)
    end

    -- Order headersList unless it's BINDING_HEADER_MISC which goes last always and FAVORITES which goes first.
    table.sort(headersList, function(a, b)
        if a == BINDING_HEADER_MISC then return false end
        if a == PET_PASSIVE then return false end
        if a == FAVORITES then return true end
        -- 
        if b == BINDING_HEADER_MISC then return true end
        if b == PET_PASSIVE then return true end
        if b == FAVORITES then return false end
        return a < b
    end)

    -- order skills as well inside each header.
    if main.windowType == "Craft" and not CraftIsEnchanting() then
        for _, header in ipairs(headersList) do
            table.sort(skillInfoDict[header], function(a, b)
                -- If they have different name we keep the order
                if a.name ~= b.name then
                    return a.name < b.name
                else
                    -- Otherwise we order inversely by rank
                    return a.rankOrOtherDetail > b.rankOrOtherDetail
                end
            end)
            for i, skill in ipairs(skillInfoDict[header]) do
                skill.position = i
            end
        end
    elseif TimbersWiderProfessions_DB.sortRoguePoisons and select(1, GetTradeSkillLine()) == GetSpellInfo(POISONS_SPELL_ID) then
        table.sort(skillInfoDict[headersList[1]], function(a, b)
            -- compare the first 3 letters of the name.
            local nameA = string.sub(a.name, 1, 3)
            local nameB = string.sub(b.name, 1, 3)
            if nameA ~= nameB then
                return nameA < nameB
            end
            return a.name > b.name
        end)
        for i, skill in ipairs(skillInfoDict[headersList[1]]) do
            skill.position = i
        end
    end

    -- Sort skills within each category by orange skill level (ascending).
    if main.SkillLevels then
        for _, header in ipairs(headersList) do
            local skills = skillInfoDict[header]
            local hasLevels = false
            for _, skill in ipairs(skills) do
                if skill.recipeSpellId and main.SkillLevels[tonumber(skill.recipeSpellId)] then
                    hasLevels = true
                    break
                end
            end
            if hasLevels then
                table.sort(skills, function(a, b)
                    local aLevel = a.recipeSpellId and main.SkillLevels[tonumber(a.recipeSpellId)]
                    local bLevel = b.recipeSpellId and main.SkillLevels[tonumber(b.recipeSpellId)]
                    local aOrange = aLevel and aLevel[1] or 0
                    local bOrange = bLevel and bLevel[1] or 0
                    if aOrange ~= bOrange then
                        return aOrange > bOrange
                    end
                    return a.name < b.name
                end)
                for i, skill in ipairs(skills) do
                    skill.position = i
                end
            end
        end
    end

    -- If main.selectedSkill is nil, select the first one
    if main.selectedSkill == nil then
        for _, header in ipairs(headersList) do
            if not closedHeaders[header] then
                main.selectedSkill = skillInfoDict[header][1]
                main:SelectCraftTrade(main.selectedSkill.index)
                main:SetSkillDetails(main.selectedSkill)

                -- Select the first skill again to avoid some issues the first time you open the window.
                if main.selectedSkill.profession == "Pet" then
                    C_Timer.After(0.1, function()
                        if main.selectedSkill ~= nil then
                            main:SelectCraftTrade(main.selectedSkill.index)
                            main:SetSkillDetails(main.selectedSkill)
                        end
                    end)
                end
                break
            end
        end
    elseif main.selectedSkill.profession == "Pet" then -- Re-select the skill to avoid issues with pet skills.
        main:SelectCraftTrade(main.selectedSkill.index)
        main:SetSkillDetails(main.selectedSkill)
    end

    main.skillInfoDict, main.headersList = skillInfoDict, headersList

    -- Initialize closedHeaders entries if missing.
    for _, header in pairs(main.headersList) do
        if closedHeaders[header] == nil then
            closedHeaders[header] = false
        end
    end
end

function main:CraftTradeSkillFrame()
    CraftTradeSkillFrame = CreateFrame("Frame", "CraftTradeSkillFrame", UIParent, "PortraitFrameTemplate")
    local savedHeight = TimbersWiderProfessions_DB.windowHeight or 426
    CraftTradeSkillFrame:SetSize(650, savedHeight)
    CraftTradeSkillFrame:SetPoint("CENTER")
    CraftTradeSkillFrame:SetFrameStrata("HIGH")
    CraftTradeSkillFrame.TitleText:SetText("")

    -- Ignore mouse and make it pushable to the left side.
    CraftTradeSkillFrame:SetMovable(true)
    CraftTradeSkillFrame:EnableMouse(true)

    CraftTradeSkillFrame:SetAttribute("UIPanelLayout-defined", true)
    CraftTradeSkillFrame:SetAttribute("UIPanelLayout-enabled", true)
    CraftTradeSkillFrame:SetAttribute("UIPanelLayout-whileDead", nil)
    CraftTradeSkillFrame:SetAttribute("UIPanelLayout-pushable", 4)
    CraftTradeSkillFrame:SetAttribute("UIPanelLayout-area", "left")
    CraftTradeSkillFrame:SetAttribute("UIPanelLayout-width", CraftTradeSkillFrame:GetWidth())

    tinsert(UISpecialFrames, "CraftTradeSkillFrame") -- Allow escape key to close the frame.
    CreateFrame("Frame", "CraftTradeListInset", CraftTradeSkillFrame, "InsetFrameTemplate")
    CraftTradeListInset:SetSize(340, savedHeight - 76)
    CraftTradeListInset:SetPoint("BOTTOMLEFT", CraftTradeSkillFrame, "BOTTOMLEFT", 3, 0)
    
    main:AddShowOnlyAvailableCheckBox()
    main:AddShowTrainCheckBox()
    main:AddShowNewPetSkillsCheckBox()
    main:AddShowUnlearnedCheckBox()
    -- main:AddCraftButton()
    main:AddRankBar()

    -- Add a settings button below the close button.
    local settingsButton = CreateFrame("Button", "CraftTradeSkillSettingsButton", CraftTradeSkillFrame)
    settingsButton:SetSize(20, 20)
    settingsButton:SetPoint("TOPRIGHT", CraftTradeSkillFrame, "TOPRIGHT", -4, -24)
    settingsButton:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    settingsButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    settingsButton:EnableMouse(true)
    settingsButton:RegisterForClicks("AnyUp")
    settingsButton:SetFrameStrata("DIALOG")
    settingsButton:SetFrameLevel(100)
    settingsButton:SetScript("OnClick", function()
        if main.settingsCategory then
            -- Use the category object directly to open to the correct AddOns tab
            if Settings and Settings.OpenToCategory then
                Settings.OpenToCategory(main.settingsCategory:GetID())
            end
        end
    end)
    settingsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(SETTINGS, 1, 1, 1)
        GameTooltip:Show()
    end)
    settingsButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Add a scroll bar to the right of the frame that will go from 1 to 10.
    CreateFrame("Slider", "CraftTradeSkillListScrollBar", CraftTradeSkillFrame, "UIPanelScrollBarTemplate")
    CraftTradeSkillListScrollBar:SetPoint("TOPRIGHT", CraftTradeListInset, "TOPRIGHT", -8, -40)
    CraftTradeSkillListScrollBar:SetPoint("BOTTOMRIGHT", CraftTradeListInset, "BOTTOMRIGHT", -8, 20)
    CraftTradeSkillListScrollBar:SetMinMaxValues(0, 1)
    CraftTradeSkillListScrollBar:SetValueStep(1)
    
    CraftTradeSkillListScrollBar:SetScript("OnValueChanged", function(self, value, firstPass)
        CraftTradeSkillListScrollBar:SetValue(value, false)
        main:RefreshList()

        -- Update the buttons state when on extremas.
        -- The 0.5 here is because the scrollbar moves position in 0.5 increments, but value is continuous.
        local minValue, maxValue = CraftTradeSkillListScrollBar:GetMinMaxValues()
        if math.floor(value +MINIMUM_SCROLLBAR_INCREMENT) <= minValue then
            self.ScrollUpButton:Disable()
            self.ScrollDownButton:Enable()
            return -- Only one of the two can be disable at a time, mostly the first.
        else
            self.ScrollUpButton:Enable()
        end
        if math.ceil(value -MINIMUM_SCROLLBAR_INCREMENT) >= maxValue then
            self.ScrollDownButton:Disable()
        else
            self.ScrollDownButton:Enable()
        end
    end)

    CraftTradeSkillListScrollBar:SetValue(0)
    CraftTradeSkillListScrollBar:SetWidth(16)

    -- The arrows should change the value by one step.
    CraftTradeSkillListScrollBar.ScrollUpButton:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        local value = CraftTradeSkillListScrollBar:GetValue()
        CraftTradeSkillListScrollBar:SetValue(value - 1)
        CraftTradeSkillFrame.searchBar:ClearFocus()
    end)

    CraftTradeSkillListScrollBar.ScrollDownButton:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        local value = CraftTradeSkillListScrollBar:GetValue()
        CraftTradeSkillListScrollBar:SetValue(value + 1)
        CraftTradeSkillFrame.searchBar:ClearFocus()
    end)

    CraftTradeSkillListScrollBar:SetScript("OnMinMaxChanged", function(self, min, max)
        if max == 0 then
            CraftTradeSkillListScrollBar:Hide()
            CraftTradeListInset:SetScript("OnMouseWheel", nil)
        else
            CraftTradeSkillListScrollBar:Show()
            CraftTradeListInset:SetScript("OnMouseWheel", function(self, delta)
                local value = CraftTradeSkillListScrollBar:GetValue()
                CraftTradeSkillListScrollBar:SetValue(value - delta)
            end)
        end
    end)

    CreateFrame("Frame", "CraftTradeReagentsInset", CraftTradeSkillFrame, "InsetFrameTemplate")
    CraftTradeReagentsInset:SetSize(CraftTradeSkillFrame:GetWidth() -CraftTradeListInset:GetWidth(), savedHeight - 76)
    CraftTradeReagentsInset:SetPoint("BOTTOMRIGHT", CraftTradeSkillFrame, "BOTTOMRIGHT", -3, 0)


    main:AddSearchBar()
    
    CraftTradeReagentsInset:CreateTexture("CraftTradeDetailSquare", "BACKGROUND")
    CraftTradeDetailSquare:SetTexture("130964")
    CraftTradeDetailSquare:SetPoint("TOPLEFT", 5, -1)
    CraftTradeDetailSquare:SetSize(CraftTradeReagentsInset:GetWidth()-5, 79)
    CraftTradeDetailSquare:Hide()

    CraftTradeReagentsInset:CreateTexture("CraftTradeDetailIcon", "OVERLAY")
    CraftTradeDetailIcon:SetSize(45, 45)
    CraftTradeDetailIcon:SetPoint("TOPLEFT", 14, -9)
    CraftTradeDetailIcon:SetTexture("")
    CraftTradeDetailIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        
        if main.windowType == "Craft" then
            GameTooltip:SetCraftSpell(GetCraftSelectionIndex())
            GameTooltip:Show()
            return
        end

        -- Everything else we can handle.
        GameTooltip:SetHyperlink(main.selectedSkill.link)
    end)
    CraftTradeDetailIcon:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    CraftTradeDetailIcon:Hide()
    
    CraftTradeReagentsInset.count = CraftTradeReagentsInset:CreateFontString("DetailIconCount", "OVERLAY", "GameFontNormal")
    CraftTradeReagentsInset.count:SetPoint("BOTTOMRIGHT", CraftTradeDetailIcon, "BOTTOMRIGHT", -4, 2)
    CraftTradeReagentsInset.count:SetText("")
    CraftTradeReagentsInset.count:SetVertexColor(1, 1, 1)
    CraftTradeReagentsInset.count:SetFont("Fonts\\FRIZQT__.TTF", 13)
    CraftTradeReagentsInset.count:SetShadowColor(0, 0, 0, 1)
    CraftTradeReagentsInset.count:SetShadowOffset(1, -1)

    -- A special label used for hunters pet training window.
    CraftTradeRankLabel = CraftTradeReagentsInset:CreateFontString("CraftTradeRankLabel", "OVERLAY", "GameFontHighlight")
    CraftTradeRankLabel:SetPoint("TOPRIGHT", CraftTradeReagentsInset, "TOPRIGHT", -10, -10)
    CraftTradeRankLabel:SetText("")
    CraftTradeRankLabel:Hide()

    CraftTradePetPointsLabel = CraftTradeReagentsInset:CreateFontString("CraftTradePetPointsLabel", "OVERLAY", "GameFontNormal")
    CraftTradePetPointsLabel:SetPoint("BOTTOMLEFT", CraftTradeReagentsInset, "BOTTOMLEFT", 15, 12)
    CraftTradePetPointsLabel:SetText("Training Points: ")
    CraftTradePetPointsLabel:Hide()

    CraftTradeReagentsInset:CreateFontString("CraftTradeDetailName", "OVERLAY", "GameFontNormal")
    CraftTradeDetailName:SetPoint("TOPLEFT", 70, -15)
    CraftTradeDetailName:SetSize(240, 10)
    CraftTradeDetailName:SetText("")
    CraftTradeDetailName:SetJustifyH("LEFT")

    -- Skill levels display (orange, yellow, green, gray)
    CraftTradeReagentsInset:CreateFontString("CraftTradeSkillLevels", "OVERLAY", "GameFontNormalSmall")
    CraftTradeSkillLevels:SetPoint("TOPLEFT", CraftTradeDetailName, "BOTTOMLEFT", 0, -3)
    CraftTradeSkillLevels:SetSize(220, 12)
    CraftTradeSkillLevels:SetText("")
    CraftTradeSkillLevels:SetJustifyH("LEFT")
    CraftTradeSkillLevels:Hide()

    CraftTradeReagentsInset:CreateFontString("CraftTradeDetailDescription", "OVERLAY", "GameFontNormal")
    CraftTradeDetailDescription:SetPoint("TOPLEFT", CraftTradeDetailSquare, "BOTTOMLEFT", 10, 10)
    CraftTradeDetailDescription:SetSize(CraftTradeReagentsInset:GetWidth()-25, 60)
    CraftTradeDetailDescription:SetText("")
    CraftTradeDetailDescription:SetJustifyH("LEFT")
    CraftTradeDetailDescription:SetJustifyV("TOP")
    CraftTradeDetailDescription:SetTextColor(1, 1, 1)
    CraftTradeDetailDescription:SetFont("Fonts\\FRIZQT__.TTF", 10)

    CreateFrame("Button", "CraftTradeFavorite", CraftTradeReagentsInset)
    CraftTradeFavorite:SetSize(30, 30)
    CraftTradeFavorite:SetPoint("TOPLEFT", CraftTradeDetailName, "TOPRIGHT", -30, -20)
    CraftTradeFavorite:SetNormalTexture("Interface\\Common\\FavoritesIcon")
    CraftTradeFavorite:SetAlpha(0.5)
    CraftTradeFavorite:Hide()
    CraftTradeFavorite:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(BATTLE_PET_FAVORITE, 1, 1, 1)
        if C_CVar.GetCVarBool("showNewbieTips") == true then
            GameTooltip:AddLine(main.ClientLocale.FavoriteTooltip, nil, nil, nil, true)
        end
        GameTooltip:Show()

        self:SetAlpha(1)
    end)

    CraftTradeFavorite:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        -- Unhighlight the button
        local skill = main.selectedSkill
        if TimbersWiderProfessions_DB.favorites[skill.profession][skill.skillId] ~= nil then
            self:SetAlpha(1)
        else
            self:SetAlpha(0.5)
        end
    end)

    CraftTradeFavorite:SetScript("OnClick", function(self)
        local skill = main.selectedSkill
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

        if TimbersWiderProfessions_DB.favorites[skill.profession][skill.skillId] ~= nil then
            TimbersWiderProfessions_DB.favorites[skill.profession][skill.skillId] = nil
            self:SetAlpha(0.5)
        else
            if TimbersWiderProfessions_DB.favorites[skill.profession] == nil then
                TimbersWiderProfessions_DB.favorites[skill.profession] = {}
            end
            TimbersWiderProfessions_DB.favorites[skill.profession][skill.skillId] = true
            self:SetAlpha(1)
        end

        main:FetchSkillData()
        main:RefreshList()
    end)


    -- And a hide button.
    CraftTradeReagentsInset:CreateFontString("CraftTradeDetailReagents", "OVERLAY", "GameFontNormal")
    CraftTradeDetailReagents:SetPoint("TOPLEFT", CraftTradeDetailDescription, "BOTTOMLEFT", 0, 20)
    CraftTradeDetailReagents:SetSize(CraftTradeReagentsInset:GetWidth()-20, 0)
    CraftTradeDetailReagents:SetText(MINIMAP_TRACKING_VENDOR_REAGENT.. ":")
    CraftTradeDetailReagents:SetJustifyH("LEFT")
    CraftTradeDetailReagents:Hide()

    for i = 1, MAX_CRAFT_REAGENTS do
        local x = (i-1) % MAX_REAGENTS_PER_LINE
        local y = floor((i-1) / MAX_REAGENTS_PER_LINE)

        -- Create a reagent window.
        local reagent = CreateFrame("Frame", "CraftTradeReagent"..i, CraftTradeReagentsInset)
        reagent:SetSize(150, 45)
        reagent:SetPoint("TOPLEFT", CraftTradeDetailReagents, "BOTTOMLEFT", x*148, -50 * y -10)
        reagent:Hide()

        local background = reagent:CreateTexture(nil, "BACKGROUND")
        background:SetTexture("136796")
        background:SetSize(122, 65)
        background:SetPoint("TOPLEFT", 31, 10)

        reagent.icon = reagent:CreateTexture(nil, "OVERLAY")
        reagent.icon:SetSize(40, 40)
        reagent.icon:SetPoint("TOPLEFT", 0, -2.5)
        reagent.icon:SetTexture("")
        reagent.icon:SetVertexColor(0.5, 0.5, 0.5)

        reagent.count = reagent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        reagent.count:SetPoint("BOTTOMRIGHT", reagent.icon, "BOTTOMRIGHT", -3, 2)
        reagent.count:SetText("0/0")
        reagent.count:SetVertexColor(1, 1, 1)

        reagent.name = reagent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        reagent.name:SetPoint("LEFT", reagent.icon, "RIGHT", 8, 0)
        reagent.name:SetSize(90, 30)
        reagent.name:SetText(" ")
        reagent.name:SetJustifyH("LEFT")
        reagent.name:SetTextColor(0.5, 0.5, 0.5)
    end

    if isHunter then
        local MAX_PETS_PER_LINE = 6
        for i = 1, MAX_PETS_SHOWN do
            local x = (i-1) % MAX_PETS_PER_LINE
            local y = floor((i-1) / MAX_PETS_PER_LINE)

            -- Create a reagent window.
            local petFamily = CreateFrame("Frame", "CraftTradePet"..i, CraftTradeReagentsInset)
            petFamily:SetSize(45, 45)
            petFamily:SetPoint("TOPLEFT", CraftTradeDetailReagents, "BOTTOMLEFT", x*49 +3, -50 * y -10)
            petFamily:Hide()

            petFamily.icon = petFamily:CreateTexture(nil, "OVERLAY")
            petFamily.icon:SetSize(40, 40)
            petFamily.icon:SetPoint("TOPLEFT", 0, -2.5)

            -- We create a function to set the pet family name and icon.
            petFamily.SetPetFamily = function(self, petFamilyName, petFamilyIcon)
                if petFamilyName == nil then
                    petFamily.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    petFamily.icon:SetVertexColor(0.5, 0.5, 0.5)

                    -- If you hover it show the tooltip.
                    petFamily:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(UNKNOWN, 1, 1, 1)
                        GameTooltip:AddLine(main.ClientLocale.PetUnknownTooltip, nil, nil, nil, true)
                        GameTooltip:Show()
                    end)
                    return
                end
                self.icon:SetTexture(petFamilyIcon and petFamilyIcon or "Interface\\Icons\\ability_hunter_pet_".. petFamilyName)
                self.icon:SetVertexColor(1, 1, 1)

                -- Update the tooltip as well.
                self:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(petFamilyName, 1, 1, 1)
                    GameTooltip:Show()
                end)
            end

            petFamily:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
            end)

            petFamily:SetPetFamily(nil)
        end

        -- A label that will write main.locale.AllPetsCanLearn below reagentsdetails
        CraftTradeAllPetsCanLearnLabel = CraftTradeReagentsInset:CreateFontString("CraftTradeAllPetsCanLearnLabel", "OVERLAY", "GameFontHighlight")
        CraftTradeAllPetsCanLearnLabel:SetPoint("BOTTOMLEFT", CraftTradeDetailReagents, "BOTTOMLEFT", 0, -20)
        CraftTradeAllPetsCanLearnLabel:SetText(main.ClientLocale.AllPetsCanLearn)
        CraftTradeAllPetsCanLearnLabel:SetFont("Fonts\\FRIZQT__.TTF", 10)
        CraftTradeAllPetsCanLearnLabel:Hide()
    end

    CraftTradeListInset:CreateTexture("CraftTradeHighlight", "OVERLAY")
    CraftTradeHighlight:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    CraftTradeHighlight:SetSize(CraftTradeListInset:GetWidth() - 15, 20)
    CraftTradeHighlight:SetPoint("TOPLEFT", 0, 0)
    CraftTradeHighlight:SetBlendMode("BLEND")
    CraftTradeHighlight:SetVertexColor(0.306, 0.302, 0.306)  -- Default gray #4E4D4E
    CraftTradeHighlight:Hide()
    
    for i = 1, MAX_SKILLS_CREATABLE do
        -- Add a skillline button to the left of the frame.
        local skillButton = CreateFrame("Button", "CraftTradeSkillButton"..i, CraftTradeListInset)
        skillButton:SetSize(CraftTradeListInset:GetWidth()-33, 20)
        skillButton:SetPoint("TOPLEFT", CraftTradeListInset, "TOPLEFT", 8, -20 * i -5)
        skillButton.normalFont = CreateFont("SkillButtonNormalFont".. i)
        skillButton.normalFont:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        skillButton.normalFont:SetTextColor(0.5, 0.5, 0.5) --(0.5, 0.88, 0) nice color :)
        skillButton:SetNormalFontObject(skillButton.normalFont)
        skillButton:SetHighlightFontObject("GameFontHighlight")
        skillButton:SetDisabledFontObject("GameFontDisable")
        skillButton:SetText("h")
        skillButton:Hide()
        skillButton:GetFontString():SetSize(CraftTradeListInset:GetWidth()-58, 20)
        skillButton:GetFontString():SetJustifyH("LEFT")
        skillButton.type = ""

        skillButton.efficiencyIcon = skillButton:CreateTexture("CraftTradeSkillButtonIcon"..i, "OVERLAY")
        skillButton.efficiencyIcon:SetSize(15, 13)
        skillButton.efficiencyIcon:SetPoint("LEFT", 0, -1)
        skillButton.efficiencyIcon:SetTexture("")

        skillButton.headerFrame = skillButton:CreateTexture("CraftTradeSkillButtonHeader"..i, "BACKGROUND")
        skillButton.headerFrame:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        skillButton.headerFrame:SetSize(CraftTradeListInset:GetWidth()-15, 20)
        skillButton.headerFrame:SetPoint("TOPLEFT", 0, 0)
        skillButton.headerFrame:SetVertexColor(0.3, 0.3, 0.35, 0.4)
        skillButton.headerFrame:Hide()

        skillButton.closeText = skillButton:CreateFontString("CraftTradeSkillButton"..i.. "Close", "OVERLAY", "GameFontNormal")
        skillButton.closeText:SetPoint("RIGHT", -8, 0)
        skillButton.closeText:SetText("-")
        skillButton.closeText:SetTextColor(1, 1, 1)
        skillButton.closeText:SetFont("Fonts\\FRIZQT__.TTF", 13)
        skillButton.closeText:Hide()

        -- A highlight for newly learned skills.
        skillButton.newHighlight = skillButton:CreateTexture("CraftTradeSkillButtonNewHighlight"..i, "OVERLAY")
        skillButton.newHighlight:SetTexture("interface/glues/common/glues-bigbutton-glow")
        skillButton.newHighlight:SetSize(305, 30)
        skillButton.newHighlight:SetPoint("TOPLEFT", 11, 4.5)
        skillButton.newHighlight:SetBlendMode("ADD")
        skillButton.newHighlight:SetVertexColor(1, 1, 0, 0.8)
        skillButton.newHighlight:SetTexCoord(0.17, 0.83, 0, 1)
        skillButton.newHighlight:Hide()

        -- Skill levels display (right-aligned)
        skillButton.skillLevels = skillButton:CreateFontString("CraftTradeSkillButtonLevels"..i, "OVERLAY", "GameFontNormalSmall")
        skillButton.skillLevels:SetPoint("RIGHT", skillButton, "RIGHT", -5, 0)
        skillButton.skillLevels:SetJustifyH("RIGHT")
        skillButton.skillLevels:Hide()

        skillButton:SetScript("OnMouseDown", function(self)
            if IsModifiedClick("CHATLINK") and self.link then
                ChatEdit_InsertLink(self.link)
            end
        end)

        skillButton.SetHeader = function(self, text)
            self.efficiencyIcon:Hide()
            self.newHighlight:Hide()
            self.skillLevels:Hide()
            self.headerFrame:Show()
            skillButton.closeText:Show()
            self:SetText(text)
            self:SetSelected(false)
            self:SetNormalFontObject("GameFontHighlight")
            self:GetFontString():SetPoint("LEFT", 13, 0)
            self:Show()
            self.type = "header"
            self.link = nil

            self:SetScript("OnClick", function(self)
                if IsModifiedClick("CHATLINK") then -- Toggle all headers.
                    CraftTradeSkillFrame.searchBar:ClearFocus()
                    local goalState = not closedHeaders[text]
                    for headerText, _ in pairs(closedHeaders) do
                        closedHeaders[headerText] = goalState
                    end
                    main:RefreshList()
                    return
                end
                CraftTradeSkillFrame.searchBar:ClearFocus()
                closedHeaders[text] = not closedHeaders[text]
                main:RefreshList()
            end)
        end

        skillButton.SetSkill = function(self, skill)
            local isNew = TimbersWiderProfessions_DB.knownTradeskills[skill.skillId] == nil
            self.headerFrame:Hide()
            skillButton.closeText:Hide()
            if skill.numAvailable == 0 then
                self:SetText(skill.displayName)
            else
                self:SetText(skill.displayName.. " [".. skill.numAvailable.. "]")
            end
            local textWidth = self:GetFontString():GetStringWidth()
            self.newHighlight:SetSize(textWidth +25, 30)

            self:GetFontString():SetPoint("LEFT", 20, 0)
            if skill.isUnlearned then
                self.normalFont:SetTextColor(0.5, 0.5, 0.5, 0.5)
            elseif TimbersWiderProfessions_DB.skillColorMode == "difficulty" then
                local color = GetDifficultyTextColor(skill.rankEfficiency)
                self.normalFont:SetTextColor(color[1], color[2], color[3])
            elseif TimbersWiderProfessions_DB.skillColorMode == "rarity" and skill.rarityColor ~= "|c7c7c7c7c" then
                self.normalFont:SetTextColor(ColorCodeToRGB(skill.rarityColor))
            else
                self.normalFont:SetTextColor(0.5, 0.5, 0.5)
            end
            self:SetNormalFontObject(self.normalFont)
            self.type = "skill"
            self:SetSelected(not skill.isUnlearned and main.selectedSkill ~= nil and main.selectedSkill.skillId == skill.skillId)
            if skill.isUnlearned or skill.rankEfficiency == "trivial" then
                self.efficiencyIcon:Hide()
            else
                self.efficiencyIcon:SetTexture("Interface\\AddOns\\TimbersWiderProfessions\\Assets\\".. skill.rankEfficiency)
                self.efficiencyIcon:Show()
            end

            -- Show skill levels in list (right-aligned, color-coded)
            if not skill.isUnlearned and TimbersWiderProfessions_DB.showSkillLevelsInList and skill.recipeSpellId and main.SkillLevels then
                local levels = main.SkillLevels[tonumber(skill.recipeSpellId)]
                if levels then
                    local levelsText = string.format(
                        "|cffff8000%d|r |cffffff00%d|r |cff00ff00%d|r |cff808080%d|r",
                        levels[1], levels[2], levels[3], levels[4]
                    )
                    self.skillLevels:SetText(levelsText)
                    self.skillLevels:Show()
                else
                    self.skillLevels:Hide()
                end
            else
                self.skillLevels:Hide()
            end

            self:Show()
            self.link = skill.link

            if skill.isUnlearned then
                self:SetScript("OnClick", nil)
            else
                self:SetScript("OnClick", function(self2)
                    if IsModifiedClick("CHATLINK") then return end
                    CraftTradeSkillFrame.searchBar:ClearFocus()
                    for i = 1, MAX_SKILLS_CREATABLE do
                        _G["CraftTradeSkillButton"..i]:SetSelected(false)
                    end
                    main:SetSkillDetails(skill)
                    self2:SetSelected(true)
                    self2.newHighlight:Hide()
                    TimbersWiderProfessions_DB.knownTradeskills[skill.skillId] = 0
                end)
            end

            -- Handle new skill highlights
            self.newHighlight:SetShown(not skill.isUnlearned and isNew)
        end
        
        skillButton.SetSelected = function(self, selected)
            self.isSelected = selected

            if self.type == "header" then return end
            if not selected then
                self:SetNormalFontObject(self.normalFont)
            else
                self:SetNormalFontObject("GameFontHighlight")

                CraftTradeHighlight:ClearAllPoints()
                CraftTradeHighlight:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
                CraftTradeHighlight:SetDesaturated(false)
                CraftTradeHighlight:SetVertexColor(0.306, 0.302, 0.306)  -- Default gray #4E4D4E
                local selectedSkill = main.selectedSkill
                if selectedSkill ~= nil then
                    if selectedSkill.profession == "Pet" then
                        if selectedSkill.canLearnState == "never" then
                            CraftTradeHighlight:SetVertexColor(0.8, 0, 0)
                        elseif selectedSkill.canLearnState == "notYetLevel" or selectedSkill.canLearnState == "notYetPoints" then
                            CraftTradeHighlight:SetVertexColor(0.306, 0.302, 0.306)  -- Gray #4E4D4E
                        else
                            -- Green
                            CraftTradeHighlight:SetVertexColor(0.153, 0.451, 0.153)  -- Green #277327
                        end
                        if selectedSkill.rankEfficiency == "used" then
                            CraftTradeHighlight:SetDesaturated(true)
                            CraftTradeHighlight:SetVertexColor(0.306, 0.302, 0.306)  -- Gray #4E4D4E
                        end
                    elseif TimbersWiderProfessions_DB.skillColorMode == "difficulty" then
                        local color = GetDifficultyHighlightColor(selectedSkill.rankEfficiency)
                        CraftTradeHighlight:SetVertexColor(color[1], color[2], color[3])
                    end
                end
                CraftTradeHighlight:Show()
            end
        end

        skillButton:SetSelected(false)
    end
end

function main:CleanSkillDetails()
    main.selectedSkill = nil

    CraftTradeDetailName:SetText("")
    CraftTradeDetailDescription:SetText("")
    CraftTradeSkillLevels:SetText("")
    CraftTradeSkillLevels:Hide()
    CraftTradeDetailIcon:SetTexture("")
    CraftTradeReagentsInset.count:SetText("")
    CraftTradeDetailIcon:Hide()
    CraftTradeDetailReagents:Hide()
    CraftTradeDetailSquare:Hide()
    CraftTradeFavorite:Hide()
    
    if TradeSkillRequirementLabel then
        TradeSkillRequirementLabel:ClearAllPoints()
        TradeSkillRequirementLabel:Hide()
        TradeSkillRequirementText:ClearAllPoints()
        TradeSkillRequirementText:Hide()
        TradeSkillSkillCooldown:ClearAllPoints()
        TradeSkillSkillCooldown:Hide()
    end

    if CraftRequirements then
        CraftRequirements:ClearAllPoints()
        CraftRequirements:Hide()
    end
    if CraftCost then
        CraftCost:ClearAllPoints()
        CraftCost:Hide()
    end

    for i = 1, MAX_CRAFT_REAGENTS do
        local reagent = _G["CraftTradeReagent"..i]
        reagent:Hide()
    end

    if isHunter then
        for i = 1, MAX_PETS_SHOWN do
            local petFamily = _G["CraftTradePet"..i]
            petFamily:Hide()
            petFamily:SetPetFamily(nil)
        end
        CraftTradeAllPetsCanLearnLabel:Hide()
    end
end

function main:CleanStolenButtons()
    if CraftRequirements then
        CraftRequirements:ClearAllPoints()
        CraftRequirements:Hide()
    end
    if CraftCost then
        CraftCost:ClearAllPoints()
        CraftCost:Hide()
    end

    if TradeSkillRequirementLabel then
        TradeSkillRequirementLabel:ClearAllPoints()
        TradeSkillRequirementLabel:Hide()
        TradeSkillRequirementText:ClearAllPoints()
        TradeSkillRequirementText:Hide()
    end

    if CraftCreateButton then
        CraftCreateButton:ClearAllPoints()
        CraftCreateButton:Hide()
        -- CraftCreateButton:SetPoint("BOTTOMRIGHT", CraftFrame, "BOTTOMRIGHT", -10, 10)
    end

    if TradeSkillInvSlotDropdown then
        TradeSkillInvSlotDropdown:ClearAllPoints()
        TradeSkillInvSlotDropdown:Hide()
    end
    
    if TradeSkillSubClassDropdown then
        TradeSkillSubClassDropdown:ClearAllPoints()
        TradeSkillSubClassDropdown:Hide()
    end

    if TradeSkillCreateButton then
        TradeSkillCreateButton:ClearAllPoints()
        TradeSkillCreateButton:Hide()
    end
end

function main:SetSkillDetails(skill)
    main.selectedSkill = skill

    -- Determine the anchor for requirements based on whether skill levels are shown
    local hasSkillLevels = skill.recipeSpellId and main.SkillLevels and main.SkillLevels[tonumber(skill.recipeSpellId)]
    local requirementsAnchor = hasSkillLevels and CraftTradeSkillLevels or CraftTradeDetailName
    local requirementsOffset = hasSkillLevels and -3 or -5
    local cooldownOffset = hasSkillLevels and -18 or -20

    if main.windowType == "Craft" then
        CraftRequirements:ClearAllPoints()
        CraftRequirements:SetPoint("TOPLEFT", requirementsAnchor, "BOTTOMLEFT", 0, requirementsOffset)
        CraftRequirements:SetParent(CraftTradeReagentsInset)
        CraftRequirements:SetJustifyH("LEFT")
        if skill.canLearnState == "notYetLevel" then
            CraftRequirements:SetTextColor(1, 0, 0)
        else
            CraftRequirements:SetTextColor(1, 1, 1)
        end
        CraftRequirements:Show()
        if skill.profession == "Pet" then
            CraftCost:ClearAllPoints()
            CraftCost:SetPoint("TOPLEFT", requirementsAnchor, "BOTTOMLEFT", 0, cooldownOffset)
            CraftCost:SetParent(CraftTradeReagentsInset)
            CraftCost:SetJustifyH("LEFT")
            CraftCost:Show()
        end
    else
        TradeSkillRequirementLabel:ClearAllPoints()
        TradeSkillRequirementLabel:SetPoint("TOPLEFT", requirementsAnchor, "BOTTOMLEFT", 0, requirementsOffset)
        TradeSkillRequirementLabel:SetParent(CraftTradeReagentsInset)
        TradeSkillRequirementLabel:SetJustifyH("LEFT")
        TradeSkillRequirementLabel:Show()

        TradeSkillRequirementText:ClearAllPoints()
        TradeSkillRequirementText:SetPoint("LEFT", TradeSkillRequirementLabel, "RIGHT", 3, 0)
        TradeSkillRequirementText:SetParent(CraftTradeReagentsInset)
        TradeSkillRequirementText:SetJustifyH("LEFT")
        TradeSkillRequirementText:Show()

        TradeSkillSkillCooldown:ClearAllPoints()
        TradeSkillSkillCooldown:SetPoint("TOPLEFT", requirementsAnchor, "BOTTOMLEFT", 0, cooldownOffset)
        TradeSkillSkillCooldown:SetParent(CraftTradeReagentsInset)
        TradeSkillSkillCooldown:SetJustifyH("LEFT")
        TradeSkillSkillCooldown:Show()
    end

    if TimbersWiderProfessions_DB.favorites[skill.profession][skill.skillId] then
        CraftTradeFavorite:SetAlpha(1)
    else
        CraftTradeFavorite:SetAlpha(0.5)
    end

    CraftTradeDetailName:SetText(skill.name)
    CraftTradeDetailSquare:Show()
    CraftTradeDetailDescription:SetText(skill.description)

    -- Display skill levels with color coding (orange, yellow, green, gray)
    if skill.recipeSpellId and main.SkillLevels then
        local levels = main.SkillLevels[tonumber(skill.recipeSpellId)]
        if levels then
            local orangeLevel = levels[1]
            local yellowLevel = levels[2]
            local greenLevel = levels[3]
            local grayLevel = levels[4]
            local levelsText = string.format(
                "|cffff8000%d|r / |cffffff00%d|r / |cff00ff00%d|r / |cff808080%d|r",
                orangeLevel, yellowLevel, greenLevel, grayLevel
            )
            CraftTradeSkillLevels:SetText(levelsText)
            CraftTradeSkillLevels:Show()
        else
            CraftTradeSkillLevels:Hide()
        end
    else
        CraftTradeSkillLevels:Hide()
    end

    CraftTradeDetailReagents:ClearAllPoints()
    CraftTradeDetailReagents:SetPoint("TOP", CraftTradeDetailDescription, "TOP", 0, -CraftTradeDetailDescription:GetStringHeight() -15)
    CraftTradeDetailReagents:Hide()
    
    if skill.profession == "Pet" then
        CraftTradeFavorite:Hide()
        CraftTradeRankLabel:SetText(skill.rankOrOtherDetail)
        CraftTradeRankLabel:Show()
        CraftTradePetPointsLabel:Show()
        if main.hasBeastLore then
            CraftTradeDetailReagents:Show()
        end

        if main.hasBeastLore then
            local petDetails = main.createPetSkillsCategoryMap[skill.name]
            
            local numberObserved = 1
            local numberOfFamiliesThatCanLearn = 0
            local observedFamiliesThatCanLearn = {}
            if petDetails ~= nil and petDetails["Families"] ~= nil then
                numberOfFamiliesThatCanLearn = #petDetails["Families"]

                -- We find the common set between TimbersWiderProfessions_DB.petFamilies and petDetails["Families"]
                -- local observedFamilies = {1, 2, 3, 4, 5, 6, 7, 8, 9, 20}
                local observedFamilies = {}
                for familyId, _ in pairs(TimbersWiderProfessions_DB.petFamiliesTrained) do
                    table.insert(observedFamilies, familyId)
                end
                for _, family in ipairs(observedFamilies) do
                    for _, petFamily in ipairs(petDetails["Families"]) do
                        if family == petFamily then
                            table.insert(observedFamiliesThatCanLearn, family)
                        end
                    end
                end
                numberObserved = #observedFamiliesThatCanLearn
            end
            for i = 1, MAX_PETS_SHOWN do
                local petFrame = _G["CraftTradePet".. i]
                if i <= math.min(numberObserved +1, numberOfFamiliesThatCanLearn) then
                    local familyName = petDetails["Families"][i]
                    if i == numberObserved +1 then
                        petFrame:SetPetFamily(nil)
                    else
                        local creatureFamilyInfo = C_CreatureInfo.GetCreatureFamilyInfo(observedFamiliesThatCanLearn[i])
                        petFrame:SetPetFamily(creatureFamilyInfo.name, creatureFamilyInfo.iconFile)
                    end
                    petFrame:Show()
                else
                    petFrame:Hide()
                end
            end
            if numberOfFamiliesThatCanLearn == 0 then
                CraftTradeAllPetsCanLearnLabel:Show()
            else
                CraftTradeAllPetsCanLearnLabel:Hide()
            end
        end
    else
        CraftTradeFavorite:Show()
        CraftTradeRankLabel:Hide()
        CraftTradePetPointsLabel:Hide()
        CraftTradeDetailReagents:Show()
        if isHunter then
            for i = 1, MAX_PETS_SHOWN do
                local petFrame = _G["CraftTradePet"..i]
                petFrame:SetPetFamily(nil)
                petFrame:Hide()
            end
        end
    end


    CraftTradeDetailIcon:SetTexture(skill.texture)
    if skill.minProduced == nil or skill.maxProduced == nil or (skill.minProduced == 1 and skill.maxProduced == 1) then
        CraftTradeReagentsInset.count:SetText("")
    elseif skill.minProduced == skill.maxProduced then
        CraftTradeReagentsInset.count:SetText(skill.minProduced)
    else
        -- Show as a range
        CraftTradeReagentsInset.count:SetText(skill.minProduced.. "-".. skill.maxProduced)
    end
    CraftTradeDetailIcon:Show()

    CraftTradeDetailIcon:SetScript("OnMouseDown", function(self, button)
        if IsModifiedClick("CHATLINK") then
            linkItemInTextBar(skill.name, skill.link)
        elseif IsModifiedClick("DRESSUP") then
            DressUpItemLink(skill.link)
        end
    end)

    for k, _reagent in ipairs(skill.reagents) do
        local reagent = _G["CraftTradeReagent"..k]
        reagent.icon:SetTexture(_reagent.icon)
        reagent.name:SetText(_reagent.name)
        reagent.count:SetText(_reagent.playerCount.. "/".. _reagent.count)
        if _reagent.playerCount < _reagent.count then
            reagent.icon:SetVertexColor(0.5, 0.5, 0.5)
            reagent.name:SetTextColor(0.5, 0.5, 0.5)
        else
            reagent.icon:SetVertexColor(1, 1, 1)
            reagent.name:SetTextColor(1, 1, 1)
        end
        reagent:Show()

        reagent:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(reagent.icon, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(_reagent.link)
            GameTooltip:Show()
        end)

        reagent:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        
        -- On modified chat click, link the item.
        reagent:SetScript("OnMouseDown", function(self, button)
            if IsModifiedClick("CHATLINK") then
                linkItemInTextBar(_reagent.name, _reagent.link)
            end
        end)
    end
    
    for i = #skill.reagents +1, MAX_CRAFT_REAGENTS do
        local reagent = _G["CraftTradeReagent"..i]
        reagent:Hide()

        reagent:SetScript("OnEnter", function(self)
            GameTooltip:Hide()
        end)

        reagent:SetScript("OnMouseDown", function() end)
    end

    main:SelectCraftTrade(main.selectedSkill.index)

    -- This prevents empty requirement labels from showing.
    if TradeSkillRequirementText:GetText() == nil then
        TradeSkillRequirementLabel:Hide()
        TradeSkillRequirementText:Hide()
    end
end

function main:SelectCraftTrade(index)
    -- Move the old frame's selection.
    local scrollBar, selectFunction, totalSkills, buttonName
    if main.windowType == "Craft" then
        scrollBar = CraftListScrollFrameScrollBar
        selectFunction = SelectCraft
        totalSkills = GetNumCrafts()
        buttonName = "Craft"
    else
        scrollBar = TradeSkillListScrollFrameScrollBar
        selectFunction = SelectTradeSkill
        totalSkills = GetNumTradeSkills()
        buttonName = "TradeSkillSkill"
    end

    local goalScrollbarHeight = 16 *(index -1)
    scrollBar:SetValue(goalScrollbarHeight)

    local shiftedWindowIndex = 1
    if goalScrollbarHeight > select(2, scrollBar:GetMinMaxValues()) then
        if totalSkills < 8 then
            shiftedWindowIndex = index
        else
            shiftedWindowIndex = 8 -(totalSkills -index)
        end
    end

    selectFunction(shiftedWindowIndex)
    _G[buttonName.. shiftedWindowIndex]:Click()
end

function main:RefreshList()
    if main.headersList == nil then return end
    local totalSkills = 0
    for key, value in pairs(main.skillInfoDict) do
        if not closedHeaders[key] then
            totalSkills = totalSkills + #value
        end
    end
    
    CraftTradeSkillListScrollBar:SetMinMaxValues(0, max(MAX_SKILLS_SHOWN, #main.headersList +totalSkills) -MAX_SKILLS_SHOWN)
    CraftTradeHighlight:Hide()

    if main.windowType == "Craft" and not CraftIsEnchanting() then
        local hasPet = UnitExists("pet")
        if hasPet then
            local totalPoints, pointsSpent = GetPetTrainingPoints();
            local availaiblePoints = totalPoints - pointsSpent
            CraftTradePetPointsLabel:SetText("Training Points: |cffffffff".. availaiblePoints)
            ShowNewPetSkillsTradeCrafts:Show()
        else
            CraftTradePetPointsLabel:SetText("|cffff0000".. SPELL_FAILED_NO_PET.. ".")
            ShowNewPetSkillsTradeCrafts:Hide()
        end
        CraftTradePetPointsLabel:Show()
    else
        CraftTradePetPointsLabel:Hide()
    end

    local drawnSkillsIndex = 1
    local totalSkillsIndex = 1
    local headerIndex = 1
    local scrollOffset = CraftTradeSkillListScrollBar:GetValue()

    repeat
        local skillType = main.headersList[headerIndex]
        local skills = main.skillInfoDict[skillType]
        if skills == nil then break end

        if totalSkillsIndex > scrollOffset then
            _G["CraftTradeSkillButton"..drawnSkillsIndex]:SetHeader(skillType)
            drawnSkillsIndex = drawnSkillsIndex + 1
        end

        if not closedHeaders[skillType] then
            for skillIndex = 1, #skills do
                totalSkillsIndex = totalSkillsIndex + 1
                if totalSkillsIndex > MAX_SKILLS_SHOWN +scrollOffset then break end
                local skill = skills[skillIndex]
                
                if totalSkillsIndex > scrollOffset then
                    _G["CraftTradeSkillButton"..drawnSkillsIndex]:SetSkill(skill)
                    drawnSkillsIndex = drawnSkillsIndex + 1
                end
            end
        end
        totalSkillsIndex = totalSkillsIndex + 1
        headerIndex = headerIndex + 1
    until totalSkillsIndex > MAX_SKILLS_SHOWN +scrollOffset

    for i = drawnSkillsIndex, MAX_SKILLS_SHOWN do
        _G["CraftTradeSkillButton"..i]:Hide()
    end
end

function main:AddSearchBar()
    -- Add collapse/expand all button above the search bar
    local collapseAllButton = CreateFrame("Button", "CraftTradeCollapseAllButton", CraftTradeListInset)
    collapseAllButton:SetSize(36, 16)
    collapseAllButton:SetPoint("BOTTOMLEFT", CraftTradeListInset, "TOPLEFT", 8, 2)

    collapseAllButton.text = collapseAllButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    collapseAllButton.text:SetPoint("RIGHT", collapseAllButton, "RIGHT", -2, 0)
    collapseAllButton.text:SetText("All")
    collapseAllButton.text:SetTextColor(1, 0.82, 0)

    collapseAllButton.icon = collapseAllButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    collapseAllButton.icon:SetPoint("LEFT", collapseAllButton, "LEFT", 2, 0)
    collapseAllButton.icon:SetText("-")
    collapseAllButton.icon:SetTextColor(1, 1, 1)
    collapseAllButton.icon:SetFont("Fonts\\FRIZQT__.TTF", 12)

    collapseAllButton.isCollapsed = false

    collapseAllButton:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        CraftTradeSkillFrame.searchBar:ClearFocus()

        self.isCollapsed = not self.isCollapsed
        for headerText, _ in pairs(closedHeaders) do
            closedHeaders[headerText] = self.isCollapsed
        end

        if self.isCollapsed then
            self.icon:SetText("+")
        else
            self.icon:SetText("-")
        end

        main:RefreshList()
    end)

    collapseAllButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)

    collapseAllButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(1, 0.82, 0)
    end)

    CraftTradeSkillFrame.searchBar = CreateFrame("EditBox", "CraftTradeSkillFrameSearchBar", CraftTradeSkillFrame, "SearchBoxTemplate")
    CraftTradeSkillFrame.searchBar:SetSize(CraftTradeListInset:GetWidth()-17, 20)
    CraftTradeSkillFrame.searchBar:SetPoint("TOPLEFT", CraftTradeListInset, "TOPLEFT", 10, -3)
    CraftTradeSkillFrame.searchBar:SetAutoFocus(false)
    CraftTradeSkillFrame.searchBar.Instructions:SetText(SEARCH)
    
    CraftTradeSkillFrame.searchBar:SetScript("OnTextChanged", function(self)
        -- This fires immediately when it first appears for whatever reason.
        local inputText = self:GetText()
        if inputText == "" then
            main:FetchSkillData()
            main:RefreshList()
            self.clearButton:Hide()
            return
        end
        
        self.clearButton:Show()
        main:FetchSkillData()
        main:RefreshList()
    end)

    CraftTradeSkillFrame:SetScript("OnMouseDown", function(self)
        if not CraftTradeSkillFrame.searchBar:HasFocus() then return end
        CraftTradeSkillFrame.searchBar:ClearFocus()
    end)

    CraftTradeSkillFrame.searchBar:SetScript("OnEscapePressed", CraftTradeSkillFrame.searchBar.ClearFocus)
    CraftTradeSkillFrame.searchBar:SetScript("OnEnterPressed", CraftTradeSkillFrame.searchBar.ClearFocus)

    CraftTradeSkillFrame.searchBar:SetScript("OnEditFocusLost", function(self)
        local inputText = self:GetText()
        if inputText == "" or string.match(inputText, "^%s*$") then
            self.Instructions:Show()
            self:SetText("")
        end

        self:HighlightText(0, 0)

        main:RefreshList()
    end)

    CraftTradeSkillFrame.searchBar:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        self.Instructions:Hide()
    end)

    CraftTradeSkillFrame.searchBar.clearButton:HookScript("OnClick", function(self)
        CraftTradeSkillFrame.searchBar.Instructions:Show()
    end)

    CraftTradeSkillFrame:SetScript("OnMouseDown", function(self)
        CraftTradeSkillFrame.searchBar:ClearFocus()
    end)
end

function main:AddShowOnlyAvailableCheckBox()
    local checkbox = CreateFrame("CheckButton", "ShowOnlyAvailableTradeCrafts", CraftTradeSkillFrame, "UICheckButtonTemplate")
    checkbox:SetSize(20, 20)
    
    checkbox.text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkbox.text:SetPoint("TOPLEFT", checkbox, "TOPLEFT", 20, -3.5)
    checkbox.text:SetText(CRAFT_IS_MAKEABLE)
    checkbox.text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    checkbox:SetPoint("TOPRIGHT", CraftTradeSkillFrame, "TOPRIGHT", -checkbox.text:GetStringWidth() -15, -55)
    checkbox:SetChecked(false)

    checkbox:SetScript("OnClick", function(self)
        if self:GetChecked() then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end

        main:FetchSkillData()
        main:RefreshList()
    end)

    -- When hovered show the tooltip.
    checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(CRAFT_IS_MAKEABLE, 1, 1, 1)
        if C_CVar.GetCVarBool("showNewbieTips") == true then
            GameTooltip:AddLine(CRAFT_IS_MAKEABLE_TOOLTIP, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)

    checkbox:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

function main:AddShowTrainCheckBox()
    local checkbox = CreateFrame("CheckButton", "ShowTrainTradeCrafts", CraftTradeSkillFrame, "UICheckButtonTemplate")
    checkbox:SetSize(20, 20)
    
    checkbox.text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkbox.text:SetPoint("TOPLEFT", checkbox, "TOPLEFT", 20, -3.5)
    checkbox.text:SetText(main.ClientLocale.CanRankUp)
    checkbox.text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    local maxStringWidth = 110 -- To avoid pushing other buttons too far.
    checkbox.text:SetJustifyH("LEFT")
    if maxStringWidth < checkbox.text:GetStringWidth() then
        checkbox.text:SetWidth(min(checkbox.text:GetStringWidth(), maxStringWidth))
        checkbox.text:SetWordWrap(false)
    end
    checkbox:SetPoint("RIGHT", ShowOnlyAvailableTradeCrafts, "RIGHT", -min(checkbox.text:GetStringWidth(), maxStringWidth) -25, 0)
    checkbox:SetChecked(false)

    checkbox:SetScript("OnClick", function(self)
        if self:GetChecked() then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end

        main:FetchSkillData()
        main:RefreshList()
    end)

    checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(main.ClientLocale.CanRankUp, 1, 1, 1)
        if C_CVar.GetCVarBool("showNewbieTips") == true then
            GameTooltip:AddLine(main.ClientLocale.CanRankUpTooltip, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)

    checkbox:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

function main:AddShowNewPetSkillsCheckBox()
    local checkbox = CreateFrame("CheckButton", "ShowNewPetSkillsTradeCrafts", CraftTradeSkillFrame, "UICheckButtonTemplate")
    checkbox:SetSize(20, 20)
    
    checkbox.text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkbox.text:SetPoint("TOPLEFT", checkbox, "TOPLEFT", 20, -3.5)
    checkbox.text:SetText(main.ClientLocale.petCanLearn)
    checkbox.text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    checkbox.text:SetJustifyH("LEFT")
    checkbox:SetPoint("TOPRIGHT", CraftTradeSkillFrame, "TOPRIGHT", -checkbox.text:GetStringWidth() -15, -55)
    checkbox:SetChecked(false)

    checkbox:SetScript("OnClick", function(self)
        if self:GetChecked() then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        
        main:FetchSkillData()
        main:RefreshList()
    end)

    checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(main.ClientLocale.petCanLearn, 1, 1, 1)
        if C_CVar.GetCVarBool("showNewbieTips") == true then
            GameTooltip:AddLine(main.ClientLocale.petCanLearnTooltip, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)

    checkbox:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

function main:AddShowUnlearnedCheckBox()
    local checkbox = CreateFrame("CheckButton", "ShowUnlearnedTradeCrafts", CraftTradeSkillFrame, "UICheckButtonTemplate")
    checkbox:SetSize(20, 20)

    checkbox.text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkbox.text:SetPoint("TOPLEFT", checkbox, "TOPLEFT", 20, -3.5)
    checkbox.text:SetText(main.ClientLocale.ShowUnlearned)
    checkbox.text:SetFont("Fonts\\FRIZQT__.TTF", 10)
    checkbox:SetPoint("RIGHT", ShowTrainTradeCrafts, "RIGHT", -checkbox.text:GetStringWidth() -310, 0)
    checkbox:SetChecked(false)
    checkbox:Hide()

    checkbox:SetScript("OnClick", function(self)
        if self:GetChecked() then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end

        main:FetchSkillData()
        main:RefreshList()
    end)

    checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(main.ClientLocale.ShowUnlearned, 1, 1, 1)
        if C_CVar.GetCVarBool("showNewbieTips") == true then
            GameTooltip:AddLine(main.ClientLocale.ShowUnlearnedTooltip, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)

    checkbox:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

function main:StealButton(button)
    if button == nil then return end
    button:SetParent(CraftTradeSkillFrame)
    button:SetPoint("BOTTOMRIGHT", CraftTradeSkillFrame, "BOTTOMRIGHT", -10, 10)
    button:Show()
end

main.CleanFrameAttributes = function(frame)
    if frame == nil then return end
    frame:SetAttribute("UIPanelLayout-defined", true)
    frame:SetAttribute("UIPanelLayout-enabled", true)
    frame:SetAttribute("UIPanelLayout-whileDead", nil)
    frame:SetAttribute("UIPanelLayout-pushable", 8)
    frame:SetAttribute("UIPanelLayout-width", 0)
end

main.CleanOriginalFrameAttributes = function()
    CraftTradeSkillFrame:SetScale(TimbersWiderProfessions_DB.windowScale / 100)
    main.CleanFrameAttributes(CraftFrame)
    main.CleanFrameAttributes(TradeSkillFrame)

    if TimbersWiderProfessions_DB.canDragFrame then
        CraftTradeSkillFrame:SetAttribute("UIPanelLayout-area", nil)
        CraftTradeSkillFrame.TitleContainer:EnableMouse(true)
        CraftTradeSkillFrame.TitleContainer:RegisterForDrag("LeftButton")
        CraftTradeSkillFrame.TitleContainer:SetScript("OnDragStart", function()
            CraftTradeSkillFrame:StartMoving()
        end)
        CraftTradeSkillFrame.TitleContainer:SetScript("OnDragStop", function()
            CraftTradeSkillFrame:StopMovingOrSizing()
        end) 
    else
        CraftTradeSkillFrame:SetAttribute("UIPanelLayout-area", "left")
        CraftTradeSkillFrame.TitleContainer:EnableMouse(false)
        CraftTradeSkillFrame.TitleContainer:SetScript("OnDragStart", nil)
        CraftTradeSkillFrame.TitleContainer:SetScript("OnDragStop", nil)
    end
end

function main:SetWindowHeight(height)
    MAX_SKILLS_SHOWN = math.floor((height - 101) / 20)
    local insetHeight = height - 76
    CraftTradeSkillFrame:SetHeight(height)
    CraftTradeListInset:SetHeight(insetHeight)
    CraftTradeReagentsInset:SetHeight(insetHeight)
    if main.headersList then
        main:RefreshList()
    end
    CraftTradeSkillFrame:Show()
end

main.HideOriginalFrames = function()
    if CraftFrame ~= nil then
        CraftFrame:ClearAllPoints()
        CraftFrame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 0, 0)
    end

    if TradeSkillFrame ~= nil then
        TradeSkillFrame:ClearAllPoints()
        TradeSkillFrame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 0, 0)
    end
end

main.CRAFT_TRADE_UPDATE = function()
    if main.windowType == nil then return end
    main:FetchSkillData()
    main:RefreshList()

    local currentProfession, rank, maxRank;
    if main.windowType == "Craft" then
        if not CraftIsEnchanting() then
            currentProfession = "Pet"
            name = GetSpellInfo(BEAST_TRAINING_SPELL_ID) or ""
            maxRank = UnitLevel("player") *VANILLA_SKILL_RANKS_PER_LEVEL
            rank = maxRank
        else
            currentProfession, rank, maxRank = GetCraftDisplaySkillLine()
        end
    elseif main.windowType == "TradeSkill" then
        currentProfession, rank, maxRank = GetTradeSkillLine()
    end

    main.canRankUp = rank < maxRank
    -- We need this to control when to update on same window and when a new window forces an update.
    local previousRank = TradeSkillRankBar:GetValue()
    local previousProfession = CraftTradeSkillFrame.TitleText:GetText()

    TradeSkillRankBar.Text:SetText(rank.. "/".. maxRank)
    TradeSkillRankBar:SetMinMaxValues(0, maxRank)
    TradeSkillRankBar:SetValue(rank)

    -- At tmes, previousRank can be 0 before it loads properly; so we ignore that to avoid flashing unnecessarily.
    if previousRank < rank and previousRank > 0 and currentProfession == previousProfession then
        TradeSkillRankBar:Flash()
    end

    if main.selectedSkill ~= nil then -- Ugliest way to update the reagents.
        local categorySkills = main.skillInfoDict[main.selectedSkill.category]
        if categorySkills == nil then return end
        local movedSelected = categorySkills[main.selectedSkill.position]
        if movedSelected == nil then return end
        if movedSelected.name == main.selectedSkill.name then
            main.selectedSkill = movedSelected
            main:SetSkillDetails(movedSelected)
        else
            main:CleanSkillDetails()
        end
    end
end

main.CRAFT_TRADE_CLOSE = function()
    if main.windowType == nil then return end

    HideUIPanel(CraftTradeSkillFrame)
end

function main.OnEvent(self, event, ...)
    -- Call the function with the same name as the event.
    self[event](self, event, ...)
end

main.PLAYER_LOGIN = function()
    -- We need to wait for the skills to load which happens after the addons do.
    main:ReadSkillDescriptions()

    main:UnregisterEvent("PLAYER_LOGIN")
end

main:RegisterEvent("ADDON_LOADED")
main:RegisterEvent("PLAYER_LOGIN")
main:SetScript("OnEvent", main.OnEvent)

-- hooksecure to whenever any item in the inventory is shiftclicked
hooksecurefunc("HandleModifiedItemClick", function(link)
    if not link then return end
    if not CraftTradeSkillFrame:IsShown() then return end
    if not CraftTradeSkillFrame.searchBar:HasFocus() then return end
    if ChatFrame1EditBox:HasFocus() then return end
    local itemName = GetItemInfo(link)
    if itemName then
        -- Focus on the search bar and set its text to the item name
        CraftTradeSkillFrame.searchBar:SetText(itemName)
        CraftTradeSkillFrame.searchBar.Instructions:Hide()

        -- If merchant frame is open, assume the player is buying reagents and do not cancel splitting.
        if MerchantFrame and MerchantFrame:IsShown() then return end
        
        -- Cancel item splitting if it was triggered.
        C_Timer.After(0, function()
            StackSplitCancelButton:Click()  -- This will trigger the OnTextChanged event
        end)
    end
end)
