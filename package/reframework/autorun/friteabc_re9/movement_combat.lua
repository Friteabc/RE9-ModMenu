local M={forceShoot=false}
local current
local hooks={}
local scopes={}
local nextProbe=0
local probeRows={}
local probeMethodsSaved,probeLogged=false,false
local probeTypes={}
local eligibility={onUpdateScanPhase=true,updateHoldAction=true,isApplyShotAttack=true,isClearHoldInput=true,isContinueHoldInput=true,isEnableMeleeHold=true,isEnableMeleeAttack=true,checkShootEnable=true,isPermitOtherAttack=true}
local restrictions={get_IsRestrictionHold=true,get_IsRestrictionMeleeWepAttack=true,get_IsRestrictionCameraControl=true}
local function matches(args,address,native)
    return (args[2] and sdk.to_int64(args[2])==address) or (native and args[1] and sdk.to_int64(args[1])==address)
end
local function record(state,name,value,boolean)
    if not state or not state.stats then return end
    local entry=state.stats[name]
    if not entry then entry={calls=0,inScope=0};state.stats[name]=entry end
    entry.calls=entry.calls+1
    if (scopes[thread.get_id()] or 0)>0 then entry.inScope=entry.inScope+1 end
    if boolean then
        local ok,bit=pcall(function() return sdk.to_int64(value)%2==1 end)
        if ok then
            local key=bit and 'returnedTrue' or 'returnedFalse'
            entry[key]=(entry[key] or 0)+1
        end
    end
end
local function airCombat(s,input,updater)
    s.inputAddress=input:get_address()
    s.updaterAddress=updater:get_address()
    local controller=updater:call('get_CharacterController')
    s.controllerAddress=controller:get_address()
    local function walk(object,fn)
        local class=object:get_type_definition()
        while class do
            for _,method in ipairs(class:get_methods()) do fn(method) end
            class=class:get_parent_type()
        end
    end
    for _,entry in ipairs({{input,'inputAddress'},{updater,'updaterAddress'}}) do
        local object,role=entry[1],entry[2]
        walk(object,function(method)
            local key=method:get_function()
            if eligibility[method:get_name()] and not hooks[key] then
                local name=method:get_name()
                local boolean=method:get_return_type():get_full_name()=='System.Boolean'
                sdk.hook(method,function(args)
                    local state=current
                    if state then state.eligibilityCalls=state.eligibilityCalls+1 end
                    local storage=thread.get_hook_storage()
                    local id=thread.get_id()
                    storage.previousAirCombat=scopes[id]
                    storage.airCombatEntered=state and state.active and matches(args,state[role],false)
                    storage.airCombatTrack=state and matches(args,state[role],false) and state or nil
                    if storage.airCombatEntered then scopes[id]=(scopes[id] or 0)+1 end
                end,function(value)
                    local storage=thread.get_hook_storage()
                    if storage.airCombatEntered then scopes[thread.get_id()]=storage.previousAirCombat end
                    if storage.airCombatTrack then pcall(record,storage.airCombatTrack,name,value,boolean) end
                    return value
                end)
                hooks[key]=true
            end
        end)
    end
    for _,entry in ipairs({{controller,{get_Ground=true},true,'controllerAddress'},{updater,{get_IsGroundForUpdate=true,get_IsGroundForLateUpdate=true},false,'updaterAddress'}}) do
        local object,names,native,role=entry[1],entry[2],entry[3],entry[4]
        walk(object,function(method)
            local key=method:get_function()
            if names[method:get_name()] and method:get_num_params()==0 and method:get_return_type():get_full_name()=='System.Boolean' and not hooks[key] then
                local name=method:get_name()
                local ok,why=pcall(sdk.hook,method,function(args)
                    local state=current
                    local mine=state and matches(args,state[role],native)
                    local override=mine and state.active and (scopes[thread.get_id()] or 0)>0
                    thread.get_hook_storage().airCombatGround=override
                    thread.get_hook_storage().airCombatGroundTrack=mine and not override and state or nil
                    if override then pcall(record,state,name..' (overridden)',nil,false) end
                    if override then
                        state.groundOverrides=state.groundOverrides+1
                        if not state.airCombatSeen then
                            state.airCombatSeen=true
                            log.info('[Friteabc RE9] Air combat ground condition intercepted')
                        end
                    end
                    return override and sdk.PreHookResult.SKIP_ORIGINAL or sdk.PreHookResult.CALL_ORIGINAL
                end,function(value)
                    if thread.get_hook_storage().airCombatGround then return sdk.to_ptr(true) end
                    local tracked=thread.get_hook_storage().airCombatGroundTrack
                    if tracked then pcall(record,tracked,name,value,true) end
                    return value
                end)
                if ok then hooks[key]=true else log.error('[Friteabc RE9] Air combat ground hook: '..tostring(why)) end
            end
        end)
    end
