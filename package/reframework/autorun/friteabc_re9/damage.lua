local M={enabled=false,forceKill=false,status=nil,window=1.5}
local hooked={}
local installed=false
local playerHP,driverAddress,equipmentAddress,playerAddress
local lastAttack=-100
local reported={}
local survivors={}
local targets={}
local protected={}
local attackNames={onAttackCalc=true,onAttackAfterCalc=true,onAttackFinal=true,notifyShellHit=true,onShootedGameObject=true}
local equipmentNames={execFire=true,useMeleeWeapon=true,execCreateThrowingShell=true}
local numeric={['System.Int32']='int',['System.Int64']='int',['System.Single']='float'}
local function passthrough(value) return value end
local function address(object)
    if not object then return nil end
    local ok,value=pcall(function() return object:get_address() end)
    return ok and value or nil
end
local function markAttack(args)
    local this=sdk.to_int64(args[2])
    if this~=nil and (this==driverAddress or this==equipmentAddress or (equipmentAddress==nil and playerAddress~=nil)) then lastAttack=os.clock() end
    return sdk.PreHookResult.CALL_ORIGINAL
end
local function hookHierarchy(object,names)
    if not object then return 0 end
    local count=0
    local class=object:get_type_definition()
    while class do
        for _,method in ipairs(class:get_methods()) do
            if names[method:get_name()] then
                local key=method:get_function()
                if key~=nil and not hooked[key] then sdk.hook(method,markAttack,passthrough);hooked[key]=true end
                count=count+1
            end
        end
        class=class:get_parent_type()
    end
    return count
end
local function signed32(value)
    value=value%4294967296
    if value>=2147483648 then value=value-4294967296 end
    return value
end
local function lethal(slot,kind)
    return function(args)
        if not M.enabled or os.clock()-lastAttack>M.window then return sdk.PreHookResult.CALL_ORIGINAL end
        local this=sdk.to_int64(args[2])
        if this==nil or this==playerHP then return sdk.PreHookResult.CALL_ORIGINAL end
        local hp=sdk.to_managed_object(args[2])
        local current=hp and hp:call('get_CurrentHitPoint')
        if type(current)~='number' or current<=0 then return sdk.PreHookResult.CALL_ORIGINAL end
        local amount=math.min(math.floor(current)*2+100,1000000000)
        if kind=='int' then
            local raw=signed32(sdk.to_int64(args[slot]))
            if raw==0 then return sdk.PreHookResult.CALL_ORIGINAL end
            args[slot]=sdk.to_ptr(raw<0 and -amount or amount)
        else
            local raw=sdk.to_float(args[slot])
            if type(raw)~='number' or raw==0 then return sdk.PreHookResult.CALL_ORIGINAL end
            args[slot]=sdk.float_to_ptr(raw<0 and -amount or amount)
        end
        targets[this]=os.clock()
        thread.get_hook_storage().oneShot=hp
        return sdk.PreHookResult.CALL_ORIGINAL
    end
end
local function verify(signature)
    return function(value)
        local hp=thread.get_hook_storage().oneShot
        if hp then
            thread.get_hook_storage().oneShot=nil
            local ok,left=pcall(function() return hp:call('get_CurrentHitPoint') end)
            if ok and type(left)=='number' and left>0 then
                local key=hp:get_address()
                protected[key]=true
                if M.forceKill then survivors[key]=os.clock() end
                if not reported[signature] then
                    reported[signature]=true
                    log.info('[Friteabc RE9] One-shot: target kept '..tostring(left)..' HP after '..signature..(M.forceKill and ', finishing it' or ', left alive'))
                end
            end
        end
        return value
    end
