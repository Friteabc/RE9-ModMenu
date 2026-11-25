local M={fov=0,distance=0,height=0,side=0,status=nil}
local config='friteabc_re9_view.json'
local loaded,settings=pcall(json.load_file,config)
if loaded and type(settings)=='table' then
    for _,key in ipairs({'fov','distance','height','side'}) do
        if type(settings[key])=='number' and settings[key]==settings[key] then M[key]=settings[key] end
    end
end
function M.Save() pcall(json.dump_file,config,{fov=M.fov,distance=M.distance,height=M.height,side=M.side}) end
function M.Moved() return M.distance~=0 or M.height~=0 or M.side~=0 or M.shake~=nil end
local fovBase,fovWritten
function M.ApplyFov(free)
    local camera=sdk.get_primary_camera()
    if not camera then return end
    if free or M.fov==0 then
        if fovWritten and not free then
            local current=camera:call('get_FOV')
            if type(current)=='number' and math.abs(current-fovWritten)<0.01 then camera:call('set_FOV',fovBase) end
        end
        fovBase,fovWritten=nil,nil
        return
    end
    local current=camera:call('get_FOV')
    if type(current)~='number' then return end
    if not fovWritten or math.abs(current-fovWritten)>0.01 then fovBase=current end
    local wanted=math.max(10,math.min(150,fovBase+M.fov))
    if math.abs(current-wanted)>0.01 then camera:call('set_FOV',wanted) end
    fovWritten=wanted
end
local reach=1.0
local last
function M.OnCamera(transform)
    if not M.Moved() then return end
    local p=transform:call('get_Position')
    local ax,ay,az=transform:call('get_AxisX'),transform:call('get_AxisY'),transform:call('get_AxisZ')
    local ox=az.x*M.distance+ay.x*M.height+ax.x*M.side
    local oy=az.y*M.distance+ay.y*M.height+ax.y*M.side
    local oz=az.z*M.distance+ay.z*M.height+ax.z*M.side
    last={x=p.x,y=p.y,z=p.z,ox=ox,oy=oy,oz=oz}
    local k=M.shake
    local position=Vector3f.new(p.x+ox*reach+(k and k.x or 0),p.y+oy*reach+(k and k.y or 0),p.z+oz*reach+(k and k.z or 0))
    transform:call('set_Position',position)
    pcall(function()
        local joint=transform:call('get_Joints'):get_element(0)
        if joint then joint:call('set_Position',position) end
    end)
end
function M.Clamp(distanceTo)
    if not M.Moved() or not last then reach=1.0;return end
    local length=math.sqrt(last.ox*last.ox+last.oy*last.oy+last.oz*last.oz)
    if length<0.01 then reach=1.0;return end
    local hit=distanceTo(last.x,last.y,last.z,last.x+last.ox,last.y+last.oy,last.z+last.oz)
    reach=hit and math.max(0,(hit-0.25)/length) or 1.0
    reach=math.min(1.0,reach)
end
function M.Release()
    local fov=M.fov
    M.fov=0
    pcall(M.ApplyFov,false)
    M.fov=fov
end
function M.Reset()
    M.fov=0;M.distance=0;M.height=0;M.side=0;M.Save()
end
return M
