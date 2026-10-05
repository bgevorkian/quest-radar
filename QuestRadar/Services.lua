local _, ns = ...
local byMap={}
ns.ServiceByID={}
for _, entry in ipairs(ns.Services or {}) do
    ns.ServiceByID[entry.id]=entry
    for _, point in ipairs(entry.points) do
        local mapID=point[1]
        byMap[mapID]=byMap[mapID] or {}
        table.insert(byMap[mapID],{entry=entry,x=point[2],y=point[3]})
    end
end
local categories={
    banker={"Банк","Banker"},auctioneer={"Аукцион","Auctioneer"},
    classTrainer={"Учитель класса","TrainerClass"},professionTrainer={"Учитель профессии","TrainerProfession"},
    trainer={"Учитель","TrainerProfession"},repair={"Ремонт","Repair"},
    mailbox={"Почта","Mailbox"},innkeeper={"Трактирщик","Innkeeper"},
    flight={"Распорядитель полётов","TaxiNode"},stablemaster={"Смотритель стойл","Stablemaster"},
    battlemaster={"Военачальник","Battlemaster"},vendor={"Торговец","VendorReagent"},
}
local order={"banker","auctioneer","classTrainer","professionTrainer","trainer","repair","mailbox","innkeeper","flight","stablemaster","battlemaster","vendor"}
local classLabels={[1]="Учитель воинов",[2]="Учитель паладинов",[3]="Учитель охотников",[4]="Учитель разбойников",
    [5]="Учитель жрецов",[7]="Учитель шаманов",[8]="Учитель магов",[9]="Учитель чернокнижников",[11]="Учитель друидов"}
local professionLabels={
    ["Алхимия"]="Учитель алхимии",["Кузнечное дело"]="Учитель кузнечного дела",
    ["Наложение чар"]="Учитель наложения чар",["Инженерное дело"]="Учитель инженерного дела",
    ["Травничество"]="Учитель травничества",["Кожевничество"]="Учитель кожевничества",
    ["Горное дело"]="Учитель горного дела",["Снятие шкур"]="Учитель снятия шкур",
    ["Портняжное дело"]="Учитель портняжного дела",["Кулинария"]="Учитель кулинарии",
    ["Рыбная ловля"]="Учитель рыбной ловли",["Первая помощь"]="Учитель первой помощи",
    ["Верховая езда"]="Учитель верховой езды",
}
local textures,textureError
local function trackingTextures()
    if textures then return textures end
    textures={}
    if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingFilter and C_Minimap.GetTrackingInfo then
        local ok,reason=pcall(function()
            for i=1,C_Minimap.GetNumTrackingTypes() do
                local filter=C_Minimap.GetTrackingFilter(i)
                local info=C_Minimap.GetTrackingInfo(i)
                if filter and filter.filterID and info and info.texture then textures[filter.filterID]=info.texture end
            end
        end)
        if not ok then textureError=tostring(reason) end
    end
    return textures
end
function ns.ResetServiceTextures()textures=nil;textureError=nil end
local function icon(category)
    local enum=Enum and Enum.MinimapTrackingFilter
    local key=categories[category][2]
    return enum and trackingTextures()[enum[key]]
end
local function name(entry)
    if GetLocale()=="ruRU" and entry.nameRU and entry.nameRU~="" then return entry.nameRU end
    return entry.name
end
local function label(entry,category)
    if category=="classTrainer" then return classLabels[entry.classID] or categories[category][1] end
    if category=="professionTrainer" and entry.role then return professionLabels[entry.role] or entry.role end
    if category=="trainer" then return entry.role or "Учитель (специальность неизвестна)" end
    return categories[category][1]
end
function ns.InitServicePins()
    QuestRadarServicePinMixin=CreateFromMixins(MapCanvasPinMixin)
    function QuestRadarServicePinMixin:OnLoad()
        self:UseFrameLevelType("PIN_FRAME_LEVEL_QUEST_OFFER")
        self:SetScalingLimits(1,1,1)
    end
    function QuestRadarServicePinMixin:OnAcquired(group)
        self.group=group
        self:SetPosition(group.x,group.y)
        self.Texture:SetTexture(group.texture)
    end
    function QuestRadarServicePinMixin:OnMouseUpAction(button)
        if button=="LeftButton" and IsShiftKeyDown() then
            local ids={}
            for _, item in ipairs(self.group.items) do ids[#ids+1]=item.entry.id end
            ns.ShowBugReport({kind="service",mapID=self:GetMap():GetMapID(),x=self.group.x,y=self.group.y,
                ids=ids,name=name(self.group.items[1].entry)})
        end
    end
    function QuestRadarServicePinMixin:OnMouseEnter()
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        local shown={}
        for _, item in ipairs(self.group.items) do
            local heading=label(item.entry,item.category)
            local text=name(item.entry)
            local key=heading..":"..text
            if not shown[key] then
                if next(shown) then GameTooltip:AddLine(" ") end
                if text~="" and item.category~="mailbox" then
                    GameTooltip:AddLine(text,1,1,1)
                    GameTooltip:AddLine(heading,1,.82,0)
                else GameTooltip:AddLine(heading,1,1,1) end
                shown[key]=true
            end
        end
        GameTooltip:Show()
    end
    function QuestRadarServicePinMixin:OnMouseLeave()GameTooltip:Hide()end
    function QuestRadarServicePinMixin:OnReleased()
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        self.group=nil
        MapCanvasPinMixin.OnReleased(self)
    end
end
function ns.RefreshServices(map,mapID,ctx,cfg)
    map:RemoveAllPinsByTemplate("QuestRadarServicePinTemplate")
    local report={source=ns.ServiceDataInfo,points=0,missingIcons={},candidates=0}
    ns.LastServiceReport=report
    if not cfg.enabled or not cfg.services then return end
    local faction=ctx.faction==1 and "H" or ctx.faction==2 and "A" or nil
    local groups={}
    for _, category in ipairs(order) do
        if category~="vendor" or cfg.vendors then
            for _, candidate in ipairs(byMap[mapID] or {}) do
                local entry=candidate.entry
                local eligible=(entry.faction=="" or (faction and entry.faction:find(faction,1,true)))
                    and (not entry.classID or entry.classID==ctx.class)
                if eligible then
                    for _, kind in ipairs(entry.categories) do
                        if kind==category then
                            report.candidates=report.candidates+1
                            local texture=icon(category)
                            if not texture then report.missingIcons[category]=true
                            else
                                local group
                                for _, g in ipairs(groups) do
                                    if g.category==category and math.abs(g.x-candidate.x)<.006 and math.abs(g.y-candidate.y)<.006 then group=g;break end
                                end
                                if not group then
                                    group={x=candidate.x,y=candidate.y,texture=texture,category=category,items={},seen={}}
                                    groups[#groups+1]=group
                                end
                                local key=entry.id..":"..category
                                if not group.seen[key] then
                                    group.items[#group.items+1]={entry=entry,category=category}
                                    group.seen[key]=true
                                end
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    for _, group in ipairs(groups) do map:AcquirePin("QuestRadarServicePinTemplate",group) end
    report.points=#groups
    report.iconAPIError=textureError
end
