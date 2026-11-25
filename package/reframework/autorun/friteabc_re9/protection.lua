local M={enabled=false,status=nil,blocked=0}
local installed=false
local playerAddress,hpAddress
local unit,grabBackup
local function pass(value) return value end
local function no() return sdk.to_ptr(0) end
local function mine(args,address) return address~=nil and sdk.to_int64(args[2])==address end
local function note(what)
    M.blocked=M.blocked+1
    log.info('[Friteabc RE9] God mode blocked: '..what)
end
local function each(typeName,name,fn)
    local definition=sdk.find_type_definition(typeName)
    if not definition then return 0 end
    local count=0
    for _,method in ipairs(definition:get_methods()) do
        if method:get_name()==name then fn(method,method:get_return_type():get_full_name());count=count+1 end
    end
    return count
end
local function install()
    if installed then return end
    local count=0
    count=count+each('app.CharacterContext','forceDead',function(method)
        sdk.hook(method,function(args)
            if M.enabled and mine(args,playerAddress) then note('forced death');return sdk.PreHookResult.SKIP_ORIGINAL end
            return sdk.PreHookResult.CALL_ORIGINAL
        end,pass)
    end)
    local function denyBool(typeName,name,address)
        count=count+each(typeName,name,function(method,returns)
            if returns~='System.Boolean' then return end
            sdk.hook(method,function(args)
                thread.get_hook_storage().deny=M.enabled and mine(args,address())
                return sdk.PreHookResult.CALL_ORIGINAL
            end,function(value)
                if thread.get_hook_storage().deny then return no() end
                return value
            end)
        end)
    end
    denyBool('app.CharacterContext','isFatalDamage',function() return playerAddress end)
    denyBool('app.HitPoint','_checkDead',function() return hpAddress end)
    count=count+each('app.CharacterManager','requestGameOver',function(method,returns)
        if returns~='System.Void' and returns~='System.Boolean' then return end
        sdk.hook(method,function()
            if M.enabled and not M.suspended and playerAddress then note('game over');thread.get_hook_storage().skip=true;return sdk.PreHookResult.SKIP_ORIGINAL end
            thread.get_hook_storage().skip=false
            return sdk.PreHookResult.CALL_ORIGINAL
        end,function(value)
            if thread.get_hook_storage().skip and returns=='System.Boolean' then return no() end
            return value
        end)
    end)
    each('app.AttackDamageCommonBlackboardUnit','get_EnableIgnoreDamageGrapple',function(method,returns)
        if returns~='System.Boolean' then return end
        sdk.hook(method,function(args)
            thread.get_hook_storage().grab=M.enabled and unit~=nil and mine(args,unit:get_address())
            return sdk.PreHookResult.CALL_ORIGINAL
        end,function(value)
            if thread.get_hook_storage().grab then return sdk.to_ptr(1) end
            return value
        end)
    end)
    assert(count>0,'Scripted death protection unavailable')
    installed=true
end
local function releaseGrab()
    if unit and grabBackup~=nil then pcall(function() unit:call('set_EnableIgnoreDamageGrapple',grabBackup) end) end
    unit,grabBackup=nil,nil
end
function M.Apply(player)
    install()
    M.enabled=true
    playerAddress=player:get_address()
    local hp=player:call('get_HitPoint')
    hpAddress=hp and hp:get_address() or nil
    local current
    pcall(function() current=player:call('get_Updater'):call('get_AttackDamageBlackboardUnit') end)
    if current and (not unit or unit:get_address()~=current:get_address()) then
        releaseGrab()
        local value=current:call('get_EnableIgnoreDamageGrapple')
        if type(value)=='boolean' then unit,grabBackup=current,value end
    end
    if unit and unit:call('get_EnableIgnoreDamageGrapple')~=true then unit:call('set_EnableIgnoreDamageGrapple',true) end
end
function M.Release()
    M.enabled=false
    releaseGrab()
end
return M
