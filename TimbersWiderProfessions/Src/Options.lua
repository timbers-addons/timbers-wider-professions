local main = TimbersWiderProfessionsAddon
local Compat = main.Compat
local ALCHEMY_NAME = Compat.GetSpellName(2259) or "Alchemy" -- Alchemy spell id
local COOKING_NAME = Compat.GetSpellName(2550) or "Cooking" -- Cooking spell id
local ENCHANTING_NAME = Compat.GetSpellName(7412) or "Enchanting" -- Enchanting spell id
local PET_TRAINING_NAME = Compat.GetSpellName(5149) or "Beast Training" -- Beast Training spell id
-- The category and poison options only apply to the Classic window.
local isPreCata = Compat.IsPreCata

local defaultVariables = {
    favorites = {},
    knownTradeskills = {},
    openedAddonFirstTimeForProfession = {}, -- This is used to initialize old skills so that they dont count as new.
    petFamiliesTrained = {},
    showAlchemyCategories = true,
    showCookingCategories = true,
    showEnchantingCategories = true,
    showPetCategories = true,
    skillColorMode = "difficulty", -- "rarity" or "difficulty"
    showSkillLevelsInList = false,
    canDragFrame = false,
    showAlternateRanks = true,
    sortRoguePoisons = false,
    windowScale = 100,
    windowHeight = 426,
    listMode = "blizzard", -- Forever window: "blizzard", "level" or "alpha"
}

function main:GetDefaultVariables()
    return defaultVariables
end

