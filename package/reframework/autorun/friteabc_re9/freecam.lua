local M={enabled=false,speed=4,lookSpeed=1.0,lookAtPlayer=false,showBody=true,status=nil,paused=false,frozenHead=0,customFov=false,fov=60,roll=0}
local s
local function vec(x,y,z) return Vector3f.new(x,y,z) end
local function quat(yaw,pitch,roll)
    local sy,cy=math.sin(yaw/2),math.cos(yaw/2)
    local sp,cp=math.sin(pitch/2),math.cos(pitch/2)
    local x,y,z,w=cy*sp,sy*cp,-sy*sp,cy*cp
    if roll and roll~=0 then
        local sr,cr=math.sin(roll/2),math.cos(roll/2)
        x,y,z,w=x*cr+y*sr,-x*sr+y*cr,w*sr+z*cr,w*cr-z*sr
    end
    return Vector4f.new(x,y,z,w)
end
local function forward(yaw,pitch) return -math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch) end
local function cameraTransform()
    local camera=sdk.get_primary_camera()
    return camera and camera:call('get_GameObject'):call('get_Transform')
end
local function aimAt(x,y,z)
    local dx,dy,dz=x-s.x,y-s.y,z-s.z
    local len=math.sqrt(dx*dx+dy*dy+dz*dz)
    if len<0.001 then return end
    s.pitch=math.asin(math.max(-1,math.min(1,dy/len)))
    s.yaw=math.atan(-dx,-dz)
end
local function head(player)
    local p=player:call('get_Transform'):call('get_Position')
    return p.x,p.y+1.55,p.z
end
local hooked={}
local SKIP={updateInput=true,updateActionFromInput=true}
local function hookInput(driver)
    local class=driver:get_type_definition()
    while class do
        for _,method in ipairs(class:get_methods()) do
            local key=method:get_function()
            if SKIP[method:get_name()] and method:get_num_params()==0 and method:get_return_type():get_full_name()=='System.Void' and not hooked[key] then
                local ok=pcall(sdk.hook,method,function(args)
                    if s and s.driverAddress and sdk.to_int64(args[2])==s.driverAddress then return sdk.PreHookResult.SKIP_ORIGINAL end
                    return sdk.PreHookResult.CALL_ORIGINAL
                end,function(value) return value end)
                if ok then hooked[key]=true end
            end
        end
        class=class:get_parent_type()
    end
end
local function setInput(enabled)
    local driver=s.updater and s.updater:call('get_InputDriver')
    if not driver then return end
    for _,name in ipairs({'setEnable(System.Boolean)','set_IsEnable'}) do
        if pcall(function() driver:call(name,enabled) end) then return end
    end
end
local function writePose(transform)
    local position,rotation=vec(s.x,s.y,s.z),quat(s.yaw,s.pitch,math.rad(M.roll or 0))
    if M.customFov then pcall(function() sdk.get_primary_camera():call('set_FOV',M.fov) end) end
    transform:call('set_Position',position)
    transform:call('set_Rotation',rotation)
    pcall(function()
        local joint=transform:call('get_Joints'):get_element(0)
        if joint then joint:call('set_Position',position);joint:call('set_Rotation',rotation) end
    end)
end
local hookedTransforms={}
local function hookCamera()
    local transform=cameraTransform()
    if not transform then return end
    local key=transform:get_address()
    if hookedTransforms[key] then return end
    local ok=pcall(function()
        transform:hook_update(function(updated)
            if s then pcall(writePose,updated)
            elseif M.External then pcall(M.External,updated) end
        end)
    end)
    hookedTransforms[key]=ok
