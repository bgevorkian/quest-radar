local _, ns = ...
local frame = CreateFrame("Frame")
local observations = {} -- confirmations never survive a reload, login, or progress change
local hoveredPin
local requestedQuestData={}
local provider, scheduled
ns.LastMapReport = {}
local function safe(object, key, ...)
    if not object or type(object[key])~="function" then return nil end
    local ok, result = pcall(object[key], ...)
    if ok then return result end
end
local function settings()
    QuestRadarSettings = QuestRadarSettings or {enabled=true, uncertain=true}
    if QuestRadarSettings.services==nil then QuestRadarSettings.services=true end
    if QuestRadarSettings.vendors==nil then QuestRadarSettings.vendors=true end
    return QuestRadarSettings
end
ns.GetSettings=settings
local function context()
    local faction = UnitFactionGroup("player")
    local completed = safe(C_QuestLog,"GetAllCompletedQuestIDs")
    local completeSet
    if type(completed)=="table" then
        completeSet={}
        for _, id in ipairs(completed) do completeSet[id]=true end
    end
    local skillCache, repCache = {}, {}
    return {
        level=UnitLevel("player"), class=select(3,UnitClass("player")), race=select(3,UnitRace("player")),
        faction=faction=="Horde" and 1 or faction=="Alliance" and 2 or 0,
        completed=function(id)
            if completeSet then return completeSet[id] or false end
            return nil
        end,
        onQuest=function(id) return safe(C_QuestLog,"IsOnQuest",id) end,
        skill=function(id)
            if skillCache[id]~=nil then return skillCache[id] end
            if not C_SkillInfo or not C_SkillInfo.GetSkillLineInfoByID then return nil end
            local data=safe(C_SkillInfo,"GetSkillLineInfoByID",id)
            skillCache[id]=data and data.rank or 0
            return skillCache[id]
        end,
        reputation=function(id)
            if repCache[id]~=nil then return repCache[id] end
            local data=safe(C_Reputation,"GetFactionDataByID",id)
            repCache[id]=data and data.currentStanding
            return repCache[id]
        end,
    }
end
local function observation(q)
    local o=observations[q.id]
    if not o or GetTime()-o.time>60 then return nil end
    if #q.qgs>0 then
        local matches=false
        for _, id in ipairs(q.qgs) do if id==o.npcID then matches=true end end
        if not matches then return nil end
    end
    return o
end
local function title(id)
    return safe(C_QuestLog,"GetTitleForQuestID",id) or "Задание"