function main:CreateSettingsFrame()
    local category, layout = Settings.RegisterVerticalLayoutCategory("TimbersWiderProfessions")
    main.settingsCategory = category

    local function createCheckBox(text, variableName, tooltipText)
        local variableKey = variableName
        local defaultValue = defaultVariables[variableName]

        local setting = Settings.RegisterAddOnSetting(category, variableName, variableKey, TimbersWiderProfessions_DB, type(defaultValue), text, defaultValue)

        Settings.CreateCheckbox(category, setting, tooltipText)
    end

    local function createSlider(text, variableName, tooltipText, minValue, maxValue, step)
        local defaultValue = defaultVariables[variableName]

        local function GetValue()
            return TimbersWiderProfessions_DB[variableName] or defaultValue
        end

        local function SetValue(value)
            TimbersWiderProfessions_DB[variableName] = value
            -- Open the frame to test the scale immediately.
            if main.window then
                main.window:SetScale(value / 100)
                main.window:Show()
            end
        end

        local setting = Settings.RegisterProxySetting(category, variableName, type(defaultValue), text, defaultValue, GetValue, SetValue)

        local options = Settings.CreateSliderOptions(minValue, maxValue, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right);
        Settings.CreateSlider(category, setting, options, tooltipText)
    end

    local function createDropdown(text, variableName, tooltipText, optionsTable)
        local defaultValue = defaultVariables[variableName]

        local function GetValue()
            return TimbersWiderProfessions_DB[variableName] or defaultValue
        end

        local function SetValue(value)
            TimbersWiderProfessions_DB[variableName] = value
        end

        local setting = Settings.RegisterProxySetting(category, variableName, type(defaultValue), text, defaultValue, GetValue, SetValue)

        local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            for _, option in ipairs(optionsTable) do
                container:Add(option.value, option.label)
            end
            return container:GetData()
        end

        Settings.CreateDropdown(category, setting, GetOptions, tooltipText)
    end

    if isPreCata then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(main.ClientLocale.AdditionalCategories, main.ClientLocale.AdditionalCategoriesTooltip))
        createCheckBox(ALCHEMY_NAME, "showAlchemyCategories", main.ClientLocale.AddAlchemyTooltip)
        createCheckBox(COOKING_NAME, "showCookingCategories", main.ClientLocale.AddCookingTooltip)
        createCheckBox(ENCHANTING_NAME, "showEnchantingCategories", main.ClientLocale.AddEnchantingTooltip)
        createCheckBox(PET_TRAINING_NAME, "showPetCategories", main.ClientLocale.AddPetsTooltip)
    else
        TimbersWiderProfessions_DB.showAlchemyCategories = false
        TimbersWiderProfessions_DB.showCookingCategories = false
        TimbersWiderProfessions_DB.showEnchantingCategories = false
        TimbersWiderProfessions_DB.showPetCategories = false
    end

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(BINDING_HEADER_MISC))
    if Compat.HasRecipeAPI then
        local listModeDefault = defaultVariables.listMode
        local function GetValue()
            return TimbersWiderProfessions_DB.listMode or listModeDefault
        end
        local function SetValue(value)
            main:SetListMode(value)
        end
        local setting = Settings.RegisterProxySetting(category, "listMode", type(listModeDefault), main.ClientLocale.ListMode, listModeDefault, GetValue, SetValue)
        local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            container:Add("blizzard", main.ClientLocale.ListBlizzard)
            container:Add("level", main.ClientLocale.ListByLevel)
            container:Add("alpha", main.ClientLocale.ListAlphabetical)
            return container:GetData()
        end
        Settings.CreateDropdown(category, setting, GetOptions, main.ClientLocale.ListModeTooltip)
    end
    createDropdown(main.ClientLocale.SkillColors, "skillColorMode", main.ClientLocale.SkillColorsTooltip, {
        { value = "difficulty", label = main.ClientLocale.ColorByDifficulty },
        { value = "rarity", label = main.ClientLocale.ColorByRarity },
    })
    createCheckBox(main.ClientLocale.ShowSkillLevelsInList, "showSkillLevelsInList", main.ClientLocale.ShowSkillLevelsInListTooltip)
    if isPreCata then
        createCheckBox(main.ClientLocale.ShowAlternateRanks, "showAlternateRanks", main.ClientLocale.ShowAlternateRanksTooltip)
    end
    do
        local canDragDefault = defaultVariables.canDragFrame
        local function GetValue()
            return TimbersWiderProfessions_DB.canDragFrame
        end
        local function SetValue(value)
            TimbersWiderProfessions_DB.canDragFrame = value
        end
        local canDragSetting = Settings.RegisterProxySetting(category, "canDragFrame", type(canDragDefault), main.ClientLocale.CanDragFrame, canDragDefault, GetValue, SetValue)
        local canDragInitializer = Settings.CreateCheckbox(category, canDragSetting, main.ClientLocale.CanDragFrameTooltip)

        if canDragInitializer and canDragInitializer.AddModifier then
            local reloadButton
            canDragInitializer:AddModifier(function(initializer, control, name)
                if not reloadButton then
                    reloadButton = CreateFrame("Button", nil, control, "UIPanelButtonTemplate")
                    reloadButton:SetText(main.ClientLocale.ReloadRequired)
                    reloadButton:SetSize(reloadButton:GetTextWidth() + 20, 22)
                    reloadButton:SetPoint("LEFT", control.Checkbox, "RIGHT", 8, 0)
                    reloadButton:SetScript("OnClick", ReloadUI)
                    reloadButton:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(main.ClientLocale.ReloadRequiredTooltip, 1, 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    reloadButton:SetScript("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                end
                reloadButton:SetShown(not canDragSetting:GetValue())
            end)
        end
    end
    if isPreCata then
        createCheckBox(main.ClientLocale.SortPoisons, "sortRoguePoisons", main.ClientLocale.SortPoisonsTooltip)
    end
    createSlider(main.ClientLocale.WindowScale, "windowScale", main.ClientLocale.WindowScaleTooltip, 50, 300, 5)

    do
        local heightDefault = defaultVariables.windowHeight
        local function GetValue()
            return TimbersWiderProfessions_DB.windowHeight or heightDefault
        end
        local function SetValue(value)
            TimbersWiderProfessions_DB.windowHeight = value
            if main.SetWindowHeight then main:SetWindowHeight(value) end
        end
        local setting = Settings.RegisterProxySetting(category, "windowHeight", type(heightDefault), main.ClientLocale.WindowHeight, heightDefault, GetValue, SetValue)
        local options = Settings.CreateSliderOptions(426, 800, 10)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, setting, options, main.ClientLocale.WindowHeightTooltip)
    end

    Settings.RegisterAddOnCategory(category)
end