end
local function fallGuard(s,updater)
    s.fallBlocked=0
    local report={hooked={},checker=nil}
    local class=updater:get_type_definition()
    while class do
        for _,method in ipairs(class:get_methods()) do
            if method:get_name()=='set_RequestedFallingHash' and method:get_num_params()==1 then
                local key=method:get_function()
                if not hooks[key] then
                    local ok,why=pcall(sdk.hook,method,function(args)
                        local state=current
                        if state and state.active and sdk.to_int64(args[2])==state.updaterAddress then
                            state.fallBlocked=state.fallBlocked+1
                            if not state.fallLogged then state.fallLogged=true;log.info('[Friteabc RE9] Fall animation request blocked') end
                            return sdk.PreHookResult.SKIP_ORIGINAL
                        end
                        return sdk.PreHookResult.CALL_ORIGINAL
                    end,function(value) return value end)
                    if ok then hooks[key]=true;report.hooked[#report.hooked+1]='Updater.set_RequestedFallingHash'
                    else log.error('[Friteabc RE9] Fall request hook: '..tostring(why)) end
                end
            end
        end
        class=class:get_parent_type()
    end
    local ok,checker=pcall(function() return updater:call('get_AnimFallGroundChecker') end)
    if ok and checker then
        s.checkerAddress=checker:get_address()
        local info={type=checker:get_type_definition():get_full_name(),methods={},fields={}}
        report.checker=info
        local class=checker:get_type_definition()
        while class do
            for _,field in ipairs(class:get_fields()) do info.fields[#info.fields+1]=field:get_name()..' : '..field:get_type():get_full_name() end
            for _,method in ipairs(class:get_methods()) do
                local name=method:get_name()
                local ret=method:get_return_type():get_full_name()
                info.methods[#info.methods+1]=name..'('..method:get_num_params()..') -> '..ret
                local wanted
                if ret=='System.Boolean' and (name=='checkFallGround' or name=='checkFallGroundCore') then wanted=true end
                local key=method:get_function()
                if wanted~=nil and not hooks[key] then
                    local hooked=pcall(sdk.hook,method,function(args)
                        local state=current
                        local mine=state and sdk.to_int64(args[2])==state.checkerAddress and state or nil
                        local storage=thread.get_hook_storage()
                        storage.fallCheckerState=mine
                        storage.fallChecker=mine and mine.active
                        return sdk.PreHookResult.CALL_ORIGINAL
                    end,function(value)
                        local storage=thread.get_hook_storage()
                        if storage.fallCheckerState then pcall(record,storage.fallCheckerState,name,value,true) end
                        if storage.fallChecker then
                            local state=storage.fallCheckerState
                            if not state.checkerLogged then state.checkerLogged=true;log.info('[Friteabc RE9] Fall ground check overridden: '..name) end
                            return sdk.to_ptr(wanted)
                        end
                        return value
                    end)
                    if hooked then hooks[key]=true;report.hooked[#report.hooked+1]='FallChecker.'..name..'='..tostring(wanted) end
                end
            end
            class=class:get_parent_type()
        end
    end
    pcall(function() json.dump_file('friteabc_re9_fall.json',report) end)
    log.info('[Friteabc RE9] Fall guard hooks: '..#report.hooked)
end
local FALL_FLAG=2097152
local envSkip={
    ['app.EnvironmentProcessDriver']={updateFallInfo=true,detectGroundForAutoFallAction=true},
    ['app.PlayerEnvironmentProcessDriver']={checkFallLengthRequestedFallingHash=true,landingPlayerProcess=true,
        checkSafeAreaFallEnd=true,setLandingAction=true,onUpdateScanPhase=true,lateUpdateAdditionalAction=true}
}
local envHeights={'HeightKeepGround','HeightPreventFall'}
local function field(object,name)
    for _,candidate in ipairs({'<'..name..'>k__BackingField','_'..name,name}) do
        local ok,value=pcall(function() return object:get_field(candidate) end)
        if ok and value~=nil then return value,candidate end
    end
end
local function setField(object,name,value)
    local _,candidate=field(object,name)
    if candidate then pcall(function() object:set_field(candidate,value) end) end
end
local function envGuard(s,updater)
    local env=field(updater,'EnvironmentProcessDriver')
    if not env then pcall(function() env=updater:call('get_EnvironmentProcessDriver') end) end
    if not env then log.info('[Friteabc RE9] Fall system driver unavailable');return end
    s.env=env;s.envAddress=env:get_address();s.envOriginal={}
    for _,name in ipairs(envHeights) do s.envOriginal[name]=field(env,name) end
    local installed=0
    for typeName,names in pairs(envSkip) do
        local definition=sdk.find_type_definition(typeName)
        if definition then
            for _,method in ipairs(definition:get_methods()) do
                local name=method:get_name()
                local key=method:get_function()
                if names[name] and method:get_return_type():get_full_name()=='System.Void' and not hooks[key] then
                    local ok=pcall(sdk.hook,method,function(args)
                        local state=current
                        if state and state.active and state.envAddress and sdk.to_int64(args[2])==state.envAddress then
                            state.envSkipped=(state.envSkipped or 0)+1
                            return sdk.PreHookResult.SKIP_ORIGINAL
                        end
                        return sdk.PreHookResult.CALL_ORIGINAL
                    end,function(value) return value end)
                    if ok then hooks[key]=true;installed=installed+1 end
                end
            end
        end
    end
    log.info('[Friteabc RE9] Fall system hooks: '..installed)
end
local function suppressFall(s)
    local env=s.env
    if not env then return end
    for _,name in ipairs({'preventFall','stopFreeFallCtrl'}) do
        if s.envNoArg==nil then s.envNoArg={} end
        if s.envNoArg[name]==nil then
            s.envNoArg[name]=false
            pcall(function()
                local class=env:get_type_definition()
                while class do
                    for _,method in ipairs(class:get_methods()) do
                        if method:get_name()==name and method:get_num_params()==0 then s.envNoArg[name]=true end
                    end
                    class=class:get_parent_type()
                end
            end)
        end
        if s.envNoArg[name] then pcall(function() env:call(name) end) end
    end
    for _,name in ipairs(envHeights) do setField(env,name,100000.0) end
    setField(env,'FallHeight',0.0);setField(env,'PrevFallHeight',0.0)
    setField(env,'IsKeepGround',true);setField(env,'IsPrevKeepGround',true)
    pcall(function() if s.common:call('get_FallType')~=0 then s.common:call('set_FallType',0) end end)
    local now=os.clock()
    if now<(s.nextFallExit or 0) then return end
    pcall(function()
        local actions=s.updater:call('get_ActionBlackboardUnit')
        local tag=actions:call('get_ActionState'):call('get_Tag')
        if type(tag)=='number' and math.floor(tag/FALL_FLAG)%2==1 then
            s.nextFallExit=now+0.3
            actions:call('requestEndCurrentAction')
            if not s.fallExitLogged then s.fallExitLogged=true;log.info('[Friteabc RE9] Fall action ended for noclip') end
        end
    end)
end
local function restoreEnv(s)
    if not s.env or not s.envOriginal then return end
    for _,name in ipairs(envHeights) do
        if s.envOriginal[name]~=nil then setField(s.env,name,s.envOriginal[name]) end
    end
end
function M.Release()
    local s=current;current=nil
    if s then
        pcall(restoreEnv,s)
        local ok,why=pcall(function() s.common:call('set_ForceShootEnable',s.original) end)
        if not ok then log.error('[Friteabc RE9] Combat restore: '..tostring(why)) end
    end
end
function M.Bind(player,updater)
    M.Release()
    local common=player:call('get_Common')
    assert(common,'Player shooting settings unavailable')
    local original=common:call('get_ForceShootEnable')
    assert(type(original)=='boolean','Unsupported shooting permission')
    local s={common=common,original=original,updater=updater,active=false,groundOverrides=0,eligibilityCalls=0,stats={}}
    current=s
    s.updaterAddress=updater:get_address()
    local envOK,envWhy=pcall(envGuard,s,updater)
    if not envOK then log.error('[Friteabc RE9] Fall system: '..tostring(envWhy)) end
    local fallOK,fallWhy=pcall(fallGuard,s,updater)
    if not fallOK then log.error('[Friteabc RE9] Fall guard: '..tostring(fallWhy)) end
    local input=updater:call('get_InputDriver')
    if input then airCombat(s,input,updater) end
    local ok,unit=pcall(function() return input:call('get_RestrictUnit') end)
    if not ok or not unit then
        log.info('[Friteabc RE9] Movement combat: restriction unit unavailable')
        return
    end
    s.address=unit:get_address()
    local class=unit:get_type_definition()
    while class do
        for _,method in ipairs(class:get_methods()) do
            if restrictions[method:get_name()] and method:get_num_params()==0 and method:get_return_type():get_full_name()=='System.Boolean' then
                local key=method:get_function()
                if not hooks[key] then
                    sdk.hook(method,function(args)
                        local state=current
                        local override=state and state.active and sdk.to_int64(args[2])==state.address
                        thread.get_hook_storage().movementCombat=override
                        return override and sdk.PreHookResult.SKIP_ORIGINAL or sdk.PreHookResult.CALL_ORIGINAL
                    end,function(value)
                        if thread.get_hook_storage().movementCombat then return sdk.to_ptr(false) end
                        return value
                    end)
                    hooks[key]=true
                end
            end
        end
        class=class:get_parent_type()
    end
end
function M.Apply(enabled)
    local s=current
    if not s then return end
    local control=s.updater:call('get_IsControlModeInput')
    s.controlMode=control
    local wasActive=s.active
    s.active=enabled and control==true
    if s.active then pcall(suppressFall,s) elseif wasActive then pcall(restoreEnv,s) end
    if M.forceShoot then
        local wanted=s.active or s.original
        if s.common:call('get_ForceShootEnable')~=wanted then s.common:call('set_ForceShootEnable',wanted) end
    elseif s.common:call('get_ForceShootEnable')~=s.original then
        s.common:call('set_ForceShootEnable',s.original)
    end
end
local keyFrames={frames=0,leftMouse=0,rightMouse=0}
function M.Probe(player,enabled)
    if not player then return end
    keyFrames.frames=keyFrames.frames+1
    pcall(function()
        if reframework:is_key_down(1) then keyFrames.leftMouse=keyFrames.leftMouse+1 end
        if reframework:is_key_down(2) then keyFrames.rightMouse=keyFrames.rightMouse+1 end
    end)
    if os.clock()<nextProbe then return end
    nextProbe=os.clock()+0.5
    local keys=keyFrames;keyFrames={frames=0,leftMouse=0,rightMouse=0}
    local row={keys=keys,time=os.clock(),movement=enabled,active=current and current.active or false,
        eligibilityCalls=current and current.eligibilityCalls or 0,groundOverrides=current and current.groundOverrides or 0}
    if current then row.hookResults=current.stats;current.stats={};row.fallBlocked=current.fallBlocked;row.envSkipped=current.envSkipped;current.envSkipped=0 end
    pcall(function()
        local p=player:call('get_Transform'):call('get_Position')
        row.position={x=p.x,y=p.y,z=p.z}
    end)
    local objects={Player=player}
    local function child(label,parent,getter)
        if not parent then return end
        local ok,value=pcall(function() return parent:call(getter) end)
        if ok then objects[label]=value end
        return ok and value or nil
    end
    local updater=child('Updater',player,'get_Updater')
    local common=child('Common',player,'get_Common')
    child('Controller',updater,'get_CharacterController')
    local input=child('InputDriver',updater,'get_InputDriver')
    child('InputUnit',updater,'get_InputUnit')
    child('Restriction',input,'get_RestrictUnit')
    local actions=child('Actions',updater,'get_ActionBlackboardUnit')
    child('ActionState',actions,'get_ActionState')
    child('SubActionState',actions,'get_SubActionState')
    local getters={
        Common={'ForceShootEnable','IsShootEnable','IsShooting','FallType','ActionControl','ForceShootPreInput'},
        Updater={'IsControlModeInput','IsControlModeThink','IsGroundForUpdate','IsGroundForLateUpdate'},
        Controller={'Enabled','Ground'},InputDriver={'IsEnable'},
        InputUnit={'IsHoldInput','IsOriginHoldInput','IsShotAttackInput','IsShotAttackContinueInput','IsReloadInput'},
        Restriction={'IsRestrictionHold','IsRestrictionMeleeWepAttack','IsRestrictionCameraControl'},
        ActionState={'Action','PrevAction','Category','PrevActionCategry','Priority','OverridePriority','Tag','TagType','ActionEnd','ThinkOff'},
        SubActionState={'Action','PrevAction','Category','PrevActionCategry','Priority','OverridePriority','Tag','TagType','ActionEnd','ThinkOff'}
    }
    for label,object in pairs(objects) do
        local values={type=object:get_type_definition():get_full_name()}
        row[label]=values
        for _,prop in ipairs(getters[label] or {}) do pcall(function()
            local value=object:call('get_'..prop)
            if type(value)=='number' or type(value)=='boolean' or type(value)=='string' then values[prop]=value
            elseif value~=nil and (label=='ActionState' or label=='SubActionState') then
                local ok,text=pcall(function() return value:call('ToString()') end)
                if ok and type(text)=='string' then values[prop]=text
                else pcall(function() values[prop]=value:get_type_definition():get_full_name() end) end
            end
        end) end
        if label=='ActionState' or label=='SubActionState' then
            values.fields={}
            if not probeMethodsSaved then values.methods={} end
            for _,field in ipairs(object:get_type_definition():get_fields()) do pcall(function()
                local value=field:get_data(object)
                values.fields[field:get_name()]={type=field:get_type():get_full_name(),value=(type(value)=='number' or type(value)=='boolean' or type(value)=='string') and value or nil}
            end) end
            if values.methods then
                for _,method in ipairs(object:get_type_definition():get_methods()) do values.methods[#values.methods+1]=method:get_name() end
                probeTypes[label]={type=values.type,methods=values.methods}
                values.methods=nil
            end
        end
    end
    pcall(function()
        local u=objects.Updater
        if not u then return end
        local ground={}
        row.groundState=ground
        for _,name in ipairs({'CurrentGroundPosition','PreviousGroundPosition'}) do
            local entry={}
            ground[name]=entry
            pcall(function()
                local value=u:get_field('<'..name..'>k__BackingField')
                entry.luaType=type(value)
                if value==nil then entry.isNil=true;return end
                for _,flag in ipairs({'hasValue','_hasValue','HasValue'}) do
                    local ok,v=pcall(function() return value:get_field(flag) end)
                    if ok and v~=nil then entry.hasValue=v;break end
                end
                local ok,inner=pcall(function() return value:get_field('value') end)
                if ok and inner then
                    for _,axis in ipairs({'x','y','z'}) do
                        local okAxis,n=pcall(function() return inner[axis] or inner:get_field(axis) end)
                        if okAxis and type(n)=='number' then entry[axis]=n end
                    end
                end
            end)
        end
        for _,getter in ipairs({'IsOnStair','UpdateGroundMinDistanceSQ','IsGroundForUpdate','IsGroundForLateUpdate'}) do
            pcall(function()
                local v=u:call('get_'..getter)
                if type(v)=='number' or type(v)=='boolean' then ground[getter]=v end
            end)
        end
        pcall(function()
            local v=u:get_field('_SafeFallTimer')
            if type(v)=='number' then ground.safeFallTimer=v end
        end)
    end)
    row.enums={}
    for _,name in ipairs({'app.CharacterFallParam.FallType','app.PlayerDefine.ActionControlType','app.PlayerDefine.ActionFlag'}) do pcall(function()
        local definition=sdk.find_type_definition(name)
        if definition then
            local values={};row.enums[name]=values
            for _,field in ipairs(definition:get_fields()) do if field:is_static() then
                local value=field:get_data(nil)
                if type(value)=='number' then values[field:get_name()]=value end
            end end
        end
    end) end
    probeRows[#probeRows+1]=row
    if #probeRows>100 then table.remove(probeRows,1) end
    if not probeMethodsSaved and next(probeTypes) then probeMethodsSaved=true;json.dump_file('friteabc_re9_combat_types.json',probeTypes) end
    json.dump_file('friteabc_re9_combat.json',probeRows)
    if not probeLogged then probeLogged=true;log.info('[Friteabc RE9] Combat probe recording to friteabc_re9_combat.json') end
end
return M
