local M={multiplier=1.0,status=nil,active=false}
local config='friteabc_re9_speed.json'
local loaded,settings=pcall(json.load_file,config)
if loaded and type(settings)=='table' and type(settings.multiplier)=='number' and settings.multiplier==settings.multiplier then
    M.multiplier=math.max(0.5,math.min(4,settings.multiplier))
end
function M.Save() pcall(json.dump_file,config,{multiplier=M.multiplier}) end
if not (loaded and type(settings)=='table') then M.Save() end
local hooked={}
local driverAddress,updater
local blocked=false
local reported=false
local lastHook=-100
local PRIMARY={getMoveSpeed=true}
local FALLBACK={getBaseMoveSpeed=true}
local function hookNames(driver,names)
    local count=0
    local class=driver:get_type_definition()
    while class do
        for _,method in ipairs(class:get_methods()) do
            if names[method:get_name()] and method:get_return_type():get_full_name()=='System.Single' then
                local key=method:get_function()
                if key~=nil and not hooked[key] then
                    local name=method:get_name()
                    sdk.hook(method,function(args)
                        thread.get_hook_storage().walk=driverAddress~=nil and sdk.to_int64(args[2])==driverAddress
                        return sdk.PreHookResult.CALL_ORIGINAL
                    end,function(value)
                        if not thread.get_hook_storage().walk or blocked or M.multiplier==1 then return value end
                        local ok,speed=pcall(sdk.to_float,value)
                        if not ok or type(speed)~='number' then return value end
                        M.active=true
                        lastHook=os.clock()
                        if not reported and speed>0 then
                            reported=true
                            log.info(string.format('[Friteabc RE9] Walk speed: %s %.2f -> %.2f',name,speed,speed*M.multiplier))
                        end
                        return sdk.float_to_ptr(speed*M.multiplier)
                    end)
                    hooked[key]=true
                end
                count=count+1
            end
        end
        class=class:get_parent_type()
    end
    return count
end
local function bindDriver(driver)
    driverAddress=driver and driver:get_address() or nil
    if not driver then M.status='Walk speed unavailable for this character';return end
    local count=hookNames(driver,PRIMARY)
    if count==0 then count=hookNames(driver,FALLBACK) end
    if count>0 then M.status=nil else M.status='Walk speed unavailable for this movement mode' end
end
local motion,base,written,last
local function key(code)
    local ok,down=pcall(function() return reframework:is_key_down(code) end)
    return ok and down==true
end
local function moving(player)
    for _,code in ipairs({0x57,0x5A,0x41,0x51,0x53,0x44}) do if key(code) then return true end end
    local ok,position=pcall(function() return player:call('get_Transform'):call('get_Position') end)
    if not ok or not position then return false end
    local now=os.clock()
    local result=false
    if last and now>last.t then
        local dx,dz=position.x-last.x,position.z-last.z
        result=math.sqrt(dx*dx+dz*dz)/(now-last.t)>0.6
    end
    last={x=position.x,z=position.z,t=now}
    return result
end
local function giveBack()
    if motion and written then
        pcall(function()
            local current=motion:call('get_PlaySpeed')
            if type(current)=='number' and math.abs(current-written)<0.001 then motion:call('set_PlaySpeed',base or 1.0) end
        end)
    end
    written=nil
end
local function animationSpeed(player)
    local useAnimation=M.multiplier~=1 and not blocked and os.clock()-lastHook>0.3 and not key(0x01) and not key(0x02) and moving(player)
    if not useAnimation or not motion then giveBack();return end
    local current=motion:call('get_PlaySpeed')
    if type(current)~='number' then return end
    if not written or math.abs(current-written)>0.001 then base=current end
    local wanted=base*M.multiplier
    if not written or math.abs(current-wanted)>0.001 then motion:call('set_PlaySpeed',wanted) end
    written=wanted
end
function M.Bind(player)
    giveBack()
    updater,driverAddress,motion,base,last=nil,nil,nil,nil,nil
    if not player then return end
    updater=player:call('get_Updater')
    pcall(function() motion=updater:call('get_Motion') end)
    bindDriver(updater and updater:call('get_MovementDriver'))
    if motion then M.status=nil end
end
local nextCheck=0
function M.Tick(player,isBlocked)
    blocked=isBlocked==true
    if player then pcall(animationSpeed,player) end
    if not player or not updater or os.clock()<nextCheck then return end
    nextCheck=os.clock()+0.5
    local driver=updater:call('get_MovementDriver')
    local address=driver and driver:get_address() or nil
    if address~=driverAddress then bindDriver(driver) end
end
function M.Release() M.active=false;giveBack() end
return M
