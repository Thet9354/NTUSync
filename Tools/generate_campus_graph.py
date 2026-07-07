import json, math

def hav(a, b):
    R = 6371000.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp = math.radians(b[0]-a[0]); dl = math.radians(b[1]-a[1])
    h = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2*R*math.asin(math.sqrt(h))

# id: (name, lat, lon, elev, indoor)
N = {
 "bldg.hive":          ("The Hive (LHN)",            1.34443, 103.68361, 32, False),
 "bldg.lwn":           ("Lee Wee Nam Library",       1.34775, 103.68183, 40, False),
 "bldg.spms":          ("SPMS",                      1.34228, 103.68240, 30, False),
 "bldg.sbs":           ("SBS",                       1.34570, 103.67950, 36, False),
 "bldg.adm":           ("ADM",                       1.34960, 103.68370, 28, False),
 "bldg.nie":           ("NIE",                       1.34870, 103.67760, 36, False),
 "bldg.wkw":           ("WKWSCI",                    1.34270, 103.67870, 33, False),
 "bldg.northspine":    ("North Spine Plaza",         1.34640, 103.68110, 38, False),
 "bldg.southspine":    ("South Spine",               1.34240, 103.68450, 28, False),
 "bldg.canteen2":      ("Canteen 2",                 1.34395, 103.68490, 22, False),
 "bldg.yunnan":        ("Yunnan Garden",             1.33920, 103.67970, 18, False),
 "hall.1":             ("Hall 1",                    1.34700, 103.68680, 25, False),
 "hall.2":             ("Hall 2",                    1.34540, 103.68720, 22, False),
 "hall.4":             ("Hall 4",                    1.34430, 103.68760, 20, False),
 "hall.6":             ("Hall 6",                    1.34840, 103.68610, 24, False),
 "indoor.lwn-b1":      ("LWN Basement B1",           1.34770, 103.68190, 34, True),
 "indoor.hive-atrium": ("Hive Atrium",               1.34448, 103.68355, 32, True),
 "indoor.ns-underpass":("North Spine Underpass",     1.34610, 103.68050, 32, True),
 "stop.hall1":         ("Hall 1 Bus Stop",           1.34690, 103.68640, 25, False),
 "stop.hall2":         ("Hall 2 Bus Stop",           1.34535, 103.68700, 22, False),
 "stop.canteen2":      ("Canteen 2 Bus Stop",        1.34380, 103.68520, 22, False),
 "stop.spms":          ("SPMS Bus Stop",             1.34215, 103.68300, 29, False),
 "stop.wkw":           ("WKWSCI Bus Stop",           1.34290, 103.67900, 32, False),
 "stop.nie":           ("NIE Bus Stop",              1.34860, 103.67800, 35, False),
 "stop.lwn":           ("LWN Bus Stop",              1.34800, 103.68150, 39, False),
 "stop.hive":          ("Hive Bus Stop",             1.34470, 103.68330, 31, False),
 "jct.nanyang-crest":  (None,                        1.34450, 103.68050, 42, False),
 "jct.hall-spine":     (None,                        1.34480, 103.68580, 24, False),
 "bldg.gaia":          ("NBS @ Gaia",                1.34260, 103.68080, 26, False),
 "bldg.scse":          ("SCSE (N4)",                 1.34560, 103.68240, 40, False),
 "bldg.mae":           ("MAE (N3)",                  1.34600, 103.68180, 39, False),
 "bldg.eee":           ("EEE (S1)",                  1.34280, 103.68170, 29, False),
 "bldg.hss":           ("HSS",                       1.34290, 103.68570, 26, False),
 "bldg.canteen1":      ("Canteen 1",                 1.34620, 103.68690, 24, False),
 "hall.3":             ("Hall 3",                    1.34390, 103.68680, 21, False),
 "hall.5":             ("Hall 5",                    1.34480, 103.68820, 19, False),
 "hall.8":             ("Hall 8",                    1.34960, 103.68690, 22, False),
 "hall.9":             ("Hall 9",                    1.35050, 103.68740, 20, False),
 "bldg.northhill":     ("North Hill Halls",          1.35300, 103.68630, 30, False),
 "bldg.pioneer":       ("Pioneer Hall",              1.34200, 103.68830, 18, False),
 "bldg.crescent":      ("Crescent Hall",             1.34160, 103.68780, 18, False),
 "stop.hall8":         ("Hall 8 Bus Stop",           1.34950, 103.68660, 22, False),
 "stop.northhill":     ("North Hill Bus Stop",       1.35290, 103.68600, 29, False),
 "stop.pioneer":       ("Pioneer Hall Bus Stop",     1.34210, 103.68800, 18, False),
 "stop.gaia":          ("Gaia Bus Stop",             1.34250, 103.68060, 25, False),
}

