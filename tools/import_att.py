"""Import committed ATT Forever category data. Run with: uv run --with lupa python tools/import_att.py"""
from pathlib import Path
import json, re, subprocess, collections, xml.etree.ElementTree as ET
from lupa.lua51 import LuaRuntime, lua_type
from raw_zephras import read_zephras

ROOT = Path(__file__).resolve().parents[1]
ATT = ROOT / 'upstream/AllTheThings'
DB = ATT / 'db/Camelot'
raw_levels={q['questID']:q['lvl'] for q in read_zephras(ATT) if 'lvl' in q}
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
categories = {}
local api = {}
api.AddEventHandler = function(event, fn) assert(event == 'OnBuildDataCache' or event == 'OnBuildHiddenDataCache'); if event == 'OnBuildDataCache' then fn(categories) end end
api.ResolveQuestData = function(t) return t end
api.asset = function(s) return s end
api.OnTooltipDB = setmetatable({}, {__index=function() return function() end end})
api.OnUpdateDB = api.OnTooltipDB
api.Settings = {Get=function() return false end}
api.ClassIndex, api.RaceIndex = -1, -1
setmetatable(api, {__index=function(t, key)
    assert(key:match('^Create'), 'Unsupported ATT API: '..key)
    local fn=function(id, ...)
        local data={}
        for i=1,select('#',...) do local v=select(i,...); if type(v)=='table' then data=v end end
        data._kind=key; data._id=id
        return data
    end
    rawset(t,key,fn);return fn
end})
local env={rawset=rawset, pairs=pairs, ipairs=ipairs, type=type, tonumber=tonumber, tostring=tostring, math=math, string=string, table=table, select=select}
function readCategory(s)
    local fn=assert(loadstring(s)); setfenv(fn,env);fn('ATT',api)
