local M={hidden=false,count=0,status=nil}
local hiddenObjects={}
local nextScan=0
local function scene()
    return sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
end
local function hideAll()
    local list=scene():call('findComponents(System.Type)',sdk.typeof('via.gui.GUI'))
    if not list then return end
    for _,gui in ipairs(list:get_elements()) do
        pcall(function()
            local object=gui:call('get_GameObject')
            local key=object:get_address()
            if not hiddenObjects[key] then
                if object:call('get_DrawSelf') then
                    object:call('set_DrawSelf',false)
                    hiddenObjects[key]=object
                end
            elseif object:call('get_DrawSelf') then
                object:call('set_DrawSelf',false)
            end
        end)
    end
    local count=0
    for _ in pairs(hiddenObjects) do count=count+1 end
    M.count=count
end
function M.Set(value)
    M.hidden=value==true
    if M.hidden then nextScan=0;M.Tick() else M.Release() end
end
function M.Tick()
    if not M.hidden or os.clock()<nextScan then return end
    nextScan=os.clock()+0.5
    local ok,why=pcall(hideAll)
    M.status=not ok and ('Interface: '..tostring(why)) or nil
end
function M.Release()
    for _,object in pairs(hiddenObjects) do
        pcall(function() object:call('set_DrawSelf',true) end)
    end
    hiddenObjects={};M.count=0;M.hidden=false
end
return M
