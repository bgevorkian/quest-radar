"""Build town-service data from MIT-licensed WaypointTracker/pfQuest and ATT.
Run: python3 tools/import_services.py. Upstream checkouts are read-only inputs.
"""
from pathlib import Path
import collections
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
WT = ROOT / 'upstream/WaypointTracker'
ATT = ROOT / 'upstream/AllTheThings'
CATEGORIES = {'auctioneer','banker','battlemaster','flight','innkeeper','mailbox','repair','stablemaster','vendor','trainer'}
CLASSES = {'Warrior':1,'Paladin':2,'Hunter':3,'Rogue':4,'Priest':5,'Shaman':7,'Mage':8,'Warlock':9,'Druid':11}
PROFESSIONS = {
    'Alchemy':'Алхимия', 'Alchemist':'Алхимия', 'Blacksmith':'Кузнечное дело',
    'Enchanting':'Наложение чар','Enchanter':'Наложение чар','Engineering':'Инженерное дело',
    'Engineer':'Инженерное дело','Herbalism':'Травничество','Herbalist':'Травничество',
    'Leatherworking':'Кожевничество','Leatherworker':'Кожевничество','Mining':'Горное дело',
    'Miner':'Горное дело','Skinning':'Снятие шкур','Skinner':'Снятие шкур',
    'Tailoring':'Портняжное дело','Tailor':'Портняжное дело','Cooking':'Кулинария',
    'Cook':'Кулинария','Fishing':'Рыбная ловля','Fisherman':'Рыбная ловля',
    'First Aid':'Первая помощь','Riding':'Верховая езда',
}

def block(path, key):
    text = path.read_text()
    match = re.search(r'\b'+re.escape(key)+r'\s*=\s*\[==\[\n(.*?)\]==\]',text,re.S)
    if not match: raise ValueError(f'Missing data block {path}: {key}')
    return [line.split('\t') for line in match[1].splitlines() if line]

def trainer_role(title):
    for name, ident in CLASSES.items():
        if re.search(r'\b'+name+r' Trainer\b',title):
            return {'category':'classTrainer','classID':ident,'role':name+' Trainer'}
    for name, ru in PROFESSIONS.items():
        if name in title and ('Trainer' in title or re.search(r'\b(Apprentice|Journeyman|Expert|Artisan|Master)\b',title)):
            return {'category':'professionTrainer','role':ru}
    for key,ru in {'Pet Trainer':'Дрессировщик питомцев','Demon Trainer':'Учитель демонов','Weapon Master':'Мастер оружия','Portal Trainer':'Учитель порталов'}.items():
        if key in title:return {'category':'trainer','role':ru}
    return None

def points(text):
    out=[]
    for group in text.split(';'):
        if not group: continue
        map_id, coords=group.split(':')
        values=[int(v)/1000 for v in coords.split(',')]
        assert len(values)%2==0
        out.extend([int(map_id),x,y] for x,y in zip(values[::2],values[1::2]) if 0<=x<=1 and 0<=y<=1)
    return out

def lua(value):
    if isinstance(value,str): return json.dumps(value,ensure_ascii=False)
    if isinstance(value,(int,float)): return str(value)
    if isinstance(value,list): return '{'+','.join(lua(v) for v in value)+'}'
    if isinstance(value,dict): return '{'+','.join('['+lua(k)+']='+lua(v) for k,v in sorted(value.items()))+'}'
    raise TypeError(value)

