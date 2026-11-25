local M={}
function M.Create(controller)
    local definition=sdk.find_type_definition('via.physics.System')
    assert(definition,'Physics system type unavailable')
    local method
    local diagnostics={methods={},native=false,managed=false}
    for _,candidate in ipairs(definition:get_methods()) do
        if candidate:get_name():lower():find('ray',1,true) then
            local names={}
            for _,param in ipairs(candidate:get_param_types()) do names[#names+1]=param:get_full_name() end
            diagnostics.methods[#diagnostics.methods+1]={name=candidate:get_name(),params=names,static=candidate:is_static(),returns=candidate:get_return_type():get_full_name()}
            if candidate:get_name()=='castRay' and #names==2 and names[1]=='via.physics.CastRayQuery' and names[2]=='via.physics.CastRayResult' then method=candidate end
            if candidate:get_name()=='castRay' and #names==1 and names[1]=='via.physics.CastRayQuery' and candidate:is_static() then method=candidate end
        end
    end
    local system=sdk.get_native_singleton('via.physics.System')
    diagnostics.native=system~=nil
    if not system then system=sdk.get_managed_singleton('via.physics.System');diagnostics.managed=system~=nil end
    json.dump_file('friteabc_re9_ground.json',diagnostics)
    assert(method and (system or method:is_static()),'Ground query unavailable; physics signature recorded')
    local query=sdk.create_instance('via.physics.CastRayQuery')
    local direct=method:get_num_params()==1
    local result=not direct and sdk.create_instance('via.physics.CastRayResult') or nil
    assert(query and (direct or result),'Ground query creation failed')
    query:add_ref()
    if result then result:add_ref() end
    for _,name in ipairs({'via.physics.CastRayQuery','via.physics.CastRayResult'}) do
        local type=sdk.find_type_definition(name)
        local rows={}
        if type then for _,fn in ipairs(type:get_methods()) do
            local params={};for _,param in ipairs(fn:get_param_types()) do params[#params+1]=param:get_full_name() end
            rows[#rows+1]={name=fn:get_name(),params=params,returns=fn:get_return_type():get_full_name()}
        end end
        diagnostics[name]=rows
    end
    json.dump_file('friteabc_re9_ground.json',diagnostics)
    query:call('clearOptions')
    query:call('enableAllHits')
    query:call('enableNearSort')
    local filter=query:call('get_FilterInfo')
    filter:call('set_Group',math.max(0,controller:call('get_GroupId')))
    filter:call('set_MaskBits',4294967295)
    filter:call('set_Layer',controller:call('get_FilterInfo'):call('get_Layer'))
    query:call('set_FilterInfo',filter)
    local function invoke(label,fn,...)
        local ok,value=pcall(fn,...)
        if not ok then error(label..': '..tostring(value)) end
        return value
    end
    local function sample(x,y,z)
        invoke('setRay',function() query:call('setRay(via.vec3, via.vec3)',Vector3f.new(x,y+0.7,z),Vector3f.new(x,y-3,z)) end)
        if direct then result=invoke('castRay',function() return method:call(nil,query) end)
        else invoke('castRay',function() method:call(system,query,result) end) end
        if not result then return nil end
        local count=invoke('contact count',function() return result:call('get_NumContactPoints') end)
        for index=0,math.min(count,64)-1 do
            local point=result:call('getContactPoint(System.UInt32)',index)
            local normal=point:get_field('Normal')
            local position=point:get_field('Position')
            if normal.y>=0.6 and position.y<=y+0.65 and position.y>=y-3 then return position.y end
        end
    end
    local disposed=false
    return sample,function()
        if disposed then return end
        disposed=true
        query:release()
        if not direct and result then result:release() end
    end
end
return M
