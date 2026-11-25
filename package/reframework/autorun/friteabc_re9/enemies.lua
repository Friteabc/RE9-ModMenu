local Teleport=require('friteabc_re9.teleport')
local M={learned=nil,list={},status=nil,pending={}}
local SIGNATURE='requestSpawn(app.ContextID, app.CharacterKindID, app.MontageID, System.Int32, System.Boolean, app.CharacterUsePurposeFlag)'
local hooked=false
local function manager() return sdk.get_managed_singleton('app.CharacterManager') end
local function text(value)
    local ok,result=pcall(function() return value:call('ToString()') end)
    return ok and type(result)=='string' and result or '?'
end
function M.Install()
    if hooked then return end
    local definition=sdk.find_type_definition('app.CharacterManager')
    assert(definition,'Character manager type unavailable')
    for _,method in ipairs(definition:get_methods()) do
        if method:get_name()=='requestSpawn' and (method:get_num_params()==6 or method:get_num_params()==5) then
            local six=method:get_num_params()==6
            local flagType=method:get_param_types()[six and 6 or 3]
            local flagIsValue=flagType:is_value_type()
            sdk.hook(method,function(args)
                if M.ownCall then return sdk.PreHookResult.CALL_ORIGINAL end
                pcall(function()
                    local learned={int=six and (sdk.to_int64(args[6]) & 0xFFFFFFFF) or 0,bool=(sdk.to_int64(args[six and 7 or 7]) & 1)==1}
                    if learned.int>=0x80000000 then learned.int=learned.int-0x100000000 end
                    local flagArg=args[six and 8 or 5]
                    if flagIsValue then learned.flag=sdk.to_int64(flagArg)
                    else
                        local flag=sdk.to_managed_object(flagArg)
                        if flag then flag:add_ref();learned.flag=flag end
                    end
                    if learned.flag~=nil then
                        M.learned=learned
                        log.info('[Friteabc RE9] Spawn parameters learned: int='..learned.int..' bool='..tostring(learned.bool)..' flag='..tostring(learned.flag))
                    end
                end)
                return sdk.PreHookResult.CALL_ORIGINAL
            end,function(value) return value end)
        end
    end
    hooked=true
