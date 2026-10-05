from pathlib import Path
from lupa.lua51 import LuaRuntime
from xml.etree import ElementTree
root=Path(__file__).parents[1]
ElementTree.parse(root/'QuestRadar/Pins.xml')
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
ns={}; frames={}; timers={}; now=100; completed={}; active={}
function loadAddon(s) assert(loadstring(s))('QuestRadar',ns) end
local methods={}
function methods:SetScript(k,v) self[k]=v end
function methods:HookScript(k,v) self[k]=v end
function methods:RegisterEvent() end
function methods:Hide()end
function methods:SetChecked(v)self.checked=v end
function methods:GetChecked()return self.checked end
function methods:CreateFontString()return setmetatable({},{__index=methods})end
function methods:SetSize() end
function methods:SetPoint() end
function methods:SetFrameLevel() end
function methods:GetFrameLevel() return 1 end
function methods:SetText(t) self.text=t end
function methods:SetFontObject(font)self.font=font end
function methods:SetAtlas(v) self.atlas=v end
function methods:SetTexture(v) self.texture=v end
function methods:SetDesaturated(v)self.desaturated=v end
function methods:SetAlpha(v)self.alpha=v end
function methods:IsShown() return true end
function CreateFrame() local f=setmetatable({},{__index=methods}); f.Text=setmetatable({},{__index=methods});frames[#frames+1]=f;return f end
function CreateFromMixins(base) local t={};for k,v in pairs(base) do t[k]=v end;return t end
MapCanvasPinMixin={OnReleased=function()end,UseFrameLevelType=function(self,layer)self.layer=layer end,SetScalingLimits=function()end,SetPosition=function(self,x,y)self.x=x;self.y=y end}
MapCanvasDataProviderMixin={GetMap=function(self)return self.map end}
WorldMapFrame=CreateFrame(); WorldMapFrame.pins={}; WorldMapFrame.mapID=2521
function WorldMapFrame:GetMapID()return self.mapID end
function WorldMapFrame:RemoveAllPinsByTemplate(template)
 local keep={};for _,p in ipairs(self.pins)do if p.template~=template then keep[#keep+1]=p end end;self.pins=keep
end
function WorldMapFrame:AddDataProvider(p)self.provider=p;p.map=self end
function WorldMapFrame:AcquirePin(template,g)
 assert(template=='QuestRadarPinTemplate' or template=='QuestRadarServicePinTemplate')
 local p=CreateFromMixins(template=='QuestRadarPinTemplate' and QuestRadarPinMixin or QuestRadarServicePinMixin);p.template=template;p.Texture=CreateFrame();p:OnLoad();p:OnAcquired(g)
 assert(p.layer=="PIN_FRAME_LEVEL_QUEST_OFFER", "Quest pins must render above map overlays")
 self.pins[#self.pins+1]=p
end
function UnitFactionGroup()return 'Horde'end
function UnitLevel()return 8 end
function UnitClass()return 'Druid','DRUID',11 end
function UnitRace()return 'Skyborne','Skyborne',85 end
function UnitGUID()return 'Creature-0-123-2521-1-249350-ABC123'end
function strsplit(delim,s) local t={};for v in s:gmatch('[^'..delim..']+')do t[#t+1]=v end;return unpack(t)end
function GetTime()return now end
function time()return 1000 end
function GetBuildInfo()return '1.60.1'end
function GetLocale()return 'ruRU'end
function IsShiftKeyDown()return true end
function print()end
C_Timer={After=function(delay,fn)timers[#timers+1]={at=now+delay,fn=fn}end}
function advance(seconds)
 now=now+seconds
 local old=timers;timers={}
 for _,t in ipairs(old)do if t.at<=now then t.fn()else timers[#timers+1]=t end end
end
C_QuestLog={GetAllCompletedQuestIDs=function()return completed end,IsOnQuest=function(id)return active[id] or false end}
C_Map={GetBestMapForUnit=function()return 2521 end,GetPlayerMapPosition=function()return {GetXY=function()return .5,.5 end}end}
C_GossipInfo={GetAvailableQuests=function()return {{questID=123,title='Offer'}}end}
ns.Quests={{id=123,points={{2521,.5,.5}},qgs={249350},uncertain={'special-condition'},constraints={{lvl=2}},start='npc'}}
''')
for f in ['Rules.lua','Map.lua']:
 lua.globals().loadAddon((root/'QuestRadar'/f).read_text())
lua.execute(r'''
local driver=frames[2]
driver:OnEvent('PLAYER_LOGIN')
assert(#WorldMapFrame.pins==1 and WorldMapFrame.pins[1].Texture.atlas=='QuestNormal' and WorldMapFrame.pins[1].Texture.desaturated)
ns.ToggleUncertain();assert(#WorldMapFrame.pins==0)
driver:OnEvent('GOSSIP_SHOW');advance(.3)
assert(#WorldMapFrame.pins==1 and WorldMapFrame.pins[1].entries[1].status=='confirmed')
assert(QuestRadarObservations[1].npcID==249350 and QuestRadarObservations[1].race==85)
advance(61);advance(.3);assert(#WorldMapFrame.pins==0)
ns.ToggleUncertain()
driver:OnEvent('GOSSIP_SHOW');active[123]=true;driver:OnEvent('QUEST_ACCEPTED');advance(.3)
assert(#WorldMapFrame.pins==0)
active[123]=nil;completed={123};driver:OnEvent('QUEST_TURNED_IN');advance(.3)
assert(#WorldMapFrame.pins==0)
completed={};driver:OnEvent('QUEST_LOG_UPDATE');advance(.3);assert(#WorldMapFrame.pins==1)
WorldMapFrame.mapID=1458;WorldMapFrame.provider:RefreshAllData();assert(#WorldMapFrame.pins==0)
WorldMapFrame.mapID=2521;ns.Toggle();assert(#WorldMapFrame.pins==0)
ns.Toggle();assert(#WorldMapFrame.pins==1)
for i=1,205 do driver:OnEvent('GOSSIP_SHOW')end
assert(#QuestRadarObservations==200)
''')
print('PASS: map lifecycle, toggles, NPC GUID, expiry, accept/turn-in and bounded observations; XML parsed')

lua.execute(r'''
local driver=frames[2]
ns.DataInfo={revision='test-revision'}
driver:OnEvent('QUEST_ACCEPTED',123)
driver:OnEvent('QUEST_ACCEPTED',0)
driver:OnEvent('QUEST_ACCEPTED','456')
assert(QuestRadarUnknownQuests==nil)
C_GossipInfo.GetAvailableQuests=function()return {{questID=456,title='Unknown offer'}}end
driver:OnEvent('GOSSIP_SHOW')
assert(QuestRadarUnknownQuests==nil)
driver:OnEvent('QUEST_ACCEPTED',456)
local entry=QuestRadarUnknownQuests[456]
assert(entry.title=='Unknown offer' and entry.offeredByNPC==249350)
assert(entry.mapID==2521 and entry.x==.5 and entry.y==.5)
assert(entry.level==8 and entry.class==11 and entry.race==85 and entry.faction==1)
assert(entry.dataRevision=='test-revision' and entry.client=='1.60.1')
assert(ns.ByID[456]==nil)
driver:OnEvent('QUEST_REMOVED',456)
driver:OnEvent('QUEST_ACCEPTED',456)
assert(QuestRadarUnknownQuests[456]==entry)
local oldMap,oldGUID=C_Map,UnitGUID
C_Map=nil;UnitGUID=function()return nil end
local requested
C_QuestLog.RequestLoadQuestByID=function(id)requested=id end
driver:OnEvent('QUEST_ACCEPTED',789)
local item=QuestRadarUnknownQuests[789]
assert(item and item.mapID==nil and item.offeredByNPC==nil and requested==789)
C_QuestLog.GetTitleForQuestID=function()return 'Loaded title' end
driver:OnEvent('QUEST_DATA_LOAD_RESULT',789,false)
assert(item.title==nil)
driver:OnEvent('QUEST_DATA_LOAD_RESULT',789,true)
assert(item.title=='Loaded title')
driver:OnEvent('PLAYER_LOGIN')
assert(QuestRadarUnknownQuests[456]==entry and QuestRadarUnknownQuests[789]==item)
C_Map=oldMap;UnitGUID=oldGUID
C_QuestLog.RequestLoadQuestByID=nil;C_QuestLog.GetTitleForQuestID=nil
''')
print('PASS: unknown acceptances, deduplication, missing NPC/map, async title, retained data on login')

lua.execute("""
Settings={RegisterCanvasLayoutCategory=function(p)optionsPanel=p;return {GetID=function()return 77 end}end,
RegisterAddOnCategory=function()end,OpenToCategory=function(id)openedCategory=id end}
ns.ShowReport=function()reportOpened=true end
ns.ShowBugReport=function(marker)bugOpened=true;reportedMarker=marker end
""")
lua.globals().loadAddon((root/'QuestRadar/Settings.lua').read_text())
lua.execute("""
ns.OpenSettings();assert(openedCategory==77)
optionsPanel:OnShow()
local checked=0
for _,f in ipairs(frames)do
 if f.Text.text=='Показывать отметки QuestRadar на карте' then
  assert(f:GetChecked()==QuestRadarSettings.enabled)
  f:SetChecked(false);f:OnClick();assert(QuestRadarSettings.enabled==false and #WorldMapFrame.pins==0)
  checked=checked+1
 elseif f.Text.text=='Показывать задания с неуточнёнными условиями (серые !)' then
  f:SetChecked(false);f:OnClick();assert(QuestRadarSettings.uncertain==false)
  checked=checked+1
 elseif f.Text.text=='Показывать учителей и городские службы' then
  assert(f:GetChecked()==true);f:SetChecked(false);f:OnClick();assert(QuestRadarSettings.services==false);checked=checked+1
 elseif f.Text.text=='Показывать обычных торговцев' then
  assert(f:GetChecked()==true);f:SetChecked(false);f:OnClick();assert(QuestRadarSettings.vendors==false);checked=checked+1
 elseif f.text=='Выгрузить отчёт' then f:OnClick();assert(reportOpened);checked=checked+1
 elseif f.text=='Сообщить об ошибке' then f:OnClick();assert(bugOpened);checked=checked+1 end
end
assert(checked==6)
""")
print('PASS: settings category opens, both checkboxes apply to map, report button opens report')

lua.execute(r'''
GameTooltip={lines={},SetOwner=function(self,p)self.owner=p;self.lines={}end,
AddLine=function(self,t)self.lines[#self.lines+1]=t end,Show=function()end,
Hide=function()end,IsOwned=function(self,p)return self.owner==p end}
local requests=0
C_QuestLog.GetTitleForQuestID=function()return "Тестовое задание" end
C_QuestLog.GetQuestDifficultyLevel=function()return 19 end
C_QuestLog.RequestLoadQuestByID=function()requests=requests+1 end
local q={id=777,start='npc',constraints={{lvl=10},{lvl=15}},uncertain={},minimumLevelKnown=true}
local pin=CreateFromMixins(QuestRadarPinMixin)
pin.entries={{quest=q,status='calculated',reason=''}}
pin:OnMouseEnter()
assert(GameTooltip.lines[1]=='[19] Тестовое задание')
assert(#GameTooltip.lines==1)
C_QuestLog.GetQuestDifficultyLevel=function()return nil end
q.minimumLevelKnown=false;pin.entries[1].status='uncertain'
ns.PinTooltip(pin)
assert(GameTooltip.lines[1]=='[?] Тестовое задание')
assert(GameTooltip.lines[2]=='Условия открытия неизвестны')
assert(#GameTooltip.lines==2 and requests==1)
C_QuestLog.GetQuestDifficultyLevel=function()return 20 end
frames[2]:OnEvent('QUEST_DATA_LOAD_RESULT',777,true)
assert(GameTooltip.lines[1]=='[20] Тестовое задание' and requests==1)
''')
print('PASS: native compact tooltip hides ID/minimum/debug text, handles unknown difficulty and updates without repeat requests')

lua.execute(r'''
ns.Services={
 {id=1,name='Smith',nameRU='Кузнец',role='Кузнечное дело',faction='H',categories={'professionTrainer'},points={{2521,.2,.3}}},
 {id=2,name='Banker',faction='A',categories={'banker'},points={{2521,.4,.5}}},
 {id=3,name='Wrong class',faction='H',classID=1,categories={'classTrainer'},points={{2521,.6,.7}}},
 {id=4,name='My trainer',faction='H',classID=11,categories={'classTrainer'},points={{2521,.7,.8}}},
 {id=5,name='Shop',faction='H',categories={'vendor'},points={{2521,.8,.9}}},
}
Enum={MinimapTrackingFilter={TrainerProfession=128,TrainerClass=8388608,Banker=2,VendorReagent=256}}
C_Texture={GetAtlasInfo=function(name)return ({profession=true,class=true,banker=true})[name] end}
local ids={128,8388608,2,256}
C_Minimap={GetNumTrackingTypes=function()return #ids end,
 GetTrackingFilter=function(i)return {filterID=ids[i]}end,
 GetTrackingInfo=function(i)return {texture=1000+i,active=false}end}
''')
lua.globals().loadAddon((root/'QuestRadar/Services.lua').read_text())
lua.execute(r'''
ns.InitServicePins()
QuestRadarSettings.enabled=true;QuestRadarSettings.services=true;QuestRadarSettings.vendors=true;QuestRadarSettings.uncertain=true
ns.Refresh()
assert(ns.LastServiceReport.points==3)
local service
for _,p in ipairs(WorldMapFrame.pins)do
 if p.template=='QuestRadarServicePinTemplate' and p.x==.2 then service=p end
end
assert(service.Texture.atlas=='profession', 'Use the client map atlas, independent of tracking-menu textures')
for _,p in ipairs(WorldMapFrame.pins)do
 if p.template=='QuestRadarServicePinTemplate' and p.x==.8 then
  assert(p.Texture.texture=='Interface\\Cursor\\Buy', 'Generic vendors must not use the reagent icon')
 end
end
service:OnMouseEnter()
assert(GameTooltip.lines[1]=='Кузнец' and GameTooltip.lines[2]=='Учитель кузнечного дела')
service.GetMap=function()return WorldMapFrame end
service:OnMouseUpAction('LeftButton')
assert(reportedMarker.ids[1]==1 and reportedMarker.mapID==2521 and reportedMarker.x==.2)
QuestRadarSettings.vendors=false;ns.Refresh();assert(ns.LastServiceReport.points==2)
QuestRadarSettings.services=false;ns.Refresh();assert(ns.LastServiceReport.points==0 and #WorldMapFrame.pins==1)
QuestRadarSettings.services=true
WorldMapFrame.mapID=1458;ns.Refresh();assert(#WorldMapFrame.pins==0)
WorldMapFrame.mapID=2521
C_Minimap=nil;ns.ResetServiceTextures();ns.Refresh()
assert(ns.LastServiceReport.points==2, "Map icons do not depend on minimap tracking filters")
C_Texture=nil;ns.ResetServiceTextures();ns.Refresh()
assert(ns.LastServiceReport.points==0 and ns.LastServiceReport.missingIcons.professionTrainer)
C_Texture={GetAtlasInfo=function()error('atlas failed')end}
ns.ResetServiceTextures();ns.Refresh()
assert(ns.LastServiceReport.iconAPIError:find('atlas failed',1,true))
''')
print('PASS: native service icons, exact trainer tooltip, faction/class filtering, layer toggles and missing API')