end
function ns.PinTooltip(pin)
    GameTooltip:SetOwner(pin,"ANCHOR_RIGHT")
    for i, entry in ipairs(pin.entries) do
        if i>8 then GameTooltip:AddLine("И ещё "..(#pin.entries-8).." заданий"); break end
        if i>1 then GameTooltip:AddLine(" ") end
        local difficulty=safe(C_QuestLog,"GetQuestDifficultyLevel",entry.quest.id)
        local heading=title(entry.quest.id)
        local color={r=1,g=0.82,b=0}
        if type(difficulty)=="number" and difficulty>0 then
            heading="["..difficulty.."] "..heading
            color=GetQuestDifficultyColor and GetQuestDifficultyColor(difficulty) or color
        else
            heading="[?] "..heading
        end
        GameTooltip:AddLine(heading,color.r,color.g,color.b,true)
        if entry.status=="uncertain" then
            GameTooltip:AddLine("Условия открытия неизвестны",0.7,0.7,0.7,true)
        elseif entry.status=="confirmed" then
            GameTooltip:AddLine("Предложено NPC",0.5,1,0.5)
        end
        if entry.quest.start=="item" then GameTooltip:AddLine("Начинается с предмета",0.8,0.8,0.8) end
        if not requestedQuestData[entry.quest.id] then
            requestedQuestData[entry.quest.id]=true
            safe(C_QuestLog,"RequestLoadQuestByID",entry.quest.id)
        end
    end
    GameTooltip:Show()
end
function ns.Refresh()
    if not provider or not WorldMapFrame:IsShown() then return end
    local mapID=WorldMapFrame:GetMapID()
    WorldMapFrame:RemoveAllPinsByTemplate("QuestRadarPinTemplate")
    local cfg=settings()
    local ctx=context()
    local groups, report, seen={}, {}, {}
    for _, candidate in ipairs(ns.ByMap[mapID] or {}) do
        local q, point=candidate.quest,candidate.point
        local status, reason=ns.Evaluate(q,ctx)
        local o=observation(q)
        if o and o.mapID==mapID and math.abs(o.x-point[2])<0.02 and math.abs(o.y-point[3])<0.02 and not ctx.onQuest(q.id) then
            status,reason="confirmed","NPC предложил задание менее минуты назад"
        end
        if not seen[q.id..":"..status] then
            report[#report+1]={id=q.id,status=status,reason=reason}; seen[q.id..":"..status]=true
        end
        if cfg.enabled and status~="hidden" and (cfg.uncertain or status~="uncertain") then
            local key=string.format("%.4f:%.4f",point[2],point[3])
            local group=groups[key]
            if not group then group={x=point[2],y=point[3],entries={},ids={}}; groups[key]=group end
            if not group.ids[q.id] then
                local entry={quest=q,status=status,reason=reason}
                group.ids[q.id]=entry;group.entries[#group.entries+1]=entry
            else
                local rank={uncertain=1,calculated=2,confirmed=3}
                local entry=group.ids[q.id]
                if rank[status]>rank[entry.status] then entry.quest=q;entry.status=status;entry.reason=reason end
            end
        end
    end
    local count=0
    for _, group in pairs(groups) do
        table.sort(group.entries,function(a,b)return a.quest.id<b.quest.id end)
        WorldMapFrame:AcquirePin("QuestRadarPinTemplate",group);count=count+1
    end
    ns.LastMapReport={mapID=mapID,client=select(1,GetBuildInfo()),source=ns.DataInfo,points=count,quests=report,
        player={level=ctx.level,class=ctx.class,race=ctx.race,faction=ctx.faction}}
    if ns.RefreshServices then ns.RefreshServices(WorldMapFrame,mapID,ctx,cfg) end

end
local function schedule()
    if scheduled then return end
    scheduled=true
    C_Timer.After(0.2,function()scheduled=false;ns.Refresh()end)
end
function ns.Toggle()
    local cfg=settings();cfg.enabled=not cfg.enabled;ns.Refresh()
    print("QuestRadar: отметки "..(cfg.enabled and "включены" or "выключены"))
end
function ns.ToggleUncertain()
    local cfg=settings();cfg.uncertain=not cfg.uncertain;ns.Refresh()
    print("QuestRadar: сомнительные задания "..(cfg.uncertain and "показаны" or "скрыты"))
end
local function install()
    if provider or not WorldMapFrame or not MapCanvasPinMixin then return end
    if ns.InitServicePins then ns.InitServicePins() end
    QuestRadarPinMixin=CreateFromMixins(MapCanvasPinMixin)
    function QuestRadarPinMixin:OnLoad()
        self:UseFrameLevelType("PIN_FRAME_LEVEL_QUEST_OFFER")
        self:SetScalingLimits(1,1,1)
    end
    function QuestRadarPinMixin:OnAcquired(group)
        self.entries=group.entries; self:SetPosition(group.x,group.y)
        local status="uncertain"
        for _, e in ipairs(group.entries) do
            if e.status=="confirmed" then status="confirmed";break end
            if e.status=="calculated" then status="calculated" end
        end
        self.Texture:SetAtlas("QuestNormal")
        self.Texture:SetDesaturated(status=="uncertain")
        self.Texture:SetAlpha(status=="uncertain" and 0.8 or 1)
    end
    function QuestRadarPinMixin:OnMouseEnter()hoveredPin=self;ns.PinTooltip(self)end
    function QuestRadarPinMixin:OnMouseUpAction(button)
        if button=="LeftButton" and IsShiftKeyDown() then
            local x,y=self:GetPosition()
            local ids={}
            for _, entry in ipairs(self.entries) do ids[#ids+1]=entry.quest.id end
            ns.ShowBugReport({kind="quest",mapID=self:GetMap():GetMapID(),x=x,y=y,ids=ids,name=title(ids[1])})
        end
    end
    function QuestRadarPinMixin:OnMouseLeave()hoveredPin=nil;GameTooltip:Hide()end
    function QuestRadarPinMixin:OnReleased()
        if hoveredPin==self then hoveredPin=nil;GameTooltip:Hide() end
        MapCanvasPinMixin.OnReleased(self)
    end
    provider=CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RefreshAllData()ns.Refresh()end
    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate("QuestRadarPinTemplate")
        self:GetMap():RemoveAllPinsByTemplate("QuestRadarServicePinTemplate")
    end
    WorldMapFrame:AddDataProvider(provider)
    WorldMapFrame:HookScript("OnShow",schedule)
    ns.Refresh()
end
local function capture(id, name)
    if not id or id<=0 then return end
    local mapID=safe(C_Map,"GetBestMapForUnit","player")
    local position=mapID and safe(C_Map,"GetPlayerMapPosition",mapID,"player")
    if not position then return end
    local x,y=position:GetXY()
    local guid=UnitGUID("npc")
    local npcPart=guid and select(6,strsplit("-",guid))
    local npcID=tonumber(npcPart)
    if not npcID then return end
    local ctx=context()
    local o={time=GetTime(),mapID=mapID,x=x,y=y,npcID=npcID,title=name}
    observations[id]=o
    QuestRadarObservations=QuestRadarObservations or {}
    QuestRadarObservations[#QuestRadarObservations+1]={questID=id,npcID=npcID,mapID=mapID,x=x,y=y,
        time=time(),level=ctx.level,class=ctx.class,race=ctx.race,faction=ctx.faction,
        note="Позиция игрока при разговоре; наблюдение не доказывает условия открытия"}
    if #QuestRadarObservations>200 then table.remove(QuestRadarObservations,1) end
    -- A confirmation expires even when the character stands still with the map open.
    C_Timer.After(61,schedule)
end
local function captureAccepted(id)
    if type(id)~="number" or id<=0 or id%1~=0 or ns.ByID[id] then return end
    QuestRadarUnknownQuests=QuestRadarUnknownQuests or {}
    if QuestRadarUnknownQuests[id] then return end
    local mapID=safe(C_Map,"GetBestMapForUnit","player")
    local position=mapID and safe(C_Map,"GetPlayerMapPosition",mapID,"player")
    local x,y
    if position then x,y=position:GetXY() end
    local ctx=context()
    local offer=observations[id]
    if offer and GetTime()-offer.time>60 then offer=nil end
    local version,build=GetBuildInfo()
    local entry={questID=id,title=safe(C_QuestLog,"GetTitleForQuestID",id) or (offer and offer.title),
        time=time(),mapID=mapID,x=x,y=y,level=ctx.level,class=ctx.class,race=ctx.race,faction=ctx.faction,
        addonVersion="0.2.14",dataRevision=ns.DataInfo and ns.DataInfo.revision,client=version,build=build,
        note="Позиция игрока при принятии; условия открытия неизвестны"}
    -- An offer is evidence about this quest; the current NPC alone is not.
    if offer then entry.offeredByNPC=offer.npcID end
    QuestRadarUnknownQuests[id]=entry
    if not entry.title then safe(C_QuestLog,"RequestLoadQuestByID",id) end
end
frame:SetScript("OnEvent",function(_,event,...)
    if event=="MINIMAP_UPDATE_TRACKING" and ns.ResetServiceTextures then ns.ResetServiceTextures() end
    if event=="PLAYER_LOGIN" or event=="ADDON_LOADED" then install();return end
    if event=="QUEST_DATA_LOAD_RESULT" then
        local id,success=...
        local entry=QuestRadarUnknownQuests and QuestRadarUnknownQuests[id]
        if success and entry and not entry.title then entry.title=safe(C_QuestLog,"GetTitleForQuestID",id) end
        if hoveredPin and GameTooltip:IsOwned(hoveredPin) then ns.PinTooltip(hoveredPin) end
        return
    end
    if event=="GOSSIP_SHOW" then
        for _, q in ipairs(safe(C_GossipInfo,"GetAvailableQuests") or {}) do capture(q.questID,q.title) end
    elseif event=="QUEST_DETAIL" then capture(GetQuestID(),GetTitleText())
    elseif event=="QUEST_ACCEPTED" then captureAccepted(...);observations={}
    elseif event=="QUEST_TURNED_IN" or event=="PLAYER_LEVEL_UP" or event=="ZONE_CHANGED_NEW_AREA" or event=="SKILL_LINES_CHANGED" or event=="UPDATE_FACTION" or event=="QUEST_REMOVED" then observations={} end
    schedule()
end)
for _,event in ipairs({"PLAYER_LOGIN","ADDON_LOADED","GOSSIP_SHOW","QUEST_DETAIL","QUEST_ACCEPTED","QUEST_TURNED_IN","QUEST_REMOVED","QUEST_LOG_UPDATE","QUEST_DATA_LOAD_RESULT","PLAYER_LEVEL_UP","ZONE_CHANGED_NEW_AREA","SKILL_LINES_CHANGED","UPDATE_FACTION","MINIMAP_UPDATE_TRACKING"}) do
    pcall(frame.RegisterEvent,frame,event)
end
ns.GetObservations=function()return QuestRadarObservations end