end
local function contexts(getter)
    local out={}
    pcall(function()
        local list=manager():call(getter)
        for _,context in ipairs(list:call('ToArray'):get_elements()) do out[#out+1]=context end
    end)
    return out
end
local function spawnDataOf(context)
    local ok,data=pcall(function() return context:get_field('<SpawnData>k__BackingField') end)
    if ok and data then return data end
    local okRef,ref=pcall(function() return manager():call('getSpawnDataRef(app.ContextID)',context:get_field('<ID>k__BackingField')) end)
    if okRef and ref then return ref end
    return nil
end
local function donorFor(kind)
    local fallback,fallbackContext
    for _,context in ipairs(contexts('get_EnemyContextList')) do
        local data=spawnDataOf(context)
        if data and text(context:get_field('<KindID>k__BackingField'))==kind then
            local okSpawn,spawned=pcall(function() return context:call('get_IsSpawn') end)
            if okSpawn and spawned then return data,context end
            fallback,fallbackContext=fallback or data,fallbackContext or context
        end
    end
    return fallback,fallbackContext
end
local function visibleModel(kind)
    for _,context in ipairs(contexts('get_EnemyContextList')) do
        local ok,match=pcall(function()
            return text(context:get_field('<KindID>k__BackingField'))==kind and context:call('get_IsSpawn')==true and context:get_field('<Transform>k__BackingField')~=nil
        end)
        if ok and match then return context end
    end
end
local function objectOf(context)
    local ok,go=pcall(function() return context:call('get_GameObject') end)
    if ok and go then return go end
    local okT,transform=pcall(function() return context:get_field('<Transform>k__BackingField') end)
    if okT and transform then return transform:call('get_GameObject') end
end
local function meshes(go,depth,out)
    out=out or {}
    if not go or depth>4 then return out end
    pcall(function()
        for _,component in ipairs(go:call('get_Components'):get_elements()) do
            local okName,name=pcall(function() return component:get_type_definition():get_full_name() end)
            if okName and name=='via.render.Mesh' then out[#out+1]={component=component,object=go} end
        end
    end)
    pcall(function()
        local child=go:call('get_Transform'):call('get_Child')
        local count=0
        while child and count<64 do meshes(child:call('get_GameObject'),depth+1,out);child=child:call('get_Next');count=count+1 end
    end)
    return out
end
local function showBody(context)
    local go=objectOf(context)
    if not go then return 0,0 end
    pcall(function() if go:call('get_DrawSelf')==false then go:call('set_DrawSelf',true) end end)
    local list=meshes(go,0)
    local fixed=0
    for _,entry in ipairs(list) do
        pcall(function()
            if entry.component:call('get_Enabled')==false then entry.component:call('set_Enabled',true);fixed=fixed+1 end
            if entry.object:call('get_DrawSelf')==false then entry.object:call('set_DrawSelf',true);fixed=fixed+1 end
        end)
    end
    return #list,fixed
end
local function same(a,b) return text(a)==text(b) end
local function copySpawnData(context,donor,x,y,z)
    local data
    pcall(function() data=donor:call('MemberwiseClone') end)
    if not data then
        data=sdk.create_instance(donor:get_type_definition():get_full_name())
        assert(data,'Spawn data could not be created')
        local class=donor:get_type_definition()
        while class do
            for _,field in ipairs(class:get_fields()) do
                if not field:is_static() then pcall(function() data:set_field(field:get_name(),field:get_data(donor)) end) end
            end
            class=class:get_parent_type()
        end
    end
    data:add_ref()
    local id=context:get_field('<ID>k__BackingField')
    data:set_field('<ContextID>k__BackingField',id)
    assert(same(data:get_field('<ContextID>k__BackingField'),id),'Spawn data copy refused the enemy ID')
    pcall(function() data:set_field('<KindID>k__BackingField',context:get_field('<KindID>k__BackingField')) end)
    pcall(function() data:set_field('<Position>k__BackingField',Vector3f.new(x,y,z)) end)
    pcall(function() data:set_field('<IsFirstSpawn>k__BackingField',true) end)
    return data
end
function M.Refresh()
    M.Install()
    local list={}
    local dump={}
    local seenAddress={}
    for _,getter in ipairs({'get_EnemyContextList','get_SpawnableContextList'}) do
        for _,context in ipairs(contexts(getter)) do
            local okSpawn,spawned=pcall(function() return context:call('get_IsSpawn') end)
            local address=context:get_address()
            if okSpawn and spawned==false and not seenAddress[address] then
                seenAddress[address]=true
                local kind=text(context:get_field('<KindID>k__BackingField'))
                context:add_ref()
                local flag
                local ok,why=pcall(function()
                    local data=context:get_field('<SpawnData>k__BackingField')
                    local row={kind=kind,type=data and data:get_type_definition():get_full_name() or 'nil',fields={},context={}}
                    for _,name in ipairs({'<IsSuspended>k__BackingField','<IsSpawn>k__BackingField','<IsRespawn>k__BackingField','<ResumeAreaID>k__BackingField','<Managed>k__BackingField','<ContextStoreStyle>k__BackingField'}) do
                        pcall(function() local v=context:get_field(name);row.context[name]=type(v)=='userdata' and text(v) or v end)
                    end
                    if not data then if #dump<6 then dump[#dump+1]=row end;return end
                    local class=data:get_type_definition()
                    while class do
                        for _,field in ipairs(class:get_fields()) do
                            if not field:is_static() then
                                local typeName=field:get_type():get_full_name()
                                local okValue,v=pcall(field.get_data,field,data)
                                row.fields[field:get_name()]=typeName..' = '..tostring(okValue and (type(v)=='userdata' and text(v) or v) or '?')
                                if typeName=='app.CharacterUsePurposeFlag' and okValue and flag==nil then flag=v end
                            end
                        end
                        class=class:get_parent_type()
                    end
                    if #dump<6 then dump[#dump+1]=row end
                end)
                if not ok and #dump<6 then dump[#dump+1]={kind=kind,error=tostring(why)} end
                local ready=spawnDataOf(context)~=nil
                local copy=not ready and donorFor(kind)~=nil
                list[#list+1]={kind=kind,context=context,flag=flag,ready=ready,copy=copy}
            end
        end
    end
    local spawned={}
    local function shape(object,depth)
        local ok,definition=pcall(function() return object:get_type_definition() end)
        if not ok or not definition then return tostring(object) end
        local out={type=definition:get_full_name(),fields={}}
        local class=definition
        while class do
            for _,field in ipairs(class:get_fields()) do
                if not field:is_static() then
                    local typeName=field:get_type():get_full_name()
                    local okValue,v=pcall(field.get_data,field,object)
                    if okValue and type(v)=='userdata' and depth>0 and not typeName:find('Action') then
                        out.fields[field:get_name()]={type=typeName,value=shape(v,depth-1),text=text(v)}
                    else
                        out.fields[field:get_name()]={type=typeName,value=okValue and (type(v)=='userdata' and text(v) or v) or '?'}
                    end
                end
            end
            class=class:get_parent_type()
        end
        return out
    end
    for _,context in ipairs(contexts('get_EnemyContextList')) do
        local okSpawn,isSpawned=pcall(function() return context:call('get_IsSpawn') end)
        if okSpawn and isSpawned and #spawned<3 then
            pcall(function()
                spawned[#spawned+1]={kind=text(context:get_field('<KindID>k__BackingField')),
                    spawnData=shape(context:get_field('<SpawnData>k__BackingField'),2),id=shape(context:get_field('<ID>k__BackingField'),1)}
            end)
        end
    end
    local flags={}
    pcall(function()
        for _,field in ipairs(sdk.find_type_definition('app.CharacterUsePurposeFlag'):get_fields()) do
            if field:is_static() then pcall(function() local v=field:get_data(nil);flags[field:get_name()]=type(v)=='userdata' and text(v) or v end) end
        end
    end)
    pcall(function() json.dump_file('friteabc_re9_spawn_targets.json',{targets=dump,purposeFlags=flags,spawned=spawned}) end)
    local function rank(entry) return entry.ready and 0 or (entry.copy and 1 or 2) end
    table.sort(list,function(a,b) if rank(a)~=rank(b) then return rank(a)<rank(b) end return a.kind<b.kind end)
    local usable=0
    for i,entry in ipairs(list) do
        entry.name=entry.kind..'  #'..i..((entry.ready or entry.copy) and '' or '  (unavailable)')
        if entry.ready or entry.copy then usable=usable+1 end
    end
    M.list=list
    M.status=usable..' / '..#list..' can be spawned'
end
local function near(player,index)
    local transform=player:call('get_Transform')
    local p=transform:call('get_Position')
    local f=transform:call('get_AxisZ')
    local side=((index or 0)%3-1)*1.2
    return p.x+f.x*3+f.z*side,p.y,p.z+f.z*3-f.x*side
end
function M.Spawn(player,entry)
    assert(player,'No playable character')
    local params=M.learned or {int=0,bool=false,flag=entry.flag~=nil and entry.flag or 0,default=true}
    local context=entry.context
    local characters=manager()
    local x,y,z=near(player,#M.pending)
    if not spawnDataOf(context) then
        local donor=assert(donorFor(entry.kind),'No '..entry.kind..' in this area to copy its spawn settings from')
        log.info('[Friteabc RE9] Spawn: copying spawn settings for '..entry.kind)
        local data=copySpawnData(context,donor,x,y,z)
        log.info('[Friteabc RE9] Spawn: registering spawn settings')
        characters:call('registerSpawnData(app.CharacterSpawnData)',data)
        if not pcall(function() assert(context:get_field('<SpawnData>k__BackingField')) end) then
            pcall(function() context:set_field('<SpawnData>k__BackingField',data) end)
        end
        assert(spawnDataOf(context),'The game did not accept the spawn settings')
    end
    local model,modelFrom=context:get_field('_MontageID'),'own'
    local visible=visibleModel(entry.kind)
    if visible and visible~=context then
        local okModel,value=pcall(function() return visible:get_field('_MontageID') end)
        if okModel and value then model,modelFrom=value,'visible '..entry.kind end
    end
    M.ownCall=true
    local ok,why=pcall(function()
        characters:call(SIGNATURE,context:get_field('<ID>k__BackingField'),context:get_field('<KindID>k__BackingField'),
            model,params.int,params.bool,params.flag)
    end)
    M.ownCall=false
    assert(ok,'Spawn refused: '..tostring(why))
    M.pending[#M.pending+1]={context=context,deadline=os.clock()+10,index=#M.pending,kind=entry.kind,model=model,modelFrom=modelFrom}
    log.info('[Friteabc RE9] Spawn model: '..modelFrom..' '..text(model))
    M.status='Spawning '..entry.name..(params.default and ' (default parameters)...' or '...')
    log.info('[Friteabc RE9] Spawn requested: '..entry.name..' int='..tostring(params.int)..' bool='..tostring(params.bool)..' flag='..tostring(params.flag))
end
local function place(context,x,y,z)
    local ok,why=pcall(Teleport.Warp,context,x,y,z,false)
    if ok then return true end
    local ok2,why2=pcall(function()
        local transform=context:get_field('<Transform>k__BackingField')
        if not transform then transform=context:call('get_GameObject'):call('get_Transform') end
        transform:call('set_Position',Vector3f.new(x,y,z))
    end)
    if ok2 then return true end
    return false,tostring(why)..' / '..tostring(why2)
end
local function inWorld(context)
    local ok,transform=pcall(function() return context:get_field('<Transform>k__BackingField') end)
    return ok and transform~=nil
end
function M.Tick(player)
    if #M.pending==0 or not player then return end
    local keep={}
    local now=os.clock()
    for _,job in ipairs(M.pending) do
        local okSpawn,spawned=pcall(function() return job.context:call('get_IsSpawn') end)
        if not job.target then
            if okSpawn and spawned and inWorld(job.context) then
                local x,y,z=near(player,job.index)
                job.target={x=x,y=y,z=z};job.until_=now+2;job.next=0
                log.info('[Friteabc RE9] Spawn performed by the game')
            elseif now>job.deadline then
                M.status='Not spawned: no spawn data for this enemy'
                log.info('[Friteabc RE9] Spawn not performed by the game')
                job.done=true
            end
        end
        if job.target and not job.visualChecked and now>=job.until_-1 then
            job.visualChecked=true
            local count,fixed=showBody(job.context)
            local report={kind=job.kind,meshes=count,fixed=fixed,montage=text(job.context:get_field('_MontageID')),modelFrom=job.modelFrom}
            if count==0 and job.model then
                local ok,why=pcall(function()
                    manager():call('requestInstantiateMontage(via.GameObject, app.CharacterKindID, app.MontageID, System.Action`1<app.MontageManager.Results>, System.Boolean, System.Int32, System.Boolean)',
                        objectOf(job.context),job.context:get_field('<KindID>k__BackingField'),job.model,nil,false,0,false)
                end)
                report.instantiate=ok and 'requested' or tostring(why)
                log.info('[Friteabc RE9] Spawn: no body found, model load '..report.instantiate)
            end
            M.visualReports=M.visualReports or {}
            table.insert(M.visualReports,1,report)
            while #M.visualReports>5 do table.remove(M.visualReports) end
            pcall(json.dump_file,'friteabc_re9_spawn_visual.json',M.visualReports)
            log.info('[Friteabc RE9] Spawn body check: '..tostring(job.kind)..' meshes='..count..' fixed='..fixed..' montage='..tostring(report.montage))
            M.status=count>0 and 'Spawned near you' or 'Spawned, but the game did not load its body (details saved)'
        end
        if job.target and now>=job.next then
            job.next=now+0.25
            local ok,why=place(job.context,job.target.x,job.target.y,job.target.z)
            if ok then M.status='Spawned near you'
            elseif not job.logged then job.logged=true;M.status='Spawned, but could not move it: '..tostring(why);log.error('[Friteabc RE9] Enemy placement: '..tostring(why)) end
            if now>=job.until_ then job.done=true end
        end
        if not job.done then keep[#keep+1]=job end
    end
    M.pending=keep
end
function M.BringAll(player)
    assert(player,'No playable character')
    local moved=0
    for i,context in ipairs(contexts('get_EnemyContextList')) do
        local okSpawn,spawned=pcall(function() return context:call('get_IsSpawn') end)
        if okSpawn and spawned then
            local x,y,z=near(player,i)
            local ok,why=place(context,x,y,z)
            if ok then moved=moved+1 else log.error('[Friteabc RE9] Enemy placement: '..tostring(why)) end
        end
    end
    M.status=moved..' enemies brought to you'
end
M.freeze=false;M.esp=false;M.undetected=false;M.radius=30;M.overlay={}
local frozen={}
local function spawnedEnemies()
    local out={}
    for _,context in ipairs(contexts('get_EnemyContextList')) do
        local okSpawn,spawned=pcall(function() return context:call('get_IsSpawn') end)
        if okSpawn and spawned and inWorld(context) then out[#out+1]=context end
    end
    return out
end
local function positionOf(context)
    local transform=context:get_field('<Transform>k__BackingField')
    return transform:call('get_Position')
end
local function health(context)
    local hp=context:call('get_HitPoint')
    if not hp then return nil end
    return hp:call('get_CurrentHitPoint'),hp:call('get_CurrentMaximumHitPoint'),hp
end
local function alive(context)
    local ok,dead=pcall(function() return context:call('get_IsDead') end)
    if ok and dead==true then return false end
    local okHp,current=pcall(health,context)
    return not (okHp and type(current)=='number' and current<=0)
end
function M.KillNearby(player)
    assert(player,'No playable character')
    local p=player:call('get_Transform'):call('get_Position')
    local killed,failed=0,0
    for _,context in ipairs(spawnedEnemies()) do
        local okPos,q=pcall(positionOf,context)
        if okPos and q and alive(context) then
            local dx,dy,dz=q.x-p.x,q.y-p.y,q.z-p.z
            if math.sqrt(dx*dx+dy*dy+dz*dz)<=M.radius then
                local ok=pcall(function() context:call('forceDead') end)
                if not ok then
                    ok=pcall(function() local _,_,hp=health(context);hp:call('set_CurrentHitPoint',0) end)
                end
                if ok then killed=killed+1 else failed=failed+1 end
            end
        end
    end
    M.status=killed..' enemies killed within '..math.floor(M.radius)..' m'..(failed>0 and (' ('..failed..' refused)') or '')
end
local function motionOf(context)
    return context:call('get_Updater'):call('get_Motion')
end
local function unfreezeAll()
    for _,entry in pairs(frozen) do pcall(function() entry.motion:call('set_PlaySpeed',entry.speed) end) end
    frozen={}
end
local nextFreezeScan=0
local function keepFrozen()
    for _,entry in pairs(frozen) do
        pcall(function() if entry.motion:call('get_PlaySpeed')~=0 then entry.motion:call('set_PlaySpeed',0.0) end end)
    end
    if os.clock()<nextFreezeScan then return end
    nextFreezeScan=os.clock()+0.5
    for _,context in ipairs(spawnedEnemies()) do
        pcall(function()
            local key=context:get_address()
            local entry=frozen[key]
            if not entry then
                local motion=motionOf(context)
                local speed=motion:call('get_PlaySpeed')
                entry={motion=motion,speed=type(speed)=='number' and speed>0 and speed or 1.0}
                frozen[key]=entry
            end
            if entry.motion:call('get_PlaySpeed')~=0 then entry.motion:call('set_PlaySpeed',0.0) end
        end)
    end
end
function M.SetFreeze(value)
    M.freeze=value==true
    if not M.freeze then unfreezeAll() else nextFreezeScan=0 end
end
local STEALTH={'Untargetable','Invisible','IgnoreTarget','NoTarget','Stealth','Hidden','IgnoreFind','DisableFind','NotFind'}
local stealthSetters,stealthBackup=nil,{}
local function findStealth(player)
    local found={}
    local function scan(object,label)
        if not object then return end
        local class=object:get_type_definition()
        while class do
            for _,method in ipairs(class:get_methods()) do
                local name=method:get_name()
                if name:sub(1,4)=='set_' and method:get_num_params()==1 then
                    local okType,param=pcall(function() return method:get_param_types()[1]:get_full_name() end)
                    if okType and param=='System.Boolean' then
                        for _,word in ipairs(STEALTH) do
                            if name:find(word) then found[#found+1]={object=object,name=name:sub(5),label=label..'.'..name:sub(5)};break end
                        end
                    end
                end
            end
            class=class:get_parent_type()
        end
    end
    scan(player,'Player')
    pcall(function() scan(player:call('get_Updater'),'Updater') end)
    pcall(function() scan(player:call('get_Common'),'Common') end)
    return found
end
function M.SetUndetected(player,value)
    if value then
        assert(player,'No playable character')
        stealthSetters=findStealth(player)
        local names={}
        for _,entry in ipairs(stealthSetters) do
            local ok,was=pcall(function() return entry.object:call('get_'..entry.name) end)
            if ok and type(was)=='boolean' then
                stealthBackup[#stealthBackup+1]={object=entry.object,name=entry.name,was=was}
                pcall(function() entry.object:call('set_'..entry.name,true) end)
                names[#names+1]=entry.label
            end
        end
        log.info('[Friteabc RE9] Undetected switches: '..(#names>0 and table.concat(names,', ') or 'none found'))
        M.undetected=#names>0
        M.stealthStatus=#names>0 and ('Using: '..table.concat(names,', ')) or 'Not available in this game. Use Freeze enemies.'
    else
        for _,entry in ipairs(stealthBackup) do pcall(function() entry.object:call('set_'..entry.name,entry.was) end) end
        stealthBackup={};M.undetected=false;M.stealthStatus=nil
    end
end
local function keepUndetected()
    for _,entry in ipairs(stealthBackup) do
        pcall(function() if entry.object:call('get_'..entry.name)~=true then entry.object:call('set_'..entry.name,true) end end)
    end
end
local nextOverlay=0
local function gatherOverlay(player)
    local p=player:call('get_Transform'):call('get_Position')
    local rows={}
    for _,context in ipairs(spawnedEnemies()) do
        pcall(function()
            if not alive(context) then return end
            local q=positionOf(context)
            local current,maximum=health(context)
            local dx,dy,dz=q.x-p.x,q.y-p.y,q.z-p.z
            local kind='?'
            pcall(function() kind=text(context:get_field('<KindID>k__BackingField')) end)
            rows[#rows+1]={x=q.x,y=q.y,z=q.z,hp=current,max=maximum,dist=math.sqrt(dx*dx+dy*dy+dz*dz),kind=kind}
        end)
    end
    M.overlay=rows
end
function M.Update(player)
    if not player then return end
    if M.freeze then keepFrozen() end
    if M.undetected and os.clock()>=(M.nextStealth or 0) then M.nextStealth=os.clock()+0.25;keepUndetected() end
    if (M.esp or M.gather) and os.clock()>=nextOverlay then
        nextOverlay=os.clock()+0.1
        pcall(gatherOverlay,player)
    elseif not (M.esp or M.gather) then M.overlay={} end
end
function M.Draw()
    if not M.esp or not draw then return end
    for _,row in ipairs(M.overlay) do
        local screen=draw.world_to_screen(Vector3f.new(row.x,row.y+2.0,row.z))
        if screen then
            local label=row.kind..'  '..math.floor(row.dist+0.5)..' m'
            draw.text(label,screen.x-30,screen.y-16,0xFFE0E4E6)
            if type(row.hp)=='number' and type(row.max)=='number' and row.max>0 then
                local ratio=math.max(0,math.min(1,row.hp/row.max))
                draw.filled_rect(screen.x-30,screen.y,60,5,0xC0000000)
                draw.filled_rect(screen.x-30,screen.y,60*ratio,5,ratio>0.5 and 0xFF5FB86A or (ratio>0.25 and 0xFF3FB0E0 or 0xFF3A41C2))
                draw.text(math.floor(row.hp)..' / '..math.floor(row.max),screen.x-30,screen.y+7,0xFFB0B4B8)
            end
        end
    end
end
function M.Release()
    pcall(M.ReleaseScale)
    unfreezeAll()
    if #stealthBackup>0 then M.SetUndetected(nil,false) end
    M.overlay={}
end
M.scale=1.0
local scaled={}
local nextScale=0
function M.TickScale()
    if M.scale==1 and next(scaled)==nil then return end
    if os.clock()<nextScale then return end
    nextScale=os.clock()+0.5
    for _,context in ipairs(spawnedEnemies()) do
        pcall(function()
            local transform=context:get_field('<Transform>k__BackingField')
            local key=transform:get_address()
            if not scaled[key] then
                local s=transform:call('get_LocalScale')
                scaled[key]={transform=transform,x=s.x,y=s.y,z=s.z}
            end
            local e=scaled[key]
            transform:call('set_LocalScale',Vector3f.new(e.x*M.scale,e.y*M.scale,e.z*M.scale))
            if M.scale==1 then scaled[key]=nil end
        end)
    end
end
function M.ReleaseScale()
    for _,e in pairs(scaled) do pcall(function() e.transform:call('set_LocalScale',Vector3f.new(e.x,e.y,e.z)) end) end
    scaled={};M.scale=1.0
end
return M
