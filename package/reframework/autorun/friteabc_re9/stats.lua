local M={distance=0,kills=0,start=os.clock(),status=nil}
local last
local states={}
local nextKills=0
function M.Reset() M.distance=0;M.kills=0;M.start=os.clock();last=nil;states={} end
function M.Tick(player,ignoreMove)
    if not player then last=nil;return end
    local ok,p=pcall(function() return player:call('get_Transform'):call('get_Position') end)
    if ok and p then
        if last and not ignoreMove then
            local dx,dz=p.x-last.x,p.z-last.z
            local step=math.sqrt(dx*dx+dz*dz)
            if step<8 then M.distance=M.distance+step end
        end
        last={x=p.x,z=p.z}
    end
    if os.clock()<nextKills then return end
    nextKills=os.clock()+0.5
    pcall(function()
        local list=sdk.get_managed_singleton('app.CharacterManager'):call('get_EnemyContextList'):call('ToArray'):get_elements()
        local seen={}
        for _,context in ipairs(list) do
            local key=context:get_address()
            seen[key]=true
            local spawned=context:call('get_IsSpawn')==true
            local dead=context:call('get_IsDead')==true
            if spawned and not dead then states[key]='alive'
            elseif dead and states[key]=='alive' then states[key]='dead';M.kills=M.kills+1 end
        end
        for key in pairs(states) do if not seen[key] then states[key]=nil end end
    end)
end
function M.Time()
    local t=math.floor(os.clock()-M.start)
    return string.format('%d:%02d:%02d',math.floor(t/3600),math.floor(t/60)%60,t%60)
end
function M.Lines()
    return {'Session '..M.Time(),'Kills '..M.kills,string.format('Distance %.0f m',M.distance)}
end
return M
