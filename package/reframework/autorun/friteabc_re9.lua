if rawget(_G,'__friteabc_re9_loaded') then
    log.info('[Friteabc RE9] Already loaded; duplicate execution ignored')
    return
end
rawset(_G,'__friteabc_re9_loaded',true)
local Movement=require('friteabc_re9.movement_v2')
local Equipment=require('friteabc_re9.equipment')
local Visuals=require('friteabc_re9.visuals')
local Camera=require('friteabc_re9.camera')
local Freecam=require('friteabc_re9.freecam')
local Skins=require('friteabc_re9.skins')
local Teleport=require('friteabc_re9.teleport')
local Remover=require('friteabc_re9.remover')
local SpawnProbe=require('friteabc_re9.spawn_probe')
local Enemies=require('friteabc_re9.enemies')
local LevelProbe=require('friteabc_re9.level_probe')
local Speed=require('friteabc_re9.speed')
local Damage=require('friteabc_re9.damage')
local Protection=require('friteabc_re9.protection')
local Tweaks=require('friteabc_re9.tweaks')
local TimeScale=require('friteabc_re9.timescale')
local Hud=require('friteabc_re9.hud')
local View=require('friteabc_re9.view')
local Radar=require('friteabc_re9.radar')
local Unlock=require('friteabc_re9.unlock')
local Hotkeys=require('friteabc_re9.hotkeys')
local Profiles=require('friteabc_re9.profiles')
local Stats=require('friteabc_re9.stats')
local Shield=require('friteabc_re9.shield')
local Savepoint=require('friteabc_re9.savepoint')
local Ambience=require('friteabc_re9.ambience')
local Nuke=require('friteabc_re9.nuke')
local hotkeyRun
pcall(Enemies.Install)
local state={open=true,status='Waiting for a playable character',last_probe=0,god=false,next_update=0,notice=nil,layout_ready=false}
local player,health,backup,marker
local protected={'Invincible','NoDieCharacter','NoWince'}
local function same(a,b)
    if a==nil or b==nil then return a==b end
    return a:get_address()==b:get_address()
