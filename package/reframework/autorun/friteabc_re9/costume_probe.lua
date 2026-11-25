local M={done=nil}
local function describe(object,depth,seen)
    if object==nil then return nil end
    local ok,definition=pcall(function() return object:get_type_definition() end)
    if not ok or not definition then return tostring(object) end
    local address=object:get_address()
    if seen[address] then return {ref=definition:get_full_name()} end
    seen[address]=true
    local out={type=definition:get_full_name(),fields={},methods={}}
    local class=definition
    while class do
        for _,field in ipairs(class:get_fields()) do
            if not field:is_static() then
                local entry={type=field:get_type():get_full_name()}
                pcall(function()
                    local value=field:get_data(object)
                    local kind=type(value)
                    if kind=='number' or kind=='boolean' or kind=='string' then entry.value=value
                    elseif kind=='userdata' and depth>0 then
                        local okArray,size=pcall(function() return value:get_size() end)
                        if okArray and type(size)=='number' then
                            entry.size=size;entry.items={}
                            for i=0,math.min(size,40)-1 do
                                local okItem,item=pcall(function() return value:get_element(i) end)
                                if okItem then entry.items[#entry.items+1]=describe(item,depth-1,seen) end
                            end
                        else entry.value=describe(value,depth-1,seen) end
                    end
                end)
                out.fields[field:get_name()]=entry
            end
        end
        for _,method in ipairs(class:get_methods()) do out.methods[#out.methods+1]=method:get_name() end
        class=class:get_parent_type()
    end
    return out
end
local function enum(name)
    local definition=sdk.find_type_definition(name)
    if not definition then return nil end
    local values={}
    for _,field in ipairs(definition:get_fields()) do
        if field:is_static() then pcall(function()
            local value=field:get_data(nil)
            if type(value)=='number' then values[field:get_name()]=value end
        end) end
    end
    return values
end
function M.Run(player)
    if not player or M.done==player:get_address() then return end
    M.done=player:get_address()
    local seen={}
    local report={enums={PlayerMode=enum('app.PlayerMode'),CharacterKindID=enum('app.CharacterKindID')}}
    pcall(function() report.bodyViewMode=player:call('get_CurrentBodyViewMode') end)
    pcall(function() report.viewMode=player:call('get_CurrentViewMode') end)
    pcall(function() report.kind=player:call('get_KindID') end)
    local updater=player:call('get_Updater')
    pcall(function() report.costume=describe(updater:call('get_CurrentCostumeSetting'),3,seen) end)
    pcall(function() report.meshController=describe(updater:call('get_MeshController'),2,seen) end)
    pcall(function() report.customParts=describe(updater:call('getCustomPartsInfo'),2,seen) end)
    report.singletons={}
    for _,name in ipairs({'app.CostumeManager','app.PlayerCostumeManager','app.CharacterCostumeManager','app.CostumeSystem',
        'app.PlayerManager','app.GameDataManager','app.CharacterManager'}) do
        pcall(function()
            local instance=sdk.get_managed_singleton(name)
            if instance then
                local fields={}
                for _,field in ipairs(instance:get_type_definition():get_fields()) do
                    local typeName=field:get_type():get_full_name()
                    if typeName:find('Costume') or field:get_name():find('Costume') then fields[field:get_name()]=typeName end
                end
                local methods={}
                for _,method in ipairs(instance:get_type_definition():get_methods()) do
                    if method:get_name():find('Costume') or method:get_name():find('Player') then methods[#methods+1]=method:get_name() end
                end
                report.singletons[name]={fields=fields,methods=methods}
            end
        end)
    end
    local function signatures(definition,filter)
        local out={}
        local class=definition
        while class do
            for _,method in ipairs(class:get_methods()) do
                local name=method:get_name()
                if not filter or name:find(filter) then
                    local params={}
                    pcall(function() for _,param in ipairs(method:get_param_types()) do params[#params+1]=param:get_full_name() end end)
                    out[#out+1]=name..'('..table.concat(params,', ')..') -> '..method:get_return_type():get_full_name()
                end
            end
            class=class:get_parent_type()
        end
        return out
    end
    report.montageMethods={}
    pcall(function()
        local manager=sdk.get_managed_singleton('app.CharacterManager')
        report.montageMethods.CharacterManager=signatures(manager:get_type_definition(),'Montage')
    end)
    pcall(function() report.montageMethods.Updater=signatures(updater:get_type_definition(),'Montage') end)
    pcall(function() report.montageMethods.UpdaterCostume=signatures(updater:get_type_definition(),'Costume') end)
    pcall(function() report.montageMethods.MeshController=signatures(updater:call('get_MeshController'):get_type_definition(),'Montage') end)
    pcall(function() report.montageMethods.MeshDisplay=signatures(updater:call('get_MeshController'):get_type_definition(),'Display') end)
    pcall(function() report.montageMethods.MeshHead=signatures(updater:call('get_MeshController'):get_type_definition(),'Head') end)
    pcall(function() report.montageMethods.MeshTemp=signatures(updater:call('get_MeshController'):get_type_definition(),'temp') end)
    pcall(function() report.montageMethods.ControlMode=signatures(updater:get_type_definition(),'ControlMode') end)
    pcall(function() report.montageMethods.InputDriver=signatures(updater:call('get_InputDriver'):get_type_definition(),nil) end)
    pcall(function() report.montageMethods.InputUnit=signatures(updater:call('get_InputUnit'):get_type_definition(),nil) end)
    pcall(function() report.headParts=describe(updater:call('get_MeshController'):call('getHeadPartsIDArray'),1,{}) end)
    report.enums.ControlMode=enum('app.character.ControlMode')
    report.enums.PlayerMontagePartsID=enum('app.PlayerMontagePartsID')
    report.types={}
    for _,name in ipairs({'app.PlayerCostumeSettingUserData','app.PlayerMontagePresetUserData','app.PlayerMontagePreset',
        'app.PlayerMontageID','app.PlayerMontagePresetID','app.BonusID','app.BonusManager','app.CostumeID','app.PlayerCostumeID',
        'app.PlayerMontageChangeRequest','app.PlayerMontageUserData','app.MontagePresetID','app.CharacterMontageManager',
        'app.PlayerMontageManager','app.MontageManager','app.BonusCostumeUserData','app.PlayerMontagePresetRef'}) do
        pcall(function()
            local definition=sdk.find_type_definition(name)
            if not definition then return end
            local info={methods=signatures(definition),fields={},statics={},singleton=sdk.get_managed_singleton(name)~=nil}
            for _,field in ipairs(definition:get_fields()) do
                if field:is_static() then pcall(function()
                    local value=field:get_data(nil)
                    if type(value)=='number' or type(value)=='string' then info.statics[field:get_name()]=value end
                end)
                else info.fields[#info.fields+1]=field:get_name()..' : '..field:get_type():get_full_name() end
            end
            report.types[name]=info
        end)
    end
    report.updaterCostumeFields={}
    pcall(function()
        local class=updater:get_type_definition()
        while class do
            for _,field in ipairs(class:get_fields()) do
                local typeName=field:get_type():get_full_name()
                if typeName:find('Costume') or typeName:find('Montage') or field:get_name():find('Costume') or field:get_name():find('Montage') then
                    report.updaterCostumeFields[field:get_name()]={type=typeName,value=describe(field:get_data(updater),2,{})}
                end
            end
            class=class:get_parent_type()
        end
    end)
    report.cameraSystem={}
    pcall(function()
        local system=sdk.get_managed_singleton('app.CameraSystem')
        report.cameraSystem.exists=system~=nil
        if not system then return end
        report.cameraSystem.methods=signatures(system:get_type_definition(),'Option')
        local okSub,sub=pcall(function() return system:call('get_OptionSubSystem') end)
        report.cameraSystem.subsystem=okSub and (sub and sub:get_type_definition():get_full_name() or 'nil') or ('error '..tostring(sub))
        if okSub and sub then
            local fields={}
            for _,field in ipairs(sub:get_type_definition():get_fields()) do fields[#fields+1]=field:get_name()..' : '..field:get_type():get_full_name() end
            report.cameraSystem.subsystemFields=fields
            local okList,list=pcall(function() return sub:get_field('_CameraOptionSettingCharacters') end)
            report.cameraSystem.characters=okList and (list and list:get_size() or 'nil') or ('error '..tostring(list))
            if okList and list and list:get_size()>0 then
                report.cameraSystem.first=describe(list:get_element(0),2,{})
            end
        end
    end)
    json.dump_file('friteabc_re9_costume.json',report)
    log.info('[Friteabc RE9] Costume discovery saved')
end
return M
