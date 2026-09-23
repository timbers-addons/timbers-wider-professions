# Forever (camelot) support plan

Written 2026-09-21 from the TWPProbe measurements (see Dev/TWPProbe). Classic
clients keep the existing window untouched; Forever gets a new window built on
C_TradeSkillUI that replaces Blizzard's crafting page.

## What the probe established

- Forever loads `_Camelot.toc`. Interface 16001, `WOW_PROJECT_ID` mainline.
- Old trade skill / craft API, `TradeSkillFrame`, `CraftFrame`, `GetSpellInfo`,
  `GetItemInfo`, `GetItemCount`, `GetNumSkillLines`, `UIParentLoadAddOn`,
  `StackSplitCancelButton` are all gone. `CRAFT_*` and `TRADE_SKILL_UPDATE`
  cannot be registered. `TRADE_SKILL_CLOSE` fires three times per close.
- Recipes: `GetAllRecipeIDs` (learned + unlearned), `GetRecipeInfo`
  (`learned`, `relativeDifficulty` 0-3, `maxTrivialLevel`, `categoryID`,
  `favorite`, `hyperlink`, `icon`), `GetCraftableCount(recipeID)`,
  `GetRecipeSchematic` (reagents, quantities, output item), `GetCategoryInfo`.
  Classic recipes keep Classic spell ids, so `Lists/Vanilla.lua` thresholds
  still apply. `GetRecipeSourceText` is empty on Forever.
- Rank: `GetBaseProfessionInfo` gives skillLevel / maxSkillLevel.
- Crafting from an addon click: `CraftRecipe(id, n)` works. Enchants need
  `CraftEnchant(id, n, nil, C_Item.GetItemLocation(guid))` with a GUID from
  `GetEnchantItems(id)`; plain `CraftRecipe` on an enchant is blocked.
  Replacing an enchant raises `REPLACE_TRADESKILL_ENCHANT`; accepting it from
  addon code is blocked, so the popup stays.
- `OpenTradeSkill` is blocked. Switching professions needs a
  `SecureActionButtonTemplate` casting the profession spell
  (`C_SpellBook.GetSpellBookItemInfo(spellOffset + 1, Player).spellID`).
- Action bar opens are visible through `hooksecurefunc("UseAction")` +
  `GetActionInfo(slot)`; direct casts through `UNIT_SPELLCAST_SUCCEEDED`.
- `ProfessionsFrame` (LoadOnDemand `Blizzard_Professions`) can be ghosted
  (alpha 0, mouse off) and the data stays readable; hiding it closes the
  trade skill. It is 673x594, in `UIPanelWindows`, area left.
- `PortraitFrameTemplate` has no `TitleText` key on Forever; use `SetTitle`.

## Product decisions (agreed)

- New window on Forever, not a modification of Blizzard's.
- Three list modes, switchable from the window and the options page:
  Blizzard categories; one unified list sorted by skill-up level; one unified
  list alphabetical. Favorites header on top in every mode.
- Search box like Forever's. Favorites stored with Blizzard's flag
  (`SetRecipeFavorite`) so both windows agree.
- Colored thresholds (orange/yellow/green/gray) in the list and details.
- Adjustable height, tight 20px rows.
- Wide rank bar with a "link profession" button.
- Enchant target slot in the details pane (picker from `GetEnchantItems`);
  the overwrite popup remains Blizzard's.
- Profession tabs on the right edge (secure cast buttons).
- Linked / guild / NPC professions: our window stands down, Blizzard's shows.
- Native look: built from client templates, so it takes Forever's style there
  and Classic's on Classic. No gamepad support for now.

## Files

Shared by every client:
- `Src/Core.lua` (new, first in every TOC): creates the
  `TimbersWiderProfessionsAddon` frame and nothing else. `main.lua` stops
  creating it.
- `Src/Compat.lua` (new, second): the only file touching client-specific
  globals. Wrappers: `GetSpellInfo` -> name, icon; `GetItemInfo`;
  `GetItemCount`; `InsertLink`; `LoadAddOn`; `SetWindowTitle`; and the
  capability flags `HasClassicTradeSkill`, `HasCraftAPI`, `HasRecipeAPI`.
- `Src/Options.lua`: load-time `GetSpellInfo` calls go through Compat; Classic
  only options (Alchemy / Cooking / Enchanting categories, rogue poisons) are
  hidden when `HasClassicTradeSkill` is false; adds the list mode dropdown.
- `Src/Localization.lua`, `Lists/Vanilla.lua`: unchanged.

Forever only (`Src/Forever/`):
- `Recipes.lua`: reads C_TradeSkillUI into the addon's own recipe records
  (name, icon, link, difficulty, craftable count, category, thresholds,
  reagents, isEnchant, favorite, learned) and builds the header list for the
  active mode plus search and filters.
