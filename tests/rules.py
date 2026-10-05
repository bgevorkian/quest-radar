from pathlib import Path
from lupa.lua51 import LuaRuntime
root=Path(__file__).parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('ns={}; function loadAddon(s) assert(loadstring(s))("QuestRadar",ns) end')
lua.globals().loadAddon((root/'QuestRadar/Data.lua').read_text())
lua.globals().loadAddon((root/'QuestRadar/Rules.lua').read_text())
lua.execute('''
local completed,active,skills,reps={},{},{},{}
local ctx={level=8,class=11,race=85,faction=1,
 completed=function(id)return completed[id] or false end,
 onQuest=function(id)return active[id] or false end,
 skill=function(id)return skills[id] or 0 end,
 reputation=function(id)return reps[id] end}
local function quest(id) assert(ns.ByID[id],id);return ns.ByID[id][1] end
local function result(id) return ns.Evaluate(quest(id),ctx) end
-- Real ATT druid chain: must finish 92461; level/class gates apply.
assert(result(92485)=='hidden')
completed[92461]=true
assert(result(92485)=='calculated')
ctx.class=1;assert(result(92485)=='hidden');ctx.class=11
ctx.level=1;assert(result(92485)=='hidden');ctx.level=8
active[92485]=true;assert(result(92485)=='hidden');active[92485]=nil
completed[92485]=true;assert(result(92485)=='hidden');completed[92485]=nil
-- Missing predecessors do not block calculated availability; this is not NPC confirmation.
assert(result(92460)=='calculated') -- reviewed starter correction
completed[92460]=true
assert(result(92462)=='calculated') -- level-1 quest after starter
active[92462]=true;assert(result(92462)=='hidden');active[92462]=nil
completed[92460]=nil;assert(result(92462)=='hidden')
assert(quest(94490).start=='item' and quest(94490).providers[1][2]==265476)
assert(result(92465)=='calculated') -- level-unlocked offer, not NPC confirmation
ctx.level=1;assert(result(92465)=='hidden');ctx.level=8
assert(result(94490)=='hidden') -- item starter requires level 9
ctx.level=9;assert(result(94490)=='uncertain');ctx.level=8
-- Mutually exclusive faction starters should not demand both factions.
completed[92514]=true
assert(result(92517)=='calculated')
assert(result(93951)=='calculated')
completed[92514]=nil;assert(result(93951)=='hidden')
-- AND prerequisites cannot pass after only one completion.
completed[92642]=true;assert(result(92880)=='hidden')
completed[92645]=true;assert(result(92880)=='calculated')
-- Pure fixtures for profession/reputation/recurring/unknown state.
local q={id=123,points={},qgs={},uncertain={},constraints={{lvl=2,requireSkill=333,minReputation={1,3000}}}}
assert(ns.Evaluate(q,ctx)=='hidden')
skills[333]=1;assert(ns.Evaluate(q,ctx)=='uncertain')
reps[1]=2000;assert(ns.Evaluate(q,ctx)=='hidden')
reps[1]=3000;assert(ns.Evaluate(q,ctx)=='calculated')
q.constraints[1].repeatable=true;completed[123]=true;assert(ns.Evaluate(q,ctx)=='uncertain')
q.constraints[1].u=1;assert(ns.Evaluate(q,ctx)=='hidden')
q.constraints={{lvl=2}};q.uncertain={};ctx.completed=function()return nil end
assert(ns.Evaluate(q,ctx)=='uncertain')
assert(ns.ByMap[2521] and ns.ByMap[1458] and ns.ByMap[1411])
assert(ns.ByID[93463]==nil) -- hidden trigger must not become an offer
''')
print('PASS: real ATT class/faction/AND/OR chains; active/completed, professions, reputation, unknown state, repeatable, hidden and multiple maps')