end
local function install()
    if installed then return end
    local definition=assert(sdk.find_type_definition('app.HitPoint'),'Health system unavailable')
    local signatures,count={},0
    for _,method in ipairs(definition:get_methods()) do
        if method:get_name()=='addDamageHitPoint' then
            local params={}
            local slot,kind
            for index,param in ipairs(method:get_param_types()) do
                local name=param:get_full_name()
                params[#params+1]=name
                if not slot and numeric[name] then slot,kind=index+2,numeric[name] end
            end
            local signature='addDamageHitPoint('..table.concat(params,', ')..')'
            signatures[#signatures+1]=signature
            if slot then sdk.hook(method,lethal(slot,kind),verify(signature));count=count+1 end
        end
    end
    log.info('[Friteabc RE9] Damage methods: '..table.concat(signatures,' | '))
    local context=sdk.find_type_definition('app.CharacterContext')
    if context then
        for _,method in ipairs(context:get_methods()) do
            if method:get_name()=='isFatalDamage' and method:get_return_type():get_full_name()=='System.Boolean' then
                sdk.hook(method,function(args)
                    local fatal=false
                    if M.enabled and next(targets) then
                        local this=sdk.to_int64(args[2])
                        if this~=nil and this~=playerAddress then
                            pcall(function()
                                local hp=sdk.to_managed_object(args[2]):call('get_HitPoint')
                                local key=hp and hp:get_address()
                                local when=key and targets[key]
                                fatal=when~=nil and os.clock()-when<=0.5 and (M.forceKill or not protected[key])
                            end)
                        end
                    end
                    thread.get_hook_storage().fatal=fatal
                    return sdk.PreHookResult.CALL_ORIGINAL
                end,function(value)
                    if thread.get_hook_storage().fatal then return sdk.to_ptr(1) end
                    return value
                end)
            end
        end
    end
    assert(count>0,'One-shot unavailable: no damage method with an amount')
    installed=true
end
local function first(...)
    for _,fn in ipairs({...}) do
        local ok,value=pcall(fn)
        if ok and value then return value end
    end
end
local function hookType(typeName,names)
    local definition=sdk.find_type_definition(typeName)
    if not definition then return 0 end
    local count=0
    for _,method in ipairs(definition:get_methods()) do
        if names[method:get_name()] then
            local key=method:get_function()
            if key~=nil and not hooked[key] then sdk.hook(method,markAttack,passthrough);hooked[key]=true end
            count=count+1
        end
    end
    return count
end
M.sources=''
function M.Bind(player)
    playerHP,driverAddress,equipmentAddress,playerAddress=nil,nil,nil,nil
    if not player then return end
    playerAddress=player:get_address()
    playerHP=address(first(function() return player:call('get_HitPoint') end))
    local updater=first(function() return player:call('get_Updater') end,function() return player:get_field('<Updater>k__BackingField') end)
    local driver=updater and first(function() return updater:call('get_AttackDamageDriver') end,function() return updater:get_field('<AttackDamageDriver>k__BackingField') end)
    local equipment=updater and first(function() return updater:call('get_Equipment') end,function() return updater:get_field('<Equipment>k__BackingField') end,
        function() return updater:call('get_MeshController'):get_field('_Equipment') end)
    driverAddress,equipmentAddress=address(driver),address(equipment)
    if M.enabled then
        local fromDriver=hookHierarchy(driver,attackNames)
        local fromEquipment=hookHierarchy(equipment,equipmentNames)+hookType('app.PlayerEquipment',equipmentNames)
        local parts={}
        if fromDriver>0 then parts[#parts+1]='hits' end
        if fromEquipment>0 then parts[#parts+1]='shots' end
        parts[#parts+1]='mouse'
        M.sources=table.concat(parts,', ')
        M.status=nil
        log.info('[Friteabc RE9] One-shot attack detection: '..M.sources..' (driver='..tostring(driverAddress~=nil)..', equipment='..tostring(equipmentAddress~=nil)..')')
    end
end
function M.Poll()
    local ok,down=pcall(function() return reframework:is_key_down(0x01) end)
    if ok and down==true and not reframework:is_drawing_ui() then lastAttack=os.clock() end
end
function M.Set(value,player)
    if value then
        install()
        M.enabled=true
        M.Bind(player)
    else
        M.enabled=false
    end
end
function M.Tick()
    local now=os.clock()
    for key,time in pairs(targets) do if now-time>2 then targets[key]=nil end end
    if not M.forceKill then survivors={};return end
    if not next(survivors) then return end
    local due=false
    for _,time in pairs(survivors) do if now-time>=0.3 then due=true end end
    if not due then return end
    local list=sdk.get_managed_singleton('app.CharacterManager'):call('get_EnemyContextList'):call('ToArray'):get_elements()
    for _,context in ipairs(list) do
        local ok,hp=pcall(function() return context:call('get_HitPoint') end)
        local key=ok and hp and hp:get_address()
        if key and survivors[key] and now-survivors[key]>=0.3 then
            survivors[key]=nil
            local left=hp:call('get_CurrentHitPoint')
            if type(left)=='number' and left>0 and not context:call('get_IsDead') then
                pcall(function() context:call('forceDead') end)
            end
        end
    end
    for key,time in pairs(survivors) do if now-time>2 then survivors[key]=nil end end
end
function M.Clear()
    survivors,targets,protected={},{},{}
end
return M
