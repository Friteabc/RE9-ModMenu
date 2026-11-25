local M={radius=150,active=false,status=nil}
local start,saved
local DURATION=6.0
function M.Trigger(player,Enemies,Visuals,TimeScale,View)
    assert(player,'No playable character')
    assert(not M.active,'Already exploding')
    saved={radius=Enemies.radius,exposure=Visuals.exposure,speed=TimeScale.speed}
    M.refs={Enemies=Enemies,Visuals=Visuals,TimeScale=TimeScale,View=View}
    Enemies.radius=M.radius
    local ok=pcall(Enemies.KillNearby,player)
    Enemies.radius=saved.radius
    M.status=ok and Enemies.status or 'Boom'
    TimeScale.speed=0.25
    start=os.clock()
    M.active=true
    log.info('[Friteabc RE9] Nuke: '..tostring(M.status))
end
local function finish()
    local r=M.refs
    if r and saved then
        r.Visuals.exposure=saved.exposure
        r.TimeScale.speed=saved.speed
        r.View.shake=nil
    end
    M.active=false;saved=nil;M.flash=0;M.glow=0
end
function M.Tick()
    if not M.active then return end
    local t=os.clock()-start
    local r=M.refs
    if t>=DURATION then finish();return end
    if t<0.15 then M.flash=t/0.15 elseif t<1.6 then M.flash=1-(t-0.15)/1.45 else M.flash=0 end
    M.glow=t<4 and math.min(1,t/0.6)*(1-t/4) or 0
    r.Visuals.exposure=saved.exposure+8*math.max(0,1-t/3)
    if t>=2.2 then r.TimeScale.speed=saved.speed elseif t>=1.2 then r.TimeScale.speed=0.25+(saved.speed-0.25)*((t-1.2)/1.0) end
    local power=math.max(0,1-t/3.5)
    r.View.shake=power>0 and {x=(math.random()*2-1)*0.35*power,y=(math.random()*2-1)*0.25*power,z=(math.random()*2-1)*0.35*power} or nil
end
function M.Draw()
    if not M.active or not draw then return end
    local w,h=8000,5000
    pcall(function() local size=imgui.get_display_size();w,h=size.x,size.y end)
    if (M.glow or 0)>0 then
        local a=math.floor(170*M.glow)
        draw.filled_rect(0,0,w,h,a*0x1000000+0x1060FF)
    end
    if (M.flash or 0)>0 then
        local a=math.floor(255*math.min(1,M.flash))
        draw.filled_rect(0,0,w,h,a*0x1000000+0xFFFFFF)
    end
end
function M.Release() if M.active then finish() end end
return M
