local main = TimbersWiderProfessionsAddon

-- Client API compatibility layer.
--
-- Classic Era, TBC Anniversary and Mists run the pre-Midnight API. WoW: Forever
-- runs the Midnight (retail) engine, which removed or moved a number of
-- globals. This is the only file that touches a client-specific global; the
-- files shared between clients call the Compat wrappers below. The Classic-only
-- files (main.lua, CraftFrame.lua, TradeSkillFrame.lua, CategoryList.lua) are
-- never loaded on Forever and keep their direct calls.

local Compat = {}
main.Compat = Compat

local interface = select(4, GetBuildInfo())
Compat.interface = interface

-- Recipe data through C_TradeSkillUI (Forever / retail engine).
Compat.HasRecipeAPI = C_TradeSkillUI ~= nil
    and type(C_TradeSkillUI.GetAllRecipeIDs) == "function"
    and type(C_TradeSkillUI.GetRecipeInfo) == "function"

-- The old index-based trade skill window (every Classic flavor).
Compat.HasClassicTradeSkill = type(GetNumTradeSkills) == "function"

-- The Craft window (Enchanting and Beast Training before Cataclysm).
Compat.HasCraftAPI = type(GetNumCrafts) == "function"

-- Forever's interface number (16001) sorts below Cataclysm's, so a bare
-- numeric check would treat it as Vanilla.
Compat.IsPreCata = interface < 40000 and not Compat.HasRecipeAPI

-- name, iconFileDataID
function Compat.GetSpellInfo(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name, info.iconID end
        return nil
    end
    local name, _, icon = GetSpellInfo(spellID)
    return name, icon
end

function Compat.GetSpellName(spellID)
    return (Compat.GetSpellInfo(spellID))
end

-- Same positional returns on every client.
function Compat.GetItemInfo(item)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(item)
    end
    return GetItemInfo(item)
end

function Compat.GetItemCount(item, includeBank)
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(item, includeBank)
    end
    return GetItemCount(item, includeBank)
end

-- Puts a link into the active chat edit box. Returns true when something took it.
function Compat.InsertLink(link)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        return ChatFrameUtil.InsertLink(link)
    end
    return ChatEdit_InsertLink(link)
end

function Compat.LoadAddOn(name)
    if C_AddOns and C_AddOns.LoadAddOn then
        return C_AddOns.LoadAddOn(name)
    end
    return UIParentLoadAddOn(name)
end

-- PortraitFrameTemplate keeps its title text in different places per client.
function Compat.SetWindowTitle(frame, text)
    if frame.SetTitle then
        frame:SetTitle(text)
    elseif frame.TitleText then
        frame.TitleText:SetText(text)
    end
end

function Compat.GetWindowTitle(frame)
    if frame.GetTitleText then
        local title = frame:GetTitleText()
        if type(title) == "table" then return title:GetText() end
        return title
    elseif frame.TitleText then
        return frame.TitleText:GetText()
    end
end

-- The player's professions, for the window's side tabs: { name, icon,
-- skillLine, spellID } per profession that has a crafting window. The opening
-- spell is the first entry of the profession's spellbook range, which is how
-- Blizzard's own tabs find it.
function Compat.GetProfessionTabs()
    local tabs = {}
    if not GetProfessions or not GetProfessionInfo then return tabs end
    local count = select("#", GetProfessions())
    for i = 1, count do
        local index = select(i, GetProfessions())
        if index then
            local name, icon, _, _, _, spellOffset, skillLine = GetProfessionInfo(index)
            local spellID
            if spellOffset then
                if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
                    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
                    local item = C_SpellBook.GetSpellBookItemInfo(spellOffset + 1, bank)
                    spellID = item and item.spellID
                elseif GetSpellBookItemInfo then
                    local kind, id = GetSpellBookItemInfo(spellOffset + 1, "spell")
                    if kind == "SPELL" then spellID = id end
                end
            end
            local hasWindow = spellID ~= nil
            if hasWindow and C_TradeSkillUI and C_TradeSkillUI.CanTradeSkillShowCraftingUI then
                hasWindow = C_TradeSkillUI.CanTradeSkillShowCraftingUI(spellID)
            end
            if name and hasWindow then
                tabs[#tabs + 1] = { name = name, icon = icon, skillLine = skillLine, spellID = spellID, spellName = Compat.GetSpellName(spellID) }
            end
        end
    end
    return tabs
end

-- The Midnight engine hands tainted callers "secret" values for restricted
-- information; testing or comparing one errors. Callers treat nil as unknown.
function Compat.IsReadable(value)
    if issecretvalue then
        return not issecretvalue(value)
    end
    return pcall(function() return value == value end)
end
