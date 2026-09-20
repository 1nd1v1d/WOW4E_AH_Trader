local AHT = WOW4E_AHT

AHT.Scanner = { running = false, queue = {}, completed = 0, total = 0 }

local function AddTarget(targets, seen, item)
    if not item or not item.itemID then return end
    local key = tostring(item.itemID)
    if not seen[key] then
        seen[key] = true
        table.insert(targets, { itemID = item.itemID, name = item.name, kind = item.kind })
    end
end

function AHT.Scanner:BuildTargets()
    local targets, seen = {}, {}
    for _, target in ipairs(AHT.Recipes:Targets()) do AddTarget(targets, seen, target) end
    if AHT.Reputation then
        for _, target in ipairs(AHT.Reputation:Targets()) do AddTarget(targets, seen, target) end
    end
    for _, material in pairs(AHT.DB and AHT.DB.materials or {}) do
        if material.enabled ~= false then AddTarget(targets, seen, material) end
    end
    return targets
end

function AHT.Scanner:Start(targets)
    if self.running then
        AHT:Print("Ein Scan läuft bereits.")
        return
    end
    if not AHT.AHOpen then
        AHT:Print(AHT.L.noAH)
        return
    end
    targets = targets or self:BuildTargets()
    self.queue = targets
    self.completed = 0
    self.total = #targets
    self.running = self.total > 0
    if not self.running then
        AHT:Print(AHT.L.noRecipes)
        return
    end
    AHT.State.status = "scanning"
    AHT:Print(string.format(AHT.L.scanStart, self.total))
    self:Next()
end

function AHT.Scanner:Next()
    if not self.running then return end
    local target = table.remove(self.queue, 1)
    if not target then
        self.running = false
        AHT.State.status = AHT.AHOpen and "ah_open" or "ready"
        AHT:Print(string.format(AHT.L.scanDone, self.completed))
        AHT:Refresh()
        return
    end

    AHT.AH:Search(target, function(results, meta)
        if meta.error then
            AHT:Print((target.name or tostring(target.itemID)) .. ": " .. meta.error)
        else
            local minPrice = results[1] and results[1].unitPrice or nil
            local totalQuantity = meta.totalQuantity or 0
            AHT.Store:RecordMarket(target, {
                kind = meta.kind,
                minPrice = minPrice,
                totalQuantity = totalQuantity,
                listingCount = meta.listingCount or #results,
                prices = meta.prices,
            })
        end
        self.completed = self.completed + 1
        if AHT.UI then AHT.UI:RefreshStatus() end
        self:Next()
    end)
end

function AHT.Scanner:Stop(reason)
    if not self.running then return end
    self.running = false
    self.queue = {}
    AHT:Print(reason == "user" and AHT.L.scanStopped or "Scan abgebrochen: " .. tostring(reason))
end
