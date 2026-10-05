"""Validate the shipped service dataset against its manifest and source guarantees."""
from pathlib import Path
import collections
import json
from lupa.lua51 import LuaRuntime

root=Path(__file__).parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('ns={};function loadAddon(s)assert(loadstring(s))("QuestRadar",ns)end')
lua.globals().loadAddon((root/'QuestRadar/ServiceData.lua').read_text())
summary=json.loads((root/'research/service-import-summary.json').read_text())
entries={}
counts=collections.Counter()
point_count=0
maps=set()
for _,e in lua.globals().ns.Services.items():
    assert e.id not in entries and isinstance(e.id,int)
    entries[e.id]=e
    categories=list(e.categories.values())
    assert categories and e.name and e.faction in ('','A','H','AH')
    counts.update(categories)
    if 'classTrainer' in categories: assert e.classID in (1,2,3,4,5,7,8,9,11)
    if 'professionTrainer' in categories: assert e.role
    seen=set()
    for _,p in e.points.items():
        m,x,y=p[1],p[2],p[3]
        assert 0<=x<=1 and 0<=y<=1 and m>0
        assert (m,x,y) not in seen
        seen.add((m,x,y));maps.add(m);point_count+=1
assert len(entries)==summary['entities'] and point_count==summary['points']
assert len(maps)==summary['maps'] and dict(counts)==summary['categories']
assert 1458 in maps and 1453 in maps and 2521 in maps
# Existing classic banker remains routed to Undercity; player-observed new
# Forever trainer is included with the reported class rather than treated as vendor.
assert any(p[1]==1458 for p in entries[4549].points.values())
assert entries[260093].classID==2
assert any(p[1]==1458 and abs(p[2]-.473)<1e-8 for p in entries[260093].points.values())
# The original 4598 location at 56/37.5 is replaced on that map by the Forever sighting.
assert all(abs(p[2]-.559)<1e-8 and abs(p[3]-.369)<1e-8 for p in entries[4598].points.values() if p[1]==1458)
print('PASS: shipped service schema, provenance counts, map coverage, Forever trainer and location overrides')

# Zephras used to contain only generic vendors. Preserve its actual services.
zone=[e for e in entries.values() if any(p[1]==2521 for p in e.points.values())]
assert sum('classTrainer' in list(e.categories.values()) for e in zone)>=17
assert sum('professionTrainer' in list(e.categories.values()) for e in zone)>=24
assert entries[255940].categories[1]=='innkeeper'
assert entries[257020].role=='Наложение чар'
assert len(entries[257020].points)==1 and entries[257020].points[1][2]==.432
assert entries[251905].nameRU=='Зеррил Нежный Ветерок'
assert 'repair' in list(entries[252479].categories.values())
print('PASS: Zephras trainers, innkeepers, repair and corrected NPC roles/locations')

assert entries[256507].nameRU=='Беланн Древо Ветров'
assert list(entries[256507].categories.values())==['repair']
assert entries[256507].faction=='H'
assert entries[256507].points[1][1]==2521 and abs(entries[256507].points[1][2]-.628973)<1e-8
print('PASS: user-observed staff vendor/repair location and conservative faction')
