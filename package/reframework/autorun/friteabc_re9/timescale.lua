local M={speed=1.0,status=nil}
local applied,base
local function scene()
    return sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
end
local function near(a,b) return math.abs(a-b)<0.0001 end
function M.Tick(paused)
    if paused then return end
    if M.speed==1 and not applied then return end
    local current=scene():call('get_TimeScale')
    if type(current)~='number' then return end
    if M.speed==1 then
        if near(current,applied) then scene():call('set_TimeScale',base or 1.0) end
        applied,base=nil,nil
        return
    end
    if not applied or not near(current,applied) then base=current end
    local wanted=math.max(0.01,(base or 1.0)*M.speed)
    if not near(current,wanted) then scene():call('set_TimeScale',wanted) end
    applied=wanted
end
function M.Release()
    if applied then
        pcall(function()
            local current=scene():call('get_TimeScale')
            if type(current)=='number' and near(current,applied) then scene():call('set_TimeScale',base or 1.0) end
        end)
    end
    applied,base=nil,nil
end
return M
