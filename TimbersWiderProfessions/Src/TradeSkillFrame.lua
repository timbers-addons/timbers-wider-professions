local main = TimbersWiderProfessionsAddon
local ALCHEMY_NAME = GetSpellInfo(2259) -- Alchemy spell id
local COOKING_NAME = GetSpellInfo(2550) -- Cooking spell id
local FIRSTAID_ICON = 135966 -- First Aid icon id
local buildVersion = select(4, GetBuildInfo())

function main:FetchTradeSkills(filterWord)
    local skillInfoDict = {}
    local headersList = {}

    local showOnlyAvailable = ShowOnlyAvailableTradeCrafts:GetChecked()
    local showOnlyTrain = ShowTrainTradeCrafts:GetChecked()
    local selectedExists = false

    local profession = select(1, GetTradeSkillLine())
    local recentHeader = nil
    local shouldInitializeOldSkills = TimbersWiderProfessions_DB.openedAddonFirstTimeForProfession[profession] == nil
    if shouldInitializeOldSkills then
        TimbersWiderProfessions_DB.openedAddonFirstTimeForProfession[profession] = 0
    end

    for index = 1, GetNumTradeSkills() do
        local skillName, rankEfficiencyOrHeader, numAvailable, isExpanded = GetTradeSkillInfo(index)
        local displayName = skillName
        local skillDescription = GetTradeSkillDescription(index) -- [string|nil]
        local texture = GetTradeSkillIcon(index)
        
        if rankEfficiencyOrHeader == "header" or rankEfficiencyOrHeader == nil then
            recentHeader = skillName
            -- Also expand the header if it is not expanded.
            if not isExpanded then
                ExpandTradeSkillSubClass(index)
            end
        end
        local skillType = recentHeader
        if skillType == nil then return skillInfoDict, headersList end
    
        if rankEfficiencyOrHeader ~= "header" and not (showOnlyAvailable and numAvailable == 0) and not (showOnlyTrain and rankEfficiencyOrHeader == "trivial") then
            local skillLink = GetTradeSkillItemLink(index)
            local skillId = nil
            local recipeSpellId = nil
            if buildVersion >= 40000 then
                skillLink = skillLink or GetTradeSkillRecipeLink(index)
                skillId = string.match(skillLink, "item:(%d+)") or string.match(skillLink, "enchant:(%d+)")
                displayName, _ = main:FindEnchantType(skillName, skillLink)
            else
                skillId = string.match(skillLink, "item:(%d+)") -- I call it skillID, but I guess its just createdItemID.
            end
            -- Extract recipe spell ID for skill level lookup
            local recipeLink = GetTradeSkillRecipeLink(index)
            if recipeLink then
                recipeSpellId = string.match(recipeLink, "enchant:(%d+)")
            end
            if shouldInitializeOldSkills and skillId then
                TimbersWiderProfessions_DB.knownTradeskills[skillId] = 0
            end

            if profession == ALCHEMY_NAME and TimbersWiderProfessions_DB.showAlchemyCategories then--and skillType == "Consumable" then
                skillType = main.alchemyCategoryMap[skillName] or skillType
            elseif profession == COOKING_NAME and TimbersWiderProfessions_DB.showCookingCategories then
                skillType = main.cookingCategoryMap[skillName] or skillType
            end
            
            local rarityColor = "|c".. (string.match(skillLink, "|c(%x+)|H") or "7c7c7c7c")
            if rarityColor == "|cffffffff" then
                rarityColor = "|c7c7c7c7c"
            end

            local reagents = {}
            for reagentIndex = 1, GetTradeSkillNumReagents(index) do
                local reagentName, reagentTexture, reagentCount, playerReagentCount = GetTradeSkillReagentInfo(index, reagentIndex)
                local reagentLink = GetTradeSkillReagentItemLink(index, reagentIndex)

                table.insert(reagents, {name = reagentName, link = reagentLink, icon = reagentTexture, count = reagentCount, playerCount = playerReagentCount})
            end

            local hasPassedFilter = true
            if filterWord then
                hasPassedFilter = string.find(string.lower(skillName), filterWord)
                for _, reagent in ipairs(reagents) do
                    if reagent.name == nil then
                        hasPassedFilter = false
                    else
                        hasPassedFilter = hasPassedFilter or string.find(string.lower(reagent.name), filterWord)
                    end
                end
            end

            if hasPassedFilter then

                if TimbersWiderProfessions_DB.favorites[profession] == nil then
                    TimbersWiderProfessions_DB.favorites[profession] = {}
                end

                local isFavorite = TimbersWiderProfessions_DB.favorites[profession][skillId]
                local minProduced, maxProduced = GetTradeSkillNumMade(index)

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
                    rankEfficiency = rankEfficiencyOrHeader,
                    numAvailable = numAvailable,
                    reagents = reagents,
                    category = skillType,
                    index = index, -- The index of the craft at the original window.
                    position = #skillInfoDict[skillType] +1,
                    profession = profession,
                    skillId = skillId,
                    recipeSpellId = recipeSpellId,
                    minProduced = minProduced,
                    maxProduced = maxProduced,
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
                        rankEfficiency = rankEfficiencyOrHeader,
                        numAvailable = numAvailable,
                        reagents = reagents,
                        category = FAVORITES,
                        index = index,
                        position = #skillInfoDict[FAVORITES] +1,
                        profession = profession,
                        skillId = skillId,
                        recipeSpellId = recipeSpellId,
                        minProduced = minProduced,
                        maxProduced = maxProduced,
                    })
                end

                -- If there are multiple ways to create an items, then this breaks...
                if main.selectedSkill and main.selectedSkill.skillId == skillId then
                    selectedExists = true
                end
            end
        end
    end

    if not selectedExists then
        main:CleanSkillDetails()
    end

    -- Inject unlearned recipes from hardcoded spell lists
    if ShowUnlearnedTradeCrafts:GetChecked() then
        local spellList = nil
        local categoryMap = nil
        if profession == ALCHEMY_NAME then
            spellList = main:GetAlchemyList()
            categoryMap = main.alchemyCategoryMap
        elseif profession == COOKING_NAME then
            spellList = main:GetCookingList()
            categoryMap = main.cookingCategoryMap
        end

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
                            local skillType = recentHeader or ""
                            if categoryMap and categoryMap[localizedSpellName] then
                                skillType = categoryMap[localizedSpellName]
                            elseif category == "Misc" then
                                skillType = BINDING_HEADER_MISC
                            elseif main.ClientLocale[category] then
                                skillType = main.ClientLocale[category]
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
                                    displayName = localizedSpellName,
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
                                    profession = profession,
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

