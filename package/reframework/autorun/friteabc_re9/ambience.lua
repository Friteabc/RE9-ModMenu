local M={rain=true,clouds=true,wind=true,status=nil}
local TYPES={rain='app.RainEmitterRegister',clouds='app.CloudMeshController',wind='app.WindManagerBehavior'}
local touched={}
local nextScan=0
local function scene()
    return sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
end
local function apply(kind,on)
    local list=scene():call('findComponents(System.Type)',sdk.typeof(TYPES[kind]))
    local count=0
    for _,component in ipairs(list and list:get_elements() or {}) do
        local key=component:get_address()
        if not on and not touched[key] then
            local ok,was=pcall(function() return component:call('get_Enabled') end)
            if ok and type(was)=='boolean' then touched[key]={component=component,was=was} end
        end
        local entry=touched[key]
        if entry then
            pcall(function() component:call('set_Enabled',on and entry.was or false) end)
            if on then touched[key]=nil end
            count=count+1
        end
    end
    return count
end
function M.Tick()
    if os.clock()<nextScan then return end
    nextScan=os.clock()+1
    if M.rain and M.clouds and M.wind and next(touched)==nil then return end
    local parts={}
    for kind in pairs(TYPES) do
        local ok,count=pcall(apply,kind,M[kind])
        if ok and not M[kind] then parts[#parts+1]=kind..' '..count end
    end
    M.status=#parts>0 and ('Off: '..table.concat(parts,', ')) or nil
end
function M.Release()
    M.rain,M.clouds,M.wind=true,true,true
    for _,entry in pairs(touched) do pcall(function() entry.component:call('set_Enabled',entry.was) end) end
    touched={};M.status=nil
end
return M
