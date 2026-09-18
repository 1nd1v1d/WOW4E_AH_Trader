local AHT = WOW4E_AHT

AHT.Transmute = {}

function AHT.Transmute:GetResults()
    if AHT.Calculator then return AHT.Calculator:CalculateTransmutes() end
    return {}
end

function AHT.Transmute:Print()
    local results = self:GetResults()
    if #results == 0 then
        AHT:Print("Keine Transmutationsrezepte erkannt. Öffne das Berufsfenster und aktualisiere die Rezepte.")
        return
    end
    for _, result in ipairs(results) do
        AHT:Print(string.format("%s: %s", result.name, result.profit and AHT:FormatMoney(result.profit) or AHT.L.incomplete))
    end
end
