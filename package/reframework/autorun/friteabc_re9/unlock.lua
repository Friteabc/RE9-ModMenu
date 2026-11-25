local M={status=nil,radius=2.5}
local CALLS={'forceUnlock','unlock','requestUnlock','execUnlock','doUnlock','unlockGimmick','forceSolve','solve','requestSolve','onSolved',
    'forceComplete','complete','requestComplete','onComplete','onSuccess','success','forceOpen','requestOpen','open'}
local SETTERS={set_IsUnlock=true,set_IsUnlocked=true,set_IsLocked=false,set_IsLock=false,set_IsSolved=true,set_IsSolve=true,
    set_IsClear=true,set_IsCleared=true,set_IsComplete=true,set_IsCompleted=true,set_IsOpen=true,set_IsOpened=true}
local MANAGERS={'app.GimmickManager','app.GmManager','app.GimmickFlagManager','app.FlagManager','app.GameFlagManager','app.GmDataManager',
    'app.GimmickSaveDataManager','app.ScenarioFlagManager','app.EventFlagManager','app.PuzzleManager','app.InteractManager'}
local function components(object)
    local list={}
    pcall(function() for _,c in ipairs(object:call('get_Components'):get_elements()) do list[#list+1]=c end end)
    return list
end
local function positionOf(object)
    local ok,p=pcall(function() return object:call('get_Transform'):call('get_Position') end)
    if ok and p and type(p.x)=='number' then return p end
end
local function family(target,origin)
    local objects,seen={},{}
    local function add(object) if object and not seen[object:get_address()] then seen[object:get_address()]=true;objects[#objects+1]=object end end
    add(target)
    local transform=target:call('get_Transform')
    local parent=transform
    for _=1,4 do
        local ok,p=pcall(function() return parent:call('get_Parent') end)
        if not ok or not p then break end
        add(p:call('get_GameObject'));parent=p
    end
    pcall(function()
        local child=transform:call('get_Child')
        local count=0
        while child and count<16 do add(child:call('get_GameObject'));child=child:call('get_Next');count=count+1 end
    end)
    origin=origin or positionOf(target)
    if origin then
        pcall(function()
            local scene=sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
            local near={}
            for _,core in ipairs(scene:call('findComponents(System.Type)',sdk.typeof('app.GimmickCore')):get_elements()) do
                local go=core:call('get_GameObject')
                local p=go and positionOf(go)
                if p then
                    local dx,dy,dz=p.x-origin.x,p.y-origin.y,p.z-origin.z
                    local d=math.sqrt(dx*dx+dy*dy+dz*dz)
                    if d<=M.radius then near[#near+1]={go=go,d=d} end
                end
            end
            table.sort(near,function(a,b) return a.d<b.d end)
            for i=1,math.min(#near,4) do add(near[i].go) end
        end)
    end
    return objects
end
local function methodsOf(component)
    local list={}
    local class=component:get_type_definition()
    while class do
        local name=class:get_full_name()
        if name:find('^via%.') or name=='System.Object' then break end
        for _,method in ipairs(class:get_methods()) do list[#list+1]=method end
        class=class:get_parent_type()
    end
    return list
end
local function signature(method)
    local params={}
    pcall(function() for _,p in ipairs(method:get_param_types()) do params[#params+1]=p:get_full_name() end end)
    local ret='?'
    pcall(function() ret=method:get_return_type():get_full_name() end)
    return method:get_name()..'('..table.concat(params,', ')..')->'..ret
end
local function plain(value)
    local t=type(value)
    if t=='boolean' or t=='number' or t=='string' then return value end
    if t=='userdata' then
        local ok,text=pcall(function() return value:call('ToString()') end)
        if ok and type(text)=='string' then return text end
    end
    return t
end
local function fieldsOf(object)
    local list={}
    pcall(function()
        local class=object:get_type_definition()
        while class do
            local name=class:get_full_name()
            if name:find('^via%.') or name=='System.Object' then break end
            for _,field in ipairs(class:get_fields()) do
                if not field:is_static() then list[#list+1]={name=field:get_name(),type=field:get_type():get_full_name()} end
            end
            class=class:get_parent_type()
        end
    end)
    return list
end
local function wanted(name)
    local low=name:lower()
    if low:find('unlock') or low:find('open') or low:find('solve') or low:find('clear') or low:find('complete') or low:find('success') then
        if low:find('can') or low:find('enable') or low:find('request') then return nil end
        return true
    end
    if low:find('lock') then return false end
end
local function describe(object)
    local row={}
    for _,field in ipairs(fieldsOf(object)) do
        local ok,value=pcall(function() return object:get_field(field.name) end)
        row[#row+1]=field.name..':'..field.type..'='..tostring(ok and plain(value) or '?')
    end
    return row
end
local function managers()
    local found={}
    for _,name in ipairs(MANAGERS) do
        local ok,object=pcall(function() return sdk.get_managed_singleton(name) end)
        if ok and object then
            local entry={type=name,methods={}}
            pcall(function()
                for _,method in ipairs(methodsOf(object)) do
                    local n=method:get_name():lower()
                    if n:find('flag') or n:find('gimmick') or n:find('unlock') or n:find('open') or n:find('solve') or n:find('clear') then entry.methods[#entry.methods+1]=signature(method) end
                end
            end)
            found[#found+1]=entry
        end
    end
    return found
end
local function enumNames(typeName)
    local map={}
    pcall(function()
        for _,field in ipairs(sdk.find_type_definition(typeName):get_fields()) do
            if field:is_static() then
                local ok,value=pcall(function() return field:get_data(nil) end)
                if ok and type(value)=='number' then map[value]=field:get_name() end
            end
        end
    end)
    return map
end
local OPEN={'unlock','open','solve','clear','complete','success'}
local function openStatus(names)
    for _,word in ipairs(OPEN) do
        for value,name in pairs(names) do
            local low=name:lower()
            if low:find(word) and not low:find('not') and not low:find('wait') and not low:find('request') then return value,name end
        end
    end
end
local function isTrigger(object,name)
    if name and (name:find('AreaHit') or name:find('Trigger') or name:find('Sensor')) then return true end
    for _,component in ipairs(components(object)) do
        local ok,typeName=pcall(function() return component:get_type_definition():get_full_name() end)
        if ok and (typeName:find('LevelFlow') or typeName:find('AreaHit')) then return true end
    end
    return false
end
local function hasGimmick(object)
    for _,component in ipairs(components(object)) do
        local ok,typeName=pcall(function() return component:get_type_definition():get_full_name() end)
        if ok and typeName=='app.GimmickCore' then return true end
    end
    return false
end
local function pick(contacts)
    local chosen
    for _,contact in ipairs(contacts) do
        if hasGimmick(contact.object) then return contact end
        if not chosen and not isTrigger(contact.object,contact.name) then chosen=contact end
    end
    return chosen or contacts[1]
end
function M.UnlockAimed(aim)
    assert(aim,'Aim at the lock or puzzle (centre of the screen)')
    local target,origin,seen=aim,nil,nil
    if type(aim)=='table' and aim.get_address==nil then
        local contact=pick(aim)
        assert(contact,'Aim at the lock or puzzle (centre of the screen)')
        target,origin=contact.object,{x=contact.x,y=contact.y,z=contact.z}
        seen={}
        for _,c in ipairs(aim) do seen[#seen+1]=c.name end
    end
    local statusNames=enumNames('app.GmBase.StatusType')
    local openValue,openName=openStatus(statusNames)
    local report={target=target:call('get_Name'),contacts=seen,objects={},changed={},statusNames={}}
    for value,name in pairs(statusNames) do report.statusNames[#report.statusNames+1]=name..'='..tostring(value) end
    local done={}
    local work={}
    for _,object in ipairs(family(target,origin)) do
        local row={name=object:call('get_Name'),components={}}
        for _,component in ipairs(components(object)) do
            local typeName=component:get_type_definition():get_full_name()
            local entry={type=typeName,methods={}}
            if not typeName:find('^via%.') then
                for _,method in ipairs(methodsOf(component)) do entry.methods[#entry.methods+1]=signature(method) end
                entry.fields=describe(component)
                pcall(function()
                    local status=component:get_field('_StatusType')
                    if type(status)=='number' then entry.status=tostring(statusNames[status] or status) end
                end)
                if typeName=='app.GimmickCore' then
                    pcall(function()
                        local context=component:call('get_Context')
                        if context then
                            entry.context={type=context:get_type_definition():get_full_name(),fields=describe(context)}
                            pcall(function()
                                local sdc=context:get_field('_SDC')
                                local methods={}
                                for _,method in ipairs(methodsOf(sdc)) do methods[#methods+1]=signature(method) end
                                entry.context.sdc={type=sdc:get_type_definition():get_full_name(),fields=describe(sdc),methods=methods}
                            end)
                            pcall(function()
                                local data=component:get_field('_GmBaseData')
                                entry.baseData={type=data:get_type_definition():get_full_name(),fields=describe(data)}
                            end)
                            work[#work+1]={object=context,name='GimmickContext'}
                        end
                    end)
                end
                work[#work+1]={object=component,name=typeName,entry=entry}
            end
            row.components[#row.components+1]=entry
        end
        report.objects[#report.objects+1]=row
    end
    report.managers=managers()
    pcall(json.dump_file,'friteabc_re9_unlock.json',report)
    for _,item in ipairs(work) do
        local component,typeName=item.object,item.name
        local short=typeName:gsub('^app%.','')
        if item.entry then
            local byName={}
            for _,method in ipairs(methodsOf(component)) do
                if method:get_num_params()==0 and not byName[method:get_name()] then byName[method:get_name()]=method end
            end
            for _,name in ipairs(CALLS) do
                if byName[name] then
                    log.info('[Friteabc RE9] Unlock: '..typeName..'.'..name)
                    if pcall(function() component:call(name) end) then done[#done+1]=short..'.'..name end
                    break
                end
            end
            for _,method in ipairs(methodsOf(component)) do
                local value=SETTERS[method:get_name()]
                if value~=nil and method:get_num_params()==1 then
                    local okType,param=pcall(function() return method:get_param_types()[1]:get_full_name() end)
                    if okType and param=='System.Boolean' then
                        log.info('[Friteabc RE9] Unlock: '..typeName..'.'..method:get_name()..'('..tostring(value)..')')
                        if pcall(function() component:call(method:get_name(),value) end) then done[#done+1]=short..'.'..method:get_name() end
                    end
                end
            end
        end
        if typeName:find('^app%.Gm') or typeName=='GimmickContext' then
            for _,field in ipairs(fieldsOf(component)) do
                if field.type=='System.Boolean' then
                    local value=wanted(field.name)
                    if value~=nil then
                        local ok,before=pcall(function() return component:get_field(field.name) end)
                        if ok and type(before)=='boolean' and before~=value then
                            if pcall(function() component:set_field(field.name,value) end) then
                                local after=component:get_field(field.name)
                                report.changed[#report.changed+1]=short..'.'..field.name..' '..tostring(before)..' -> '..tostring(after)
                                if after==value then done[#done+1]=short..'.'..field.name end
                                log.info('[Friteabc RE9] Unlock: '..typeName..'.'..field.name..' '..tostring(before)..' -> '..tostring(after))
                            end
                        end
                    end
                end
            end
        end
    end
    if openValue then
        for _,item in ipairs(work) do
            local component=item.object
            local short=item.name:gsub('^app%.','')
            if item.entry and item.name:find('^app%.Gm') and item.name~='app.GmGlobalFlag2Switcher' then
                local ok,current=pcall(function() return component:get_field('_RequestStatusType') end)
                if ok and type(current)=='number' and current~=openValue then
                    if pcall(function() component:set_field('_RequestStatusType',openValue) end) then
                        report.changed[#report.changed+1]=short..'._RequestStatusType '..tostring(statusNames[current] or current)..' -> '..openName
                        done[#done+1]=short..' -> '..openName
                        log.info('[Friteabc RE9] Unlock: '..item.name..' status -> '..openName)
                    end
                end
            end
        end
    end
    report.called=done
    pcall(json.dump_file,'friteabc_re9_unlock.json',report)
    M.status=#done>0 and ('Unlocked: '..table.concat(done,', ')) or ('No unlock function on '..tostring(report.target)..' (details saved)')
end
return M
