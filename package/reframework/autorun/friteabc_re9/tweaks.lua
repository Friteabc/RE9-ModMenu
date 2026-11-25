local M={fireRate=1.0,reloadSpeed=1.0,noFear=false,instantFire=false,noRecoil=false,instantReload=false,status=nil}
local hooked={}
local updaterAddress,equipmentAddress,commonAddress
local common,heart,heartWas
local reported={}
local function pass(value) return value end
local function mineFor(getAddress)
    return function(args)
        thread.get_hook_storage().mine=getAddress()~=nil and sdk.to_int64(args[2])==getAddress()
        return sdk.PreHookResult.CALL_ORIGINAL
    end
end
local function scaled(factor)
    return function(value)
        if not thread.get_hook_storage().mine then return value end
        local m=factor()
        if m==1 then return value end
        local ok,v=pcall(sdk.to_float,value)
        if not ok or type(v)~='number' then return value end
        return sdk.float_to_ptr(v*m)
    end
end
local function hookIn(object,name,pre,post)
    if not object then return 0 end
    local count=0
    local class=object:get_type_definition()
    while class do
        for _,method in ipairs(class:get_methods()) do
            if method:get_name()==name then
                local key=method:get_function()
                if key~=nil and not hooked[key] then sdk.hook(method,pre,post);hooked[key]=true end
                count=count+1
            end
        end
        class=class:get_parent_type()
    end
    return count
end
local function afterShot(value)
    if thread.get_hook_storage().mine and M.fireRate~=1 then
        pcall(function()
            local equipment=sdk.to_managed_object(thread.get_hook_storage().this)
            for _,field in ipairs({'_ShotInterval','_CalcShotInterval'}) do
                local current=equipment:get_field(field)
                if type(current)=='number' and current>0 then
                    equipment:set_field(field,current/M.fireRate)
                    if not reported[field] then reported[field]=true;log.info('[Friteabc RE9] Fire rate: '..field..' '..current..' -> '..current/M.fireRate) end
                end
            end
        end)
    end
    return value
end
function M.Bind(player)
    updaterAddress,equipmentAddress,commonAddress,common=nil,nil,nil,nil
    M.Release()
    if not player then return end
    local updater=player:call('get_Updater')
    local equipment=updater and updater:call('get_Equipment')
    updaterAddress=updater and updater:get_address() or nil
    equipmentAddress=equipment and equipment:get_address() or nil
    pcall(function() common=player:call('get_Common');commonAddress=common and common:get_address() or nil end)
    local found=0
    found=found+hookIn(updater,'getAttachmentShootSpeed',mineFor(function() return updaterAddress end),scaled(function() return M.fireRate end))
    found=found+hookIn(updater,'getAttachmentBoltActionSpeed',mineFor(function() return updaterAddress end),scaled(function() return M.fireRate end))
    found=found+hookIn(updater,'getAttachmentReloadSpeed',mineFor(function() return updaterAddress end),scaled(function() return M.reloadSpeed end))
    hookIn(equipment,'execFire',function(args)
        local storage=thread.get_hook_storage()
        storage.mine=equipmentAddress~=nil and sdk.to_int64(args[2])==equipmentAddress
        storage.this=args[2]
        if storage.mine then M.lastShot=os.clock() end
        return sdk.PreHookResult.CALL_ORIGINAL
    end,afterShot)
    hookIn(common,'getFearLevelRate',mineFor(function() return commonAddress end),function(value)
        if thread.get_hook_storage().mine and M.noFear then return sdk.float_to_ptr(0.0) end
        return value
    end)
    pcall(function() heart=updater:call('get_HeartRateDriver') end)
    if found>0 then M.status=nil else M.status='Weapon speed controls unavailable for this character' end
end
local function setHeart(on)
    if not heart then return end
    for _,name in ipairs({'setEnable(System.Boolean)','set_IsEnable'}) do
        if pcall(function() heart:call(name,on) end) then return true end
    end
end
function M.Tick(player)
    if not player then return end
    if M.noFear then
        if common then pcall(function() common:call('setFearLevelRate(System.Single)',0.0) end) end
        if heart and heartWas==nil then
            local ok,was=pcall(function() return heart:call('get_IsEnable') end)
            heartWas=ok and type(was)=='boolean' and was or true
        end
        if heart and heartWas~=nil then setHeart(false) end
    elseif heartWas~=nil then
        setHeart(heartWas);heartWas=nil
    end
end
local combatHooked=false
local recoilNames={}
local holdBackup,infoBackup,customInfo
local function skipWhen(flag,owner)
    return function(args)
        if M[flag] and (owner==nil or (owner()~=nil and sdk.to_int64(args[2])==owner())) then return sdk.PreHookResult.SKIP_ORIGINAL end
        return sdk.PreHookResult.CALL_ORIGINAL
    end
