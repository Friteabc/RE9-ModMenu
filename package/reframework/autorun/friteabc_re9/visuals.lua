local M={mode=1,exposure=0,fog=true,lightsOff=false,status=nil}
M.modes={'Default','Bright','Fullbright','Flat (lights off)','Dark'}
local presets={
    {},
    {exposure=1.5},
    {exposure=3.0,autoExposure=false,localExposure=false,fog=false},
    {exposure=3.0,autoExposure=false,localExposure=false,fog=false,lightsOff=true},
    {exposure=-1.5}
}
local LIGHT_TYPES={'via.render.SpotLight','via.render.PointLight','via.render.AreaLight','via.render.SphereLight',
    'via.render.TubeLight','via.render.ProjectionSpotLight','via.render.IESLight','via.render.RectLight','via.render.DiskLight'}
local config='friteabc_re9_visuals.json'
local original,applied,nextApply,nextScan=nil,false,0,0
local disabledLights={}
local loaded,settings=pcall(json.load_file,config)
if loaded and type(settings)=='table' then
    if type(settings.mode)=='number' and presets[settings.mode] then M.mode=settings.mode end
    if type(settings.exposure)=='number' and settings.exposure==settings.exposure then M.exposure=math.max(-6,math.min(10,settings.exposure)) end
    if type(settings.fog)=='boolean' then M.fog=settings.fog end
    if type(settings.lightsOff)=='boolean' then M.lightsOff=settings.lightsOff end
end
function M.Save() json.dump_file(config,{mode=M.mode,exposure=M.exposure,fog=M.fog,lightsOff=M.lightsOff}) end
if not (loaded and type(settings)=='table') then pcall(M.Save) end
local function manager() return sdk.get_managed_singleton('app.RenderingManager') end
local function components()
    local rendering=manager()
    if not rendering then return nil,nil end
    local tone,fog
    pcall(function() tone=rendering:get_field('_ToneMapping') end)
    pcall(function() fog=rendering:get_field('_VolumetricFogControl') end)
    return tone,fog
end
local errors={}
local function try(object,name,...)
    if not object then errors[name]='object missing';return false end
    local args={...}
    local ok,value=pcall(function() return object:call(name,table.unpack(args)) end)
    if not ok then errors[name]=tostring(value) end
    return ok,value
end
local function read(object,names)
    for _,name in ipairs(names) do
        local ok,value=try(object,name)
        if ok and value~=nil then return value end
    end
end
local function capture(tone,fog)
    original={
        exposureEnable=read(tone,{'get_ExposureEnable'}),
        ev=read(tone,{'get_EV'}),
        autoExposure=read(tone,{'getAutoExposure','get_AutoExposure'}),
        localExposure=read(tone,{'get_EnableLocalExposure'}),
        fog=read(fog,{'get_Enabled'}),
        toneAddress=tone and tone:get_address(),fogAddress=fog and fog:get_address()
    }
end
local function wanted()
    local preset=presets[M.mode] or {}
    local fog=M.fog
    if preset.fog==false then fog=false end
    return preset,(preset.exposure or 0)+M.exposure,fog,M.lightsOff or preset.lightsOff==true
end
local function sceneLights(fn)
    local scene
    pcall(function()
        scene=sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
    end)
    if not scene then return 0 end
    local count=0
    for _,name in ipairs(LIGHT_TYPES) do
        local definition=sdk.find_type_definition(name)
        if definition then pcall(function()
            local list=scene:call('findComponents(System.Type)',sdk.typeof(name))
            if list then for _,light in ipairs(list:get_elements()) do
                if light then count=count+1;pcall(fn,light) end
            end end
        end) end
    end
    return count
end
local function lightsOff()
    sceneLights(function(light)
        if light:call('get_Enabled') then
            light:call('set_Enabled',false)
            disabledLights[light:get_address()]=true
        end
    end)
end
local function lightsOn()
    if next(disabledLights)==nil then return end
    sceneLights(function(light)
        if disabledLights[light:get_address()] then light:call('set_Enabled',true) end
    end)
    disabledLights={}
end
local function restore()
    local tone,fog=components()
    if original then
        if tone and tone:get_address()==original.toneAddress then
            if original.exposureEnable~=nil then try(tone,'set_ExposureEnable',original.exposureEnable) end
            if type(original.ev)=='number' then try(tone,'set_EV',original.ev) end
            try(tone,'setAutoExposure',type(original.autoExposure)=='number' and original.autoExposure or 0)
            if original.localExposure~=nil then try(tone,'set_EnableLocalExposure',original.localExposure) end
        end
        if fog and fog:get_address()==original.fogAddress and original.fog~=nil then try(fog,'set_Enabled',original.fog) end
    end
    pcall(lightsOn)
    original,applied=nil,false
end
function M.IsDefault()
    local _,exposure,fog,off=wanted()
    return M.mode==1 and exposure==0 and fog and not off
end
function M.Tick()
    if M.IsDefault() then
        if applied then restore();M.status=nil end
        return
    end
    local now=os.clock()
    local tone,fog=components()
    if not tone then M.status='Rendering settings unavailable';return end
    if not original or original.toneAddress~=tone:get_address() then capture(tone,fog) end
    local preset,exposure,fogOn,off=wanted()
    local base=type(original.ev)=='number' and original.ev or 0
    try(tone,'set_ExposureEnable',true)
    try(tone,'set_EV',base+exposure)
    if preset.autoExposure==false then try(tone,'setAutoExposure',2)
    else try(tone,'setAutoExposure',type(original.autoExposure)=='number' and original.autoExposure or 0) end
    if preset.localExposure==false then try(tone,'set_EnableLocalExposure',false)
    elseif original.localExposure~=nil then try(tone,'set_EnableLocalExposure',original.localExposure) end
    if fog then try(fog,'set_Enabled',fogOn and (original.fog~=false)) end
    if off then
        if now>=nextScan then nextScan=now+2;pcall(lightsOff) end
    else pcall(lightsOn) end
    applied=true
    local lights=0
    for _ in pairs(disabledLights) do lights=lights+1 end
    M.status=off and ('Scene lights off: '..lights) or nil
end
function M.LightProbe()
    local found={}
    local scene
    local ok,why=pcall(function()
        scene=sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
    end)
    found.scene=scene and 'ok' or ('missing '..tostring(why))
    for _,name in ipairs(LIGHT_TYPES) do
        local definition=sdk.find_type_definition(name)
        if not definition then found[name]='no type'
        elseif scene then
            local okList,list=pcall(function() return scene:call('findComponents(System.Type)',sdk.typeof(name)) end)
            if not okList then found[name]='error '..tostring(list)
            else
                local okCount,count=pcall(function() return list and #list:get_elements() or 0 end)
                found[name]=okCount and count or ('count error '..tostring(count))
            end
        end
    end
    return found
end
function M.Reset()
    M.mode=1;M.exposure=0;M.fog=true;M.lightsOff=false
    restore();M.status=nil;M.Save()
end
function M.Release() pcall(restore) end
return M
