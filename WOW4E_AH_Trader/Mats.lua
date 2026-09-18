local AHT = WOW4E_AHT

AHT.Mats = {}

function AHT.Mats:Add(value)
    local itemID = AHT:GetItemID(value)
    if not itemID then
        AHT:Print(AHT.L.noItemID)
        return false
    end
    local name = AHT:GetItemInfo(itemID)
    AHT.Store:AddMaterial(itemID, name or tostring(itemID))
    AHT:Print("Material überwacht: " .. (name or tostring(itemID)))
    if AHT.UI then AHT.UI:Refresh() end
    return true
end

function AHT.Mats:Remove(value)
    local itemID = AHT:GetItemID(value)
    if not itemID then
        AHT:Print(AHT.L.noItemID)
        return false
    end
    AHT.Store:RemoveMaterial(itemID)
    AHT:Print("Material entfernt: " .. tostring(itemID))
    if AHT.UI then AHT.UI:Refresh() end
    return true
end

function AHT.Mats:Targets()
    local targets = {}
    for _, material in pairs(AHT.DB.materials or {}) do
        if material.enabled ~= false then table.insert(targets, material) end
    end
    return targets
end

function AHT.Mats:Print()
    local count = 0
    for _, material in pairs(AHT.DB.materials or {}) do
        count = count + 1
        AHT:Print(string.format("%s (%s)", material.name or "?", tostring(material.itemID)))
    end
    if count == 0 then AHT:Print("Keine Materialien. /aht mats add <Item-Link>") end
end