end
local function installCombat()
    if combatHooked then return end
    combatHooked=true
    local blender=sdk.find_type_definition('app.CameraBlender')
    if blender then
        for _,method in ipairs(blender:get_methods()) do
            if method:get_name()=='requestShotCameraShake' and method:get_return_type():get_full_name()=='System.Void' then
                sdk.hook(method,skipWhen('noRecoil'),pass);recoilNames[#recoilNames+1]='camera shake'
            end
        end
    end
    local recoil=sdk.find_type_definition('app.CameraRecoilController')
    if recoil then
        for _,method in ipairs(recoil:get_methods()) do
            local name=method:get_name()
            if (name:find('^request') or name:find('^add') or name:find('^start')) and method:get_return_type():get_full_name()=='System.Void' then
                sdk.hook(method,skipWhen('noRecoil'),pass);recoilNames[#recoilNames+1]=name
            end
        end
    end
    log.info('[Friteabc RE9] Recoil hooks: '..table.concat(recoilNames,', '))
end
M.magFull=false
local function noReloadNeeded(value)
    if thread.get_hook_storage().mine and M.instantReload and M.magFull then return sdk.to_ptr(0) end
    return value
end
local function hookUpdater(updater)
    for _,name in ipairs({'isAutoReload','isDisposableWeaponReload','checkReloadEnable'}) do
        hookIn(updater,name,mineFor(function() return updaterAddress end),noReloadNeeded)
    end
    hookIn(updater,'updateRecoilAngleRatio',skipWhen('noRecoil',function() return updaterAddress end),pass)
    hookIn(updater,'isApplyEquipHoldStartShoot',mineFor(function() return updaterAddress end),function(value)
        if thread.get_hook_storage().mine and M.instantFire and M.gunReady then return sdk.to_ptr(1) end
        return value
    end)
end
local argCache={}
local function callFlag(object,name)
    local key=object:get_type_definition():get_full_name()..'.'..name
    local args=argCache[key]
    if args==nil then
        args=false
        local class=object:get_type_definition()
        while class and not args do
            for _,method in ipairs(class:get_methods()) do
                if method:get_name()==name then
                    local list,ok={},true
                    for _,param in ipairs(method:get_param_types()) do
                        local t=param:get_full_name()
                        if t=='System.Boolean' then list[#list+1]=false elseif t=='System.Int32' or t=='System.Single' then list[#list+1]=0 else ok=false end
                    end
                    if ok then args=list;break end
                end
            end
            class=class:get_parent_type()
        end
        argCache[key]=args
    end
    if not args then return nil end
    return object:call(name,table.unpack(args))
end
local nextReload=0
local function refill(player)
    if not M.instantReload then M.magFull=false;return end
    if os.clock()<nextReload then return end
    nextReload=os.clock()+0.25
    local updater=player:call('get_Updater')
    if callFlag(updater,'isEquipGun')~=true or callFlag(updater,'isEquipThrowing')==true then return end
    local equipment=updater:call('get_Equipment')
    local full=nil
    pcall(function() full=equipment:call('isAmmoFull') end)
    if full==nil then
        pcall(function()
            local count,capacity=equipment:call('getLoadedAmmoCount'),equipment:call('getLoadedAmmoCapacity')
            if type(count)=='number' and type(capacity)=='number' then full=count>=capacity end
        end)
    end
    M.magFull=full==true
    if full==true then
        pcall(function() if updater:call('get_IsWaitDisposableGunReload')==true then updater:call('set_IsWaitDisposableGunReload',false) end end)
        return
    end
    if full==nil or M.ammoKept or os.clock()-(M.lastShot or -100)<0.4 then return end
    updater:call('execReload')
    pcall(function() if updater:call('get_IsWaitDisposableGunReload')==true then updater:call('set_IsWaitDisposableGunReload',false) end end)
    if not M.reloadSeen then M.reloadSeen=true;log.info('[Friteabc RE9] Instant reload: magazine refilled') end
end
M.gunReady=false
function M.TickCombat(player)
    if not player then M.gunReady=false;return end
    local refillOK,refillError=pcall(refill,player)
    if not refillOK and not M.reloadError then M.reloadError=true;log.info('[Friteabc RE9] Instant reload: '..tostring(refillError)) end
    M.gunReady=false
    if M.instantFire then
        pcall(function()
            local updater=player:call('get_Updater')
            M.gunReady=callFlag(updater,'isEquipGun')==true and callFlag(updater,'isEquipThrowing')~=true
        end)
    end
    if (M.instantFire or M.noRecoil or M.instantReload) then
        installCombat()
        pcall(function()
            local updater=player:call('get_Updater')
            if updater and updater:get_address()~=M.hookedUpdater then hookUpdater(updater);M.hookedUpdater=updater:get_address() end
        end)
    end
    if common then
        if M.instantFire and M.gunReady then
            if holdBackup==nil then
                local ok,was=pcall(function() return common:call('get_EnableHoldStartShootPose') end)
                holdBackup=ok and type(was)=='boolean' and was or false
            end
            pcall(function() if common:call('get_EnableHoldStartShootPose')~=true then common:call('set_EnableHoldStartShootPose',true) end end)
        elseif holdBackup~=nil then
            pcall(function() common:call('set_EnableHoldStartShootPose',holdBackup) end)
            holdBackup=nil
        end
    end
    pcall(function()
        local info=player:call('get_Updater'):call('get_Equipment'):get_field('_CustomInfo')
        if M.noRecoil then
            if not customInfo or customInfo:get_address()~=info:get_address() then
                customInfo=info
                infoBackup=info:get_field('RecoilShakeRate')
            end
            if info:get_field('RecoilShakeRate')~=0 then info:set_field('RecoilShakeRate',0.0) end
        elseif customInfo and type(infoBackup)=='number' then
            customInfo:set_field('RecoilShakeRate',infoBackup)
            customInfo,infoBackup=nil,nil
        end
    end)
end
function M.Release()
    if holdBackup~=nil and common then pcall(function() common:call('set_EnableHoldStartShootPose',holdBackup) end) end
    holdBackup=nil
    if customInfo and type(infoBackup)=='number' then pcall(function() customInfo:set_field('RecoilShakeRate',infoBackup) end) end
    customInfo,infoBackup=nil,nil
    if heartWas~=nil then setHeart(heartWas) end
    heartWas=nil;heart=nil
end
return M
