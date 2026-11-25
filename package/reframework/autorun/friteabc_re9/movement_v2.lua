local Math=require('friteabc_re9.movement')
local Ground=require('friteabc_re9.ground')
local Combat=require('friteabc_re9.movement_combat')
local Teleport=require('friteabc_re9.teleport')
local M={noclip=false,fly=false,speed=3,Direction=Math.Direction}
local session
local hooks={}
local lastGuardLog={}
local config='friteabc_re9_movement.json'
local loaded,settings=pcall(json.load_file,config)
if loaded and type(settings)=='table' then
    for _,key in ipairs({'noclip','fly'}) do if type(settings[key])=='boolean' then M[key]=settings[key] end end
    if type(settings.speed)=='number' and settings.speed==settings.speed then M.speed=math.max(0.5,math.min(15,settings.speed)) end
end
function M.Save() json.dump_file(config,{noclip=M.noclip,fly=M.fly,speed=M.speed}) end
local function vec(p) return Vector3f.new(p.x,p.y,p.z) end
local function copy(p) return {x=p.x,y=p.y,z=p.z} end
local function settle(s,here)
    if not here then return end
    local position=vec(here)
    pcall(function() s.transform:call('set_Position',position) end)
    pcall(function() s.controller:call('warp') end)
    local ok,why=pcall(Teleport.Warp,s.player,here.x,here.y,here.z,false)
    if not ok then log.error('[Friteabc RE9] Movement settle warp: '..tostring(why)) end
end
local function restore()
    local s=session;session=nil
    if not s then return end
    local here
    pcall(function() local p=s.transform:call('get_Position');here={x=p.x,y=p.y,z=p.z} end)
    Combat.Release()
    if s.releaseGround then pcall(s.releaseGround) end
    for _,entry in ipairs({{s.controller,'set_Enabled',s.collision},{s.driver,'setEnable(System.Boolean)',s.driverEnabled},{s.player,'set_StopByOutOfArea',s.areaStop}}) do
        local ok,why=pcall(function() entry[1]:call(entry[2],entry[3]) end)
        if not ok then log.error('[Friteabc RE9] Movement restore: '..tostring(why)) end
    end
    settle(s,here)
end
function M.Suspend() restore() end
function M.Rebase(player)
    if session and player and session.address==player:get_address() then
        session.position=copy(session.transform:call('get_Position'))
        if session.releaseGround then pcall(session.releaseGround) end
        session.ground=nil;session.releaseGround=nil
        session.floorSample=nil
    end
end
function M.Stop()
    M.noclip=false;M.fly=false;restore();M.Save()
    log.info('[Friteabc RE9] Movement disabled')
end
local function guard(object,names,role)
    local class=object:get_type_definition()
    while class do
        for _,method in ipairs(class:get_methods()) do
            local stopFlag=method:get_name()=='set_StopByOutOfArea' and method:get_num_params()==1
            if names[method:get_name()] and (method:get_num_params()==0 or stopFlag) and method:get_return_type():get_full_name()=='System.Void' then
                local key=method:get_function()
                if not hooks[key] then
                    local name=method:get_name()
                    sdk.hook(method,function(args)
                        local s=session
                        local target=s and (role=='player' and s.address or s.updaterAddress)
                        if target and (M.noclip or M.fly) and sdk.to_int64(args[2])==target and (not stopFlag or sdk.to_int64(args[3])~=0) then
                            local now=os.clock()
                            if now-(lastGuardLog[name] or -3)>2 then
                                lastGuardLog[name]=now
                                log.info('[Friteabc RE9] Movement guard blocked '..name)
                            end
                            return sdk.PreHookResult.SKIP_ORIGINAL
                        end
                        return sdk.PreHookResult.CALL_ORIGINAL
                    end,function(value) return value end)
                    hooks[key]=true
                end
            end
        end
        class=class:get_parent_type()
    end
end
local function bind(player)
    local updater=player:call('get_Updater')
    assert(updater,'Movement unavailable')
    local controller=updater:call('get_CharacterController')
    local driver=updater:call('get_MovementDriver')
    local transform=player:call('get_Transform')
    assert(controller and driver and transform,'Movement components unavailable')
    local s={player=player,updater=updater,controller=controller,driver=driver,transform=transform,
        address=player:get_address(),updaterAddress=updater:get_address(),driverAddress=driver:get_address(),position=copy(transform:call('get_Position')),
        collision=controller:call('get_Enabled'),driverEnabled=driver:call('get_IsEnable'),
        areaStop=player:call('get_StopByOutOfArea')}
    assert(type(s.collision)=='boolean' and type(s.driverEnabled)=='boolean' and type(s.areaStop)=='boolean','Unsupported movement settings')
    session=s
    Combat.Bind(player,updater)
    guard(player,{forceDead=true,set_StopByOutOfArea=true},'player')
    guard(updater,{execSafeProcFallLimit=true},'updater')
    local class=driver:get_type_definition()
    while class do
        for _,method in ipairs(class:get_methods()) do
            if method:get_name()=='get_IsApplyPos' and method:get_num_params()==0 and method:get_return_type():get_full_name()=='System.Boolean' then
                local key=method:get_function()
                if not hooks[key] then
                    sdk.hook(method,function(args)
                        local current=session
                        local manual=current and (M.noclip or M.fly) and sdk.to_int64(args[2])==current.driverAddress
                        thread.get_hook_storage().manualPosition=manual
                        return manual and sdk.PreHookResult.SKIP_ORIGINAL or sdk.PreHookResult.CALL_ORIGINAL
                    end,function(value)
                        if thread.get_hook_storage().manualPosition then return sdk.to_ptr(false) end
                        return value
                    end)
                    hooks[key]=true
                end
            end
        end
        class=class:get_parent_type()
    end
