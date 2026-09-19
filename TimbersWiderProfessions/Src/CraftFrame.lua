local main = TimbersWiderProfessionsAddon
local playerLocale = GetLocale() or "enUS"
local haveHookedCraftCreateButton = false
local BEAST_TRAINING_SPELL_ID = 5149
local BEAST_TRAINING_ICON_ID = 132162
local BEAST_LORE_SPELL_ID = 1462
local VANILLA_SKILL_RANKS_PER_LEVEL = 5
local ROMAN_NUMERIALS = {"I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"}

function main:FindEnchantType(skillName, skillLink)
    local newSkillName = skillName
    if playerLocale == "esES" or playerLocale == "esMX" then
        -- In spanish the patter has ': '
        newSkillName = string.match(skillName, ".-: (.+)")
    elseif playerLocale == "frFR" then -- In french the name is within parentheses...
        newSkillName = string.match(skillName, ".-%((.+)%)")
    else
        newSkillName = string.match(skillName, ".- %- (.+)")
    end
    -- Capitalize first letter
    if newSkillName then
        newSkillName = newSkillName:gsub("^%l", string.upper)
    end
    if TimbersWiderProfessions_DB.showEnchantingCategories then
        local newSkillType = main.enchantingCategoryMap[skillName]
        if newSkillType then
            return newSkillName or skillName, newSkillType
        end
    else
        return newSkillName or skillName, BINDING_HEADER_MISC
    end
    
    return newSkillName, BINDING_HEADER_MISC -- "Miscellaneous"
end

