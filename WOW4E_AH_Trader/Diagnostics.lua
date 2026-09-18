local AHT = WOW4E_AHT

AHT.Diagnostics = {}

function AHT.Diagnostics:Print()
    local c = AHT.Capabilities or {}
    AHT:Print("--- Runtime-Diagnose ---")
    AHT:Print(string.format("Version %s | Client %s | Build %s | Interface %s", AHT.VERSION, tostring(c.version), tostring(c.build), tostring(c.interface)))
    AHT:Print(string.format("WOW_PROJECT_ID=%s | Forever-Hinweis=%s | AH offen=%s", tostring(c.projectID), tostring(c.foreverBeta), tostring(AHT.AHOpen)))
    AHT:Print(string.format("Rezepte=%d | Markt=%d | Materialien=%d", #((AHT.Recipes and AHT.Recipes:GetList()) or {}), AHT:TableCount(AHT.DB and AHT.DB.market), AHT:TableCount(AHT.DB and AHT.DB.materials)))
    if c.functions then
        for name, available in pairs(c.functions) do
            AHT:Print(name .. "=" .. tostring(available))
        end
    end
    if AHT.State.lastError then AHT:Print("Letzter Fehler: " .. AHT.State.lastError) end
end
