local main = TimbersWiderProfessionsAddon

function main:GetPetCategory(spellName)
    -- Guard: createPetSkillsCategoryMap is only initialized for Hunters
    if type(main.createPetSkillsCategoryMap) ~= "table" then
        return PET_AGGRESSIVE -- Default category
    end

    if main.createPetSkillsCategoryMap[spellName] == nil then
        return PET_AGGRESSIVE -- Default category
    end

    local category = main.createPetSkillsCategoryMap[spellName]["Category"]
    
    if category == "Utility" then
        category = main.ClientLocale["Utility"]
    end

    return category
end

function main:createAlchemyCategoryMap()
    local categoryMap = {}

    for category, skills in pairs(main:GetAlchemyList()) do
        for skillId, _ in pairs(skills) do
            if category ~= "Misc" then
                local localizedSpellName = GetSpellInfo(tonumber(skillId))
                if localizedSpellName then
                    categoryMap[localizedSpellName] = main.ClientLocale[category]
                end
            end
        end
    end

    main.alchemyCategoryMap = categoryMap
end

function main:createCookingCategoryMap()
    local categoryMap = {}

    for category, skills in pairs(main:GetCookingList()) do
        for skillId, _ in pairs(skills) do
            if category ~= "Misc" then
                local localizedSpellName = GetSpellInfo(tonumber(skillId))
                if localizedSpellName then
                    categoryMap[localizedSpellName] = main.ClientLocale[category]
                end
            end
        end
    end

    main.cookingCategoryMap = categoryMap

    cookingSpellList = nil
end

function main:createEnchantingCategoryMap()
    local categoryMap = {}

    for category, skills in pairs(main:GetEnchantingList()) do
        for skillId, _ in pairs(skills) do
            local localizedSpellName = GetSpellInfo(tonumber(skillId))
            if localizedSpellName then
                if category == "Misc" then
                    categoryMap[localizedSpellName] = BINDING_HEADER_MISC -- "Miscellaneous"
                else
                    categoryMap[localizedSpellName] = main.ClientLocale[category]
                end
            end
        end
    end

    main.enchantingCategoryMap = categoryMap

    enchantSpellList = nil
end