# (a, b, kind, factor, bidirectional)
W = [
 ("bldg.hive","stop.hive","walk",1.20),
 ("bldg.hive","bldg.southspine","shelteredWalk",1.25),
 ("bldg.hive","indoor.hive-atrium","indoor",1.10),
 ("bldg.northspine","bldg.hive","shelteredWalk",1.30),
 ("bldg.northspine","bldg.lwn","shelteredWalk",1.25),
 ("bldg.northspine","jct.nanyang-crest","walk",1.20),
 ("jct.nanyang-crest","bldg.wkw","walk",1.20),
 ("bldg.northspine","indoor.ns-underpass","stairs",1.15),
 ("indoor.ns-underpass","bldg.sbs","indoor",1.15),
 ("bldg.northspine","bldg.sbs","walk",1.25),
 ("bldg.sbs","bldg.nie","walk",1.20),
 ("bldg.nie","stop.nie","walk",1.15),
 ("bldg.lwn","stop.lwn","walk",1.15),
 ("bldg.lwn","indoor.lwn-b1","stairs",1.60),
 ("bldg.lwn","bldg.adm","walk",1.25),
 ("bldg.adm","hall.6","walk",1.25),
 ("bldg.wkw","stop.wkw","walk",1.15),
 ("bldg.wkw","bldg.yunnan","walk",1.25),
 ("bldg.yunnan","bldg.spms","walk",1.25),
 ("bldg.spms","stop.spms","walk",1.15),
 ("bldg.spms","bldg.southspine","shelteredWalk",1.25),
 ("bldg.southspine","bldg.canteen2","walk",1.20),
 ("bldg.canteen2","stop.canteen2","walk",1.15),
 ("bldg.canteen2","hall.4","walk",1.20),
 ("hall.4","hall.2","walk",1.20),
 ("hall.2","stop.hall2","walk",1.15),
 ("hall.2","hall.1","walk",1.20),
 ("hall.1","stop.hall1","walk",1.15),
 ("hall.1","hall.6","walk",1.25),
 ("hall.6","stop.hall1","walk",1.25),
 ("jct.hall-spine","bldg.southspine","walk",1.20),
 ("jct.hall-spine","hall.2","walk",1.20),
 ("jct.hall-spine","stop.hive","walk",1.20),
 ("bldg.canteen1","hall.1","walk",1.15),
 ("bldg.canteen1","hall.2","walk",1.15),
 ("hall.3","hall.4","walk",1.20),
 ("hall.3","bldg.canteen2","walk",1.20),
 ("hall.5","hall.4","walk",1.20),
 ("hall.5","bldg.pioneer","walk",1.25),
 ("hall.8","stop.hall8","walk",1.15),
 ("hall.8","hall.6","walk",1.25),
 ("hall.9","hall.8","walk",1.20),
 ("bldg.northhill","stop.northhill","walk",1.15),
 ("bldg.northhill","hall.9","walk",1.25),
 ("bldg.pioneer","stop.pioneer","walk",1.15),
 ("bldg.crescent","bldg.pioneer","walk",1.15),
 ("bldg.crescent","hall.4","walk",1.25),
 ("bldg.gaia","stop.gaia","walk",1.15),
 ("bldg.gaia","bldg.eee","walk",1.20),
 ("bldg.eee","bldg.southspine","walk",1.25),
 ("bldg.gaia","bldg.yunnan","walk",1.25),
 ("bldg.scse","bldg.northspine","shelteredWalk",1.25),
 ("bldg.scse","bldg.hive","shelteredWalk",1.25),
 ("bldg.mae","bldg.northspine","shelteredWalk",1.20),
 ("bldg.mae","bldg.scse","shelteredWalk",1.20),
 ("bldg.hss","bldg.southspine","shelteredWalk",1.20),
 ("bldg.hss","bldg.canteen2","walk",1.20),
]

ring = ["stop.hall1","stop.hall8","stop.northhill","stop.lwn","stop.nie","stop.wkw",
        "stop.gaia","stop.spms","stop.pioneer","stop.canteen2","stop.hall2","stop.hive"]

edges = []
def add(f,t,kind,factor,line=None):
    a=(N[f][1],N[f][2]); b=(N[t][1],N[t][2])
    L=round(hav(a,b)*factor,1)
    edges.append({"from":f,"to":t,"kind":kind,"lengthMetres":L,
                  "elevationDelta":round(N[t][3]-N[f][3],1),
                  **({"line":line} if line else {})})

for f,t,kind,factor in W:
    add(f,t,kind,factor); add(t,f,kind,factor)
for i,s in enumerate(ring):
    nxt = ring[(i+1)%len(ring)]
    add(s,nxt,"shuttle",1.45,"loop-red")          # counter-clockwise
    add(nxt,s,"shuttle",1.45,"loop-blue")         # clockwise

nodes=[{"id":k,"displayName":v[0],"latitude":v[1],"longitude":v[2],
        "elevation":v[3],"isIndoor":v[4]} for k,v in N.items()]
doc={"formatVersion":1,"nodes":nodes,"edges":edges}
import os
out=os.path.join(os.path.dirname(__file__),"..","NTUSync","Resources","CampusGraph.json")
json.dump(doc,open(out,"w"),indent=1)
print(len(nodes),"nodes,",len(edges),"edges")