end
local function inspect_player(current)
    local rows={}
    local function collect(label,object)
        if not object then return end
        local definition=object:get_type_definition()
        local row={label=label,type=definition:get_full_name(),fields={},methods={}}
        local class=definition
        while class do
            for _,field in ipairs(class:get_fields()) do row.fields[#row.fields+1]=field:get_name() end
            for _,method in ipairs(class:get_methods()) do
                local params={}
                for _,param in ipairs(method:get_param_types()) do params[#params+1]=param:get_full_name() end
                row.methods[#row.methods+1]={name=method:get_name(),params=params,names=method:get_param_names(),returns=method:get_return_type():get_full_name()}
            end
            class=class:get_parent_type()
        end
        rows[#rows+1]=row
    end
    collect('Player',current)
    for _,name in ipairs({'Common','TPSUnit','FPSUnit','Updater','HitPoint','Transform','GameObject'}) do
        pcall(function() collect(name,current:call('get_'..name)) end)
    end
    local ok,updater=pcall(function() return current:call('get_Updater') end)
    if ok and updater then
        for _,name in ipairs({'CharacterController','MovementDriver','MovementUnitControl','FPSMovementBlackboardUnit','InputUnit'}) do
            pcall(function() collect(name,updater:call('get_'..name)) end)
        end
    end
    json.dump_file('friteabc_re9_player.json',rows)
end
local function restore()
    pcall(Protection.Release)
    if health and backup then
        for name,value in pairs(backup) do pcall(function() health:call('set_'..name,value) end) end
    end
    health,backup=nil,nil
end
local function update()
    local manager=sdk.get_managed_singleton('app.CharacterManager')
    local current=manager and manager:call('get_PlayerContextFast')
    if not same(current,player) then
        restore();player=current
        state.settleUntil=os.clock()+3
        if Freecam.enabled then pcall(Freecam.Disable) end
        if current then pcall(inspect_player,current) end
        pcall(Speed.Bind,current)
        state.chaptersLoaded=false
        pcall(Damage.Bind,current)
        pcall(Tweaks.Bind,current)
    end
    if not player then state.status='Waiting for a playable character';return end
    state.status='Player ready'
    if not state.god then restore();return end
    local hp=player:call('get_HitPoint')
    if not same(hp,health) then
        restore()
        if not hp then return end
        local values={}
        for _,name in ipairs(protected) do
            local ok,value=pcall(function() return hp:call('get_'..name) end)
            if ok and type(value)=='boolean' then values[name]=value
            elseif name=='Invincible' then error('Invincibility is unavailable for this character') end
        end
        health,backup=hp,values
    end
    for name in pairs(backup) do
        if health:call('get_'..name)~=true then health:call('set_'..name,true) end
        assert(health:call('get_'..name)==true,'The game rejected '..name)
    end
    local guarded,why=pcall(Protection.Apply,player)
    Protection.status=not guarded and ('Scripted deaths: '..tostring(why)) or nil
end
local function action(fn)
    local ok,why=pcall(fn)
    if not ok then state.notice=tostring(why);log.error('[Friteabc RE9] '..state.notice) end
end
local queue={}
local function defer(fn) queue[#queue+1]=fn end
local function runQueue()
    local jobs=queue;queue={}
    for _,fn in ipairs(jobs) do action(fn) end
end
local function prepareLevelChange()
    pcall(Freecam.Disable)
    pcall(Movement.Stop)
    pcall(Remover.RestoreAll)
    pcall(Enemies.Release)
    pcall(Nuke.Release)
    pcall(Hud.Release)
    pcall(TimeScale.Release)
    Enemies.pending={}
    marker=nil
    log.info('[Friteabc RE9] Mod state cleared before level change')
end
Teleport.OnStart=prepareLevelChange
local function return_to_marker()
    assert(player and marker and marker.address==player:get_address(),'Save a position for this character first')
    Teleport.Warp(player,marker.x,marker.y,marker.z)
    Movement.Rebase(player)
    state.notice='Returned to saved position'
end
local candidates={'app.WarpOption','app.ReferenceCountBoolRequestHolder','app.PlayerManager','app.CharacterManager','app.PlayerCharacter','app.PlayerController','app.Player','app.Character','app.HitPoint','app.Health','app.PlayerContext','app.PlayerService','app.CharacterContext','app.PlayerCore','via.SceneManager','via.hid.Keyboard','via.Transform'}
local function inspect()
    local result={version='0.1.0',creator='friteabc',sdk={},types={}}
    for name in pairs(sdk) do result.sdk[#result.sdk+1]=tostring(name) end
    table.sort(result.sdk)
    for _,name in ipairs(candidates) do
        local ok,definition=pcall(sdk.find_type_definition,name)
        if ok and definition then
            local row={name=name,fields={},methods={},static_values={}}
            for _,field in ipairs(definition:get_fields()) do
                row.fields[#row.fields+1]=field:get_name()
                pcall(function()
                    if field:is_static() then
                        local value=field:get_data(nil)
                        if type(value)=='number' or type(value)=='boolean' then row.static_values[field:get_name()]=value end
                    end
                end)
            end
            for _,method in ipairs(definition:get_methods()) do row.methods[#row.methods+1]=method:get_name() end
            local found,instance=pcall(sdk.get_managed_singleton,name)
            row.singleton=found and instance~=nil
            result.types[#result.types+1]=row
        end
    end
    json.dump_file('friteabc_re9_discovery.json',result)
    state.status='RE9 menu loaded'
    log.info('[Friteabc RE9] Discovery saved; types='..#result.types)
end
re.on_frame(function()
    if state.last_probe==0 then
        state.last_probe=os.clock()
        local ok,why=pcall(inspect)
        if not ok then state.status=tostring(why);log.error('[Friteabc RE9] '..state.status) end
    end
    local now=os.clock()
    if now>=state.next_update then
        state.next_update=now+0.1
        local ok,why=pcall(update)
        if not ok then restore();state.god=false;state.notice=tostring(why) end
    end
end)
re.on_script_reset(restore)
re.on_script_reset(Movement.Suspend)
re.on_script_reset(Equipment.Reset)
re.on_script_reset(Visuals.Release)
re.on_script_reset(Camera.Release)
re.on_script_reset(function() pcall(Speed.Release) end)
re.on_script_reset(function() pcall(Nuke.Release);pcall(Teleport.RestoreNext);pcall(Shield.Release);pcall(Ambience.Release);pcall(View.Release);pcall(TimeScale.Release);pcall(Hud.Release);pcall(Enemies.Release);pcall(Tweaks.Release) end)
re.on_script_reset(Freecam.Disable)
re.on_script_reset(function() pcall(Remover.RestoreAll) end)
re.on_pre_application_entry('UpdateBehavior',function()
    local busy=Teleport.Busy()
    Protection.suspended=Teleport.pending~=nil
    pcall(Teleport.Watch,busy)
    if Teleport.refresh and not busy then Teleport.refresh=false;pcall(Teleport.Chapters) end
    pcall(Teleport.TickChain)
    state.busy=busy
    if busy then
        Freecam.External=nil
        Radar.rows={};Enemies.overlay={}
        state.settleUntil=os.clock()+3
        pcall(Damage.Clear)
        return
    end
    local settling=os.clock()<(state.settleUntil or 0)
    runQueue()
    pcall(Hotkeys.Tick,reframework:is_drawing_ui(),function(id) if hotkeyRun then action(function() hotkeyRun(id) end) end end)
    pcall(Stats.Tick,player,false)
    local shieldOK,shieldError=true,nil
    if not settling then shieldOK,shieldError=pcall(Shield.Tick,player) end
    if not shieldOK then Shield.Release();Shield.status=tostring(shieldError) end
    pcall(Ambience.Tick)
    if not settling then
        pcall(Nuke.Tick)
        pcall(Enemies.TickScale)
    end
    if Radar.panel then Radar.extra=Stats.Lines() else Radar.extra=nil end
    local keyOK,deleteDown=pcall(function() return reframework:is_key_down(46) end)
    deleteDown=keyOK and deleteDown==true
    if Remover.deleteKey and deleteDown and not state.deleteHeld and player and not reframework:is_drawing_ui() then
        action(function() Remover.Scan(player);Remover.RemoveTarget() end)
    end
    state.deleteHeld=deleteDown
    if state.showTarget and os.clock()>=(state.nextScan or 0) then
        state.nextScan=os.clock()+0.2
        pcall(Remover.Scan,player)
    end
    state.showTarget=false
    if not settling then pcall(Enemies.Tick,player) end
    local skinOK,skinError=pcall(Skins.Tick)
    if not skinOK then Skins.pending=nil;Skins.status=tostring(skinError) end
    local speedOK,speedError=pcall(Speed.Tick,player,Freecam.enabled or Movement.noclip or Movement.fly)
    if not speedOK then pcall(Speed.Release);Speed.status=tostring(speedError) end
    Tweaks.ammoKept=Equipment.noReload==true
    if settling then Tweaks.gunReady=false else pcall(Tweaks.TickCombat,player) end
    local tweakOK,tweakError=pcall(Tweaks.Tick,player)
    if not tweakOK then Tweaks.noFear=false;Tweaks.status=tostring(tweakError) end
    local timeOK,timeError=pcall(TimeScale.Tick,Freecam.paused)
    if not timeOK then TimeScale.speed=1;TimeScale.status=tostring(timeError) end
    pcall(Hud.Tick)
    if Damage.enabled and not settling then pcall(Damage.Poll);pcall(Damage.Tick) end
    Enemies.gather=Radar.panel
    if Radar.items or Radar.panel then
        pcall(Equipment.EnsureCatalog)
        if state.radarNames~=Equipment.items then state.radarNames=Equipment.items;Radar.SetNames(Equipment.items) end
    end
    local radarOK,radarError=pcall(Radar.Update,player)
    if not radarOK then Radar.status=tostring(radarError) end
    local enemyOK,enemyError=pcall(Enemies.Update,player)
    if not enemyOK then Enemies.status=tostring(enemyError) end
    local middle=false
    pcall(function() middle=reframework:is_key_down(0x04)==true end)
    if state.aimKey and middle and not state.middleHeld and player and not reframework:is_drawing_ui() and not Freecam.enabled then
        action(function() Teleport.GoTo(player,Remover.AimPoint(player));Movement.Rebase(player) end)
    end
    state.middleHeld=middle
    if View.Moved() and player then
        Freecam.External=View.OnCamera
        pcall(Freecam.EnsureHook)
        pcall(View.Clamp,function(...) return Remover.Distance(player,...) end)
    else
        Freecam.External=nil
    end
    if Camera.frozen~=Freecam.enabled then Camera.frozen=Freecam.enabled;Camera.Changed() end
    local cameraOK,cameraError=pcall(Camera.Tick)
    if not cameraOK then Camera.status=tostring(cameraError) end
    if Freecam.enabled then
        local holdOK,holdError=pcall(Freecam.Hold,player)
        if not holdOK then pcall(Freecam.Disable);state.notice='Free camera: '..tostring(holdError) end
    end
    local combatOK,combatError=pcall(Movement.UpdateCombat)
    if not combatOK then Movement.Stop();state.notice=tostring(combatError);log.error('[Friteabc RE9] '..state.notice) end
    local equipmentOK,equipmentError=pcall(Equipment.Tick,player)
    if not equipmentOK then Equipment.Fail(equipmentError) end
end)
re.on_application_entry('LateUpdateBehavior',function()
    if Freecam.enabled then pcall(Freecam.Apply) end
end)
re.on_pre_application_entry('LockScene',function()
    if Freecam.enabled then pcall(Freecam.Apply) end
end)
re.on_pre_application_entry('BeginRendering',function()
    if state.busy then return end
    if Freecam.enabled then
        local camOK,camError=pcall(Freecam.Update,reframework:is_drawing_ui())
        if not camOK then pcall(Freecam.Disable);state.notice='Free camera: '..tostring(camError);log.error('[Friteabc RE9] '..state.notice) end
    end
    local viewOK,viewError=pcall(View.ApplyFov,Freecam.enabled and Freecam.customFov)
    if not viewOK then View.status=tostring(viewError) end
    local visualsOK,visualsError=pcall(Visuals.Tick)
    if not visualsOK then
        local message=tostring(visualsError)
        if message~=Visuals.status then log.error('[Friteabc RE9] Lighting: '..message) end
        Visuals.status=message
    end
end)
re.on_frame(function()
    if state.busy then return end
    pcall(Enemies.Draw)
    pcall(Radar.Draw,Enemies.overlay)
    pcall(Nuke.Draw)
    local ok,why=pcall(Movement.SampleGround)
    if not ok then Movement.Stop();state.notice='Ground sampling: '..tostring(why);log.error('[Friteabc RE9] '..state.notice) end
end)
re.on_pre_application_entry('UpdatePhysicsCharacterController',function()
    local ok,why=pcall(Movement.Tick,player,reframework:is_drawing_ui() or Freecam.enabled)
    if not ok then local stage=Movement.stage;Movement.Stop();state.notice='Movement: '..tostring(stage)..': '..tostring(why);log.error('[Friteabc RE9] '..state.notice) end
end)
re.on_application_entry('UpdatePhysicsCharacterController',function()
    local ok,why=pcall(Movement.Sync)
    if not ok then local stage=Movement.stage;Movement.Stop();state.notice='Movement: '..tostring(stage)..': '..tostring(why);log.error('[Friteabc RE9] '..state.notice) end
end)
local VERSION='2.0'
local theme={text=0xFFE0E4E6,muted=0xFF99908D,faint=0xFF766E6A,good=0xFF8FB87F,bad=0xFF7070E0,accent=0xFF3A41C2}
local palette={
    {0,0xFFE0E4E6},{1,0xFF766E6A},{2,0xF7171513},{3,0x00000000},{4,0xFA1C1A18},{5,0xFF2E2B29},{6,0x00000000},
    {7,0xFF221F1D},{8,0xFF2A2725},{9,0xFF312E2B},{10,0xFF121110},{11,0xFF161412},{12,0xFF121110},
    {14,0x00000000},{15,0xFF35312E},{16,0xFF403B38},{17,0xFF4A4541},
    {18,0xFF3A41C2},{19,0xFF3A41C2},{20,0xFF4A52D6},
    {21,0xFF2A2624},{22,0xFF36312E},{23,0xFF292E8E},
    {24,0xFF282422},{25,0xFF342F2C},{26,0xFF3D3734},
    {27,0xFF302C2A},{30,0x00000000},{31,0xFF36312E},{32,0xFF3A41C2},
    {33,0xFF211E1C},{34,0xFF342F2C},{35,0xFF24287A}}
local rounding={{3,6},{7,4},{12,4},{19,6},{21,3}}
local function width()
    local ok,size=pcall(imgui.get_window_size)
    local w=ok and size and size.x or 420
    return math.max(260,w-32)
end
local function half() return (width()-8)/2 end
local function third() return (width()-16)/3 end
local function heading(label)
    imgui.spacing()
    imgui.text_colored(label,theme.muted)
    imgui.separator()
end
local sub={active=false,open=false}
local function beginSections(id)
    sub.active=imgui.begin_tab_bar~=nil and imgui.begin_tab_item~=nil and imgui.end_tab_item~=nil and imgui.end_tab_bar~=nil
    sub.open=sub.active and imgui.begin_tab_bar('sub_'..id)==true
end
local function endSections()
    if sub.active and sub.open then imgui.end_tab_bar() end
    sub.active,sub.open=false,false
end
local function section(label,tipText)
    if not sub.active then heading(label:upper());return true end
    if not sub.open then return false end
    local shown=imgui.begin_tab_item(label)
    if tipText and imgui.is_item_hovered and imgui.set_tooltip and imgui.is_item_hovered() then imgui.set_tooltip(tipText) end
    if shown then imgui.spacing() end
    return shown
end
local function sectionEnd()
    if sub.active and sub.open then imgui.end_tab_item() end
end
local function hint(text) imgui.text_colored(text,theme.faint) end
local function info(text) if text then imgui.text_colored(tostring(text),theme.muted) end end
local function tip(text)
    if imgui.is_item_hovered and imgui.set_tooltip and imgui.is_item_hovered() then imgui.set_tooltip(text) end
end
local function pager(label,page,pages)
    local w=math.floor((width()-90)/2)
    local previous=imgui.button('Previous##'..label,{w,24})
    imgui.same_line();imgui.text(string.format('  %d / %d  ',page,pages));imgui.same_line()
    local following=imgui.button('Next##'..label,{w,24})
    if previous then return math.max(1,page-1) end
    if following then return math.min(pages,page+1) end
    return page
end
local iconFont
pcall(function() if imgui.load_font then iconFont=imgui.load_font('friteabc_icons.ttf',15,{0x21BB,0x21BB,0}) end end)
local function revert(id,changed,fn)
    if not changed then return end
    imgui.same_line()
    local pushed=iconFont~=nil and imgui.push_font~=nil and imgui.pop_font~=nil
    if pushed then imgui.push_font(iconFont) end
    local clicked=imgui.button((pushed and '\u{21BB}' or 'R')..'##rv_'..id,{24,20})
    if pushed then imgui.pop_font() end
    tip('Default')
    if clicked then fn() end
end
local function sliderInt(label,value,low,high)
    if imgui.slider_int then return imgui.slider_int(label,value,low,high) end
    local changed,v=imgui.slider_float(label,value,low,high,'%.0f')
    return changed,math.floor(v+0.5)
end
local function setGod(value)
    state.god=value;state.notice=nil
    local ok,why=pcall(update)
    if not ok then restore();state.god=false;state.notice=tostring(why);log.error('[Friteabc RE9] '..state.notice) end
end
local function tabPlayer()
    beginSections('Player')
    if section('Protection') then
    local changed,value=imgui.checkbox('God mode',state.god)
    if changed then setGod(value) end
    revert('god',state.god,function() setGod(false) end)
    imgui.same_line()
    local fearChanged,noFear=imgui.checkbox('No fear',Tweaks.noFear)
    if fearChanged then Tweaks.noFear=noFear end
    revert('fear',Tweaks.noFear,function() Tweaks.noFear=false end)
    local shieldChanged,shield=imgui.checkbox('Enemies cannot touch you',Shield.enabled)
    if shieldChanged then Shield.Set(shield) end
    revert('shield',Shield.enabled,function() Shield.Set(false) end)
    info(Shield.status)
    if state.god then
        info(Protection.status)
        if Protection.blocked>0 then hint('Deaths blocked: '..Protection.blocked) end
    end
    if imgui.button('Restore health',{width(),30}) then action(function()
        assert(player,'No playable character')
        local hp=player:call('get_HitPoint')
        assert(hp,'Health unavailable')
        local maximum=hp:call('get_CurrentMaximumHitPoint')
        assert(type(maximum)=='number' and maximum>0,'Maximum health unavailable')
        hp:call('set_CurrentHitPoint',maximum)
    end) end
    sectionEnd() end
    if section('Movement', 'Fly: Space up, Ctrl down, Shift faster.') then
    local noclipChanged,noclip=imgui.checkbox('Noclip',Movement.noclip)
    if noclipChanged then defer(function() Movement.Set(player,noclip,Movement.fly) end) end
    revert('noclip',Movement.noclip,function() defer(function() Movement.Set(player,false,Movement.fly) end) end)
    imgui.same_line()
    local flyChanged,fly=imgui.checkbox('Fly',Movement.fly)
    if flyChanged then defer(function() Movement.Set(player,Movement.noclip,fly) end) end
    revert('fly',Movement.fly,function() defer(function() Movement.Set(player,Movement.noclip,false) end) end)
    local speedChanged,speed=imgui.slider_float('Fly speed',Movement.speed,0.5,15,'%.1f m/s')
    if speedChanged then Movement.speed=speed;Movement.Save() end
    revert('flyspeed',Movement.speed~=3,function() Movement.speed=3;Movement.Save() end)
    local runChanged,run=imgui.slider_float('Walk speed',Speed.multiplier,0.5,4,'x%.2f')
    if runChanged then Speed.multiplier=run;Speed.Save() end
    revert('walk',Speed.multiplier~=1,function() Speed.multiplier=1;Speed.Save();pcall(Speed.Release) end)
    info(Speed.status)
    if imgui.button('Disable movement modes',{width(),26}) then defer(Movement.Stop) end
    sectionEnd() end
    if section('Stats') then
    for _,line in ipairs(Stats.Lines()) do imgui.text_colored(line,theme.muted) end
    if imgui.button('Reset stats',{width(),22}) then Stats.Reset() end
    sectionEnd() end
    if section('Position') then
    if imgui.button('Save position',{half(),30}) then action(function()
        assert(player,'No playable character')
        local position=player:call('get_Transform'):call('get_Position')
        marker={x=position.x,y=position.y,z=position.z,address=player:get_address()}
        state.notice='Position saved'
    end) end
    imgui.same_line()
    imgui.begin_disabled(not marker or not player or marker.address~=player:get_address())
    if imgui.button('Return',{half(),30}) then defer(return_to_marker) end
    imgui.end_disabled()
    sectionEnd() end
    endSections()
end
local function tabCombat()
    beginSections('Combat')
    if section('Ammo') then
    local ammoChanged,ammo=imgui.checkbox('Infinite ammo',Equipment.infinite)
    if ammoChanged then action(function() Equipment.SetInfinite(ammo) end) end
    revert('ammo',Equipment.infinite,function() action(function() Equipment.SetInfinite(false) end) end)
    imgui.same_line()
    local reloadChanged,noReload=imgui.checkbox('No reload',Equipment.noReload)
    if reloadChanged then defer(function() Equipment.SetNoReload(noReload) end) end
    revert('noreload',Equipment.noReload,function() defer(function() Equipment.SetNoReload(false) end) end)
    sectionEnd() end
    if section('Handling') then
    local rateChanged,rate=imgui.slider_float('Fire rate',Tweaks.fireRate,1,4,'x%.1f')
    if rateChanged then Tweaks.fireRate=rate end
    revert('firerate',Tweaks.fireRate~=1,function() Tweaks.fireRate=1 end)
    local reloadSpeedChanged,reloadSpeed=imgui.slider_float('Reload speed',Tweaks.reloadSpeed,1,4,'x%.1f')
    if reloadSpeedChanged then Tweaks.reloadSpeed=reloadSpeed end
    revert('reloadspeed',Tweaks.reloadSpeed~=1,function() Tweaks.reloadSpeed=1 end)
    local instantChanged,instant=imgui.checkbox('Instant fire',Tweaks.instantFire)
    if instantChanged then Tweaks.instantFire=instant end
    revert('instantfire',Tweaks.instantFire,function() Tweaks.instantFire=false end)
    tip('Shoot as soon as you aim, without waiting for the raise animation.')
    imgui.same_line()
    local recoilChanged,noRecoil=imgui.checkbox('No recoil',Tweaks.noRecoil)
    if recoilChanged then Tweaks.noRecoil=noRecoil end
    revert('norecoil',Tweaks.noRecoil,function() Tweaks.noRecoil=false end)
    local instantReloadChanged,instantReload=imgui.checkbox('Instant reload',Tweaks.instantReload)
    if instantReloadChanged then Tweaks.instantReload=instantReload end
    revert('instantreload',Tweaks.instantReload,function() Tweaks.instantReload=false end)
    tip('The magazine refills as soon as it is not full, without the reload animation.')
    info(Tweaks.status)
    sectionEnd() end
    if section('Damage', 'One-shot: enemies protected by the story still survive.') then
    local shotChanged,oneShot=imgui.checkbox('One-shot kills',Damage.enabled)
    if shotChanged then defer(function() Damage.Set(oneShot,player) end) end
    revert('oneshot',Damage.enabled,function() defer(function() Damage.Set(false,player) end) end)
    if Damage.enabled and Damage.sources~='' then hint('Detection: '..Damage.sources) end
    if Damage.enabled then
        local forceChanged,force=imgui.checkbox('Finish protected enemies',Damage.forceKill)
        if forceChanged then Damage.forceKill=force end
        revert('forcekill',Damage.forceKill,function() Damage.forceKill=false end)
        tip('Also kills bosses and scripted enemies. Can crash the game.')
    end
    info(Damage.status)
    sectionEnd() end
    if section('Arsenal') then
    action(Equipment.EnsureCatalog)
    if imgui.button('Refresh list',{half(),26}) then action(Equipment.Refresh) end
    imgui.same_line()
    local shown=Equipment.Visible()
    imgui.begin_disabled(#shown==0 or Equipment.scanning)
    if imgui.button('Give all weapons',{half(),26}) then action(function() Equipment.GiveAll(player) end) end
    local pages=math.max(1,math.ceil(#shown/8))
    Equipment.page=math.max(1,math.min(pages,Equipment.page))
    local first=(Equipment.page-1)*8+1
    imgui.spacing()
    for index=first,math.min(first+7,#shown) do
        local entry=shown[index]
        if imgui.button(entry.name..'##give_'..entry.code,{width(),26}) then action(function() Equipment.Give(entry,player) end) end
    end
    if pages>1 then Equipment.page=pager('weapons',Equipment.page,pages) end
    imgui.end_disabled()
    local hidden=Equipment.HiddenCount()
    if hidden>0 then
        hint(hidden..' hidden (other character)')
        if imgui.button('Show hidden weapons',{width(),22}) then action(Equipment.ForgetUnusable) end
    end
    info(Equipment.status)
    sectionEnd() end
    endSections()
end
local function tabItems()
    beginSections('Items')
    if section('Items') then
    action(Equipment.EnsureCatalog)
    local catChanged,cat=imgui.combo('Category',Equipment.itemCategory,Equipment.categories)
    if catChanged then Equipment.itemCategory=cat;Equipment.itemPage=1 end
    revert('category',Equipment.itemCategory~=1,function() Equipment.itemCategory=1;Equipment.itemPage=1 end)
    local findChanged,find=imgui.input_text('Search##items',Equipment.itemFilter)
    if findChanged then Equipment.itemFilter=find;Equipment.itemPage=1 end
    revert('search',Equipment.itemFilter~='',function() Equipment.itemFilter='';Equipment.itemPage=1 end)
    local qtyChanged,qty=sliderInt('Quantity',Equipment.quantity,1,99)
    if qtyChanged then Equipment.quantity=qty end
    revert('quantity',Equipment.quantity~=10,function() Equipment.quantity=10 end)
    local shown=Equipment.FilteredItems()
    local pages=math.max(1,math.ceil(#shown/10))
    Equipment.itemPage=math.max(1,math.min(pages,Equipment.itemPage or 1))
    local first=(Equipment.itemPage-1)*10+1
    imgui.begin_disabled(Equipment.scanning)
    for index=first,math.min(first+9,#shown) do
        local entry=shown[index]
        if imgui.button(entry.name..'   ['..entry.category..']##item_'..entry.code,{width(),24}) then
            action(function() Equipment.GiveItem(entry,player,Equipment.quantity) end)
        end
    end
    if pages>1 then Equipment.itemPage=pager('items',Equipment.itemPage,pages) end
    imgui.end_disabled()
    hint(#shown..' items')
    info(Equipment.status)
    sectionEnd() end
    if section('Money') then
    local moneyChanged,money=imgui.checkbox('Infinite money',Equipment.infiniteMoney)
    if moneyChanged then Equipment.infiniteMoney=money end
    revert('money',Equipment.infiniteMoney,function() Equipment.infiniteMoney=false end)
    imgui.same_line()
    if imgui.button('Add 100 000',{half()-60,24}) then defer(function() Equipment.AddMoney(player,100000) end) end
    if Equipment.money then hint('Current: '..tostring(Equipment.money)) end
    sectionEnd() end
    if section('Inventory') then
    if imgui.button('Expand inventory to the maximum',{width(),26}) then defer(function() Equipment.MaxInventory(player) end) end
    sectionEnd() end
    endSections()
end
local function tabWorld()
    beginSections('World')
    if section('Teleport') then
    local nameChanged,tpName=imgui.input_text('Name',state.tpName or '')
    if nameChanged then state.tpName=tpName end
    if imgui.button('Save this place',{width(),26}) then defer(function() Teleport.Add(player,state.tpName) end) end
    if imgui.button('Teleport to aimed point',{width(),26}) then defer(function() Teleport.GoTo(player,Remover.AimPoint(player));Movement.Rebase(player) end) end
    local aimChanged,aimKey=imgui.checkbox('Middle mouse: teleport to aimed point',state.aimKey==true)
    if aimChanged then state.aimKey=aimKey end
    revert('aimkey',state.aimKey==true,function() state.aimKey=false end)
    if #Teleport.points>0 then
        local pickChanged,pick=imgui.combo('Point',Teleport.selected,Teleport.Names())
        if pickChanged then Teleport.selected=pick end
        if imgui.button('Teleport',{third(),26}) then defer(function() Teleport.Go(player) end) end
        imgui.same_line()
        if imgui.button('Undo',{third(),26}) then defer(function() Teleport.Undo(player) end) end
        imgui.same_line()
        if imgui.button('Delete##tp',{third(),26}) then Teleport.Remove() end
    end
    info(Teleport.status)
    sectionEnd() end
    if section('Save') then
    if imgui.button('Save here (experimental)',{width(),26}) then defer(function() Savepoint.SaveHere() end) end
    if imgui.button('Go to nearest typewriter',{half(),26}) then defer(function() Savepoint.Go(player);Movement.Rebase(player) end) end
    imgui.same_line()
    imgui.begin_disabled(not Savepoint.away)
    if imgui.button('Back##typewriter',{half(),26}) then defer(function() Savepoint.Back(player);Movement.Rebase(player) end) end
    imgui.end_disabled()
    imgui.begin_disabled(Teleport.pending~=nil or state.busy==true)
    if imgui.button('Reload last save',{width(),26}) then defer(function() if not Teleport.pending then Teleport.Jump(true) end end) end
    imgui.end_disabled()
    info(Savepoint.status)
    sectionEnd() end
    if section('Chapters', 'Direct jump, back or forth. Skipped chapters give no items or story events.') then
    if not state.chaptersLoaded then state.chaptersLoaded=true;defer(function() pcall(Teleport.Chapters) end) end
    imgui.text('Current: ');imgui.same_line();imgui.text_colored(Teleport.current or '?',theme.muted)
    imgui.begin_disabled(Teleport.pending~=nil or state.busy==true)
    if imgui.button('Next chapter'..(Teleport.next and ('  ('..Teleport.next..')') or ''),{width(),28}) then
        defer(function() if not Teleport.pending then Teleport.GoToChapter(nil) end end)
    end
    if #Teleport.chapters>0 then
        local pickChanged,pick=imgui.combo('Chapter',Teleport.chapterIndex,Teleport.chapters)
        if pickChanged then Teleport.chapterIndex=pick end
        if imgui.button('Go to selected chapter',{width(),26}) then
            local target=Teleport.chapters[Teleport.chapterIndex]
            defer(function() if not Teleport.pending then Teleport.GoToChapter(target) end end)
        end
    end
    if imgui.button('Reload game scene',{half(),24}) then defer(function() if not Teleport.pending then Teleport.Jump(false) end end) end
    imgui.same_line()
    if imgui.button('Restart from save',{half(),24}) then defer(function() if not Teleport.pending then Teleport.Jump(true) end end) end
    imgui.end_disabled()
    if imgui.button('Refresh chapter list',{width(),22}) then defer(function() Teleport.Chapters() end) end
    if Teleport.pending then hint(Teleport.pending.seen and 'Loading...' or 'Waiting for the game to start the change...') end
    if Teleport.chain then
        if imgui.button('Stop at the current chapter',{width(),22}) then Teleport.CancelChain() end
    end
    if imgui.button('Scan level system',{width(),24}) then defer(LevelProbe.Run) end
    info(LevelProbe.status)
    sectionEnd() end
    if section('Objects') then
    state.showTarget=true
    imgui.text('Aimed: ');imgui.same_line();imgui.text_colored(Remover.targetName or 'nothing',theme.muted)
    if imgui.button('Remove aimed object',{width(),26}) then defer(function() Remover.Scan(player);Remover.RemoveTarget() end) end
    local keyChanged,useKey=imgui.checkbox('Delete key removes aimed object',Remover.deleteKey)
    if keyChanged then Remover.deleteKey=useKey end
    revert('deletekey',Remover.deleteKey~=true,function() Remover.deleteKey=true end)
    if imgui.button('Restore removed objects ('..Remover.Count()..')',{width(),26}) then defer(Remover.RestoreAll) end
    info(Remover.status)
    sectionEnd() end
    if section('Detection', 'Visible through walls. Enemies show their health.') then
    local espChanged,esp=imgui.checkbox('Enemies',Enemies.esp)
    if espChanged then Enemies.esp=esp end
    revert('esp',Enemies.esp,function() Enemies.esp=false end)
    imgui.same_line()
    local itemsChanged,showItems=imgui.checkbox('Items',Radar.items)
    if itemsChanged then Radar.items=showItems end
    revert('items',Radar.items,function() Radar.items=false end)
    imgui.same_line()
    local panelChanged,panel=imgui.checkbox('Info panel',Radar.panel)
    if panelChanged then Radar.panel=panel end
    revert('panel',Radar.panel,function() Radar.panel=false end)
    local filterChanged,filter=imgui.combo('Item types',Radar.filter,Radar.filters)
    if filterChanged then Radar.filter=filter end
    revert('itemfilter',Radar.filter~=1,function() Radar.filter=1 end)
    info(Radar.status)
    sectionEnd() end
    if section('Locks', 'Aim at the chest, door or puzzle, then press Unlock.') then
    if imgui.button('Unlock aimed lock / puzzle',{width(),28}) then defer(function() Unlock.UnlockAimed(Remover.Contacts(player)) end) end
    info(Unlock.status)
    sectionEnd() end
    if section('Enemies') then
    local radiusChanged,radius=imgui.slider_float('Radius',Enemies.radius,5,150,'%.0f m')
    if radiusChanged then Enemies.radius=radius end
    revert('radius',Enemies.radius~=30,function() Enemies.radius=30 end)
    if imgui.button('Kill enemies nearby',{width(),28}) then defer(function() Enemies.KillNearby(player) end) end
    local sizeChanged,size=imgui.slider_float('Enemy size',Enemies.scale,0.3,3,'x%.2f')
    if sizeChanged then Enemies.scale=size end
    revert('enemysize',Enemies.scale~=1,function() Enemies.scale=1 end)
    local freezeChanged,freeze=imgui.checkbox('Freeze enemies',Enemies.freeze)
    if freezeChanged then defer(function() Enemies.SetFreeze(freeze) end) end
    revert('freeze',Enemies.freeze,function() defer(function() Enemies.SetFreeze(false) end) end)
    imgui.same_line()
    local hideChanged,hide=imgui.checkbox('Not detected',Enemies.undetected)
    if hideChanged then defer(function() Enemies.SetUndetected(player,hide) end) end
    revert('stealth',Enemies.undetected,function() defer(function() Enemies.SetUndetected(player,false) end) end)
    info(Enemies.stealthStatus)
    imgui.spacing()
    if imgui.button('Refresh spawnable enemies',{width(),26}) then defer(Enemies.Refresh) end
    for index,entry in ipairs(Enemies.list) do
        if index>8 then break end
        if imgui.button('Spawn '..entry.name..'##spawn'..index,{width(),24}) then defer(function() Enemies.Spawn(player,entry) end) end
    end
    if imgui.button('Bring enemies to me',{width(),26}) then defer(function() Enemies.BringAll(player) end) end
    info(Enemies.status)
    if imgui.button('Scan enemy system (read only)',{width(),22}) then defer(SpawnProbe.Run) end
    info(SpawnProbe.status)
    sectionEnd() end
    if section('Fun') then
        local nukeChanged,nukeRadius=imgui.slider_float('Blast radius',Nuke.radius,20,400,'%.0f m')
        if nukeChanged then Nuke.radius=nukeRadius end
        revert('nukeradius',Nuke.radius~=150,function() Nuke.radius=150 end)
        imgui.begin_disabled(Nuke.active)
        if imgui.button('NUCLEAR EXPLOSION',{width(),40}) then defer(function() Nuke.Trigger(player,Enemies,Visuals,TimeScale,View) end) end
        imgui.end_disabled()
        info(Nuke.status)
    sectionEnd() end
    if section('Steam') then
    hint('Reset: Win+R > steam://open/console')
    hint('then: reset_all_stats 3764200')
    sectionEnd() end
    endSections()
end
local function setView(key,value) View[key]=value;View.Save() end
local function tabCamera()
    beginSections('Camera')
    if section('Camera') then
    local fovChanged,fov=imgui.slider_float('Field of view##main',View.fov,-30,60,'%+.0f deg')
    if fovChanged then setView('fov',fov) end
    revert('mainfov',View.fov~=0,function() setView('fov',0) end)
    local distChanged,dist=imgui.slider_float('Distance',View.distance,0,6,'%.1f m')
    if distChanged then setView('distance',dist) end
    revert('distance',View.distance~=0,function() setView('distance',0) end)
    local heightChanged,height=imgui.slider_float('Height',View.height,-1,2,'%+.1f m')
    if heightChanged then setView('height',height) end
    revert('height',View.height~=0,function() setView('height',0) end)
    local sideChanged,side=imgui.slider_float('Side',View.side,-2,2,'%+.1f m')
    if sideChanged then setView('side',side) end
    revert('side',View.side~=0,function() setView('side',0) end)
    info(View.status)
    sectionEnd() end
    if section('Mouse') then
    local sensChanged,sens=imgui.slider_float('Sensitivity',Camera.sensitivity,0.25,6,'x%.2f')
    if sensChanged then Camera.sensitivity=sens;Camera.Save();Camera.Changed() end
    revert('sens',Camera.sensitivity~=1,function() Camera.sensitivity=1;Camera.Save();Camera.Changed() end)
    info(Camera.status)
    sectionEnd() end
    if section('Free cam') then
    local freeChanged,free=imgui.checkbox('Free camera',Freecam.enabled)
    if freeChanged then defer(function() if free then Freecam.Enable(player) else Freecam.Disable() end end) end
    revert('free',Freecam.enabled,function() defer(Freecam.Disable) end)
    imgui.same_line()
    local lookChanged,look=imgui.checkbox('Look at character',Freecam.lookAtPlayer)
    if lookChanged then Freecam.lookAtPlayer=look end
    revert('lookat',Freecam.lookAtPlayer,function() Freecam.lookAtPlayer=false end)
    local bodyChanged,body=imgui.checkbox('Third-person view while free',Freecam.showBody)
    if bodyChanged then Freecam.showBody=body end
    revert('body',Freecam.showBody~=true,function() Freecam.showBody=true end)
    local camSpeedChanged,camSpeed=imgui.slider_float('Camera speed',Freecam.speed,0.5,20,'%.1f m/s')
    if camSpeedChanged then Freecam.speed=camSpeed end
    revert('camspeed',Freecam.speed~=4,function() Freecam.speed=4 end)
    local lookSpeedChanged,lookSpeed=imgui.slider_float('Look speed',Freecam.lookSpeed,0.2,4,'x%.1f')
    if lookSpeedChanged then Freecam.lookSpeed=lookSpeed end
    revert('lookspeed',Freecam.lookSpeed~=1,function() Freecam.lookSpeed=1 end)
    local customChanged,customFov=imgui.checkbox('Own field of view',Freecam.customFov)
    if customChanged then Freecam.customFov=customFov end
    revert('customfov',Freecam.customFov,function() Freecam.customFov=false end)
    imgui.begin_disabled(not Freecam.customFov)
    local freeFovChanged,freeFov=imgui.slider_float('Field of view##free',Freecam.fov,10,120,'%.0f deg')
    if freeFovChanged then Freecam.fov=freeFov end
    imgui.end_disabled()
    local rollChanged,roll=imgui.slider_float('Tilt',Freecam.roll,-45,45,'%.0f deg')
    if rollChanged then Freecam.roll=roll end
    revert('tilt',Freecam.roll~=0,function() Freecam.roll=0 end)
    imgui.begin_disabled(not Freecam.enabled)
    local pauseChanged,pause=imgui.checkbox('Pause game (P)',Freecam.paused)
    if pauseChanged then defer(function() Freecam.SetPause(pause) end) end
    revert('pause',Freecam.paused,function() defer(function() Freecam.SetPause(false) end) end)
    if imgui.button('Face the character',{width(),26}) then defer(Freecam.Focus) end
    imgui.end_disabled()
    if Freecam.enabled and Freecam.frozenHead==0 then hint('Head tracking: no component found') end
    sectionEnd() end
    if section('Photo') then
    local hudChanged,hud=imgui.checkbox('Hide game interface',Hud.hidden)
    if hudChanged then defer(function() Hud.Set(hud) end) end
    revert('hud',Hud.hidden,function() defer(function() Hud.Set(false) end) end)
    info(Hud.status)
    sectionEnd() end
    if section('Speed') then
    local timeChanged,timeSpeed=imgui.slider_float('Game speed',TimeScale.speed,0.1,3,'x%.2f')
    if timeChanged then TimeScale.speed=timeSpeed end
    revert('timescale',TimeScale.speed~=1,function() TimeScale.speed=1 end)
    info(TimeScale.status)
    sectionEnd() end
    endSections()
end
local function tabVisuals()
    beginSections('Visuals')
    if section('Lighting') then
    local modeChanged,mode=imgui.combo('Mode',Visuals.mode,Visuals.modes)
    if modeChanged then Visuals.mode=mode;Visuals.Save() end
    revert('lightmode',Visuals.mode~=1,function() Visuals.mode=1;Visuals.Save() end)
    local evChanged,ev=imgui.slider_float('Exposure',Visuals.exposure,-6,10,'%+.1f')
    if evChanged then Visuals.exposure=ev;Visuals.Save() end
    revert('exposure',Visuals.exposure~=0,function() Visuals.exposure=0;Visuals.Save() end)
    local fogChanged,fog=imgui.checkbox('Fog',Visuals.fog)
    if fogChanged then Visuals.fog=fog;Visuals.Save() end
    revert('fog',Visuals.fog~=true,function() Visuals.fog=true;Visuals.Save() end)
    imgui.same_line()
    local lightsChanged,lights=imgui.checkbox('Scene lights off',Visuals.lightsOff)
    if lightsChanged then Visuals.lightsOff=lights;Visuals.Save() end
    revert('lights',Visuals.lightsOff,function() Visuals.lightsOff=false;Visuals.Save() end)
    info(Visuals.status)
    sectionEnd() end
    if section('Ambience', 'Experimental. Time of day is not available.') then
    local rainChanged,rain=imgui.checkbox('Rain',Ambience.rain)
    if rainChanged then Ambience.rain=rain end
    revert('rain',not Ambience.rain,function() Ambience.rain=true end)
    imgui.same_line()
    local cloudChanged,clouds=imgui.checkbox('Clouds',Ambience.clouds)
    if cloudChanged then Ambience.clouds=clouds end
    revert('clouds',not Ambience.clouds,function() Ambience.clouds=true end)
    imgui.same_line()
    local windChanged,wind=imgui.checkbox('Wind',Ambience.wind)
    if windChanged then Ambience.wind=wind end
    revert('wind',not Ambience.wind,function() Ambience.wind=true end)
    info(Ambience.status)
    sectionEnd() end
    if section('Outfit') then
    if not Skins.loaded then
        if imgui.button('Load outfits',{width(),26}) then defer(function() Skins.Load(player) end) end
    else
        local filterChanged,filter=imgui.input_text('Search',Skins.filter)
        if filterChanged then Skins.filter=filter;Skins.page=1 end
        local shown=Skins.Filtered()
        local pages=math.max(1,math.ceil(#shown/8))
        Skins.page=math.max(1,math.min(pages,Skins.page))
        local first=(Skins.page-1)*8+1
        for index=first,math.min(first+7,#shown) do
            local entry=shown[index]
            if imgui.button(entry.name..'##skin_'..index,{width(),24}) then defer(function() Skins.Apply(player,entry) end) end
        end
        if pages>1 then Skins.page=pager('skins',Skins.page,pages) end
        imgui.begin_disabled(not Skins.HasBackup(player))
        if imgui.button('Original outfit',{half(),24}) then defer(function() Skins.Restore(player) end) end
        imgui.end_disabled()
        imgui.same_line()
        if imgui.button('Reload list',{half(),24}) then defer(function() Skins.Load(player) end) end
    end
    info(Skins.status)
    sectionEnd() end
    endSections()
end
local function snapshot()
    return {god=state.god,noFear=Tweaks.noFear,shield=Shield.enabled,flySpeed=Movement.speed,walk=Speed.multiplier,
        ammo=Equipment.infinite,noReload=Equipment.noReload,fireRate=Tweaks.fireRate,instantFire=Tweaks.instantFire,noRecoil=Tweaks.noRecoil,instantReload=Tweaks.instantReload,reloadSpeed=Tweaks.reloadSpeed,oneShot=Damage.enabled,
        money=Equipment.infiniteMoney,esp=Enemies.esp,items=Radar.items,panel=Radar.panel,itemFilter=Radar.filter,enemyScale=Enemies.scale,
        freeze=Enemies.freeze,fov=View.fov,distance=View.distance,height=View.height,side=View.side,sensitivity=Camera.sensitivity,
        timeScale=TimeScale.speed,lightMode=Visuals.mode,exposure=Visuals.exposure,fog=Visuals.fog,lightsOff=Visuals.lightsOff,
        rain=Ambience.rain,clouds=Ambience.clouds,wind=Ambience.wind}
end
local function applyProfile(p)
    local function n(v,d) return type(v)=='number' and v or d end
    local function b(v,d) if type(v)=='boolean' then return v end return d end
    if b(p.god,false)~=state.god then setGod(b(p.god,false)) end
    Tweaks.noFear=b(p.noFear,false);Shield.Set(b(p.shield,false))
    Movement.speed=n(p.flySpeed,3);pcall(Movement.Save);Speed.multiplier=n(p.walk,1);pcall(Speed.Save)
    if b(p.ammo,false)~=Equipment.infinite then action(function() Equipment.SetInfinite(b(p.ammo,false)) end) end
    if b(p.noReload,false)~=Equipment.noReload then action(function() Equipment.SetNoReload(b(p.noReload,false)) end) end
    Tweaks.fireRate=n(p.fireRate,1);Tweaks.reloadSpeed=n(p.reloadSpeed,1);Tweaks.instantFire=b(p.instantFire,false);Tweaks.noRecoil=b(p.noRecoil,false);Tweaks.instantReload=b(p.instantReload,false)
    if b(p.oneShot,false)~=Damage.enabled then action(function() Damage.Set(b(p.oneShot,false),player) end) end
    Equipment.infiniteMoney=b(p.money,false);Enemies.esp=b(p.esp,false);Radar.items=b(p.items,false);Radar.panel=b(p.panel,false)
    Radar.filter=n(p.itemFilter,1);Enemies.scale=n(p.enemyScale,1)
    if b(p.freeze,false)~=Enemies.freeze then action(function() Enemies.SetFreeze(b(p.freeze,false)) end) end
    View.fov=n(p.fov,0);View.distance=n(p.distance,0);View.height=n(p.height,0);View.side=n(p.side,0);View.Save()
    Camera.sensitivity=n(p.sensitivity,1);pcall(Camera.Save);pcall(Camera.Changed)
    TimeScale.speed=n(p.timeScale,1)
    Visuals.mode=n(p.lightMode,1);Visuals.exposure=n(p.exposure,0);Visuals.fog=b(p.fog,true);Visuals.lightsOff=b(p.lightsOff,false);pcall(Visuals.Save)
    Ambience.rain=b(p.rain,true);Ambience.clouds=b(p.clouds,true);Ambience.wind=b(p.wind,true)
end
local function onOff(label,value) state.notice=label..(value and ' on' or ' off') end
hotkeyRun=function(id)
    if id=='god' then setGod(not state.god);onOff('God mode',state.god)
    elseif id=='noclip' then Movement.Set(player,not Movement.noclip,Movement.fly);onOff('Noclip',Movement.noclip)
    elseif id=='fly' then Movement.Set(player,Movement.noclip,not Movement.fly);onOff('Fly',Movement.fly)
    elseif id=='freecam' then if Freecam.enabled then Freecam.Disable() else Freecam.Enable(player) end;onOff('Free camera',Freecam.enabled)
    elseif id=='oneshot' then Damage.Set(not Damage.enabled,player);onOff('One-shot kills',Damage.enabled)
    elseif id=='reload' then if not Teleport.pending then Teleport.Jump(true);state.notice='Reloading last save' end
    elseif id=='save' then Savepoint.Toggle(player);pcall(Movement.Rebase,player);state.notice=Savepoint.status
    elseif id=='hud' then Hud.Set(not Hud.hidden);onOff('Game interface hidden',Hud.hidden)
    elseif id=='freeze' then Enemies.SetFreeze(not Enemies.freeze);onOff('Freeze enemies',Enemies.freeze)
    elseif id=='kill' then Enemies.KillNearby(player);state.notice=Enemies.status
    elseif id=='nuke' then Nuke.Trigger(player,Enemies,Visuals,TimeScale,View);state.notice='Boom' end
end
local function tabSettings()
    beginSections('Settings')
    if section('Hotkeys', 'Click a key, then press the new one. Esc cancels. Hotkeys are ignored while this menu is open.') then
    for _,a in ipairs(Hotkeys.actions) do
        local code=Hotkeys.binds[a.id]
        local waiting=Hotkeys.waiting==a.id
        if imgui.button((waiting and 'Press a key...' or Hotkeys.Name(code))..'##hk_'..a.id,{110,22}) then Hotkeys.Capture(a.id) end
        imgui.same_line();imgui.text(a.label)
        revert('hk_'..a.id,code~=a.key,function() Hotkeys.Default(a.id) end)
        if code and code~=0 then
            imgui.same_line()
            if imgui.button('Clear##hkc_'..a.id,{50,20}) then Hotkeys.Clear(a.id) end
        end
    end
    info(Hotkeys.status)
    sectionEnd() end
    if section('Profiles') then
    local nameChanged,name=imgui.input_text('Name##profile',state.profileName or '')
    if nameChanged then state.profileName=name end
    if imgui.button('Save current settings',{width(),26}) then action(function() Profiles.Store(state.profileName,snapshot()) end) end
    if #Profiles.list>0 then
        local pickChanged,pick=imgui.combo('Profile',Profiles.selected,Profiles.list)
        if pickChanged then Profiles.selected=pick end
        if imgui.button('Load##profile',{half(),26}) then
            local chosen=Profiles.list[Profiles.selected]
            defer(function() applyProfile(assert(Profiles.Get(chosen),'Profile missing'));Profiles.status='Profile loaded: '..chosen end)
        end
        imgui.same_line()
        if imgui.button('Delete##profile',{half(),26}) then Profiles.Remove(Profiles.list[Profiles.selected]) end
    end
    info(Profiles.status)
    sectionEnd() end
    endSections()
end
local function resetSettings()
    for _,a in ipairs(Hotkeys.actions) do Hotkeys.binds[a.id]=a.key end
    Hotkeys.waiting=nil;Hotkeys.Save()
end
local function safe(fn,...) local ok,why=pcall(fn,...);if not ok then log.error('[Friteabc RE9] Reset: '..tostring(why)) end end
local function resetPlayer()
    state.god=false;safe(restore)
    Tweaks.noFear=false;safe(Tweaks.Tick,player)
    safe(Shield.Release)
    safe(Movement.Stop)
    Movement.speed=3;safe(Movement.Save)
    Speed.multiplier=1.0;safe(Speed.Save);safe(Speed.Release)
end
local function resetCombat()
    safe(Equipment.SetInfinite,false)
    safe(Equipment.SetNoReload,false)
    Tweaks.fireRate=1.0;Tweaks.reloadSpeed=1.0
    Tweaks.instantFire=false;Tweaks.noRecoil=false;Tweaks.instantReload=false;safe(Tweaks.TickCombat,player)
    safe(Damage.Set,false,player);Damage.forceKill=false
end
local function resetItems()
    Equipment.infiniteMoney=false
    Equipment.quantity=10;Equipment.itemCategory=1;Equipment.itemFilter='';Equipment.itemPage=1
end
local function resetWorld()
    state.aimKey=false
    Remover.deleteKey=true
    safe(Enemies.SetFreeze,false)
    Enemies.esp=false;Enemies.overlay={}
    Radar.items=false;Radar.panel=false;Radar.filter=1;safe(Radar.Release)
    if Enemies.undetected then safe(Enemies.SetUndetected,player,false) end
    Enemies.radius=30
    safe(Enemies.ReleaseScale)
end
local function resetCamera()
    safe(Freecam.Disable)
    Freecam.speed=4;Freecam.lookSpeed=1.0;Freecam.lookAtPlayer=false;Freecam.showBody=true
    Freecam.customFov=false;Freecam.fov=60;Freecam.roll=0
    safe(Hud.Release)
    TimeScale.speed=1.0;safe(TimeScale.Release)
    Camera.sensitivity=1.0;safe(Camera.Save);safe(Camera.Changed)
    safe(View.Reset)
end
local function resetVisuals()
    safe(Visuals.Reset)
    safe(Ambience.Release)
    if Skins.HasBackup(player) then safe(Skins.Restore,player) end
end
local function resetAll()
    resetPlayer();resetCombat();resetItems();resetWorld();resetCamera();resetVisuals()
    log.info('[Friteabc RE9] All settings reset')
end
local tabs={{'Player',tabPlayer,resetPlayer},{'Combat',tabCombat,resetCombat},{'Items',tabItems,resetItems},{'World',tabWorld,resetWorld},{'Camera',tabCamera,resetCamera},{'Visuals',tabVisuals,resetVisuals},{'Settings',tabSettings,resetSettings}}
local function body(tab)
    imgui.begin_disabled(player==nil)
    local ok,why=pcall(tab[2])
    if ok then
        imgui.spacing();imgui.spacing();imgui.separator()
        if imgui.button('Reset '..tab[1]..' settings##reset_'..tab[1],{width(),24}) then
            defer(function() tab[3]();state.notice=tab[1]..' settings reset to default' end)
        end
    end
    imgui.end_disabled()
    if not ok then error(why,0) end
end
local function draw_menu()
    imgui.text('REQUIEM MENU');imgui.same_line();imgui.text_colored('v'..VERSION,theme.faint)
    if player then imgui.text_colored('Character ready',theme.good)
    else imgui.text_colored('Waiting for a playable character',theme.muted) end
    imgui.spacing()
    if imgui.begin_tab_bar and imgui.begin_tab_item and imgui.end_tab_item and imgui.end_tab_bar then
        if imgui.begin_tab_bar('friteabc_tabs') then
            for _,tab in ipairs(tabs) do
                if imgui.begin_tab_item(tab[1]) then
                    local ok,why=pcall(body,tab)
                    imgui.end_tab_item()
                    if not ok then state.notice=tostring(why) end
                end
            end
            imgui.end_tab_bar()
        end
    else
        for _,tab in ipairs(tabs) do body(tab) end
    end
    imgui.spacing();imgui.separator()
    local confirming=state.confirmReset and os.clock()<state.confirmReset
    if imgui.button(confirming and 'Click again to reset everything##resetall' or 'Reset all settings##resetall',{width(),26}) then
        if confirming then
            state.confirmReset=nil
            defer(function() resetAll();state.notice='All settings reset to default' end)
        else
            state.confirmReset=os.clock()+3
        end
    end
    if state.notice then imgui.text_colored(state.notice,theme.muted) end
    if state.status~='Player ready' then hint(state.status) end
    hint('Insert: menu   |   Created by friteabc')
end
re.on_frame(function()
    if not reframework:is_drawing_ui() then return end
    if not state.layout_ready then
        imgui.set_next_window_size({440,680},1)
        state.layout_ready=true
    end
    imgui.set_next_window_pos({460,170},4,nil)
    for _,color in ipairs(palette) do imgui.push_style_color(color[1],color[2]) end
    local pushed=0
    if imgui.push_style_var and imgui.pop_style_var then
        for _,var in ipairs(rounding) do
            if pcall(imgui.push_style_var,var[1],var[2]) then pushed=pushed+1 end
        end
    end
    imgui.begin_window('Requiem Menu  |  friteabc###friteabc_re9_menu',nil,0)
    local ok,why=pcall(draw_menu)
    imgui.end_window()
    if pushed>0 then imgui.pop_style_var(pushed) end
    imgui.pop_style_color(#palette)
    if not ok then state.status=tostring(why);log.error('[Friteabc RE9] '..state.status) end
end)
