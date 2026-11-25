local M={points={},selected=1,status=nil,last=nil}
local config='friteabc_re9_teleports.json'
local loaded,saved=pcall(json.load_file,config)
if loaded and type(saved)=='table' and type(saved.points)=='table' then
    for _,p in ipairs(saved.points) do
        if type(p)=='table' and type(p.name)=='string' and type(p.x)=='number' and type(p.y)=='number' and type(p.z)=='number' then
            M.points[#M.points+1]={name=p.name,x=p.x,y=p.y,z=p.z}
        end
    end
end
function M.Save() json.dump_file(config,{points=M.points}) end
if not (loaded and type(saved)=='table') then pcall(M.Save) end
local option
local function warpOption()
    if option~=nil then return option end
    local optionType=sdk.find_type_definition('app.WarpOption')
    if optionType then
        for _,field in ipairs(optionType:get_fields()) do
            if field:is_static() and field:get_name()=='All' then
                option=field:get_data(nil)
                if option~=nil then break end
            end
        end
        if option==nil then
            for _,method in ipairs(optionType:get_methods()) do
                if method:get_name()=='get_Default' and method:is_static() and method:get_num_params()==0 then
                    option=method:call(nil);break
                end
            end
        end
    end
    assert(option~=nil,'Character warp options unavailable')
    return option
end
local warpMethods={}
local function findWarp(player)
    local typeName=player:get_type_definition():get_full_name()
    if warpMethods[typeName] then return warpMethods[typeName] end
    local class=player:get_type_definition()
    while class do
        for _,method in ipairs(class:get_methods()) do
            if method:get_name()=='setTransformBody' and method:get_num_params()==3 then
                local params=method:get_param_types()
                if params[1]:get_full_name()=='via.vec3' and params[2]:get_full_name()=='via.Quaternion' and params[3]:get_full_name()=='app.WarpOption' then
                    warpMethods[typeName]=method;return method
                end
            end
        end
        class=class:get_parent_type()
    end
    error('Compatible character teleport is unavailable')
end
function M.Warp(player,x,y,z,check)
    assert(player,'No playable character')
    local method=findWarp(player)
    local transform=assert(player:call('get_Transform'),'Character not ready')
    method:call(player,Vector3f.new(x,y,z),transform:call('get_Rotation'),warpOption())
    if check==false then return true end
    local actual=transform:call('get_Position')
    local dx,dy,dz=actual.x-x,actual.y-y,actual.z-z
    assert(dx*dx+dy*dy+dz*dz<0.04,'The character controller rejected the position')
    return true
end
local function here(player)
    local p=player:call('get_Transform'):call('get_Position')
    return {x=p.x,y=p.y,z=p.z}
end
function M.Add(player,name)
    assert(player,'No playable character')
    local p=here(player)
    p.name=(name and name~='') and name or ('Point '..(#M.points+1))
    M.points[#M.points+1]=p
    M.selected=#M.points
    M.Save()
    M.status='Saved '..p.name
end
function M.Go(player,index)
    local p=assert(M.points[index or M.selected],'Select a teleport point')
    local before=here(player)
    M.Warp(player,p.x,p.y,p.z)
    M.last=before
    M.status='Teleported to '..p.name
end
function M.GoTo(player,x,y,z)
    assert(player,'No playable character')
    assert(x,'Nothing aimed within 200 m')
    local before=here(player)
    M.Warp(player,x,y,z,false)
    M.last=before
    M.status=string.format('Teleported to aimed point (%.0f, %.0f, %.0f)',x,y,z)
end
function M.Undo(player)
    local p=assert(M.last,'Nothing to undo')
    M.Warp(player,p.x,p.y,p.z)
    M.last=nil
    M.status='Teleport undone'
end
function M.Remove(index)
    index=index or M.selected
    assert(M.points[index],'Select a teleport point')
    table.remove(M.points,index)
    M.selected=math.max(1,math.min(M.selected,#M.points))
    M.Save()
    M.status='Point removed'
end
function M.Names()
    local names={}
    for i,p in ipairs(M.points) do names[i]=p.name end
    return names
end
M.pending=nil
local function transition()
    return sdk.get_managed_singleton('app.SceneTransitionManager')
end
local function flow() return sdk.get_managed_singleton('app.MainGameFlowManager') end
local function controller()
    local manager=flow()
    return manager and manager:get_field('_CurrentController') or nil
end
function M.Busy()
    local ok,busy=pcall(function()
        local manager=transition()
        if manager and (manager:call('get_IsRunningTransition')==true or manager:call('get_IsCompleteSceneSetup')==false) then return true end
        local game=flow()
        if game and game:call('IsContinueToTransitionGame()')==true then return true end
        local c=controller()
        return c~=nil and c:call('get_IsContinuosTransition')==true
    end)
    return ok and busy==true
end
local function str(v)
    if v==nil then return nil end
    if type(v)=='string' then return v end
    local ok,t=pcall(function() return v:call('ToString()') end)
    return ok and type(t)=='string' and t or nil
end
local function dictionary(dict)
    local out={}
    local entries=dict:get_field('_entries')
    local count=dict:get_field('_count') or 0
    for i=0,count-1 do
        local entry=entries:get_element(i)
        local key=entry and str(entry:get_field('key'))
        if key and key~='' then out[key]=str(entry:get_field('value')) end
    end
    return out
end
M.chapters={};M.chapterIndex=1;M.current=nil;M.next=nil;M.all={}
local SPECIAL={Branch=true,ClearGame=true,ClearSubGame1=true,Return=true}
local function playable(name) return type(name)=='string' and name~='' and not SPECIAL[name] end
local function rawDictionary(dict)
    local out={}
    local entries=dict:get_field('_entries')
    for i=0,(dict:get_field('_count') or 0)-1 do
        local entry=entries:get_element(i)
        local key=entry and str(entry:get_field('key'))
        if key and key~='' then out[key]=entry:get_field('value') end
    end
    return out
end
local hashes={}
function M.Chapters()
    local manager=assert(flow(),'Game flow unavailable')
    local c=assert(controller(),'Chapter controller unavailable')
    local oneSide=manager:call('get_IsOneSideLMode')==true
    local table_=dictionary(c:get_field(oneSide and '_NextSceneTableForOneSideGame' or '_NextSceneTable'))
    pcall(function() hashes=rawDictionary(c:get_field('_HashDic')) end)
    M.current=str(c:get_field('_CurrentMainSceneName'))
    M.next=nil
    local step,guard=M.current and table_[M.current],0
    while step and guard<64 do
        if playable(step) and hashes[step]~=nil then M.next=step;break end
        step=table_[step];guard=guard+1
    end
    local first=str(manager:call('get_NewGameSceneName'))
    local list,seen={},{}
    local scene=first
    while scene and not seen[scene] do
        seen[scene]=true
        if playable(scene) and hashes[scene]~=nil then list[#list+1]=scene end
        scene=table_[scene]
    end
    M.all=list
    M.chapters=list
    M.chapterIndex=1
    for i,name in ipairs(list) do if name==M.next then M.chapterIndex=i end end
    pcall(function()
        local loadHash=manager:call('get_LoadMainGameNameHash')
        M.mappingOk=M.current~=nil and hashes[M.current]==loadHash
        json.dump_file('friteabc_re9_chapters.json',{current=M.current,next=M.next,order=list,table=table_,hashes=hashes,loadHash=loadHash,currentHash=manager:call('get_CurrentMainGameNameHash'),mappingOk=M.mappingOk})
    end)
    return list
end
local function managedString(value)
    if sdk.create_managed_string then return sdk.create_managed_string(value) end
    return value
end
local patched
local function nextTableName()
    local manager=flow()
    return manager and manager:call('get_IsOneSideLMode')==true and '_NextSceneTableForOneSideGame' or '_NextSceneTable'
end
local function setNext(from,to)
    local dict=controller():get_field(nextTableName())
    dict:call('set_Item(System.String, System.String)',managedString(from),managedString(to))
    return dictionary(dict)[from]
end
function M.RestoreNext()
    if not patched then return end
    local p=patched
    patched=nil
    local ok,why=pcall(setNext,p.from,p.original)
    log.info('[Friteabc RE9] Chapter table restored: '..p.from..' -> '..tostring(p.original)..(ok and '' or (' failed: '..tostring(why))))
end
M.trace={}
local traceHooked=false
local TRACED={'selectFlow','loadGameFlow','switchGameSceneFlow','setupSwitchGameScene','activateGameScene','updateCurrentMainSceneName',
    'makeTargetActiveGameSceneList','continueToTransitionGameFlow','startupScene','changePhase'}
local function snapshotFlow(name)
    local c=controller()
    local row={t=os.clock(),call=name}
    if c then
        row.current=str(c:get_field('_CurrentMainSceneName'))
        row.jumpTarget=str(c:get_field('_JumpTargetMainSceneName'))
        row.switchTo=str(c:get_field('_SwitchGameSceneName'))
        pcall(function() row.phase=c:get_field('_CurrentPhase') end)
    end
    return row
end
function M.Trace(on)
    M.tracing=on
    if not on or traceHooked then return end
    local definition=sdk.find_type_definition('app.MainGameFlowController')
    if not definition then return end
    traceHooked=true
    local wanted={}
    for _,n in ipairs(TRACED) do wanted[n]=true end
    for _,method in ipairs(definition:get_methods()) do
        local name=method:get_name()
        if wanted[name] then
            sdk.hook(method,function(args)
                if M.tracing and #M.trace<400 then
                    local row=snapshotFlow(name)
                    if name=='updateCurrentMainSceneName' then pcall(function() row.arg=str(sdk.to_managed_object(args[3])) end) end
                    M.trace[#M.trace+1]=row
                end
                return sdk.PreHookResult.CALL_ORIGINAL
            end,function(value) return value end)
        end
    end
end
function M.SaveTrace()
    pcall(json.dump_file,'friteabc_re9_chapter_trace.json',M.trace)
end
local function position(name)
    for i,n in ipairs(M.chapters) do if n==name then return i end end
end
function M.GoToChapter(target)
    assert(not M.pending,'A chapter change is already in progress')
    assert(not M.Busy(),'The game is already loading')
    M.Chapters()
    target=target or M.next
    assert(target,'No next chapter after '..tostring(M.current))
    assert(position(target),'Unknown chapter '..tostring(target))
    assert(target~=M.current,'Already in '..target)
    M.trace={}
    pcall(M.Trace,true)
    local from=M.current
    local original=dictionary(controller():get_field(nextTableName()))[from]
    local direct=false
    if original~=target then
        local ok,now=pcall(setNext,from,target)
        if ok and now==target then
            patched={from=from,original=original}
            direct=true
            log.info('[Friteabc RE9] Chapter table: '..from..' -> '..target..' (was '..tostring(original)..')')
        else
            log.info('[Friteabc RE9] Chapter table could not be changed: '..tostring(now))
        end
    else
        direct=true
    end
    if not direct then
        local here,there=position(from),position(target)
        assert(not here or there>here,'Only forward: use a save to go back')
        M.chain=target
    end
    local ok,why=pcall(M.Jump,false)
    if not ok then M.RestoreNext();M.chain=nil;error(why,0) end
    M.pending.chapter=target
    M.status='Going to '..target..(direct and '' or ' step by step')..', please wait...'
    log.info('[Friteabc RE9] Chapter change: '..tostring(from)..' -> '..target..(direct and ' (direct)' or ' (step by step)'))
end
function M.CancelChain() M.chain=nil;M.chainAt=nil end
function M.TickChain()
    if not M.chain or M.pending or M.Busy() then return end
    if not M.chainAt then M.chainAt=os.clock()+3;return end
    if os.clock()<M.chainAt then return end
    M.chainAt=nil
    local ok=pcall(M.Chapters)
    if not ok then return end
    if M.current==M.chain then
        M.status='Now in '..M.chain
        log.info('[Friteabc RE9] '..M.status)
        M.chain=nil
        return
    end
    local here,there=position(M.current),position(M.chain)
    if not here or not there or there<=here then
        M.status='Stopped in '..tostring(M.current)..' (could not reach '..M.chain..')'
        M.chain=nil
        return
    end
    local target=M.chain
    local jumped=pcall(M.Jump,false)
    if not jumped then M.chain=nil;M.status='Stopped in '..tostring(M.current);return end
    M.pending.chapter=target
    M.status='Going to '..target..' ('..(there-here)..' step'..((there-here)>1 and 's' or '')..' left)...'
end
function M.Watch(busy)
    local p=M.pending
    if not p then return end
    if busy then
        if not p.seen then
            p.seen=true
            if M.OnStart then pcall(M.OnStart) end
        end
        return
    end
    if p.seen then
        M.pending=nil
        if p.chapter then M.RestoreNext();M.SaveTrace();M.tracing=false end
        local now
        pcall(function() M.Chapters();now=M.current end)
        if p.chapter and M.chain then M.status='Now in '..tostring(now or '?')..', continuing to '..M.chain
        else M.status=p.chapter and ('Now in '..tostring(now or '?')) or (p.restart and 'Save loaded' or 'Scene reloaded') end
        M.refresh=true
        log.info('[Friteabc RE9] '..M.status)
    elseif os.clock()-p.time>12 then
        M.pending=nil
        if p.chapter then M.RestoreNext();M.SaveTrace();M.tracing=false end
        M.status='The game did not start the change here. Try another place.'
        log.info('[Friteabc RE9] '..M.status)
    end
end
function M.Jump(restart)
    assert(not M.pending,'A chapter change is already in progress')
    local manager=transition()
    assert(manager,'Scene transition manager unavailable')
    assert(manager:call('get_IsRunningTransition')==false,'A transition is already running')
    assert(manager:call('get_IsCompleteSceneSetup')==true,'The current scene is not ready yet')
    manager:call('requestMainGameJump(System.Boolean)',restart==true)
    M.pending={time=os.clock(),restart=restart==true}
    M.status=restart and 'Loading last save, please wait...' or 'Changing chapter, please wait...'
    log.info('[Friteabc RE9] '..(restart and 'Restarting from last save' or 'Jumping to next chapter'))
end
return M
