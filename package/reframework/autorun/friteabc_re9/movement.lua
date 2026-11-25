local M={noclip=false,fly=false,azerty=true,speed=3}
local session
local function restore()
    local s=session;session=nil
    if not s then return end
    local errors={}
    for _,entry in ipairs({{s.controller,'set_Enabled',s.collision},{s.driver,'setEnable(System.Boolean)',s.driverEnabled}}) do
        local ok,why=pcall(function() entry[1]:call(entry[2],entry[3]) end)
        if not ok then errors[#errors+1]=tostring(why) end
    end
    if #errors>0 then log.error('[Friteabc RE9] Movement restore: '..table.concat(errors,'; ')) end
end
local function bind(player)
    local updater=player:call('get_Updater')
    assert(updater,'Movement unavailable')
    local controller=updater:call('get_CharacterController')
    local driver=updater:call('get_MovementDriver')
    assert(controller and driver,'Character controller unavailable')
    local enabled=controller:call('get_Enabled')
    local driverEnabled=driver:call('get_IsEnable')
    assert(type(enabled)=='boolean' and type(driverEnabled)=='boolean','Unsupported movement controls')
    local transform=player:call('get_Transform')
    session={player=player,address=player:get_address(),transform=transform,updater=updater,
        controller=controller,driver=driver,collision=enabled,driverEnabled=driverEnabled,
        height=transform:call('get_Position').y}
    driver:call('setEnable(System.Boolean)',false)
    assert(driver:call('get_IsEnable')==false,'The game rejected manual movement')
end
local function apply()
    local s=session
    if not s then return end
    local collision=not M.noclip and s.collision
    if s.controller:call('get_Enabled')~=collision then s.controller:call('set_Enabled',collision) end
    assert(s.controller:call('get_Enabled')==collision,'The game rejected collision mode')
end
function M.Set(player,noclip,fly)
    if not noclip and not fly then M.noclip=false;M.fly=false;restore();return end
    assert(player,'No playable character')
    local ok,why=pcall(function()
        if not session or session.address~=player:get_address() then restore();bind(player) end
        M.noclip=noclip;M.fly=fly;apply()
    end)
    if not ok then M.Stop();error(why) end
end
function M.Stop() M.noclip=false;M.fly=false;restore() end
local function normalized(x,y,z)
    local length=math.sqrt(x*x+y*y+z*z)
    if length<0.0001 then return 0,0,0 end
    return x/length,y/length,z/length
end
function M.Direction(forward,right,up,axisX,axisZ,flight)
    local fx,fy,fz=-axisZ.x,flight and -axisZ.y or 0,-axisZ.z
    if not flight and fx*fx+fz*fz<0.0001 then fx,fz=axisX.z,-axisX.x end
    fx,fy,fz=normalized(fx,fy,fz)
    local rx,ry,rz=normalized(axisX.x,flight and axisX.y or 0,axisX.z)
    local x,y,z=fx*forward+rx*right,fy*forward+ry*right+(flight and up or 0),fz*forward+rz*right
    local length=math.sqrt(x*x+y*y+z*z)
    if length>1 then x,y,z=x/length,y/length,z/length end
    return x,y,z
end
function M.Tick(player,menuOpen)
    if not M.noclip and not M.fly then return end
    if not player then restore();return end
    if not session or session.address~=player:get_address() then bind(player);apply() end
    if menuOpen then return end
    local s=session
    apply()
    if s.driver:call('get_IsEnable') then s.driver:call('setEnable(System.Boolean)',false) end
    local dt=s.updater:call('get_DeltaTime')
    if type(dt)~='number' or dt<=0 then return end
    dt=math.min(dt,0.05)
    local camera=sdk.get_primary_camera()
    if not camera then return end
    local view=camera:call('get_GameObject'):call('get_Transform')
    local function down(key) return reframework:is_key_down(key) and 1 or 0 end
    local forward=down(M.azerty and 90 or 87)-down(83)
    local right=down(68)-down(M.azerty and 81 or 65)
    local up=down(32)-math.max(down(17),down(162),down(163))
    local x,y,z=M.Direction(forward,right,up,view:call('get_AxisX'),view:call('get_AxisZ'),M.fly)
    local sprint=math.max(down(16),down(160),down(161))
    local speed=M.speed*(sprint==1 and 2.5 or 1)
    local position=s.transform:call('get_Position')
    local wantedY=s.height+y*speed*dt
    if x~=0 or y~=0 or z~=0 or math.abs(position.y-wantedY)>0.0001 then
        s.transform:call('set_Position',Vector3f.new(position.x+x*speed*dt,wantedY,position.z+z*speed*dt))
    end
end
function M.Sync()
    if not session then return end
    local s=session
    local position=s.transform:call('get_Position')
    s.height=position.y
    s.player:call('set_Position',position)
end
return M
