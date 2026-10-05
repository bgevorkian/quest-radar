local addon, ns = ...
ns = ns or {}
local command = "qradar"
local frame = CreateFrame("Frame")
local active, serial = nil, 0
local window, edit
local bugWindow, bugContext, bugText, bugLocation, bugChoice, bugChecks
local function say(text) print("|cff88ddff" .. addon .. ":|r " .. text) end
local function call(namespace, method, ...)
    local fn = namespace and namespace[method]
    if type(fn) ~= "function" then return { status = "missing" } end
    local ok, value = pcall(fn, ...)
    if not ok then return { status = "error", message = tostring(value) } end
    return { status = value == nil and "nil" or "ok", value = value }
end
local function dump(value, depth)
    depth = depth or 0
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end
    if depth > 8 then return '"<depth limit>"' end
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        out[#out + 1] = string.rep("  ", depth + 1) .. "[" .. dump(key) .. "] = " .. dump(value[key], depth + 1)
    end
    return "{\n" .. table.concat(out, ",\n") .. "\n" .. string.rep("  ", depth) .. "}"
end
local function saved() return _G[addon .. "DB"] end
local function append(entry)
    local db = saved()
    if not db then return end
    entry.elapsed = GetTime() - (active and active.started or GetTime())
    db.samples[#db.samples + 1] = entry
    if #db.samples > 20 then table.remove(db.samples, 1) end
end
local function snapshot(reason)
    if not active then return end
    local result = call(C_QuestLine, "GetAvailableQuestLines", active.mapID)
    local flags = {}
    if result.status == "ok" and type(result.value) == "table" then
        for _, quest in ipairs(result.value) do
            if quest.questID then
                flags[quest.questID] = {
                    onQuest = call(C_QuestLog, "IsOnQuest", quest.questID),
                    completed = call(C_QuestLog, "IsQuestFlaggedCompleted", quest.questID),
                }
            end
        end
    end
    -- Serialize immediately: later client updates must not mutate earlier observations.
    append({ reason = reason, offers = dump(result), questFlags = dump(flags),
        forced = dump(call(C_QuestLine, "GetForceVisibleQuests", active.mapID)) })
    local count = result.status == "ok" and type(result.value) == "table" and #result.value
    say(reason .. ": " .. (count and (count .. " записей API") or result.status))
end
local function showReport()
    if not window then
        window = CreateFrame("Frame", addon .. "Report", UIParent, "BasicFrameTemplateWithInset")
        window:SetSize(720, 480)
        window:SetFrameStrata("DIALOG")
        window:SetPoint("CENTER")
        window:SetMovable(true)
        window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)
        window.TitleText:SetText("Отчёт для отправки: Ctrl+A, Ctrl+C")
        local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -36)
        scroll:SetPoint("BOTTOMRIGHT", -32, 14)
        edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(660)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() window:Hide() end)
        scroll:SetScrollChild(edit)
        UISpecialFrames[#UISpecialFrames + 1] = addon .. "Report"
    end
    window:Show()
    edit:SetText(dump({format=1,context=ns.CaptureReportContext and ns.CaptureReportContext(),
        map=ns.LastMapReport,services=ns.LastServiceReport,api=saved(),
        observations=ns.GetObservations and ns.GetObservations(),unknownQuests=QuestRadarUnknownQuests,
        serviceObservations=QuestRadarServiceObservations,bugs=QuestRadarBugReports}))
    edit:SetFocus()
    edit:HighlightText()
end
ns.ShowReport=showReport
function ns.ShowBugReport(marker)
    -- Freeze before showing any controls: no location change while composing.
    bugContext=ns.CaptureReportContext()
    bugContext.marker=marker
    if not bugWindow then
        bugWindow=CreateFrame("Frame",addon.."BugReport",UIParent,"BasicFrameTemplateWithInset")
        bugWindow:SetSize(580,350)
        bugWindow:SetFrameStrata("DIALOG")
        bugWindow:SetPoint("CENTER")
        bugWindow.TitleText:SetText("Сообщить об ошибке")
        bugLocation=bugWindow:CreateFontString(nil,"ARTWORK","GameFontHighlight")
        bugLocation:SetPoint("TOPLEFT",18,-40)
        bugLocation:SetWidth(544)
        bugLocation:SetJustifyH("LEFT")
        bugChecks={}
        for index,choice in ipairs(ns.BugKinds) do
            local key=choice[1]
            local box=CreateFrame("CheckButton",nil,bugWindow,"UICheckButtonTemplate")
            box:SetPoint("TOPLEFT",18,-90-(index-1)*30)
            box.Text:SetFontObject(GameFontNormal)
            box.Text:SetText(choice[2])
            box:SetScript("OnClick",function()
                bugChoice=key
                for kind,check in pairs(bugChecks) do check:SetChecked(kind==key) end
            end)
            bugChecks[key]=box
        end
        local caption=bugWindow:CreateFontString(nil,"ARTWORK","GameFontNormal")
        caption:SetPoint("TOPLEFT",20,-220)
        caption:SetText("Комментарий (необязательно)")
        bugText=CreateFrame("EditBox",nil,bugWindow,"InputBoxTemplate")
        bugText:SetPoint("TOPLEFT",24,-242)
        bugText:SetSize(530,26)
        bugText:SetAutoFocus(false)
        bugText:SetMaxLetters(300)
        bugText:SetScript("OnEscapePressed",function()bugWindow:Hide()end)
        local save=CreateFrame("Button",nil,bugWindow,"UIPanelButtonTemplate")
        save:SetPoint("BOTTOMLEFT",18,22)
        save:SetSize(260,26)
        save:SetText("Сохранить и открыть отчёт")
        save:SetScript("OnClick",function()
            local report,reason=ns.SaveBugReport(bugChoice,bugText:GetText(),bugContext)
            if not report then say(reason);return end
            bugWindow:Hide()
            showReport()
        end)
        UISpecialFrames[#UISpecialFrames+1]=addon.."BugReport"
    end
    bugChoice=marker and "position" or "missing"
    for kind,check in pairs(bugChecks) do check:SetChecked(kind==bugChoice) end
    bugText:SetText("")
    local place=bugContext.mapName or "Локация не определена"
    if bugContext.x and bugContext.y then place=place..string.format(" (%.1f, %.1f)",bugContext.x*100,bugContext.y*100) end
    local who=bugContext.npc and bugContext.npc.name
    bugLocation:SetText("Ваше положение: "..place.."\n"..(who and ("NPC: "..who) or "Для ошибки NPC выберите его целью перед открытием формы."))
    if marker then
        bugLocation:SetText("Отметка: "..(marker.name or "")..string.format(" (%.1f, %.1f)",marker.x*100,marker.y*100).."\nМесто отметки и ваши координаты записаны.")
    end
    bugWindow:Show()
end
local function scan(mapID)
    if not mapID then
        if WorldMapFrame and WorldMapFrame:IsShown() then mapID = WorldMapFrame:GetMapID() end
        if not mapID and C_Map then mapID = C_Map.GetBestMapForUnit("player") end
    end
    if not mapID then say("Не удалось определить карту. Открой карту локации.") return end
    serial = serial + 1
    local token = serial
    active = { mapID = mapID, started = GetTime(), requests = 1 }
    local version, build, _, interface = GetBuildInfo()
    _G[addon .. "DB"] = {
        addonVersion = "0.2.14", date = date("%Y-%m-%d %H:%M:%S"),
        client = { version = version, build = build, interface = interface, locale = GetLocale() },
        mapID = mapID, mapInfo = call(C_Map, "GetMapInfo", mapID),
        player = { level = UnitLevel("player"), race = select(2, UnitRace("player")),
            class = select(2, UnitClass("player")), faction = UnitFactionGroup("player") },
        filters = { localStory = call(C_CVar, "GetCVar", "questPOILocalStory"),
            hidden = call(C_Minimap, "IsTrackingHiddenQuests"),
            accountCompleted = call(C_Minimap, "IsTrackingAccountCompletedQuests") },
        samples = {},
    }
    say("Карта " .. mapID .. ". Проверка займёт 8 секунд.")
    snapshot("before-request")
    saved().request = call(C_QuestLine, "RequestQuestLinesForMap", mapID)
    for _, delay in ipairs({ 2, 5, 8 }) do
        C_Timer.After(delay, function()
            if serial ~= token or not active then return end
            snapshot("after-" .. delay .. "s")
            if delay == 8 then
                active = nil
                say("Готово. /qradar report — скопировать отчёт. Разговоры с NPC тоже сохраняются.")
                showReport()
            end
        end)
    end
end
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "QUESTLINE_UPDATE" then
        if not active then return end
        local required = ...
        snapshot("QUESTLINE_UPDATE requestRequired=" .. tostring(required))
        if required and active.requests < 3 then
            active.requests = active.requests + 1
            append({ reason = "request-again", result = call(C_QuestLine, "RequestQuestLinesForMap", active.mapID) })
        end
    elseif event == "GOSSIP_SHOW" and saved() then
        append({ reason = event, npc = UnitName("npc"), guid = UnitGUID("npc"),
            mapID = C_Map.GetBestMapForUnit("player"),
            available = dump(call(C_GossipInfo, "GetAvailableQuests")) })
    elseif event == "QUEST_DETAIL" and saved() then
        append({ reason = event, npc = UnitName("npc"), guid = UnitGUID("npc"),
            questID = GetQuestID(), title = GetTitleText() })
    end
end)
for _, event in ipairs({ "QUESTLINE_UPDATE", "GOSSIP_SHOW", "QUEST_DETAIL" }) do
    pcall(frame.RegisterEvent, frame, event)
end
_G["SLASH_" .. addon:upper() .. "1"] = "/" .. command
SlashCmdList[addon:upper()] = function(message)
    message = strtrim(message or "")
    if message == "report" then showReport()
    elseif message == "bug" then ns.ShowBugReport()
    elseif message == "clear" then
        serial = serial + 1
        active = nil
        _G[addon .. "DB"] = nil
        if window then window:Hide() end
        say("Отчёт удалён.")
    elseif message == "" then ns.Toggle()
    elseif message == "settings" then ns.OpenSettings()
    elseif message == "uncertain" then ns.ToggleUncertain()
    elseif message == "scan" or tonumber(message) then scan(tonumber(message))
    else say("/qradar — отметки; uncertain — сомнительные; scan — проверка API; report — выгрузить отчёт; bug — сообщить об ошибке; clear — очистить отчёт API.") end
end

-- The native AddOn Compartment invokes this callback from TOC metadata.
function QuestRadar_OpenSettings()
    ns.OpenSettings()
end
