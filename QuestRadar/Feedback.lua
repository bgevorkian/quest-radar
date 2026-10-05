local _, ns = ...
local frame=CreateFrame("Frame")
local function call(object,key,...)
    local fn=object and object[key]
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn,...)
    if ok then return value end
end
local function npc(unit)
    local guid=UnitGUID(unit)
    if type(guid)~="string" or not guid:match("^Creature%-") then return nil end
    local part=select(6,strsplit("-",guid))
    local id=tonumber(part)
    if not id then return nil end
    local info={id=id,name=UnitName(unit)}
    local tooltip=call(C_TooltipInfo,"GetUnit",unit)
    -- Keep the client text as evidence; do not guess a profession from it.
    if tooltip and tooltip.lines then
        info.tooltip={}
        for i=1,math.min(3,#tooltip.lines) do
            local text=tooltip.lines[i].leftText
            if type(text)=="string" then info.tooltip[#info.tooltip+1]=text end
        end
    end
    return info
end
function ns.CaptureReportContext()
    local mapID=call(C_Map,"GetBestMapForUnit","player")
    local position=mapID and call(C_Map,"GetPlayerMapPosition",mapID,"player")
    local x,y
    if position then x,y=position:GetXY() end
    local version,build=GetBuildInfo()
    local mapInfo=mapID and call(C_Map,"GetMapInfo",mapID)
    return {time=time(),addonVersion="0.2.16",client=version,build=build,locale=GetLocale(),
        mapID=mapID,mapName=mapInfo and mapInfo.name,x=x,y=y,npc=npc("npc") or npc("target"),
        viewedMapID=WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() or nil,
        player={level=UnitLevel("player"),class=select(3,UnitClass("player")),race=select(3,UnitRace("player")),faction=UnitFactionGroup("player")},
        questData=ns.DataInfo,serviceData=ns.ServiceDataInfo}
end
local interactions={Merchant="vendor",Trainer="trainer",Banker="banker",CharacterBanker="banker",
    Auctioneer="auctioneer",TaxiNode="flight",StableMaster="stablemaster",Binder="innkeeper"}
local function capture(kind)
    local who=npc("npc")
    if not who then return end -- never attach a target NPC to a remote bank/mail window
    local ctx=ns.CaptureReportContext()
    ctx.npc=who
    ctx.kind=kind
    ctx.note="Позиция игрока при взаимодействии; не точные координаты NPC"
    local known=ns.ServiceByID and ns.ServiceByID[who.id]
    ctx.inDatabase=known~=nil
    ctx.nearKnownPoint=false
    if known and ctx.mapID and ctx.x and ctx.y then
        for _, p in ipairs(known.points) do
            if p[1]==ctx.mapID and math.abs(p[2]-ctx.x)<.02 and math.abs(p[3]-ctx.y)<.02 then ctx.nearKnownPoint=true;break end
        end
    end
    -- Store one latest observation per NPC and interaction, not an unbounded event log.
    QuestRadarServiceObservations=QuestRadarServiceObservations or {}
    QuestRadarServiceObservations[who.id..":"..kind]=ctx
end
frame:SetScript("OnEvent",function(_,event,interaction)
    if event~="PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then return end
    local enum=Enum and Enum.PlayerInteractionType
    if not enum then return end
    for name,kind in pairs(interactions) do
        if enum[name]==interaction then
            capture(kind)
            if kind=="vendor" and CanMerchantRepair and CanMerchantRepair() then capture("repair") end
            break
        end
    end
end)
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
ns.BugKinds={
    {"missing","Нет отметки"},{"position","Неверное место"},
    {"service","Неверный NPC / услуга"},{"other","Другая проблема"},
}
function ns.SaveBugReport(kind,description,context)
    local valid=false
    for _, choice in ipairs(ns.BugKinds) do if choice[1]==kind then valid=true;break end end
    if not valid then return nil,"Выберите, что не так." end
    description=(description or ""):match("^%s*(.-)%s*$")
    QuestRadarBugReports=QuestRadarBugReports or {}
    local report={kind=kind,description=description,context=context or ns.CaptureReportContext()}
    QuestRadarBugReports[#QuestRadarBugReports+1]=report
    return report
end
