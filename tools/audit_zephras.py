"""Compare quest acquisition fields in raw Zephras source with our generated import."""
from pathlib import Path
import json,re
from lupa.lua51 import LuaRuntime,lua_type
ROOT=Path(__file__).resolve().parents[1]
ATT=ROOT/'upstream/AllTheThings'
from raw_zephras import read_zephras,conv
quests=read_zephras(ATT)
lua=LuaRuntime();lua.execute('ns={};function read(s)assert(loadstring(s))("QuestRadar",ns)end')
lua.globals().read((ROOT/'QuestRadar/Data.lua').read_text())
records=conv(lua.globals().ns.Quests)
byid={}
for q in records:byid.setdefault(q['id'],[]).append(q)
issues=[];rows=[]
for q in quests:
 id=q['questID']
 if id==93463:
  assert id not in byid,'Hidden trigger imported as an offer'
  continue
 variants=byid.get(id,[])
 if not variants:issues.append({'id':id,'field':'missing quest'});continue
 for out in variants:
  if out['category']!='Zones':continue
  if out['points'] and not any(p[0]==2521 for p in out['points']):continue
  conditions=out['constraints']
  actual={k:v for c in conditions for k,v in c.items()}
  expected={}
  for key in ['lvl','requireSkill','altQuests','repeatable']:
   if key in q:expected[key]=q[key]
  if 'classes' in q:expected['c']=q['classes']
  if 'sourceQuest' in q:expected['sourceQuests']=[q['sourceQuest']]
  if 'sourceQuests' in q:expected['sourceQuests']=q['sourceQuests']
  if 'sourceQuestNumRequired' in q:expected['sqreq']=q['sourceQuestNumRequired']
  if q.get('races')=='HORDE_ONLY':expected['r']=1
  elif q.get('races')=='ALLIANCE_ONLY':expected['r']=2
  elif 'races' in q:expected['races']=q['races']
  for key,value in expected.items():
   got=actual.get(key)
   if key=='lvl':got=max(c.get('lvl',1) for c in conditions)
   equivalent=sorted(got)==sorted(value) if isinstance(got,list) and isinstance(value,list) else got==value
   if not equivalent:issues.append({'id':id,'field':key,'raw':value,'imported':got})
  if 'qg' in q and q['qg'] not in out['qgs']:issues.append({'id':id,'field':'qg'})
  if 'coord' in q:
   x,y,mapname=q['coord'];assert mapname=='ZEPHRAS_ISLE'
   if not any(p[0]==2521 and abs(p[1]-x/100)<1e-8 and abs(p[2]-y/100)<1e-8 for p in out['points']):issues.append({'id':id,'field':'coord'})
  if 'provider' in q and q['provider'] not in list(out['providers']):issues.append({'id':id,'field':'provider','raw':q['provider'],'imported':out['providers']})
  rows.append({'id':id,'uncertain':out['uncertain'],'mapped':bool(out['points'])})
report={'scope':'All ordinary raw Zephras quests; acquisition levels, predecessors, AND/OR, class/race/faction, skills, alternatives, repeatable, giver/provider and coordinates. Does not prove server-side completeness.','rawQuests':len(quests),'checkedRecords':len(rows),'issues':issues,'remainingUncertain': [r for r in rows if r['uncertain']],'withoutCoordinates':[r['id']for r in rows if not r['mapped']]}
(ROOT/'research/zephras-import-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items()if k not in ['scope','remainingUncertain']},ensure_ascii=False))
assert not issues,'Raw/import mismatch; inspect research/zephras-import-audit.json'
