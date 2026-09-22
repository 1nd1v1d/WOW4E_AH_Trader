local AHT = WOW4E_AHT

AHT.Recipes = { list = {}, refreshing = false }

local function RecipeKey(recipeID)
    recipeID = tonumber(recipeID)
    return recipeID and tostring(recipeID) or nil
end

local function TextValue(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "string" and value ~= "" then return value end
    end
end

local function PositiveNumber(value)
    value = tonumber(value)
    return value and value > 0 and value or nil
end

local function ProfessionKey(professionID, professionName)
    professionID = PositiveNumber(professionID)
    if professionID then return "id:" .. tostring(professionID) end
    professionName = TextValue(professionName)
    if professionName then
        return "name:" .. string.lower((professionName:gsub("%s+", "_")))
    end
    return "unknown"
end

local function ReadProfessionInfo()
    local professionID, professionName
    local api = C_TradeSkillUI
    if api and api.GetBaseProfessionInfo then
        local ok, profession = pcall(api.GetBaseProfessionInfo)
        if ok and type(profession) == "table" then
            professionID = PositiveNumber(profession.professionID or profession.parentProfessionID)
            professionName = TextValue(profession.professionName, profession.name)
        end
    end

    -- Forever can expose an empty base-profession object while the classic
    -- trade-skill line is already available. Use both API generations as a
    -- fallback so stored recipes can be attributed to a profession.
    if api and api.GetTradeSkillLine then
        local ok, lineName, _, _, _, _, lineID = pcall(api.GetTradeSkillLine)
        if ok then
            professionName = professionName or TextValue(lineName)
            professionID = professionID or PositiveNumber(lineID)
        end
    end
    if type(GetTradeSkillLine) == "function" then
        local ok, lineName, _, _, _, _, lineID = pcall(GetTradeSkillLine)
        if ok then
            professionName = professionName or TextValue(lineName)
            professionID = professionID or PositiveNumber(lineID)
        end
    end
    return professionID or 0, professionName or ""
end

local function RecipesEqual(left, right)
    if not left or not right then return false end
    if tostring(left.name or "") ~= tostring(right.name or "") then return false end
    if tonumber(left.professionID) ~= tonumber(right.professionID) then return false end
    if tostring(left.professionName or "") ~= tostring(right.professionName or "") then return false end
    local leftOutput, rightOutput = left.output or {}, right.output or {}
    for _, key in ipairs({ "itemID", "quantity", "name", "link" }) do
        if tostring(leftOutput[key] or "") ~= tostring(rightOutput[key] or "") then return false end
    end
    local leftReagents, rightReagents = left.reagents or {}, right.reagents or {}
    if #leftReagents ~= #rightReagents then return false end
    for index, leftReagent in ipairs(leftReagents) do
        local rightReagent = rightReagents[index] or {}
        if tonumber(leftReagent.itemID) ~= tonumber(rightReagent.itemID) or
                tonumber(leftReagent.quantity or 1) ~= tonumber(rightReagent.quantity or 1) or
                tostring(leftReagent.name or "") ~= tostring(rightReagent.name or "") then
            return false
        end
    end
    return true
end

local function RememberProfession(professionID, professionName, recipeIDs)
    if not AHT.DB then return false end
    AHT.DB.professions = AHT.DB.professions or {}
    local key = ProfessionKey(professionID, professionName)
    local record = AHT.DB.professions[key]
    local changed = false
    if type(record) ~= "table" then
        record = { recipeIDs = {} }
        AHT.DB.professions[key] = record
        changed = true
    end
    record.recipeIDs = record.recipeIDs or {}
    local known = {}
    for _, recipeID in ipairs(record.recipeIDs) do known[tostring(recipeID)] = true end
    for _, recipeID in ipairs(recipeIDs or {}) do
        local recipeKey = RecipeKey(recipeID)
        if recipeKey and not known[recipeKey] then
            table.insert(record.recipeIDs, tonumber(recipeID) or recipeID)
            known[recipeKey] = true
            changed = true
        end
    end
    if record.professionID ~= professionID then record.professionID = professionID; changed = true end
    if record.name ~= professionName and professionName ~= "" then record.name = professionName; changed = true end
    local now = AHT:Now()
    if not record.lastSeen or now - tonumber(record.lastSeen) > 60 then
        record.lastSeen = now
        changed = true
    end
    return changed
end

function AHT.Recipes:Load()
    self.list = {}
    local seen = {}
    for _, recipe in ipairs(AHT.DB and AHT.DB.recipes or {}) do
        local key = type(recipe) == "table" and RecipeKey(recipe.recipeID)
        if key and recipe.output and recipe.output.itemID and not seen[key] then
            recipe.recipeID = tonumber(recipe.recipeID) or recipe.recipeID
            recipe.professionID = tonumber(recipe.professionID) or 0
            recipe.professionName = recipe.professionName or ""
            recipe.reagents = recipe.reagents or {}
            table.insert(self.list, recipe)
            seen[key] = true
        end
    end
    table.sort(self.list, function(a, b) return tostring(a.name or "") < tostring(b.name or "") end)
    if AHT.DB then
        AHT.DB.recipes = self.list
        AHT.DB.recipeIndex = {}
        local professionBuckets = {}
        for _, recipe in ipairs(self.list) do
            local key = RecipeKey(recipe.recipeID)
            if key then AHT.DB.recipeIndex[key] = true end
            local professionKey = ProfessionKey(recipe.professionID, recipe.professionName)
            local bucket = professionBuckets[professionKey]
            if not bucket then
                bucket = {
                    professionID = recipe.professionID,
                    professionName = recipe.professionName,
                    recipeIDs = {},
                }
                professionBuckets[professionKey] = bucket
            end
            table.insert(bucket.recipeIDs, recipe.recipeID)
        end
        for _, bucket in pairs(professionBuckets) do
            RememberProfession(bucket.professionID, bucket.professionName, bucket.recipeIDs)
        end
        if AHT.Store then AHT.Store:Save() end
    end
    return self.list
end

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
    if not AHT.Initialized and AHT.Initialize then AHT:Initialize() end
    if not AHT.Initialized or not AHT.DB then return end
    if self.refreshing or not C_TradeSkillUI then return end
    if AHT.Store and AHT.Store.EnsureLoaded and not AHT.Store:EnsureLoaded() then return end
    self.refreshing = true
    local newList = {}
    local professionID, professionName = ReadProfessionInfo()
    local refreshedIDs = {}
    for _, recipeID in ipairs(ReadRecipeIDs()) do
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and type(info) == "table" and info.name and info.learned ~= false then
            local output = ReadOutput(recipeID)
            local reagents = ReadReagents(recipeID)
            if output and output.itemID and #reagents > 0 then
                local recipe = {
                    recipeID = recipeID,
                    name = info.name,
                    output = output,
                    reagents = reagents,
                    professionID = professionID,
                    professionName = professionName,
                    isTransmute = string.find(string.lower(info.name), "transmut") ~= nil,
                }
                table.insert(newList, recipe)
                refreshedIDs[RecipeKey(recipeID)] = true
            end
        end
    end
    -- This is deliberately an upsert/delta sync. A temporary empty or partial
    -- trade-skill event must never delete the persisted catalog; recipes from
    -- other professions remain available after a restart and new recipe IDs
    -- are simply appended.
    local merged, seen = {}, {}
    for _, recipe in ipairs(AHT.DB and AHT.DB.recipes or {}) do
        local key = type(recipe) == "table" and RecipeKey(recipe.recipeID)
        if key and not refreshedIDs[key] and not seen[key] then
            seen[key] = true
            table.insert(merged, recipe)
        end
    end
    for _, recipe in ipairs(newList) do
        local key = RecipeKey(recipe.recipeID)
        if key and not seen[key] then
            seen[key] = true
            table.insert(merged, recipe)
        else
            for index, existing in ipairs(merged) do
                if RecipeKey(existing.recipeID) == key and not RecipesEqual(existing, recipe) then
                    merged[index] = recipe
                    break
                end
            end
        end
    end
    table.sort(merged, function(a, b) return tostring(a.name or "") < tostring(b.name or "") end)
    self.list = merged
    if AHT.DB then
        AHT.DB.recipes = merged
        AHT.DB.recipeIndex = AHT.DB.recipeIndex or {}
        local newRecipeIDs = {}
        for _, recipe in ipairs(merged) do
            local key = RecipeKey(recipe.recipeID)
            if key then AHT.DB.recipeIndex[key] = true end
        end
        for _, recipe in ipairs(newList) do table.insert(newRecipeIDs, recipe.recipeID) end
        RememberProfession(professionID, professionName, newRecipeIDs)
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
