local main = TimbersWiderProfessionsAddon
local Compat = main.Compat
local T = C_TradeSkillUI

-- Recipe data for the Forever window. Reads C_TradeSkillUI into plain records
-- once per profession open, then builds the header list for whichever list
-- mode is active. Nothing here touches frames.

local Recipes = {}
main.Recipes = Recipes

Recipes.MODE_BLIZZARD = "blizzard" -- Blizzard's category tree
Recipes.MODE_LEVEL = "level" -- one list, hardest skill-up first
Recipes.MODE_ALPHA = "alpha" -- one list, alphabetical

-- Enum.TradeskillRelativeDifficulty: 0 Optimal, 1 Medium, 2 Easy, 3 Trivial.
local DIFFICULTY = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

-- Reagent lists and output counts never change for a recipe, so schematics are
-- read once per recipe id and kept for the session.
local schematics = {}
local categories = {}

Recipes.all = {}
Recipes.byID = {}
Recipes.profession = nil

function Recipes.IsReady()
    return T.IsTradeSkillReady()
end

-- Linked, guild and NPC professions are left to Blizzard's window.
function Recipes.IsForeign()
    return T.IsTradeSkillLinked() or T.IsTradeSkillGuild() or T.IsNPCCrafting()
end

function Recipes.GetProfession()
    local info = T.GetBaseProfessionInfo()
    if not info or not info.professionID or info.professionID == 0 then return nil end
    return {
        id = info.professionID,
        parentID = info.parentProfessionID, -- Fishing's window is "Bait and Tackle", a child of the Fishing skill line
        name = info.professionName,
        rank = info.skillLevel or 0,
        maxRank = info.maxSkillLevel or 0,
        icon = T.GetTradeSkillTexture and T.GetTradeSkillTexture(info.professionID) or nil,
    }
end

local function getCategory(categoryID)
    local category = categories[categoryID]
    if category == nil and categoryID then
        local info = T.GetCategoryInfo(categoryID)
        if info then
            local parent = info.parentCategoryID and T.GetCategoryInfo(info.parentCategoryID) or nil
            category = {
                id = categoryID,
                name = info.name,
                -- Blizzard's list orders parents first, then children, by uiOrder.
                order = (parent and parent.uiOrder or 0) * 1000 + (info.uiOrder or 0),
            }
        else
            category = false
        end
        categories[categoryID] = category
    end
    return category or nil
end