def build():
    geometry=json.loads((ROOT/'data/service-map-geometry.json').read_text())
    frames={m['area_id']:m for m in geometry['maps']}
    entities={}
    base=WT/'WaypointTracker_Data'
    names={loc:{kind:{int(f[0]):f[1] for f in block(base/f'Names_{loc}.lua',kind)} for kind in ('units','objects')} for loc in ('enUS','ruRU')}
    for kind,coord_col,fac_col,sign in [('units',4,2,1),('objects',2,1,-1)]:
        for f in block(base/'Data.lua',kind):
            ident=int(f[0]); mapped=[]
            for area,x,y in points(f[coord_col]):
                m=frames.get(area)
                if not m: continue # no invented routing for instances or unknown maps
                c=m['coefficients']
                x=x*c['scale_x']+c['offset_x']/100
                y=y*c['scale_y']+c['offset_y']/100
                if 0<=x<=1 and 0<=y<=1:mapped.append([m['ui_map_id'],round(x,6),round(y,6)])
            entities[sign*ident]={'id':sign*ident,'name':names['enUS'][kind].get(ident,''),'nameRU':names['ruRU'][kind].get(ident,''),'faction':f[fac_col],'points':mapped,'categories':set(),'source':'classic-reprojected'}
    for f in block(base/'Data.lua','services'):
        if f[0] not in CATEGORIES:continue
        for ident,fac in re.findall(r'(-?\d+):([AH]*)',f[1]):
            e=entities.get(int(ident))
            if e:e['categories'].add(f[0]);e['faction']=fac or e['faction']
    # ATT comments explicitly name trainer roles. Only NPC references are read;
    # never infer the role from a quest title or use quest objective coordinates.
    role_sources={}
    for folder in [ATT/'.contrib/.db/standard/02 - Outdoor Zones',ATT/'.contrib/.db/forever/zones']:
        for path in sorted(folder.rglob('*.lua')):
            for line in path.read_text().splitlines():
                match=re.search(r'(?:\bn\((\d+),|\["qg"\]\s*=\s*(\d+),|^\s*(\d+),)\s*(?:\{\s*)?--\s*[^<]+<([^>]+)>',line)
                if not match:continue
                ident=int(next(x for x in match.groups()[:3] if x)); role=trainer_role(match[4])
                if role and ident in entities:
                    entities[ident].update(role)
                    entities[ident]['categories'].add(role['category'])
                    role_sources[str(ident)]=str(path.relative_to(ATT))
    # Forever observations replace the old points on each observed map.
    for filename,key,source in [('Curated.lua','curated','att-forever'),('Forever.lua','forever','community-forever')]:
        for f in block(base/filename,key):
            if f[0]=='N':
                f+=['']*(9-len(f));ident=int(f[1])
                e=entities.setdefault(ident,{'id':ident,'name':f[2],'nameRU':'','faction':f[7],'points':[],'categories':set(),'source':source})
                pts=points(f[6])
                maps={p[0] for p in pts}
                if pts:e['points']=[p for p in e['points'] if p[0] not in maps]+pts;e['source']=source
                if f[7]:e['faction']=f[7]
                if f[3]=='1':e['faction']='hostile'
                e['categories'].update(set(f[5].split(',')) & CATEGORIES)
                role=trainer_role(f[8])
                if role:e.update(role);e['categories'].add(role['category'])
            elif f[0]=='M':
                for n,p in enumerate(points(f[1])):
                    ident=-10000000-n
                    entities[ident]={'id':ident,'name':'Mailbox','nameRU':'Почтовый ящик','faction':'','points':[p],'categories':{'mailbox'},'source':source}
            elif f[0]=='C':
                f+=['']*(5-len(f));ident=int(f[2])*(1 if f[1]=='N' else -1);e=entities.get(ident)
                if not e:continue
                for m,x,y in points(f[3]):e['points']=[p for p in e['points'] if not(p[0]==m and abs(p[1]-x)<=.02 and abs(p[2]-y)<=.02)]
                e['points']+=points(f[4]);e['source']=source
    # The quest importer preserves ATT's explicit Vendors headers. Use only
    # outdoor zones and existing WaypointTracker positions, never item coords.
    tree=json.loads((ROOT/'research/att-category-tree.json').read_text())
    vendor_ids=set()
    def collect_vendors(node, vendor=False):
        if isinstance(node,dict):
            vendor=vendor or (node.get('_kind')=='CreateCustomHeader' and node.get('_id')==-58)
            if vendor and node.get('_kind')=='CreateNPC':vendor_ids.add(node['_id'])
            for value in node.values():collect_vendors(value,vendor)
        elif isinstance(node,list):
            for value in node:collect_vendors(value,vendor)
    collect_vendors(tree['Zones'])
    for ident in vendor_ids:
        if ident in entities:entities[ident]['categories'].add('vendor')
    corrections=json.loads((ROOT/'data/service-corrections.json').read_text())
    for fix in corrections['entries']:
        ident=fix['id']
        e=entities.setdefault(ident,{'id':ident,'points':[]})
        for key in ('name','nameRU','faction','classID','role','points'):
            if key in fix:e[key]=fix[key]
        e['categories']=set(fix['categories'])
        e['source']='documented-correction'
    records=[]
    for e in entities.values():
        if not e['categories'] or not e['points'] or e['faction']=='hostile':continue
        if 'classTrainer' in e['categories'] or 'professionTrainer' in e['categories']:e['categories'].discard('trainer')
        # Repair vendors keep their useful specific category, without a duplicate shop pin.
        if len(e['categories'])>1:e['categories'].discard('vendor')
        e.pop('category',None)
        e['categories']=sorted(e['categories'])
        e['points']=[list(p) for p in sorted(set(tuple(p) for p in e['points']))]
        records.append(e)
    records.sort(key=lambda e:e['id'])
    revisions={name:subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True).strip() for name,path in [('WaypointTracker',WT),('ATT',ATT)]}
    counts=collections.Counter(c for e in records for c in e['categories'])
    summary={'revisions':revisions,'entities':len(records),'points':sum(len(e['points']) for e in records),'maps':len({p[0] for e in records for p in e['points']}),'categories':dict(sorted(counts.items())),'trainerRoleSources':role_sources,'geometrySource':geometry['source'],'limitations':'Classic-derived locations are reprojected, not verified against server spawns. ATT role comments do not cover every trainer. Community observations take precedence on their maps.'}
    summary['correctionsFile']='data/service-corrections.json'
    summary['correctionsCount']=len(corrections['entries'])
    assert counts['classTrainer'] and counts['professionTrainer'] and counts['banker']
    (ROOT/'QuestRadar/ServiceData.lua').write_text('-- Generated by tools/import_services.py. See LICENSE-Services.txt.\nlocal _, ns = ...\nns.ServiceDataInfo = '+lua({k:summary[k] for k in ['revisions','entities','points','maps','categories']})+'\nns.Services = {\n'+''.join(lua(e)+',\n' for e in records)+'}\n')
    (ROOT/'research/service-import-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'QuestRadar/LICENSE-Services.txt').write_text('Service data sources: Waypoint Tracker, pfQuest and AllTheThings.\nhttps://github.com/sanjaygbhat/wowforever-waypoint-tracker\nhttps://github.com/shagu/pfQuest\nhttps://github.com/ATTWoWAddon/AllTheThings\n\n'+(WT/'LICENSE').read_text()+'\n'+(base/'THIRD-PARTY-LICENSES.txt').read_text())
    print({k:v for k,v in summary.items() if k not in ['trainerRoleSources','geometrySource','limitations']})

if __name__=='__main__':build()
