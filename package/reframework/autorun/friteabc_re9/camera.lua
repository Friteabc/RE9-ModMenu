local M={sensitivity=1.0,applied=0,status=nil,frozen=false}
local VIEWS={'_TPS','_TPSHold','_FPS','_FPSHold'}
local COEFS={'SpeedCoefYaw','SpeedCoefPitch'}
local config='friteabc_re9_camera_settings.json'
local originals={}
local written={}
local hooked,nextCheck=false,0
local loaded,settings=pcall(json.load_file,config)
if loaded and type(settings)=='table' and type(settings.sensitivity)=='number' and settings.sensitivity==settings.sensitivity then
    M.sensitivity=math.max(0.25,math.min(6,settings.sensitivity))
end
function M.Save() json.dump_file(config,{sensitivity=M.sensitivity}) end
if not (loaded and type(settings)=='table') then pcall(M.Save) end
local function eachSetting(fn)
    local system=sdk.get_managed_singleton('app.CameraSystem')
    if not system then M.reason='CameraSystem missing';return false end
    local options=system:call('get_OptionSubSystem')
    if not options then M.reason='OptionSubSystem missing';return false end
    local list=options:get_field('_CameraOptionSettingCharacters')
    if not list then M.reason='camera settings list missing';return false end
    M.reason=nil
    for i=0,list:get_size()-1 do
        local character=list:get_element(i)
        if character then
            for _,view in ipairs(VIEWS) do
                local setting=character:get_field(view)
                if setting then fn(setting) end
            end
        end
    end
    return true
end
local function near(a,b) return type(a)=='number' and type(b)=='number' and math.abs(a-b)<0.0001 end
local function apply(scale)
    local count=0
    local found=eachSetting(function(setting)
        local key=setting:get_address()
        local saved=originals[key] or {}
        local mine=written[key] or {}
        originals[key]=saved;written[key]=mine
        for _,name in ipairs(COEFS) do
            local current=setting:call('get_'..name)
            if type(current)=='number' then
                if saved[name]==nil or not near(current,mine[name]) then saved[name]=current end
                local target=saved[name]*scale
                if not near(current,target) then setting:call('set_'..name,target) end
                mine[name]=target;count=count+1
            end
        end
    end)
    M.applied=count
    if found then M.status=nil else M.status='Camera options unavailable: '..tostring(M.reason) end
    return found
end
local function hook()
    if hooked then return end
    local definition=sdk.find_type_definition('app.CameraOptionSubSystem')
    local method=definition and definition:get_method('OptionValueChanged')
    if not method then return end
    sdk.hook(method,function() return sdk.PreHookResult.CALL_ORIGINAL end,function(value)
        nextCheck=0
        return value
    end)
    hooked=true
end
function M.Tick()
    pcall(hook)
    local now=os.clock()
    if now<nextCheck then return end
    nextCheck=now+0.5
    local scale=M.frozen and 0 or M.sensitivity
    if scale==1 and next(originals)==nil then return end
    local ok,why=pcall(apply,scale)
    if not ok then M.status='Camera options error: '..tostring(why) end
    if scale==1 then originals={};written={} end
end
function M.Changed() nextCheck=0 end
function M.Release()
    if next(originals)~=nil then pcall(apply,1) end
    originals={};written={}
end
return M
