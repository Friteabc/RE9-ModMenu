local M={target=nil,targetName=nil,removed={},status=nil,deleteKey=true}
local query,result,method,system,direct
local function setup()
    if query then return end
    local definition=sdk.find_type_definition('via.physics.System')
    for _,candidate in ipairs(definition:get_methods()) do
        local names={}
        for _,param in ipairs(candidate:get_param_types()) do names[#names+1]=param:get_full_name() end
        if candidate:get_name()=='castRay' and #names==2 and names[1]=='via.physics.CastRayQuery' and names[2]=='via.physics.CastRayResult' then method=candidate end
        if candidate:get_name()=='castRay' and #names==1 and names[1]=='via.physics.CastRayQuery' and candidate:is_static() then method=candidate end
    end
    assert(method,'Ray casting unavailable')
    system=sdk.get_native_singleton('via.physics.System') or sdk.get_managed_singleton('via.physics.System')
    direct=method:get_num_params()==1
    query=sdk.create_instance('via.physics.CastRayQuery');query:add_ref()
    if not direct then result=sdk.create_instance('via.physics.CastRayResult');result:add_ref() end
    query:call('clearOptions')
    query:call('enableAllHits')
    query:call('enableNearSort')
    local filter=query:call('get_FilterInfo')
    filter:call('set_MaskBits',4294967295)
    query:call('set_FilterInfo',filter)
end
local function ownerOf(collidable)
    for _,getter in ipairs({'get_GameObject','get_Owner','get_OwnerGameObject'}) do
        local ok,value=pcall(function() return collidable:call(getter) end)
        if ok and value then
            local okType,name=pcall(function() return value:get_type_definition():get_full_name() end)
            if okType and name=='via.GameObject' then return value end
            local okGo,go=pcall(function() return value:call('get_GameObject') end)
            if okGo and go then return go end
        end
    end
end
local function nameOf(go)
    local ok,name=pcall(function() return go:call('get_Name') end)
    return ok and type(name)=='string' and name or '?'
end
function M.Scan(player)
    setup()
    local camera=sdk.get_primary_camera()
    if not camera then M.target=nil;return end
    local transform=camera:call('get_GameObject'):call('get_Transform')
    local from=transform:call('get_Position')
    local back=transform:call('get_AxisZ')
    local to=Vector3f.new(from.x-back.x*80,from.y-back.y*80,from.z-back.z*80)
    query:call('setRay(via.vec3, via.vec3)',Vector3f.new(from.x,from.y,from.z),to)
    if direct then result=method:call(nil,query) else method:call(system,query,result) end
    M.target=nil;M.targetName=nil
    if not result then return end
    local playerObject=player and player:call('get_GameObject')
    local playerAddress=playerObject and playerObject:get_address()
    local count=result:call('get_NumContactPoints')
    for index=0,math.min(count,32)-1 do
        local ok,go=pcall(function() return ownerOf(result:call('getContactCollidable(System.UInt32)',index)) end)
        if ok and go and go:get_address()~=playerAddress then
            M.target=go;M.targetName=nameOf(go)
            return
        end
    end
end
local function setState(go,on)
    pcall(function() go:call('set_DrawSelf',on) end)
    pcall(function() go:call('set_UpdateSelf',on) end)
    pcall(function()
        for _,component in ipairs(go:call('get_Components'):get_elements()) do
            local okName,typeName=pcall(function() return component:get_type_definition():get_full_name() end)
            if okName and (typeName:find('Collider') or typeName:find('CharacterController')) then
                pcall(function() component:call('set_Enabled',on) end)
            end
        end
    end)
end
function M.RemoveTarget()
    local go=M.target
    if not go then M.status='Nothing aimed (centre of the screen)';return end
    local key=go:get_address()
    if M.removed[key] then return end
    go:add_ref()
    M.removed[key]={object=go,name=M.targetName}
    setState(go,false)
    M.status='Removed: '..tostring(M.targetName)
    log.info('[Friteabc RE9] Object removed: '..tostring(M.targetName))
    M.target=nil
end
function M.Count()
    local n=0
    for _ in pairs(M.removed) do n=n+1 end
    return n
end
function M.RestoreAll()
    for _,entry in pairs(M.removed) do
        pcall(function()
            if entry.object:call('get_Valid')~=false then setState(entry.object,true) end
        end)
    end
    M.removed={}
    M.status='Removed objects restored'
end
function M.AimPoint(player)
    setup()
    local camera=assert(sdk.get_primary_camera(),'Camera unavailable')
    local transform=camera:call('get_GameObject'):call('get_Transform')
    local from=transform:call('get_Position')
    local back=transform:call('get_AxisZ')
    local to=Vector3f.new(from.x-back.x*200,from.y-back.y*200,from.z-back.z*200)
    query:call('setRay(via.vec3, via.vec3)',Vector3f.new(from.x,from.y,from.z),to)
    if direct then result=method:call(nil,query) else method:call(system,query,result) end
    if not result then return nil end
    local playerObject=player and player:call('get_GameObject')
    local playerAddress=playerObject and playerObject:get_address()
    local count=result:call('get_NumContactPoints')
    for index=0,math.min(count,32)-1 do
        local okOwner,go=pcall(function() return ownerOf(result:call('getContactCollidable(System.UInt32)',index)) end)
        if not (okOwner and go and go:get_address()==playerAddress) then
            local point=result:call('getContactPoint(System.UInt32)',index)
            local position=point:get_field('Position')
            local normal=point:get_field('Normal')
            if position then
                if normal and normal.y>=0.6 then return position.x,position.y+0.05,position.z end
                return position.x+back.x*0.6,position.y,position.z+back.z*0.6
            end
        end
    end
    return nil
end
function M.Contacts(player)
    setup()
    local camera=assert(sdk.get_primary_camera(),'Camera unavailable')
    local transform=camera:call('get_GameObject'):call('get_Transform')
    local from=transform:call('get_Position')
    local back=transform:call('get_AxisZ')
    local to=Vector3f.new(from.x-back.x*40,from.y-back.y*40,from.z-back.z*40)
    query:call('setRay(via.vec3, via.vec3)',Vector3f.new(from.x,from.y,from.z),to)
    if direct then result=method:call(nil,query) else method:call(system,query,result) end
    local list={}
    if not result then return list end
    local playerObject=player and player:call('get_GameObject')
    local playerAddress=playerObject and playerObject:get_address()
    local count=result:call('get_NumContactPoints')
    for index=0,math.min(count,32)-1 do
        pcall(function()
            local go=ownerOf(result:call('getContactCollidable(System.UInt32)',index))
            if go and go:get_address()~=playerAddress then
                local position=result:call('getContactPoint(System.UInt32)',index):get_field('Position')
                list[#list+1]={object=go,name=nameOf(go),x=position.x,y=position.y,z=position.z}
            end
        end)
    end
    return list
end
function M.Distance(player,x1,y1,z1,x2,y2,z2)
    setup()
    query:call('setRay(via.vec3, via.vec3)',Vector3f.new(x1,y1,z1),Vector3f.new(x2,y2,z2))
    if direct then result=method:call(nil,query) else method:call(system,query,result) end
    if not result then return nil end
    local playerObject=player and player:call('get_GameObject')
    local playerAddress=playerObject and playerObject:get_address()
    local count=result:call('get_NumContactPoints')
    for index=0,math.min(count,16)-1 do
        local okOwner,go=pcall(function() return ownerOf(result:call('getContactCollidable(System.UInt32)',index)) end)
        if not (okOwner and go and go:get_address()==playerAddress) then
            local position=result:call('getContactPoint(System.UInt32)',index):get_field('Position')
            if position then
                local dx,dy,dz=position.x-x1,position.y-y1,position.z-z1
                return math.sqrt(dx*dx+dy*dy+dz*dz)
            end
        end
    end
    return nil
end
return M