end
''')
files = [n.attrib['file'] for n in ET.parse(DB / 'Database.xml').getroot() if n.attrib.get('file','').startswith('Categories/')]
for name in files:
    lua.globals().readCategory((DB / name).read_text(encoding='utf-8-sig'))
def convert(v):
    if lua_type(v) == 'function': return '<dynamic>'
    if lua_type(v) != 'table': return v
    items = dict(v.items())
    if items and set(items) == set(range(1, len(items)+1)):
        return [convert(items[i]) for i in range(1,len(items)+1)]
    return {str(k):convert(x) for k,x in items.items()}
cats=convert(lua.globals().categories)
(ROOT/'research/att-category-tree.json').write_text(json.dumps(cats,ensure_ascii=False))
print('categories',list(cats))

# Keep acquisition records separate from reward/objective coordinates.
records=[]
keys=collections.Counter()
condition_fields=('c','races','r','requireSkill','minReputation','maxReputation','sourceQuests','sqreq','altQuests','lvl','lc','lockCriteria','isBreadcrumb','repeatable','isDaily','isWeekly','e','u','awp','rwp','OnUpdate','OnInit','isYearly','isMonthly','learnedAt','pvp','sym')
def walk(node, parents, category):
    if isinstance(node,list):
        for child in node: walk(child,parents,category)
        return
    if not isinstance(node,dict): return
    # Faction-specific variants must remain distinct, rather than picking the importer's faction.
    if 'aqd' in node or 'hqd' in node:
        for name,faction in [('aqd',2),('hqd',1)]:
            if name not in node: continue
            merged={k:v for k,v in node.items() if k not in ('aqd','hqd')}
            merged.update(node[name]);merged['r']=faction
            walk(merged,parents,category)
        return
    chain=parents+[node]
    if node.get('_kind')=='CreateQuest':
        qid=int(node['_id']);keys.update(node.keys())
        constraints=[];unknown=[]
        for ancestor in chain:
            c={k:ancestor[k] for k in condition_fields if k in ancestor}
            if c: constraints.append(c)
            if any(k in ancestor for k in ('OnUpdate','OnInit','lc','lockCriteria','isBreadcrumb','e','rwp','sym','pvp')):unknown.append('special-condition')
        if category=='Holidays':unknown.append('holiday')
        if any(a.get('_kind')=='CreatePVPRank' for a in chain):unknown.append('pvp-rank')
        coords=node.get('coords');locationSource='quest'
        if not coords:
            # A parent's position is only meaningful for acquisition when it is the actual giver.
            for ancestor in reversed(parents):
                if ancestor.get('_kind')=='CreateNPC' and ancestor.get('_id') in node.get('qgs',[ancestor.get('_id')]):
                    coords=ancestor.get('coords');locationSource='parent-npc'
                    if coords:break
        points=[]
        for mid,positions in (coords or {}).items():
            if not isinstance(positions,list):continue
            for pos in positions:
                if isinstance(pos,list) and len(pos)>=2 and all(isinstance(v,(int,float)) for v in pos[:2]) and 0<=pos[0]<=100 and 0<=pos[1]<=100:
                    points.append([int(mid),pos[0]/100,pos[1]/100])
        providers=list(node.get('providers',[]))
        # Compiled ATT stores item quest starters in qss, not providers.
        for item in node.get('qss',[]):
            if ['i',item] not in providers:providers.append(['i',item])
        start='npc' if node.get('qgs') else 'unknown'
        if providers:
            types={x[0] for x in providers if isinstance(x,list) and x}
            start='item' if 'i' in types else 'object' if 'o' in types else start
        if start=='unknown':unknown.append('unknown-giver')
        if start=='item':unknown.append('item-start')
        # Restore explicit source levels lost during ATT consolidation where audited.
        if not any('lvl' in c for c in constraints) and qid in raw_levels:
            constraints.append({'lvl':raw_levels[qid]})
        level_known=any('lvl' in c for c in constraints)
        has_unlock=any(any(c.get(k) for k in ('lvl','sourceQuests','requireSkill','minReputation','maxReputation')) for c in constraints)
        if not has_unlock:unknown.append('unlock-not-recorded')
        # A runtime floor of 1 is not evidence that the source recorded a level.
        if not any('lvl' in c for c in constraints):constraints.append({'lvl':1})
        records.append({'minimumLevelKnown':level_known,'id':qid,'points':points,'qgs':node.get('qgs',[]),'providers':providers,'start':start,'constraints':constraints,'uncertain':sorted(set(unknown)),'category':category,'locationSource':locationSource})
    children=node.get('g',[])
    # Inherit restrictions, but never interpret nested reward coordinates as a quest start.
    walk(children,chain,category)
    # Header table constructors can contain anonymous array children.
    for k,v in node.items():
        if k.isdigit():walk(v,chain,category)
for category,tree in sorted(cats.items()):walk(tree,[],category)
# Reviewed corrections live outside upstream and survive database updates.
corrections=json.loads((ROOT/'data/corrections.json').read_text())
for record in records:
    correction=corrections.get(str(record['id']))
    if not correction:continue
    if 'minLevel' in correction and 'unlock-not-recorded' in record['uncertain']:
        record['constraints'].append({'lvl':correction['minLevel']})
        record['minimumLevelKnown']=True
        record['uncertain']=[x for x in record['uncertain'] if x!='unlock-not-recorded']
    record['correctionEvidence']=correction['evidence']
# Deduplicate identical appearances while retaining differing faction/source variants.
records=list({json.dumps(r,sort_keys=True):r for r in records}.values())
records.sort(key=lambda r:(r['id'],json.dumps(r,sort_keys=True)))
revision=subprocess.check_output(['git','-C',str(ATT),'rev-parse','HEAD'],text=True).strip()
def to_lua(v):
    if v is None:return 'nil'
    if isinstance(v,bool):return 'true' if v else 'false'
    if isinstance(v,(int,float)):return str(v)
    if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
    if isinstance(v,list):return '{'+','.join(map(to_lua,v))+'}'
    return '{'+','.join('['+to_lua(k)+']='+to_lua(x) for k,x in sorted(v.items()))+'}'
metadata={'revision':revision,'source':'ATT db/Camelot','questIDs':len({r['id'] for r in records}),'records':len(records),'mappedQuestIDs':len({r['id'] for r in records if r['points']}),'maps':len({p[0] for r in records for p in r['points']})}
(ROOT/'QuestRadar/Data.lua').write_text('-- Generated by tools/import_att.py; ATT MIT license: LICENSE-ATT.txt\nlocal _, ns = ...\nns.DataInfo = '+to_lua(metadata)+'\nns.Quests = {\n'+',\n'.join(to_lua(r) for r in records)+'\n}\n')
(ROOT/'QuestRadar/LICENSE-ATT.txt').write_bytes((ATT/'LICENSE').read_bytes())
(ROOT/'research/import-summary.json').write_text(json.dumps({'metadata':metadata,'fields':dict(keys),'note':'Hidden/unsorted/never-implemented categories excluded. All normal Forever categories included. A coordinate is recorded, not certified live NPC availability.'},indent=2))
print(metadata)