main.TRADE_SKILL_SHOW = function(self, event, ...)
    if CraftFrame and CraftFrame:IsVisible() then main.ForceCRAFT_CLOSE() end
    ShowTrainTradeCrafts:Show()
    ShowNewPetSkillsTradeCrafts:Hide()
    ShowOnlyAvailableTradeCrafts:Show()
    local tradeSkillName = select(1, GetTradeSkillLine())
    if tradeSkillName == ALCHEMY_NAME or tradeSkillName == COOKING_NAME then
        ShowUnlearnedTradeCrafts:Show()
    else
        ShowUnlearnedTradeCrafts:Hide()
    end
    
    main:CleanSkillDetails()
    main:CleanStolenButtons()
    main:CleanOriginalFrameAttributes()

    main:HideOriginalCraftFrame("TradeSkillFrame")
    
    ShowUIPanel(CraftTradeSkillFrame)
    main:HideOriginalFrames()
    
    local name, rank, maxRank = GetTradeSkillLine()
    main.canRankUp = rank < maxRank
    main.windowType = "TradeSkill"

    main:StealButton(TradeSkillCreateButton)

    TradeSkillIncrementButton:SetParent(CraftTradeSkillFrame)
    TradeSkillIncrementButton:SetPoint("BOTTOMRIGHT", TradeSkillCreateButton, "BOTTOMRIGHT", -10, 0)

    TradeSkillInputBox:ClearAllPoints()
    TradeSkillInputBox:SetParent(CraftTradeSkillFrame)
    TradeSkillInputBox:SetPoint("RIGHT", TradeSkillCreateButton, "LEFT", -28, 0)
    TradeSkillDecrementButton:ClearAllPoints()
    TradeSkillDecrementButton:SetParent(CraftTradeSkillFrame)
    TradeSkillDecrementButton:SetPoint("RIGHT", TradeSkillCreateButton, "LEFT", -65, 0)

    TradeSkillCreateAllButton:SetParent(CraftTradeSkillFrame)
    TradeSkillCreateAllButton:SetPoint("RIGHT", TradeSkillCreateButton, "LEFT", -90, 0)
    CraftTradeDetailReagents:SetText(MINIMAP_TRACKING_VENDOR_REAGENT.. ":")

    TradeSkillRankBar.Text:SetText(rank.. "/".. maxRank)
    TradeSkillRankBar:SetMinMaxValues(0, maxRank)
    TradeSkillRankBar:SetValue(rank)
    
    if TradeSkillInvSlotDropdown then
        TradeSkillInvSlotDropdown:SetParent(CraftTradeSkillFrame)
        TradeSkillInvSlotDropdown:ClearAllPoints()
        TradeSkillInvSlotDropdown:SetPoint("RIGHT", ShowTrainTradeCrafts, "LEFT", -5, 0)
        TradeSkillInvSlotDropdown:Show()
    end
    if TradeSkillSubClassDropdown then
        TradeSkillSubClassDropdown:SetParent(CraftTradeSkillFrame)
        TradeSkillSubClassDropdown:ClearAllPoints()
        TradeSkillSubClassDropdown:SetPoint("RIGHT", TradeSkillInvSlotDropdown, "LEFT", -5, 0)
        TradeSkillSubClassDropdown:Show()
    end
    
    CraftTradeSkillFrame.TitleText:SetText(name)
    local texture = select(3, GetSpellInfo(name))
    -- In French version First Aid is called "Secourisme" but the spell name is still "Premiers soins"...
    if name == "Secourisme" then
        texture = FIRSTAID_ICON
    end

    if texture ~= nil then
        CraftTradeSkillFrame:SetPortraitTextureRaw(texture)
    else
        CraftTradeSkillFrame:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09")
    end

    main:CRAFT_TRADE_UPDATE()

    main:RegisterEvent("TRADE_SKILL_UPDATE")
end

-- main.TRADE_SKILL_UPDATE = function() print("update") main.CRAFT_TRADE_UPDATE() end
main.TRADE_SKILL_UPDATE = main.CRAFT_TRADE_UPDATE
main.TRADE_SKILL_CLOSE = function() main.CRAFT_TRADE_CLOSE() main:UnregisterEvent("TRADE_SKILL_UPDATE") end
main.ForceTRADE_SKILL_CLOSE = function()
    -- This is to avoid running main.CRAFT_TRADE_CLOSE() and simply close the window.
    main:UnregisterEvent("TRADE_SKILL_CLOSE")
    main:UnregisterEvent("TRADE_SKILL_UPDATE")
    
    HideUIPanel(TradeSkillFrame)
    C_Timer.After(0.1, function() -- Wait a frame to ensure the event unregistration is processed.
        main:RegisterEvent("TRADE_SKILL_CLOSE")
    end)
end

main:RegisterEvent("TRADE_SKILL_SHOW")
main:RegisterEvent("TRADE_SKILL_CLOSE")