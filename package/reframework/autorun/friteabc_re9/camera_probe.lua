local M={}
local nextSample=0
local samples={}
function M.Tick(player,active)
    if not player or not active or os.clock()<nextSample then return end
    nextSample=os.clock()+1
    local updater=player:call('get_Updater')
    local row={time=os.clock(),camera={},stop=player:call('get_StopByOutOfArea')}
    pcall(function() row.pauseBits=sdk.get_managed_singleton('app.PauseManager'):get_field('_CurrentPauseTypeBits') end)
    for _,name in ipairs({'FPSPlayerCamera','TPSPlayerCamera'}) do pcall(function()
        local camera=updater:call('get_'..name)
        if not camera then return end
        local values={}
        row.camera[name]=values
        for _,prop in ipairs({'IsPause','PauseTiming','Enabled','IsBusy'}) do
            pcall(function() values[prop]=camera:call('get_'..prop) end)
        end
        pcall(function()
            local names=camera:call('get_PauseTypeNames')
            values.names={}
            if names then for _,value in ipairs(names:get_elements()) do values.names[#values.names+1]=type(value)=='string' and value or value:call('ToString') end end
        end)
        for _,field in ipairs({'_AdditionalPauseTimingBit','_PassPauseTimingBit'}) do
            pcall(function() values[field]=camera:get_field(field) end)
        end
    end) end
    samples[#samples+1]=row
    if #samples>20 then table.remove(samples,1) end
    local types={}
    for _,name in ipairs({'app.PauseManager','app.PauseTypeBits','app.CameraControllerAbilityContainer','app.CameraTwirler','app.CameraInput','via.hid.MouseDevice','via.hid.Mouse','app.CameraControllerRoot'}) do pcall(function()
        local definition=sdk.find_type_definition(name)
        if not definition then return end
        local data={fields={},methods={}}
        types[name]=data
        local instance=sdk.get_managed_singleton(name)
        if instance then data.state={} end
        for _,field in ipairs(definition:get_fields()) do
            local entry={name=field:get_name(),type=field:get_type():get_full_name()}
            if field:is_static() then pcall(function()
                local value=field:get_data(nil)
                if type(value)=='number' then entry.value=value end
            end) end
            if instance and not field:is_static() then pcall(function()
                local value=instance:get_field(field:get_name())
                if type(value)=='number' or type(value)=='boolean' then data.state[field:get_name()]=value end
            end) end
            data.fields[#data.fields+1]=entry
        end
        for _,method in ipairs(definition:get_methods()) do
            local params={};for _,param in ipairs(method:get_param_types()) do params[#params+1]=param:get_full_name() end
            data.methods[#data.methods+1]={name=method:get_name(),params=params,returns=method:get_return_type():get_full_name(),static=method:is_static()}
        end
    end) end
    json.dump_file('friteabc_re9_camera.json',{samples=samples,types=types})
end
return M
