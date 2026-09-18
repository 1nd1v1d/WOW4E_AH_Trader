local AHT = WOW4E_AHT

AHT.Transmute = {}

function AHT.Transmute:GetResults()
    if AHT.Calculator then return AHT.Calculator:CalculateTransmutes() end
    return {}
end

function AHT.Transmute:Print()
    if AHT.UI then
        AHT.UI:SetView("transmute")
        return
    end
    AHT:Print("Keine Transmutationsrezepte erkannt. Öffne das Berufsfenster und aktualisiere die Rezepte.")
end
