"""Read raw Zephras quest fields for import and audit; execute only data constructors."""
import re
from lupa.lua51 import LuaRuntime,lua_type

def conv(x):
 if lua_type(x)!='table':return x
 d=dict(x.items())
 if d and set(d)==set(range(1,len(d)+1)):return [conv(d[i])for i in range(1,len(d)+1)]
 return {k:conv(v)for k,v in d.items()}

def read_zephras(ATT):
    raw=LuaRuntime(unpack_returned_tuples=True)
    raw.execute('''
    quests={}
    local function node(id,t)return t or {} end
    local env={}
    for _,k in ipairs({'n','i','objective','exploration','faction','recipe','maproot','root'})do env[k]=node end
    env.q=function(id,t)t=t or {};t.questID=id;quests[#quests+1]=t;return t end
    env.bubbleDownClassicRep=function(_,t)return t end
    for _,k in ipairs({'MAP','ROOTS','TIMELINE'})do env[k]=setmetatable({},{__index=function(_,v)return v end})end
    setmetatable(env,{__index=function(_,k)return k end})
    function constant(k,v)env[k]=v end
    function read(s)local f=assert(loadstring(s));setfenv(f,env);f()end
    ''')
    # Read numeric constants from ATT, rather than maintaining copied class/race/skill IDs.
    for name in ['classIDs.lua','raceIDs.lua','professionIDs.lua']:
     text=(ATT/'.contrib/.db/shared/constants'/name).read_text()
     for key,value in re.findall(r'^([A-Z][A-Z_0-9]*)\s*=\s*(\d+)\s*;',text,re.M):
      raw.globals().constant(key,int(value))
    source=ATT/'.contrib/.db/forever/zones/zephras isle.lua'
    raw.globals().read(source.read_text())
    return conv(raw.globals().quests)