function main:FetchCrafts(filterWord)
    local skillInfoDict = {}
    local headersList = {}

    local showOnlyAvailable = ShowOnlyAvailableTradeCrafts:GetChecked()
    local showOnlyTrain = ShowTrainTradeCrafts:GetChecked()
    local showOnlyNewPetSkills = ShowNewPetSkillsTradeCrafts:GetChecked()
    local showAlternateRanks = TimbersWiderProfessions_DB.showAlternateRanks
    local selectedExists = false
    
    local profession = CraftIsEnchanting() and "Enchanting" or "Pet"
    if TimbersWiderProfessions_DB.favorites[profession] == nil then
        TimbersWiderProfessions_DB.favorites[profession] = {}
    end

    local shouldInitializeOldSkills = TimbersWiderProfessions_DB.openedAddonFirstTimeForProfession[profession] == nil
    if shouldInitializeOldSkills then
        TimbersWiderProfessions_DB.openedAddonFirstTimeForProfession[profession] = 0
    end
    
    -- If we are a hunter and we have a pet, save pet level
    local petLevel = UnitLevel("pet") or 0

    for index = 1, GetNumCrafts() do
        local skillName, craftSubSpellName, rankEfficiency, numAvailable, _, trainingPointCost, requiredPetLevel = GetCraftInfo(index)
        -- For Hunters rankEfficiency = none or used.
        -- Required pet level is 0 if your pet cannot learn that skill.

        local skillDescription = GetCraftDescription(index) -- [string|nil]
        local skillLink = GetCraftItemLink(index)
        local displayName, skillType, skillId
        local canLearnState = "yes" -- "yes", "notYet", "never"
        local hasPoints = false
        local totalPoints, pointsSpent = GetPetTrainingPoints();
        local isPetActive = petLevel > 0
        local availaiblePoints = totalPoints - pointsSpent

        if CraftIsEnchanting() then
            displayName, skillType = main:FindEnchantType(skillName, skillLink)
            skillId = string.match(skillLink, "enchant:(%d+)")
        else
            if trainingPointCost == 0 or availaiblePoints >= trainingPointCost then
                hasPoints = true
            end
            displayName = skillName
            if craftSubSpellName then
                if showAlternateRanks == false then
                    displayName = displayName.. "  (".. craftSubSpellName.. ")"
                else
                    local succesfullyExtractedRankNumber = false
                    local rankNumber = string.match(craftSubSpellName, "(%d+)")
                    if rankNumber then
                        succesfullyExtractedRankNumber = true
                    end
                    
                    if not succesfullyExtractedRankNumber then
                        displayName = displayName.. "  (".. craftSubSpellName.. ")"
                    elseif rankNumber ~= "1" then -- We skip the first entry based on the Poisons convention.
                        if playerLocale == "esES" then -- In European Spanish the Poisons convention doesnt use roman numerals.
                            displayName = displayName.. " ".. rankNumber
                        else
                            displayName = displayName.. " ".. ROMAN_NUMERIALS[tonumber(rankNumber)]
                        end
                    end
                end
            end

            -- First we must move the selection to the next so that GetCraftSelectionIndex() returns the correct spell.
            CraftFrame_SetSelection(index)

            -- We use a new tooltip so that we don't interfere with the main tooltip. (This causes issues when clicking checkbox and tooltip is hidden.)
            TimbersWiderProfessionsSpellReadingTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            TimbersWiderProfessionsSpellReadingTooltip:SetOwner(self, "ANCHOR_RIGHT")
            TimbersWiderProfessionsSpellReadingTooltip:SetCraftSpell(GetCraftSelectionIndex())
            TimbersWiderProfessionsSpellReadingTooltip:Show()
            _, skillId = TimbersWiderProfessionsSpellReadingTooltip:GetSpell()
            skillId = tostring(skillId)
            skillLink = "|cff71d5ff|Hspell:".. skillId .. "|h[".. skillName .."]|h|r"
            
            -- Active skills probably have more lines (must explain cost, cooldown, etc.)
            local isPassive = TimbersWiderProfessionsSpellReadingTooltip:NumLines() <= 2
            if TimbersWiderProfessions_DB.showPetCategories then
                -- skillType = isPassive and PET_PASSIVE or ACTIVE_PETS
                if isPassive then
                    skillType = PET_PASSIVE
                else
                    skillType = main:GetPetCategory(skillName)
                end
            else
                skillType = PET
            end
        end

        local texture = GetCraftIcon(index) --GetSpellTexture(string.match(skillLink, "enchant:(%d+)"))
        local rarityColor = "|c7c7c7c7c"
        if rankEfficiency == "none" then
            -- We color it green
            rarityColor = "|cff00ff00"
            if requiredPetLevel == 0 and isPetActive then -- No pet can learn this skill
                rarityColor = "|cffff0000" -- red
                canLearnState = "never"
            elseif requiredPetLevel and petLevel < requiredPetLevel then
                -- Pet level too low
                rarityColor = "|cffffa500" -- orange
                canLearnState = "notYetLevel"
            elseif not hasPoints then -- Not enoguh points to train.
                rarityColor = "|cffffa500" -- orange
                canLearnState = "notYetPoints"
            end
        elseif rankEfficiency == "used" then
            rarityColor = "|c7c7c7c7c"
        end
        if shouldInitializeOldSkills and skillId then
            TimbersWiderProfessions_DB.knownTradeskills[skillId] = 0
        end

        if not (showOnlyAvailable and numAvailable == 0) and not (showOnlyTrain and rankEfficiency == "trivial") and not (showOnlyNewPetSkills and (rankEfficiency ~= "none" or canLearnState == "never")) then
            local reagents = {}
            for reagentIndex = 1, GetCraftNumReagents(index) do
                local reagentName, reagentTexture, reagentCount, playerReagentCount = GetCraftReagentInfo(index, reagentIndex)
                local reagentLink = GetCraftReagentItemLink(index, reagentIndex)
                
                table.insert(reagents, {name = reagentName, link = reagentLink, icon = reagentTexture, count = reagentCount, playerCount = playerReagentCount})
            end
            local hasPassedFilter = true
            if filterWord then
                hasPassedFilter = string.find(string.lower(skillName), filterWord)
                for _, reagent in ipairs(reagents) do
                    hasPassedFilter = hasPassedFilter or string.find(string.lower(reagent.name), filterWord)
                end
            end
            
            if hasPassedFilter then
                local isFavorite = TimbersWiderProfessions_DB.favorites[profession][skillId]

                -- Add to original category
                if skillInfoDict[skillType] == nil then
                    skillInfoDict[skillType] = {}
                    table.insert(headersList, skillType)
                end

                table.insert(skillInfoDict[skillType], {
                    name = skillName,
                    displayName = displayName,
                    description = skillDescription,
                    texture = texture,
                    link = skillLink,
                    rarityColor = rarityColor,
                    rankEfficiency = rankEfficiency,
                    numAvailable = numAvailable,
                    reagents = reagents,
                    category = skillType,
                    index = index, -- The index of the craft at the original window.
                    position = #skillInfoDict[skillType] +1,
                    profession = profession,
                    skillId = skillId,
                    recipeSpellId = CraftIsEnchanting() and skillId or nil,
                    rankOrOtherDetail = craftSubSpellName,
                    canLearnState = canLearnState
                })

                -- Also add to Favorites category if favorited
                if isFavorite then
                    if skillInfoDict[FAVORITES] == nil then
                        skillInfoDict[FAVORITES] = {}
                        table.insert(headersList, FAVORITES)
                    end

                    table.insert(skillInfoDict[FAVORITES], {
                        name = skillName,
                        displayName = displayName,
                        description = skillDescription,
                        texture = texture,
                        link = skillLink,
                        rarityColor = rarityColor,
                        rankEfficiency = rankEfficiency,
                        numAvailable = numAvailable,
                        reagents = reagents,
                        category = FAVORITES,
                        index = index,
                        position = #skillInfoDict[FAVORITES] +1,
                        profession = profession,
                        skillId = skillId,
                        recipeSpellId = CraftIsEnchanting() and skillId or nil,
                        rankOrOtherDetail = craftSubSpellName,
                        canLearnState = canLearnState
                    })
                end

                if main.selectedSkill ~= nil and main.selectedSkill.skillId == skillId then
                    selectedExists = true
                end
            end
        end
    end

    if TimbersWiderProfessionsSpellReadingTooltip then
        TimbersWiderProfessionsSpellReadingTooltip:Hide()
    end

    if not selectedExists then
        main:CleanSkillDetails()
    end

    -- Inject unlearned enchanting recipes from hardcoded spell list
    if CraftIsEnchanting() and ShowUnlearnedTradeCrafts:GetChecked() then
        local spellList = main:GetEnchantingList()
        if spellList then
            -- Build set of learned recipe spell IDs
            local learnedSpellIds = {}
            for _, skills in pairs(skillInfoDict) do
                for _, skill in ipairs(skills) do
                    if skill.recipeSpellId then
                        learnedSpellIds[skill.recipeSpellId] = true
                    end
                end
            end

            for category, skills in pairs(spellList) do
                for spellId, _ in pairs(skills) do
                    if not learnedSpellIds[spellId] then
                        local localizedSpellName, _, spellIcon = GetSpellInfo(tonumber(spellId))
                        if localizedSpellName then
                            local displayName, skillType = main:FindEnchantType(localizedSpellName, nil)

                            if TimbersWiderProfessions_DB.showEnchantingCategories and main.enchantingCategoryMap and main.enchantingCategoryMap[localizedSpellName] then
                                skillType = main.enchantingCategoryMap[localizedSpellName]
                            elseif not skillType or skillType == BINDING_HEADER_MISC then
                                skillType = BINDING_HEADER_MISC
                            end

                            local hasPassedFilter = true
                            if filterWord then
                                hasPassedFilter = string.find(string.lower(localizedSpellName), filterWord)
                            end

                            if hasPassedFilter then
                                if skillInfoDict[skillType] == nil then
                                    skillInfoDict[skillType] = {}
                                    table.insert(headersList, skillType)
                                end

                                table.insert(skillInfoDict[skillType], {
                                    name = localizedSpellName,
                                    displayName = displayName or localizedSpellName,
                                    description = nil,
                                    texture = spellIcon,
                                    link = nil,
                                    rarityColor = "|c7c7c7c7c",
                                    rankEfficiency = "trivial",
                                    numAvailable = 0,
                                    reagents = {},
                                    category = skillType,
                                    index = -1,
                                    position = #skillInfoDict[skillType] + 1,
                                    profession = "Enchanting",
                                    skillId = "unlearned_".. spellId,
                                    recipeSpellId = spellId,
                                    isUnlearned = true,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    return skillInfoDict, headersList
end

main.CRAFT_SHOW = function(self, event, ...)
    if TradeSkillFrame and TradeSkillFrame:IsVisible() then main.ForceTRADE_SKILL_CLOSE() end

    main:CleanSkillDetails()
    main:CleanStolenButtons()
    main:CleanOriginalFrameAttributes()
    main:HideOriginalCraftFrame("CraftFrame")

    ShowUIPanel(CraftTradeSkillFrame)
    main:HideOriginalFrames()

    local name, portraitIcon, rank, maxRank
    if not CraftIsEnchanting() then
        main.hasBeastLore = IsSpellKnown(BEAST_LORE_SPELL_ID)
        name = GetSpellInfo(BEAST_TRAINING_SPELL_ID) or ""
        portraitIcon = BEAST_TRAINING_ICON_ID
        ShowTrainTradeCrafts:Hide()
        ShowOnlyAvailableTradeCrafts:Hide()
        ShowUnlearnedTradeCrafts:Hide()
        local hasPet = UnitExists("pet")
        if hasPet then
            ShowNewPetSkillsTradeCrafts:Show()
            local _, petFamilyId = UnitCreatureFamily("pet")
            if petFamilyId then
                TimbersWiderProfessions_DB.petFamiliesTrained[petFamilyId] = true
            end
        else
            ShowNewPetSkillsTradeCrafts:Hide()
        end
        maxRank = UnitLevel("player") *VANILLA_SKILL_RANKS_PER_LEVEL
        rank = maxRank

        if not TimbersWiderProfessionsSpellReadingTooltip then
            CreateFrame("GameTooltip", "TimbersWiderProfessionsSpellReadingTooltip", nil, "GameTooltipTemplate")
        end
        if main.hasBeastLore then
            CraftTradeDetailReagents:SetText(PET_FAMILIES.. ":")
        end
    else
        name, rank, maxRank = GetCraftDisplaySkillLine()
        main.canRankUp = rank < maxRank
        portraitIcon = "Interface\\Icons\\Trade_Engraving"
        ShowTrainTradeCrafts:Show()
        ShowNewPetSkillsTradeCrafts:Hide()
        ShowOnlyAvailableTradeCrafts:Show()
        ShowUnlearnedTradeCrafts:Show()
        CraftTradeDetailReagents:SetText(MINIMAP_TRACKING_VENDOR_REAGENT.. ":")
    end

    main.canRankUp = rank < maxRank
    main.windowType = "Craft"
    
    main:StealButton(CraftCreateButton)
    if not haveHookedCraftCreateButton then
        haveHookedCraftCreateButton = true
        CraftCreateButton:HookScript("OnClick", function()
            C_Timer.After(0.4, function() -- Wait a frame to ensure the craft is done.
                local totalPoints, pointsSpent = GetPetTrainingPoints();
                local availaiblePoints = totalPoints - pointsSpent
                CraftTradePetPointsLabel:SetText("Training Points: |cffffffff".. availaiblePoints)
            end)
        end)
    end
    
    TradeSkillRankBar.Text:SetText(rank.. "/".. maxRank)
    TradeSkillRankBar:SetMinMaxValues(0, maxRank)
    TradeSkillRankBar:SetValue(rank)
    
    if UnitExists("pet") then -- If a pet is summoned, we show its portrait.
        SetPortraitTexture(CraftTradeSkillFramePortrait, "pet")
        CraftTradeSkillFrame.TitleText:SetText(name.. " - ".. UnitName("pet"))
    else
        CraftTradeSkillFrame:SetPortraitTextureRaw(portraitIcon)
        CraftTradeSkillFrame.TitleText:SetText(name)
    end
    
    if CraftIsEnchanting() then -- Otherwise it runs twice and may cause an error with selecting the wrong skill.
        main:CRAFT_TRADE_UPDATE()
    end

    main:RegisterEvent("CRAFT_UPDATE")
end

main.CRAFT_UPDATE = main.CRAFT_TRADE_UPDATE
main.CRAFT_CLOSE = function() main.CRAFT_TRADE_CLOSE() main:UnregisterEvent("CRAFT_UPDATE") end
main.ForceCRAFT_CLOSE = function()
    -- This is to avoid running main.CRAFT_TRADE_CLOSE() and simply close the window.
    main:UnregisterEvent("CRAFT_CLOSE")
    main:UnregisterEvent("CRAFT_UPDATE")
    
    HideUIPanel(CraftFrame)
    C_Timer.After(0.1, function() -- Wait a frame to ensure the event unregistration is processed.
        main:RegisterEvent("CRAFT_CLOSE")
    end)
end

main:RegisterEvent("CRAFT_SHOW")
main:RegisterEvent("CRAFT_CLOSE")