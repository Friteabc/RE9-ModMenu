import math
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
def area(pts): return sum(pts[i][0]*pts[(i+1)%len(pts)][1]-pts[(i+1)%len(pts)][0]*pts[i][1] for i in range(len(pts)))/2
def contour(pen,pts):
    if area(pts)>0: pts=pts[::-1]
    pen.moveTo(pts[0])
    for p in pts[1:]: pen.lineTo(p)
    pen.closePath()
def reload_glyph():
    cx,cy,ro,ri=500,330,340,235
    a0,a1=math.radians(115),math.radians(-205)
    n=48
    outer=[(cx+ro*math.cos(a0+(a1-a0)*i/n),cy+ro*math.sin(a0+(a1-a0)*i/n)) for i in range(n+1)]
    inner=[(cx+ri*math.cos(a1+(a0-a1)*i/n),cy+ri*math.sin(a1+(a0-a1)*i/n)) for i in range(n+1)]
    ring=[(round(x),round(y)) for x,y in outer+inner]
    rm=(ro+ri)/2; th=a1
    px,py=cx+rm*math.cos(th),cy+rm*math.sin(th)
    rx,ry=math.cos(th),math.sin(th)
    tx,ty=math.sin(th),-math.cos(th)
    head=[(round(px+rx*150),round(py+ry*150)),(round(px+tx*190),round(py+ty*190)),(round(px-rx*150),round(py-ry*150))]
    pen=TTGlyphPen(None);contour(pen,ring);contour(pen,head)
    return pen.glyph()
def empty(): return TTGlyphPen(None).glyph()
fb=FontBuilder(1000,isTTF=True)
fb.setupGlyphOrder(['.notdef','space','reload'])
fb.setupCharacterMap({0x20:'space',0x21BB:'reload'})
fb.setupGlyf({'.notdef':empty(),'space':empty(),'reload':reload_glyph()})
fb.setupHorizontalMetrics({'.notdef':(1000,0),'space':(500,0),'reload':(1000,80)})
fb.setupHorizontalHeader(ascent=800,descent=-200)
fb.setupNameTable({'familyName':'FriteabcIcons','styleName':'Regular'})
fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200)
fb.setupPost()
fb.save('package/reframework/fonts/friteabc_icons.ttf')
print('ok')
