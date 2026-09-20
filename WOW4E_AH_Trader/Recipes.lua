local AHT = WOW4E_AHT

AHT.Recipes = { list = {}, refreshing = false }

local function AddRecipeID(ids, seen, recipeID)
    if type(recipeID) == "number" and not seen[recipeID] then
        seen[recipeID] = true
        table.insert(ids, recipeID)
    end
end

local function ReadRecipeIDs()
    local ids, seen = {}, {}
    local api = C_TradeSkillUI
    if not api then return ids end

    if api.GetAllRecipeIDs then
        local ok, values = pcall(api.GetAllRecipeIDs)
        if ok and type(values) == "table" then
            for _, recipeID in ipairs(values) do AddRecipeID(ids, seen, recipeID) end
        end
    end
    if #ids == 0 and api.GetRecipeIDs then
        local ok, values = pcall(api.GetRecipeIDs)
        if ok and type(values) == "table" then
            for _, recipeID in ipairs(values) do AddRecipeID(ids, seen, recipeID) end
        end
    end
    if #ids == 0 and api.GetCategories and api.GetRecipesForCategory then
        local ok, categories = pcall(api.GetCategories)
        if ok and type(categories) == "table" then
            local function ReadCategory(category)
                if not category then return end
                local categoryID = category.categoryID or category.id
                if categoryID then
                    local okRecipes, recipes = pcall(api.GetRecipesForCategory, categoryID)
                    if okRecipes and type(recipes) == "table" then
                        for _, recipeID in ipairs(recipes) do
                            if type(recipeID) == "table" then recipeID = recipeID.recipeID end
                            AddRecipeID(ids, seen, recipeID)
                        end
                    end
                end
                for _, child in ipairs(category.subCategories or category.children or {}) do
                    ReadCategory(child)
                end
            end
            for _, category in ipairs(categories) do ReadCategory(category) end
        end
    end
    return ids
end

local function ReadOutput(recipeID)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeOutputItemData then return nil end
    local ok, output = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
    if not ok or type(output) ~= "table" then return nil end
    return {
        itemID = output.itemID,
        name = output.name or AHT:GetItemInfo(output.itemID),
        link = output.hyperlink or output.link,
        quantity = output.quantity or output.numItems or 1,
    }
end

local function ReadReagents(recipeID)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then return {} end
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(schematic) ~= "table" then return {} end
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or schematic.reagents or {}) do
        local options = slot.reagents or slot.reagentOptions or {}
        local reagent = options[1] or slot
        if reagent and reagent.itemID then
            table.insert(reagents, {
                itemID = reagent.itemID,
                name = reagent.name or AHT:GetItemInfo(reagent.itemID),
                quantity = reagent.quantity or slot.quantityRequired or 1,
            })
        end
    end
    return reagents
end

function AHT.Recipes:Refresh()
    if self.refreshing or not C_TradeSkillUI then return end
    self.refreshing = true
    local newList = {}
    local professionID, professionName
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local okProfession, profession = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if okProfession and type(profession) == "table" then
            professionID = profession.professionID or profession.parentProfessionID
            professionName = profession.professionName or profession.name
        end
    end
    for _, recipeID in ipairs(ReadRecipeIDs()) do
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and type(info) == "table" and info.name and info.learned ~= false then
            local output = ReadOutput(recipeID)
            local reagents = ReadReagents(recipeID)
            if output and output.itemID and #reagents > 0 then
                table.insert(newList, {
                    recipeID = recipeID,
                    name = info.name,
                    output = output,
                    reagents = reagents,
                    professionID = professionID,
                    professionName = professionName,
                    isTransmute = string.find(string.lower(info.name), "transmut") ~= nil,
                })
            end
        end
    end
    -- The Forever client can emit a transient list-update event while the
    -- profession data is still loading. Never replace a persisted catalog
    -- with that empty intermediate result.
    if #newList == 0 then
        self.refreshing = false
        return
    end
    -- Forever exposes recipes per opened profession window. Replace the
    -- currently opened profession while retaining recipes learned from other
    -- professions so the production planner can work across all crafts.
    local merged, seen, refreshedIDs = {}, {}, {}
    for _, recipe in ipairs(newList) do
        if recipe.recipeID then refreshedIDs[recipe.recipeID] = true end
    end
    for _, recipe in ipairs(AHT.DB and AHT.DB.recipes or {}) do
        local sameProfession = professionID and tonumber(recipe.professionID) == tonumber(professionID)
        if not sameProfession and recipe.recipeID and not refreshedIDs[recipe.recipeID] and not seen[recipe.recipeID] then
            seen[recipe.recipeID] = true
            table.insert(merged, recipe)
        end
    end
    for _, recipe in ipairs(newList) do
        if recipe.recipeID and not seen[recipe.recipeID] then
            seen[recipe.recipeID] = true
            table.insert(merged, recipe)
        end
    end
    table.sort(merged, function(a, b) return tostring(a.name or "") < tostring(b.name or "") end)
    self.list = merged
    if AHT.DB then
        AHT.DB.recipes = merged
        if AHT.Store then AHT.Store:Save() end
    end
    if AHT.Inventory and AHT.Inventory.bankOpen then AHT.Inventory:RefreshKnownItems() end
    self.refreshing = false
    if #newList > 0 then AHT:Print(string.format(AHT.L.recipesLoaded, #merged)) end
    if AHT.UI and AHT.UI.frame and AHT.UI.frame:IsShown() then AHT:Refresh() end
end

function AHT.Recipes:GetList()
    if #self.list > 0 then return self.list end
    return AHT.DB and AHT.DB.recipes or {}
end

function AHT.Recipes:Targets()
    local targets, seen = {}, {}
    for _, recipe in ipairs(self:GetList()) do
        local output = recipe.output
        local function Add(item)
            if item and item.itemID and not seen[item.itemID] then
                seen[item.itemID] = true
                table.insert(targets, { itemID = item.itemID, name = item.name, kind = "unknown" })
            end
        end
        Add(output)
        for _, reagent in ipairs(recipe.reagents or {}) do Add(reagent) end
    end
    return targets
end

function AHT.Recipes:Print()
    if AHT.UI then
        AHT.UI:SetView("recipes")
        return
    end
    AHT:Print(AHT.L.noRecipes)
end