- `Window.lua`: the frame, list rows, details pane, craft controls, enchant
  slot, rank bar, link button, profession tabs, ghosting of
  `ProfessionsFrame`, event wiring.
- `Diagnostics.lua`: remembers the profession the player asked for
  (`UseAction` hook, direct casts) and reports a mismatch against
  `GetBaseProfessionInfo` when the window opens. Kept until the misfire is
  understood.

Classic only: `main.lua`, `CraftFrame.lua`, `TradeSkillFrame.lua`,
`CategoryList.lua`, `Lists/TBC.lua`, unchanged apart from `main.lua` no longer
creating the frame. They keep their bare pre-Cata globals; see Open questions.

TOCs: `_Vanilla`, `_TBC`, `_Mists` gain `Src/Core.lua` and `Src/Compat.lua`
at the top. `_Camelot` (Interface 16001) loads Core, Compat, Lists/Vanilla,
Localization, Options, Forever/Recipes, Forever/Window, Forever/Diagnostics.

## Window layout (Forever)

- `PortraitFrameTemplate`, 650 wide, height from the saved option (default
  ~600), `UIPanelLayout` attributes like the Classic window, Escape closes.
  Optional profession background atlas.
- Top: portrait = profession icon, title = profession name, rank bar
  (`StatusBar`, ~400 wide) with "rank/max" text and a link button that puts
  `GetTradeSkillListLink()` into chat via Compat `InsertLink`.
- Left inset: search box, list mode dropdown, filter checkboxes (Has skill-up,
  Makeable, Show unlearned), scrollable list of 20px rows: header rows with
  collapse toggle; recipe rows with difficulty color, name, `[count]`, and the
  four thresholds right-aligned.
- Right inset: icon with output quantity, name, thresholds line, description,
  requirements / cooldown text, reagent grid (icon, name, have/need, dimmed
  when short), enchant target slot for enchant recipes.
- Bottom right: count box with +/- buttons, Create All, Create.
- Right edge: one secure tab per known profession (icon, tooltip), current
  one highlighted.

## Behaviour

- `TRADE_SKILL_SHOW`: if `IsTradeSkillLinked/Guild/NPCCrafting`, do nothing
  (Blizzard's frame shows). Otherwise ghost `ProfessionsFrame`, wait for
  `IsTradeSkillReady()` (poll on `TRADE_SKILL_DATA_SOURCE_CHANGED` /
  `LIST_UPDATE`), build, `ShowUIPanel` ours.
- `TRADE_SKILL_LIST_UPDATE`, `TRADE_SKILL_ITEM_CRAFTED_RESULT`,
  `BAG_UPDATE_DELAYED`: coalesce into one refresh per frame
  (`C_Timer.After(0)`); refresh keeps selection and scroll.
- `TRADE_SKILL_CLOSE`: hide ours; idempotent. Our OnHide calls
  `C_TradeSkillUI.CloseTradeSkill()` when the trade skill is still open, and
  restores `ProfessionsFrame` alpha.
- Create: `CraftRecipe(recipeID, count)`; enchants: `CraftEnchant` with the
  slot's item, Create disabled until a target is chosen. Last target per recipe
  remembered for the session.
- Sorting by level: orange threshold from `Lists/Vanilla.lua`; recipes missing
  there sort by `maxTrivialLevel` and show only the gray number.
- Favorites: `SetRecipeFavorite`; Favorites header lists them in the active
  mode's order.
- Misfire: on show, compare the requested profession with the API's; print
  once per mismatch with both names. What to do about it is decided once we
  have seen one.

## Steps, each verified in game before the next

1. Core + Compat + TOC changes. Verify: Era/TBC window unchanged; Forever
   logs in with no errors and the addon does nothing yet.
2. `Recipes.lua` with a `/twp dump` command. Verify counts against the probe
   (Tailoring 477/16, Enchanting 261/10, Cooking 132/10).
3. `Window.lua` read-only: list, three modes, favorites, search, details.
   Blizzard's frame ghosted, close handling.
4. Craft controls, enchant slot, refresh on craft.
5. Rank bar + link, profession tabs, height option, options page changes.
6. `Diagnostics.lua`, README note for Forever, version bump.

Package check before any push: `Dev/` is in `.pkgmeta` ignore; the new files
under `Src/Forever/` ship.

## Open questions

- Compat scope: the shared rules say one file per addon touches client
  globals. The Classic-only files (`main.lua` and friends) are 2500 lines of
  direct pre-Cata calls that never load on Forever. Proposal: leave them as
  they are and route only the shared files through Compat; rewriting them
  gains nothing on any client. Needs a yes.
- Background art: use Blizzard's profession atlas on our frame, or plain
  insets?
- List row fonts: client default fonts and Blizzard's difficulty colors on
  Forever (proposed), or the Classic window's custom gray outlined font?
- "Show unlearned" default off (proposed).
