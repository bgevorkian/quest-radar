local addon, ns = ...
ns = ns or {}
local command = "qradar"
local frame = CreateFrame("Frame")
local active, serial = nil, 0
local window, edit, diagnostics
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
    table.sort(keys, function(a, b) if type(a)=="number" and type(b)=="number" then return a<b end
        return tostring(a) < tostring(b) end)
    local flat={}
    for _,key in ipairs(keys) do
        if type(value[key])=="table" then flat=nil;break end
        flat[#flat+1]="["..dump(key).."] = "..dump(value[key])
    end
    if flat then return "{ "..table.concat(flat,", ").." }" end
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
-- Export copies only: old SavedVariables stay intact until explicit cleanup.
function ns.BuildReport(full)
    local sources,sourceIDs={},{}
    local function compact(value)
        if type(value)~="table" then return value end
        local out={}
        for k,v in pairs(value) do
            if k~="questData" and k~="serviceData" then out[k]=compact(v) end
        end
        if value.questData or value.serviceData then
            local source={quests=value.questData and value.questData.revision,
                services=value.serviceData and value.serviceData.revisions}
            local key=dump(source)
            if not sourceIDs[key] then sources[#sources+1]=source;sourceIDs[key]=#sources end
            out.source=sourceIDs[key]
        end
        return out
    end
    local report={format=2,context=compact(ns.CaptureReportContext and ns.CaptureReportContext()),
        observations={},unknownQuests=compact(QuestRadarUnknownQuests or {}),
        serviceObservations={},bugs=compact(QuestRadarBugReports or {}),sources=sources}
    local seen={}
    for _,entry in ipairs(ns.GetObservations and ns.GetObservations() or {}) do
        local row=compact(entry)
        local stamp=row.time;row.time=nil
        local key=dump(row)
        if seen[key] then
            seen[key].time=math.max(seen[key].time or 0,stamp or 0)
        else
            row.time=stamp;seen[key]=row;report.observations[#report.observations+1]=row
        end
    end
    -- Merge services only when location, time and every other context field match.
    -- Different visits/positions must never inherit each other's service evidence.
    seen={}
    local keys={}
    for key in pairs(QuestRadarServiceObservations or {}) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do
        local row=compact(QuestRadarServiceObservations[key])
        local kind=row.kind;row.kind=nil
        local identity=dump(row)
        if not seen[identity] then
            row.kinds={};seen[identity]=row
            report.serviceObservations[#report.serviceObservations+1]=row
        end
        if kind then table.insert(seen[identity].kinds,kind) end
    end
    if full then
        report.map=ns.LastMapReport;report.services=ns.LastServiceReport;report.api=saved()
    end
    return report
end
local function clearCollected()
    serial=serial+1;active=nil
    QuestRadarDB=nil
    QuestRadarObservations={}
    QuestRadarUnknownQuests={}
    QuestRadarServiceObservations={}
    QuestRadarBugReports={}
    if window then window:Hide() end
    say("Собранные записи очищены. Новые встречи будут записываться дальше. /reload сохранит очистку.")
end
function ns.ConfirmClearCollected()
    StaticPopupDialogs["QUESTRADAR_CLEAR_COLLECTED"]={
        text="Очистить все собранные записи QuestRadar у этого персонажа?\n\nСначала отправьте или сохраните отчёт. Будут удалены наблюдения заданий и NPC, сообщения об ошибках и диагностика. Настройки и база отметок останутся.",
        button1="Очистить",button2="Отмена",OnAccept=clearCollected,
        timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
    }
    StaticPopup_Show("QUESTRADAR_CLEAR_COLLECTED")
end
local function showReport(full)

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
        scroll:SetPoint("BOTTOMRIGHT", -32, 52)
        edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(660)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() window:Hide() end)
        scroll:SetScrollChild(edit)
        local clear=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
        clear:SetSize(230,24)
        clear:SetPoint("BOTTOMLEFT",14,14)
        clear:SetText("Очистить собранные записи…")
        clear:SetScript("OnClick",ns.ConfirmClearCollected)
        diagnostics=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
        diagnostics:SetSize(200,24)
        diagnostics:SetPoint("LEFT",clear,"RIGHT",12,0)
        diagnostics:SetScript("OnClick",function()showReport(not window.full)end)
        UISpecialFrames[#UISpecialFrames + 1] = addon .. "Report"
    end
    window.full=not not full
    diagnostics:SetText(full and "Обычный отчёт" or "Полная диагностика")
    window:Show()
    window.TitleText:SetText(full and "Полная диагностика: Ctrl+A, Ctrl+C" or "Отчёт для отправки: Ctrl+A, Ctrl+C")
    edit:SetText(dump(ns.BuildReport(full)))
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
        addonVersion = "0.2.16", date = date("%Y-%m-%d %H:%M:%S"),
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
                showReport(true)
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
    elseif message == "report full" then showReport(true)
    elseif message == "clearall" then ns.ConfirmClearCollected()
    elseif message == "bug" then ns.ShowBugReport()
    elseif message == "clear" then
        serial = serial + 1
        active = nil
        _G[addon .. "DB"] = nil
        if window then window:Hide() end
        say("Диагностика API очищена. Собранные записи сохранены.")
    elseif message == "" then ns.Toggle()
    elseif message == "settings" then ns.OpenSettings()
    elseif message == "uncertain" then ns.ToggleUncertain()
    elseif message == "scan" or tonumber(message) then scan(tonumber(message))
    else say("/qradar — отметки; uncertain — сомнительные; scan — проверка API; report — выгрузить отчёт; bug — сообщить об ошибке; clear — очистить отчёт API; clearall — очистить собранное с подтверждением.") end
end

-- The native AddOn Compartment invokes this callback from TOC metadata.
function QuestRadar_OpenSettings()
    ns.OpenSettings()
end
