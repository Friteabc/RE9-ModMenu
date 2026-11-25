local Teleport=require('friteabc_re9.teleport')
local M={status=nil,away=false}
local function scene()
    return sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
end
local function nearest(player)
    local list=scene():call('findComponents(System.Type)',sdk.typeof('app.GmTypewriterV3'))
    local p=player:call('get_Transform'):call('get_Position')
    local best,bestDistance
    for _,typewriter in ipairs(list and list:get_elements() or {}) do
        pcall(function()
            local transform=typewriter:call('get_GameObject'):call('get_Transform')
            local q=transform:call('get_Position')
            local d=(q.x-p.x)^2+(q.y-p.y)^2+(q.z-p.z)^2
            if not bestDistance or d<bestDistance then best,bestDistance=transform,d end
        end)
    end
    return best,bestDistance and math.sqrt(bestDistance)
end
function M.Go(player)
    assert(player,'No playable character')
    local transform,distance=nearest(player)
    assert(transform,'No typewriter loaded in this area')
    local q=transform:call('get_Position')
    local f=transform:call('get_AxisZ')
    Teleport.GoTo(player,q.x+f.x*0.9,q.y,q.z+f.z*0.9)
    M.away=true
    M.status=string.format('At the typewriter (%.0f m away). Save, then press Back.',distance)
end
function M.Back(player)
    assert(M.away,'Not at a typewriter')
    Teleport.Undo(player)
    M.away=false
    M.status='Back where you were'
end
function M.Toggle(player)
    if M.away then M.Back(player) else M.Go(player) end
end
local function describe(object)
    local rows={}
    if not object then return rows end
    local class=object:get_type_definition()
    while class do
        local name=class:get_full_name()
        if name:find('^via%.') or name=='System.Object' then break end
        for _,method in ipairs(class:get_methods()) do
            local params={}
            pcall(function() for _,p in ipairs(method:get_param_types()) do params[#params+1]=p:get_full_name() end end)
            rows[#rows+1]=name..'.'..method:get_name()..'('..table.concat(params,', ')..') -> '..method:get_return_type():get_full_name()
        end
        class=class:get_parent_type()
    end
    return rows
end
local function callFirst(object,names,label)
    if not object then return nil end
    local byName={}
    local class=object:get_type_definition()
    while class do
        if class:get_full_name():find('^via%.') then break end
        for _,method in ipairs(class:get_methods()) do
            if method:get_num_params()==0 and not byName[method:get_name()] then byName[method:get_name()]=method end
        end
        class=class:get_parent_type()
    end
    for _,name in ipairs(names) do
        if byName[name] then
            log.info('[Friteabc RE9] Save here: '..label..'.'..name)
            local ok,result=pcall(function() return object:call(name) end)
            if ok and result~=false then return label..'.'..name end
        end
    end
end
local function fieldsOf(object)
    local rows={}
    local class=object:get_type_definition()
    while class do
        for _,field in ipairs(class:get_fields()) do
            if not field:is_static() then rows[#rows+1]=field end
        end
        class=class:get_parent_type()
    end
    return rows
end
local function enumValue(typeDefinition,wanted)
    for _,field in ipairs(typeDefinition:get_fields()) do
        if field:is_static() and field:get_name()==wanted then return field:get_data(nil) end
    end
end
local function build(typeName,report)
    local definition=sdk.find_type_definition(typeName)
    assert(definition,typeName..' unavailable')
    assert(not definition:is_value_type(),typeName..' is a raw value: not created (unsafe)')
    local object=assert(sdk.create_instance(typeName),typeName..' could not be created')
    report[typeName]={}
    for _,field in ipairs(fieldsOf(object)) do
        local fieldType=field:get_type()
        local typeText=fieldType:get_full_name()
        local entry=field:get_name()..' : '..typeText
        local okEnum,isEnum=pcall(function() return fieldType:is_value_type() and enumValue(fieldType,'Save')~=nil end)
        if okEnum and isEnum then
            local value=enumValue(fieldType,'Save')
            local ok=pcall(function() object:set_field(field:get_name(),value) end)
            entry=entry..(ok and ' = Save' or ' (Save refused)')
        end
        table.insert(report[typeName],entry)
    end
    return object
end
function M.SaveHere()
    local gui=assert(sdk.get_managed_singleton('app.GuiManager'),'Interface manager unavailable')
    local report={}
    local done
    local saveLoad
    pcall(function() saveLoad=gui:call('get_SaveLoad') end)
    if saveLoad then
        local ok,why=pcall(function()
            local setting=build('app.GuiSaveLoadOpenSetting',report)
            log.info('[Friteabc RE9] Save here: opening the save screen')
            local handle=saveLoad:call('open(app.GuiSaveLoadOpenSetting)',setting)
            assert(handle~=nil,'the game did not open the screen')
        end)
        report.saveScreen=ok and 'opened' or tostring(why)
        if ok then done='save screen' end
    end
    if not done then
        local auto
        pcall(function() auto=gui:call('get_AutoSaveFlow') end)
        if auto then
            local ok,why=pcall(function()
                local args=build('app.GuiAutoSaveFlowRequestArgs',report)
                log.info('[Friteabc RE9] Save here: requesting an auto save')
                auto:call('requestAutoSave(app.GuiAutoSaveFlowRequestArgs)',args)
            end)
            report.autoSave=ok and 'requested' or tostring(why)
            if ok then done='auto save' end
        end
    end
    pcall(json.dump_file,'friteabc_re9_saveui_try.json',report)
    log.info('[Friteabc RE9] Save here: '..tostring(done or 'failed')..' | screen='..tostring(report.saveScreen)..' | auto='..tostring(report.autoSave))
    M.status=done and ('Save: '..done) or ('Save failed: '..tostring(report.saveScreen or report.autoSave))
end
return M
