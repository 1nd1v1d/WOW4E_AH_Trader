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
    if AHT.UI then AHT.UI:SetView("materials") end
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
    if AHT.UI then AHT.UI:SetView("materials") end
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
    if AHT.UI then
        AHT.UI:SetView("materials")
        return
    end
    AHT:Print("Keine Materialien. /aht mats add <Item-Link oder Item-ID>")
end