end
local function apply()
    local s=session
    local wanted=not M.noclip and s.collision
    local enabled=s.controller:call('get_Enabled')
    if enabled~=wanted then
        local here
        if wanted then pcall(function() local p=s.transform:call('get_Position');here={x=p.x,y=p.y,z=p.z} end) end
        s.controller:call('set_Enabled',wanted)
        if wanted then settle(s,here);s.position=here or s.position end
    end
    if s.driver:call('get_IsEnable')~=s.driverEnabled then s.driver:call('setEnable(System.Boolean)',s.driverEnabled) end
    if s.player:call('get_StopByOutOfArea') then s.player:call('set_StopByOutOfArea',false) end
    Combat.Apply(M.noclip or M.fly)
end
function M.UpdateCombat()
    if session then Combat.Apply(M.noclip or M.fly) end
end
function M.ProbeCombat(player) Combat.Probe(player,M.noclip or M.fly) end
local function prepareGround()
    if M.noclip and not M.fly and not session.ground then
        local s=session
        s.ground,s.releaseGround=Ground.Create(s.controller)
        local floor=s.ground(s.position.x,s.position.y,s.position.z)
        s.footOffset=floor and math.max(0,math.min(2.5,s.position.y-floor)) or 0
    end
end
function M.SampleGround()
    local s=session
    if not s or not M.noclip or M.fly then return end
    M.stage='ground sampling'
    prepareGround()
    local floor=s.ground(s.position.x,s.position.y-(s.footOffset or 0),s.position.z)
    s.floorSample={x=s.position.x,z=s.position.z,height=floor}
end
function M.Set(player,noclip,fly)
    if not noclip and not fly then M.Stop();return end
    assert(player,'No playable character')
    local oldNoclip,oldFly=M.noclip,M.fly
    local ok,why=pcall(function()
        if not session or session.address~=player:get_address() then restore();bind(player) end
        M.noclip=noclip;M.fly=fly;apply();prepareGround();M.Save()
        log.info('[Friteabc RE9] Movement noclip='..tostring(noclip)..' fly='..tostring(fly))
    end)
    if not ok then
        if session and (oldNoclip or oldFly) then
            M.noclip=oldNoclip;M.fly=oldFly;apply()
        else M.Stop() end
        error(why)
    end
end
local function warp(s)
    local physical=s.transform:call('get_Position')
    local dx,dy,dz=physical.x-s.position.x,physical.y-s.position.y,physical.z-s.position.z
    if dx*dx+dy*dy+dz*dz>0.000001 then
        local position=vec(s.position)
        s.transform:call('set_Position',position)
        s.player:call('set_Position',position)
    end
    if s.controller:call('get_Enabled') then s.controller:call('set_Enabled',false) end
end
function M.Tick(player,menuOpen)
    M.stage='character binding'
    if not M.noclip and not M.fly then return end
    if not player then restore();return end
    if not session or session.address~=player:get_address() then restore();bind(player) end
    local s=session
    M.stage='movement settings'
    apply()
    M.stage='frame time'
    local now=os.clock()
    local dt=s.lastTick and now-s.lastTick or 1/60
    s.lastTick=now
    if dt<=0 then return end
    dt=math.min(dt,0.04)
    local x,y,z=0,0,0
    if not menuOpen then
        M.stage='primary camera'
        local camera=sdk.get_primary_camera()
        if camera then
            M.stage='camera transform'
            local view=camera:call('get_GameObject'):call('get_Transform')
            local function down(key) return reframework:is_key_down(key) and 1 or 0 end
            M.stage='camera axes and keyboard'
            x,y,z=M.Direction(math.max(down(87),down(90))-down(83),down(68)-math.max(down(65),down(81)),down(32)-math.max(down(17),down(162),down(163)),view:call('get_AxisX'),view:call('get_AxisZ'),M.fly)
            local speed=M.speed*(math.max(down(16),down(160),down(161))==1 and 2.5 or 1)
            x,y,z=x*speed*dt,y*speed*dt,z*speed*dt
        end
    end
    if not M.noclip then
        local physical=s.transform:call('get_Position')
        s.position.x=physical.x;s.position.z=physical.z
    end
    s.position.x=s.position.x+x;s.position.y=s.position.y+y;s.position.z=s.position.z+z
    if M.noclip and not M.fly and not menuOpen and (x~=0 or z~=0) then
        local floor=s.floorSample
        if floor and floor.height and math.abs(floor.x-s.position.x)<=0.75 and math.abs(floor.z-s.position.z)<=0.75 then
            s.position.y=floor.height+(s.footOffset or 0)
        end
    end
    M.stage='character movement'
    if M.noclip then warp(s) else s.transform:call('set_Position',vec(s.position)) end
end
function M.Sync()
    M.stage='physics synchronization'
    local s=session
    if not s then return end
    if M.noclip then warp(s) else
        local physical=s.transform:call('get_Position')
        s.position=copy(physical)
        s.player:call('set_Position',physical)
    end
end
return M
