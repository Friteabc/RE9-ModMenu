local M={enabled=false,status=nil}
local unit,backup
local hooked=false
local FLAGS={'EnableIgnoreDamageHit','EnableIgnoreDamageGrapple'}
local function install()
    if hooked then return end
    local definition=sdk.find_type_definition('app.AttackDamageCommonBlackboardUnit')
    assert(definition,'Damage settings unavailable')
    for _,flag in ipairs(FLAGS) do
        local method=definition:get_method('get_'..flag)
        if method then
            sdk.hook(method,function(args)
                thread.get_hook_storage().shield=M.enabled and unit~=nil and sdk.to_int64(args[2])==unit:get_address()
                return sdk.PreHookResult.CALL_ORIGINAL
            end,function(value)
                if thread.get_hook_storage().shield then return sdk.to_ptr(1) end
                return value
            end)
        end
    end
    hooked=true
end
local function release()
    if unit and backup then
        for flag,value in pairs(backup) do pcall(function() unit:call('set_'..flag,value) end) end
    end
    unit,backup=nil,nil
end
function M.Tick(player)
    if not M.enabled then if unit then release() end return end
    if not player then release();return end
    install()
    local current=player:call('get_Updater'):call('get_AttackDamageBlackboardUnit')
    if not current then M.status='Unavailable for this character';return end
    if not unit or unit:get_address()~=current:get_address() then
        release()
        unit,backup=current,{}
        for _,flag in ipairs(FLAGS) do
            local ok,value=pcall(function() return current:call('get_'..flag) end)
            if ok and type(value)=='boolean' then backup[flag]=value end
        end
    end
    for flag in pairs(backup) do
        pcall(function() if unit:call('get_'..flag)~=true then unit:call('set_'..flag,true) end end)
    end
    M.status=nil
end
function M.Set(value) M.enabled=value==true;if not M.enabled then release() end end
function M.Release() M.enabled=false;release() end
return M