local function getSchematic(recipeID)
    local schematic = schematics[recipeID]
    if schematic == nil then
        local s = T.GetRecipeSchematic(recipeID, false)
        if s then
            local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 0
            schematic = {
                quantityMin = s.quantityMin or 1,
                quantityMax = s.quantityMax or 1,
                outputItemID = s.outputItemID,
                isEnchant = s.recipeType == (Enum and Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Enchant or 3),
                reagents = {},
            }
            for _, slot in ipairs(s.reagentSlotSchematics or {}) do
                local reagent = slot.reagents and slot.reagents[1]
                local isBasic = slot.reagentType == nil or slot.reagentType == basic
                if reagent and reagent.itemID and isBasic and slot.required ~= false then
                    schematic.reagents[#schematic.reagents + 1] = { itemID = reagent.itemID, count = slot.quantityRequired or 1 }
                end
            end
        else
            schematic = false
        end
        schematics[recipeID] = schematic
    end
    return schematic or nil
end

-- Fills in the per-recipe details the list does not need: reagents with the
-- player's counts, description, output count. Cheap to call repeatedly.
function Recipes.LoadDetails(recipe)
    local schematic = getSchematic(recipe.id)
    recipe.reagents = {}
    if schematic then
        recipe.quantityMin, recipe.quantityMax = schematic.quantityMin, schematic.quantityMax
        recipe.outputItemID = schematic.outputItemID
        recipe.isEnchant = schematic.isEnchant
        for i, reagent in ipairs(schematic.reagents) do
            local name, link, _, _, _, _, _, _, _, icon = Compat.GetItemInfo(reagent.itemID)
            recipe.reagents[i] = {
                itemID = reagent.itemID,
                name = name,
                link = link,
                icon = icon,
                count = reagent.count,
                playerCount = Compat.GetItemCount(reagent.itemID, true),
            }
        end
    end
    recipe.description = T.GetRecipeDescription(recipe.id, {})
    recipe.detailsLoaded = true
    return recipe
end

local function rarityColorFromLink(link)
    local color = link and link:match("|c(%x%x%x%x%x%x%x%x)|H")
    if color and color ~= "ffffffff" then return "|c" .. color end
    return nil
end

-- Reads every recipe of the open profession. Learned recipes get their
-- reagents loaded so search can match on reagent names; unlearned ones stay
-- name-only until selected.
function Recipes.Load()
    Recipes.all, Recipes.byID = {}, {}
    Recipes.profession = Recipes.GetProfession()
    local levels = main.SkillLevels or {}

    for _, recipeID in ipairs(T.GetAllRecipeIDs()) do
        local info = T.GetRecipeInfo(recipeID)
        if info and info.name then
            local category = getCategory(info.categoryID)
            local recipe = {
                id = recipeID,
                name = info.name,
                icon = info.icon,
                link = info.hyperlink,
                recipeLink = T.GetRecipeLink(recipeID),
                rarityColor = rarityColorFromLink(info.hyperlink),
                learned = info.learned == true,
                favorite = info.favorite == true,
                difficulty = DIFFICULTY[info.relativeDifficulty] or "trivial",
                numSkillUps = info.numSkillUps or 0,
                categoryID = info.categoryID,
                categoryName = category and category.name or "",
                categoryOrder = category and category.order or 0,
                levels = levels[recipeID], -- {orange, yellow, green, gray} or nil
                grayLevel = info.maxTrivialLevel,
                isEnchant = info.isEnchantingRecipe == true,
                numAvailable = info.learned and T.GetCraftableCount(recipeID) or 0,
            }
            if recipe.learned then Recipes.LoadDetails(recipe) end
            Recipes.all[#Recipes.all + 1] = recipe
            Recipes.byID[recipeID] = recipe
        end
    end
    return Recipes.all
end

-- Refreshes what changes between crafts without re-reading everything.
function Recipes.RefreshCounts()
    for _, recipe in ipairs(Recipes.all) do
        if recipe.learned then
            recipe.numAvailable = T.GetCraftableCount(recipe.id)
            local info = T.GetRecipeInfo(recipe.id)
            if info then
                recipe.difficulty = DIFFICULTY[info.relativeDifficulty] or recipe.difficulty
                recipe.favorite = info.favorite == true
            end
            if recipe.detailsLoaded then
                for _, reagent in ipairs(recipe.reagents) do
                    reagent.playerCount = Compat.GetItemCount(reagent.itemID, true)
                end
            end
        end
    end
end

function Recipes.SetFavorite(recipe, isFavorite)
    T.SetRecipeFavorite(recipe.id, isFavorite)
    recipe.favorite = isFavorite
end

-- Sort keys ---------------------------------------------------------------

-- Orange threshold when the skill list knows the recipe; otherwise the gray
-- level from the client, which is the only threshold it reports. Forever-only
-- recipes therefore land near, not exactly at, their true place.
local function levelKey(recipe)
    if recipe.levels then return recipe.levels[1] end
    return recipe.grayLevel or 0
end

local function byName(a, b)
    return a.name < b.name
end

local function byLevel(a, b)
    local ka, kb = levelKey(a), levelKey(b)
    if ka ~= kb then return ka > kb end
    return a.name < b.name
end

local function byCategory(a, b)
    if a.categoryOrder ~= b.categoryOrder then return a.categoryOrder < b.categoryOrder end
    if a.categoryName ~= b.categoryName then return a.categoryName < b.categoryName end
    return a.name < b.name
end

local SORTERS = {
    [Recipes.MODE_BLIZZARD] = byCategory,
    [Recipes.MODE_LEVEL] = byLevel,
    [Recipes.MODE_ALPHA] = byName,
}

-- Filters -----------------------------------------------------------------

local function matchesSearch(recipe, text)
    if recipe.name:lower():find(text, 1, true) then return true end
    for _, reagent in ipairs(recipe.reagents or {}) do
        if reagent.name and reagent.name:lower():find(text, 1, true) then return true end
    end
    return false
end

-- filters: { search = string|nil, showUnlearned, onlySkillUp, onlyMakeable }
local function passes(recipe, filters)
    if not recipe.learned and not filters.showUnlearned then return false end
    if filters.onlySkillUp and (not recipe.learned or recipe.difficulty == "trivial") then return false end
    if filters.onlyMakeable and recipe.numAvailable == 0 then return false end
    if filters.search and not matchesSearch(recipe, filters.search) then return false end
    return true
end

-- Builds { {name, key, recipes = {...}}, ... } for the mode. Favorites come
-- first in every mode, in that mode's order.
function Recipes.Build(mode, filters)
    filters = filters or {}
    if filters.search == "" then filters.search = nil end
    if filters.search then filters.search = filters.search:lower() end
    local sorter = SORTERS[mode] or byCategory

    local kept = {}
    for _, recipe in ipairs(Recipes.all) do
        if passes(recipe, filters) then kept[#kept + 1] = recipe end
    end
    table.sort(kept, sorter)

    local headers = {}
    local favorites = { name = FAVORITES, key = "favorites", recipes = {} }
    for _, recipe in ipairs(kept) do
        if recipe.favorite then favorites.recipes[#favorites.recipes + 1] = recipe end
    end
    if #favorites.recipes > 0 then headers[#headers + 1] = favorites end

    if mode == Recipes.MODE_BLIZZARD then
        local byKey = {}
        for _, recipe in ipairs(kept) do
            local header = byKey[recipe.categoryID]
            if not header then
                header = { name = recipe.categoryName, key = recipe.categoryID, recipes = {} }
                byKey[recipe.categoryID] = header
                headers[#headers + 1] = header
            end
            header.recipes[#header.recipes + 1] = recipe
        end
    else
        local name = Recipes.profession and Recipes.profession.name or TRADE_SKILLS
        headers[#headers + 1] = { name = name, key = "all", recipes = kept }
    end
    return headers
end

-- /twp dump: prints what the data layer sees, for checking against the probe.
SLASH_TIMBERSWIDERPROFESSIONS1 = "/twp"
SlashCmdList["TIMBERSWIDERPROFESSIONS"] = function(msg)
    if msg:match("^%s*dump") then
        if not Recipes.IsReady() then
            print("TWP: no profession open.")
            return
        end
        Recipes.Load()
        local learned, craftable, favorites, withLevels = 0, 0, 0, 0
        for _, r in ipairs(Recipes.all) do
            if r.learned then learned = learned + 1 end
            if r.numAvailable > 0 then craftable = craftable + 1 end
            if r.favorite then favorites = favorites + 1 end
            if r.levels then withLevels = withLevels + 1 end
        end
        local p = Recipes.profession
        print(("TWP: %s %d/%d: %d recipes, %d learned, %d craftable, %d favorites, %d with thresholds."):format(
            p and p.name or "?", p and p.rank or 0, p and p.maxRank or 0, #Recipes.all, learned, craftable, favorites, withLevels))
        for _, mode in ipairs({ Recipes.MODE_BLIZZARD, Recipes.MODE_LEVEL, Recipes.MODE_ALPHA }) do
            local parts = {}
            for _, header in ipairs(Recipes.Build(mode, { showUnlearned = false })) do
                parts[#parts + 1] = ("%s(%d)"):format(header.name, #header.recipes)
            end
            print(("TWP %s: %s"):format(mode, table.concat(parts, ", ")))
        end
        local first = Recipes.Build(Recipes.MODE_LEVEL, {})[1]
        for i = 1, math.min(5, first and #first.recipes or 0) do
            local r = first.recipes[i]
            local reagents = {}
            for _, reagent in ipairs(r.reagents) do reagents[#reagents + 1] = ("%s %d/%d"):format(tostring(reagent.name), reagent.playerCount or 0, reagent.count) end
            print(("  %s [%s] %s lvl=%s cat=%s: %s"):format(r.name, r.difficulty, r.numAvailable > 0 and ("x" .. r.numAvailable) or "",
                r.levels and table.concat(r.levels, "/") or ("gray " .. tostring(r.grayLevel)), r.categoryName, table.concat(reagents, ", ")))
        end
    else
        print("TWP: /twp dump")
    end
end
