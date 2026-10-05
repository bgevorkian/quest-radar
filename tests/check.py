"""Exercise asynchronous scan handling with a mocked WoW API; no game access."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
frames, timers, SlashCmdList, UISpecialFrames = {}, {}, {}, {}
local methods = {}
function methods:SetScript(event, fn) self[event] = fn end
function methods:GetFrameLevel() return 1 end
function methods:SetSize(w,h)self.width=w;self.height=h end
function methods:SetScale(s)self.scale=s end
function methods:GetWidth()return rawget(self,"width") or 160 end
function methods:GetHeight()return rawget(self,"height") or 160 end
function methods:GetCenter()return 100,100 end
function methods:GetEffectiveScale()return 0.5 end
function methods:SetPoint(...)self.point={...}end
function GetCursorPosition()return cursorX or 50,cursorY or 50 end
function methods:IsShown() return true end
function methods:GetMapID() return 42 end
function methods:SetText(text) self.text = text end
function methods:GetText()return self.text or '' end
function methods:SetChecked(value)self.checked=value end
function methods:GetChecked()return self.checked end
function methods:Show()self.shown=true end
function methods:Hide()self.shown=false end
local mt = {__index = function(_, key) return methods[key] or function() end end}
function CreateFrame(_, name)
    local f = setmetatable({}, mt)
    f.TitleText = setmetatable({}, mt)
    f.Text = setmetatable({}, mt)
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
function methods:CreateTexture() return setmetatable({}, mt) end
function methods:CreateFontString()return setmetatable({},mt)end
Minimap, WorldMapFrame = CreateFrame(), CreateFrame()
UIParent = {}; ChatFontNormal = {}; GameTooltip = CreateFrame()
function GetTime() return 100 end
function date() return 'test-date' end
function GetBuildInfo() return '1.60.1', 'test', 'date', 16001 end
function GetLocale() return 'ruRU' end
function UnitLevel() return 10 end
function UnitRace() return 'Race', 'Race' end
function UnitClass() return 'Mage', 'MAGE' end
function UnitFactionGroup() return 'Horde' end
function UnitName() return 'Test NPC' end
function UnitGUID() return 'Creature-test' end
function GetQuestID() return 92460 end
function GetTitleText() return 'Test quest' end
function strtrim(s) return s:match('^%s*(.-)%s*$') end
function print() end
C_Timer = {After = function(_, fn) timers[#timers + 1] = fn end}
C_Map = {GetBestMapForUnit = function() return 43 end, GetMapInfo = function(id) return {mapID=id} end}
C_QuestLog = {IsOnQuest = function() return false end, IsQuestFlaggedCompleted = function() return false end}
offers = {{questID=92460, x=0.25, y=0.75, inProgress=false}}
requests = 0
C_QuestLine = {
    GetAvailableQuestLines = function() return offers end,
    RequestQuestLinesForMap = function() requests = requests + 1 end,
}
C_GossipInfo = {GetAvailableQuests = function() return {{questID=92460}} end}
''')
source = (Path(__file__).parents[1] / 'QuestRadar/QuestRadar.lua').read_text()
lua.execute('ns={OpenSettings=function() settingsOpened=true end,GetSettings=function()QuestRadarSettings=QuestRadarSettings or {};return QuestRadarSettings end};assert(loadstring(...))("QuestRadar",ns)', source)
lua.execute(r'''
SlashCmdList.QUESTRADAR('scan')
assert(QuestRadarDB.mapID == 42)
assert(requests == 1)
assert(QuestRadarDB.samples[1].offers:find('92460'))
offers[1].questID = 999
assert(not QuestRadarDB.samples[1].offers:find('999')) -- immutable baseline
local firstTimers = timers
timers = {}
SlashCmdList.QUESTRADAR('55')
for _, fn in ipairs(firstTimers) do fn() end -- obsolete callbacks ignored
assert(#QuestRadarDB.samples == 1 and QuestRadarDB.mapID == 55)
for _, fn in ipairs(timers) do fn() end
assert(#QuestRadarDB.samples == 4)
local receiver = frames[4] -- GameTooltip is frame 3; addon event frame is 4
receiver:OnEvent('GOSSIP_SHOW')
assert(QuestRadarDB.samples[5].reason == 'GOSSIP_SHOW')
for i=1,30 do receiver:OnEvent('GOSSIP_SHOW') end
assert(#QuestRadarDB.samples == 20)
C_QuestLine.GetAvailableQuestLines = nil
SlashCmdList.QUESTRADAR('scan')
assert(QuestRadarDB.samples[1].offers:find('missing'))
C_QuestLine.GetAvailableQuestLines = function() error('test failure') end
SlashCmdList.QUESTRADAR('scan')
assert(QuestRadarDB.samples[1].offers:find('test failure'))
C_QuestLine.GetAvailableQuestLines = function() return {} end
SlashCmdList.QUESTRADAR('scan')
assert(QuestRadarDB.samples[1].offers:find('ok'))
for i=1,10 do receiver:OnEvent('QUESTLINE_UPDATE', true) end
assert(#QuestRadarDB.samples <= 20)
QuestRadar_OpenSettings();assert(settingsOpened)
assert(QuestRadarButton==nil)
SlashCmdList.QUESTRADAR('clear')
assert(QuestRadarDB == nil)
for _, fn in ipairs(timers) do fn() end
assert(QuestRadarDB == nil)
''')
print('PASS: Lua 5.1 load, immutable snapshots, map selection, stale timers, NPC capture, bounded storage, missing/error/empty API, report UI and clear')

lua.execute(r'''
function time()return 1000 end
function strsplit(delim,s)local out={};for part in s:gmatch('[^'..delim..']+')do out[#out+1]=part end;return unpack(out)end
function UnitGUID(unit)if unit=='npc' then return 'Creature-0-1-2-3-999-ABC' else return 'Player-1-123' end end
C_Map.GetMapInfo=function()return {name='Тестовая локация'}end
px,py=.25,.75
C_Map.GetPlayerMapPosition=function()return {GetXY=function()return px,py end}end
Enum={PlayerInteractionType={Merchant=5,Trainer=7}}
function CanMerchantRepair()return true end
ns.ServiceByID={}
''')
feedback=(Path(__file__).parents[1]/'QuestRadar/Feedback.lua').read_text()
lua.execute('assert(loadstring(...))("QuestRadar",ns)',feedback)
lua.execute(r'''
local receiver=frames[#frames]
receiver:OnEvent('PLAYER_INTERACTION_MANAGER_FRAME_SHOW',5)
assert(QuestRadarServiceObservations['999:vendor'].inDatabase==false)
assert(QuestRadarServiceObservations['999:repair'].npc.id==999)
receiver:OnEvent('PLAYER_INTERACTION_MANAGER_FRAME_SHOW',5)
local count=0;for _ in pairs(QuestRadarServiceObservations)do count=count+1 end;assert(count==2)
local originalGUID=UnitGUID
UnitGUID=function()return 'Player-1-123'end
receiver:OnEvent('PLAYER_INTERACTION_MANAGER_FRAME_SHOW',7)
assert(QuestRadarServiceObservations['999:trainer']==nil)
assert(ns.CaptureReportContext().npc==nil)
UnitGUID=originalGUID
ns.ShowBugReport()
px,py=.8,.9 -- user moved while the form was open
local save
for _,f in ipairs(frames)do if f.text=='Сохранить и открыть отчёт' then save=f end end
assert(save);save:OnClick()
assert(#QuestRadarBugReports==1 and QuestRadarBugReports[1].description=='')
assert(QuestRadarBugReports[1].kind=='missing')
assert(QuestRadarBugReports[1].context.x==.25 and QuestRadarBugReports[1].context.y==.75)
assert(QuestRadarBugReports[1].context.npc.id==999)
local exported
for _,f in ipairs(frames)do if type(f.text)=='string' and f.text:find('serviceObservations',1,true) then exported=f.text end end
assert(exported and exported:find('bugs',1,true) and exported:find('999',1,true))
assert(ns.SaveBugReport('invalid','',{})==nil)
SlashCmdList.QUESTRADAR('clear')
assert(#QuestRadarBugReports==1 and QuestRadarServiceObservations['999:repair'])
-- SavedVariables survive loading the module again.
''')
lua.execute('assert(loadstring(...))("QuestRadar",ns)',feedback)
lua.execute('assert(#QuestRadarBugReports==1 and QuestRadarServiceObservations["999:repair"])')
print('PASS: service observations, no player identity, empty-comment bug report, frozen location, copyable export and reload retention')

toc=(Path(__file__).parents[1]/'QuestRadar/QuestRadar.toc').read_text()
assert '## AddonCompartmentFunc: QuestRadar_OpenSettings' in toc
assert '## IconAtlas: QuestNormal' in toc
print('PASS: native addon menu callback opens settings; standalone minimap button absent')
