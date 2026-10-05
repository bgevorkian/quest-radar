local _, ns = ...
local panel = CreateFrame("Frame")
panel.name = "QuestRadar"
panel:Hide()
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("QuestRadar")
local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
description:SetText("Задания и городские службы на большой карте.")
local checks = {}
for index, option in ipairs({
    {"enabled", "Показывать отметки QuestRadar на карте"},
    {"uncertain", "Показывать задания с неуточнёнными условиями (серые !)"},
    {"services", "Показывать учителей и городские службы"},
    {"vendors", "Показывать обычных торговцев"},
}) do
    local key = option[1]
    local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    box:SetPoint("TOPLEFT", 16, -72 - (index-1)*34)
    box.Text:SetFontObject(GameFontNormal)
    box.Text:SetText(option[2])
    box:SetScript("OnClick", function(self)
        ns.GetSettings()[key] = not not self:GetChecked()
        ns.Refresh()
    end)
    checks[key] = box
end
panel:SetScript("OnShow", function()
    for key, box in pairs(checks) do box:SetChecked(ns.GetSettings()[key]) end
end)
local report = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
report:SetSize(180, 24)
report:SetPoint("TOPLEFT", 20, -228)
report:SetText("Выгрузить отчёт")
report:SetScript("OnClick", function()
    if SettingsPanel then HideUIPanel(SettingsPanel)
    elseif InterfaceOptionsFrame then HideUIPanel(InterfaceOptionsFrame) end
    ns.ShowReport()
end)
local bug=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
bug:SetSize(200,24)
bug:SetPoint("LEFT",report,"RIGHT",12,0)
bug:SetText("Сообщить об ошибке")
bug:SetScript("OnClick",function()
    if SettingsPanel then HideUIPanel(SettingsPanel)
    elseif InterfaceOptionsFrame then HideUIPanel(InterfaceOptionsFrame) end
    ns.ShowBugReport()
end)
local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
hint:SetPoint("TOPLEFT", report, "BOTTOMLEFT", 0, -10)
hint:SetText("Место ошибки записывается автоматически.\nОтчёт можно скопировать: Ctrl+A, Ctrl+C. Отправьте его разработчику.")
local category
if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
else
    InterfaceOptions_AddCategory(panel)
end
function ns.OpenSettings()
    if category then Settings.OpenToCategory(category:GetID())
    else InterfaceOptionsFrame_OpenToCategory(panel) end
end