end
local function depthOfField()
    local found={}
    local function scan(object)
        if not object then return end
        pcall(function()
            for _,component in ipairs(object:call('get_Components'):get_elements()) do
                local okName,name=pcall(function() return component:get_type_definition():get_full_name() end)
                if okName and name:find('DepthOfField') then found[#found+1]=component end
            end
        end)
    end
    pcall(function() scan(sdk.get_primary_camera():call('get_GameObject')) end)
    pcall(function()
        local rendering=sdk.get_managed_singleton('app.RenderingManager')
        for _,field in ipairs(rendering:get_type_definition():get_fields()) do
            if field:get_name():find('DepthOfField') then
                local value=field:get_data(rendering)
                if value then found[#found+1]=value end
            end
        end
    end)
    return found
end
local function switchView(player,mode)
    player:call('set_CurrentViewMode',mode)
    local updater=player:call('get_Updater')
    local switch=updater:call('get_MeshController'):get_field('_SwitchPlayerView')
    if switch then switch:call('set_BodySwitchTrigger',true) end
end
local function currentScene()
    return sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
end
local function resume(session)
    if session and session.timeWas~=nil then
        local was=session.timeWas;session.timeWas=nil
        pcall(function() currentScene():call('set_TimeScale',was) end)
        log.info('[Friteabc RE9] Game resumed')
    end
    M.paused=false
end
function M.SetPause(value)
    if not s then M.paused=false;return end
    if value then
        if s.timeWas==nil then
            local scene=assert(currentScene(),'Scene unavailable')
            local was=scene:call('get_TimeScale')
            s.timeWas=type(was)=='number' and was>0 and was or 1.0
            scene:call('set_TimeScale',0.0001)
            log.info('[Friteabc RE9] Game paused')
        end
        M.paused=true
    else
        resume(s)
    end
end
local LOOK={'LookAt','EyeController','HeadAim','HeadLook','Gaze'}
local function lookComponents(player)
    local list={}
    pcall(function()
        local object=player:call('get_GameObject')
        for _,component in ipairs(object:call('get_Components'):get_elements()) do
            local okName,name=pcall(function() return component:get_type_definition():get_full_name() end)
            if okName then
                for _,word in ipairs(LOOK) do
                    if name:find(word) then list[#list+1]={component=component,name=name};break end
                end
            end
        end
    end)
    pcall(function()
        local eye=player:call('get_Updater'):call('get_AnimEyeController')
        if eye then
            local known=false
            for _,entry in ipairs(list) do if entry.component:get_address()==eye:get_address() then known=true end end
            if not known then list[#list+1]={component=eye,name='AnimEyeController'} end
        end
    end)
    return list
end
local function freezeHead(player)
    s.look={}
    local names={}
    for _,entry in ipairs(lookComponents(player)) do
        local okState,was=pcall(function() return entry.component:call('get_Enabled') end)
        if okState and type(was)=='boolean' then
            entry.was=was;s.look[#s.look+1]=entry;names[#names+1]=entry.name
            pcall(function() entry.component:call('set_Enabled',false) end)
        end
    end
    M.frozenHead=#s.look
    log.info('[Friteabc RE9] Free camera head freeze: '..(#names>0 and table.concat(names,', ') or 'no look component found'))
end
local function releaseHead(session)
    for _,entry in ipairs(session.look or {}) do pcall(function() entry.component:call('set_Enabled',entry.was) end) end
    session.look=nil
end
function M.EnsureHook() hookCamera() end
function M.Enable(player)
    assert(player,'No playable character')
    local transform=cameraTransform()
    assert(transform,'Camera unavailable')
    local p=transform:call('get_Position')
    local back=transform:call('get_AxisZ')
    s={player=player,address=player:get_address(),x=p.x,y=p.y,z=p.z,yaw=math.atan(back.x,back.z),
        pitch=math.asin(math.max(-1,math.min(1,-back.y))),updater=player:call('get_Updater'),last=os.clock()}
    local body=player:call('get_Transform')
    local pos=body:call('get_Position')
    s.pin={x=pos.x,y=pos.y,z=pos.z}
    s.pinRot=body:call('get_Rotation')
    pcall(function() s.inputWas=s.updater:call('get_InputDriver'):call('get_IsEnable') end)
    setInput(false)
    if M.showBody then
        pcall(function()
            local mode=player:call('get_CurrentViewMode')
            if mode~=0 then
                s.viewWas=mode
                switchView(player,0)
            end
        end)
    end
    pcall(function()
        local driver=s.updater:call('get_InputDriver')
        s.driverAddress=driver:get_address()
        hookInput(driver)
    end)
    s.dof={}
    for _,component in ipairs(depthOfField()) do
        local okState,was=pcall(function() return component:call('get_Enabled') end)
        if okState and type(was)=='boolean' then
            s.dof[#s.dof+1]={component=component,was=was}
            pcall(function() component:call('set_Enabled',false) end)
        end
    end
    pcall(freezeHead,player)
    pcall(function() s.fovWas=sdk.get_primary_camera():call('get_FOV') end)
    if type(s.fovWas)=='number' and not M.customFov then M.fov=s.fovWas end
    M.enabled=true;M.status=nil
    pcall(hookCamera)
    log.info('[Friteabc RE9] Free camera on')
end
function M.Disable()
    local session=s;s=nil;M.enabled=false
    if not session then M.paused=false;return end
    resume(session)
    releaseHead(session)
    if type(session.fovWas)=='number' then pcall(function() sdk.get_primary_camera():call('set_FOV',session.fovWas) end) end
    local driver
    pcall(function() driver=session.updater:call('get_InputDriver') end)
    if driver and session.inputWas~=false then
        for _,name in ipairs({'setEnable(System.Boolean)','set_IsEnable'}) do
            if pcall(function() driver:call(name,true) end) then break end
        end
    end
    if session.viewWas~=nil then pcall(switchView,session.player,session.viewWas) end
    for _,entry in ipairs(session.dof or {}) do pcall(function() entry.component:call('set_Enabled',entry.was) end) end
    if session.bodyMode~=nil and session.bodyMode~=0 then pcall(function() session.player:call('set_CurrentBodyViewMode',session.bodyMode) end) end
    if session.tpsMesh and session.mesh then
        for _,part in ipairs(session.head or {}) do
            if part.shown~=nil then pcall(function() session.mesh:call('setDisplayByPartsID',part.id,part.shown,true) end) end
        end
        pcall(function() session.mesh:call('set_ForceTempTPSMeshModeChange',session.forceWas==true) end)
        if session.ignoreDepthWas~=nil then pcall(function() session.mesh:call('set_IgnoreDepthSelf',session.ignoreDepthWas) end) end
    end
    log.info('[Friteabc RE9] Free camera off')
end
function M.Focus()
    if not s then return end
    local hx,hy,hz=head(s.player)
    local front=s.player:call('get_Transform'):call('get_AxisZ')
    s.x,s.y,s.z=hx+front.x*2.5,hy,hz+front.z*2.5
    aimAt(hx,hy,hz)
end
local function pinBody()
    local transform=s.player:call('get_Transform')
    local p=transform:call('get_Position')
    if math.abs(p.x-s.pin.x)+math.abs(p.y-s.pin.y)+math.abs(p.z-s.pin.z)>0.001 then
        local pin=vec(s.pin.x,s.pin.y,s.pin.z)
        transform:call('set_Position',pin)
        pcall(function() s.player:call('set_Position',pin) end)
    end
    if s.pinRot then pcall(function() transform:call('set_Rotation',s.pinRot) end) end
end
function M.Hold(player)
    if not s then return end
    if not player or player:get_address()~=s.address then M.Disable();return end
    setInput(false)
    pinBody()
    for _,entry in ipairs(s.look or {}) do
        pcall(function() if entry.component:call('get_Enabled') then entry.component:call('set_Enabled',false) end end)
    end
    pcall(function()
        local unit=s.updater:call('get_InputUnit')
        if unit:call('get_IsMoveInput') then unit:call('set_IsMoveInput',false) end
        if unit:call('get_MoveIntensity')~=0 then unit:call('set_MoveIntensity',0.0) end
    end)
    if s.tpsMesh then
        pcall(function() s.mesh:call('set_ForceTempTPSMeshModeChange',true) end)
        if s.ignoreDepthWas~=nil then pcall(function() if s.mesh:call('get_IgnoreDepthSelf') then s.mesh:call('set_IgnoreDepthSelf',false) end end) end
        for _,part in ipairs(s.head or {}) do
            pcall(function() if not s.mesh:call('getDisplayPartsSetting',part.id) then s.mesh:call('setDisplayByPartsID',part.id,true,true) end end)
        end
    end
end
local function mouseDelta()
    local dx,dy=0,0
    pcall(function()
        local mouse=sdk.call_native_func(sdk.get_native_singleton('via.hid.Mouse'),sdk.find_type_definition('via.hid.Mouse'),'get_Device')
        local d=mouse:call('get_DeltaPosition')
        dx,dy=d.x or 0,d.y or 0
    end)
    return dx,dy
end
function M.Update(menuOpen)
    if not s then return end
    local now=os.clock()
    local dt=math.min(0.05,math.max(0,now-s.last));s.last=now
    local pDown=false
    pcall(function() pDown=reframework:is_key_down(0x50)==true end)
    if pDown and not s.pHeld and not menuOpen then pcall(M.SetPause,not M.paused) end
    s.pHeld=pDown
    if not menuOpen and dt>0 then
        local mx,my=mouseDelta()
        s.yaw=s.yaw-mx*0.0025*M.lookSpeed
        s.pitch=math.max(-1.55,math.min(1.55,s.pitch-my*0.0025*M.lookSpeed))
        local function down(key) return reframework:is_key_down(key) and 1 or 0 end
        local f=math.max(down(87),down(90))-down(83)
        local r=down(68)-math.max(down(65),down(81))
        local u=down(32)-math.max(down(17),down(162),down(163))
        local speed=M.speed*(math.max(down(16),down(160),down(161))==1 and 3 or 1)*dt
        local fx,fy,fz=forward(s.yaw,s.pitch)
        local rx,rz=math.cos(s.yaw),-math.sin(s.yaw)
        s.x=s.x+(fx*f+rx*r)*speed
        s.y=s.y+(fy*f+u)*speed
        s.z=s.z+(fz*f+rz*r)*speed
    end
    if M.lookAtPlayer then pcall(function() aimAt(head(s.player)) end) end
    M.Apply()
end
function M.Apply()
    if not s then return end
    pcall(pinBody)
    pcall(hookCamera)
    if s.dof then for _,entry in ipairs(s.dof) do
        pcall(function() if entry.component:call('get_Enabled') then entry.component:call('set_Enabled',false) end end)
    end end
    local transform=cameraTransform()
    if not transform then return end
    writePose(transform)
end
return M
