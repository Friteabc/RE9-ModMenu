local M={items=false,panel=false,filter=1,filters={'All','Weapons','Ammo','Healing','Other'},rows={},status=nil,count=0}
local cores={}
local nextScan,nextUpdate=0,0
local fieldCache={}
local names
local function scene()
    return sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
end
local function text(value)
    local ok,result=pcall(function() return value:call('ToString()') end)
    return ok and type(result)=='string' and result or nil
end
local function idFields(definition)
    local key=definition:get_full_name()
    if fieldCache[key] then return fieldCache[key] end
    local found={}
    local class=definition
    while class do
        for _,field in ipairs(class:get_fields()) do
            if not field:is_static() then
                local okType,typeName=pcall(function() return field:get_type():get_full_name() end)
                if okType and (typeName=='app.ItemID' or typeName=='app.ItemAmountData' or typeName=='app.ItemContext') then found[#found+1]={name=field:get_name(),kind=typeName} end
            end
        end
        class=class:get_parent_type()
    end
    fieldCache[key]=found
    return found
end
local function itemCode(core)
    for _,getter in ipairs({'get_ItemID','get_ItemId'}) do
        local ok,value=pcall(function() return core:call(getter) end)
        if ok and value then local t=text(value);if t then return t end end
    end
    for _,field in ipairs(idFields(core:get_type_definition())) do
        local ok,value=pcall(function() return core:get_field(field.name) end)
        if ok and value then
            if field.kind=='app.ItemID' then local t=text(value);if t then return t end
            else
                local okInner,inner=pcall(function() return value:call('get_ItemID') end)
                if okInner and inner then local t=text(inner);if t then return t end end
            end
        end
    end
end
function M.SetNames(items)
    names={}
    for _,item in ipairs(items or {}) do names[item.code]=item end
end
local function wanted(category)
    local f=M.filters[M.filter] or 'All'
    if f=='All' then return true end
    if f=='Weapons' then return category=='Weapon' or category=='SubWeapon' or category=='Attachment' end
    if f=='Ammo' then return category=='Ammo' end
    if f=='Healing' then return category=='Heal' end
    return not (category=='Weapon' or category=='SubWeapon' or category=='Attachment' or category=='Ammo' or category=='Heal')
end
local function rescan()
    local list=scene():call('findComponents(System.Type)',sdk.typeof('app.ItemCore'))
    cores={}
    if list then for _,core in ipairs(list:get_elements()) do cores[#cores+1]=core end end
    M.count=#cores
end
function M.Update(player)
    if not (M.items or M.panel) or not player then M.rows={};return end
    local now=os.clock()
    if now>=nextScan then
        nextScan=now+1.0
        local ok,why=pcall(rescan)
        M.status=not ok and ('Items: '..tostring(why)) or nil
    end
    if now<nextUpdate then return end
    nextUpdate=now+0.2
    local p=player:call('get_Transform'):call('get_Position')
    local rows={}
    for _,core in ipairs(cores) do
        pcall(function()
            local object=core:call('get_GameObject')
            if not object or object:call('get_DrawSelf')==false then return end
            local q=object:call('get_Transform'):call('get_Position')
            local code=itemCode(core) or '?'
            local info=names and names[code]
            local category=info and info.category or 'Other'
            if not wanted(category) then return end
            local dx,dy,dz=q.x-p.x,q.y-p.y,q.z-p.z
            rows[#rows+1]={x=q.x,y=q.y,z=q.z,name=info and info.name or code,category=category,dist=math.sqrt(dx*dx+dy*dy+dz*dz)}
        end)
    end
    table.sort(rows,function(a,b) return a.dist<b.dist end)
    M.rows=rows
end
local COLORS={Weapon=0xFF4FA8F0,SubWeapon=0xFF4FA8F0,Attachment=0xFF4FA8F0,Ammo=0xFF5AC8E8,Heal=0xFF6FD08A}
function M.Draw(enemies)
    if not draw then return end
    if M.items then
        for index,row in ipairs(M.rows) do
            if index>60 then break end
            local screen=draw.world_to_screen(Vector3f.new(row.x,row.y+0.3,row.z))
            if screen then
                local color=COLORS[row.category] or 0xFFD8D8D8
                draw.filled_rect(screen.x-3,screen.y-3,6,6,color)
                draw.text(row.name..'  '..math.floor(row.dist+0.5)..' m',screen.x+6,screen.y-7,color)
            end
        end
    end
    if not M.panel then return end
    local x,y,w=24,220,250
    local lines={}
    for _,line in ipairs(M.extra or {}) do lines[#lines+1]={line,0xFFB0B4B8} end
    if M.extra then lines[#lines+1]={' ',0} end
    local list=enemies or {}
    lines[#lines+1]={'ENEMIES  '..#list,0xFF99908D}
    local sorted={}
    for _,row in ipairs(list) do sorted[#sorted+1]=row end
    table.sort(sorted,function(a,b) return a.dist<b.dist end)
    for index,row in ipairs(sorted) do
        if index>8 then break end
        local hp=(type(row.hp)=='number' and type(row.max)=='number') and (math.floor(row.hp)..' / '..math.floor(row.max)) or '?'
        lines[#lines+1]={string.format('%-10s %4d m   %s',row.kind,math.floor(row.dist+0.5),hp),0xFFE0E4E6}
    end
    lines[#lines+1]={' ',0}
    lines[#lines+1]={'ITEMS  '..#M.rows,0xFF99908D}
    for index,row in ipairs(M.rows) do
        if index>10 then break end
        lines[#lines+1]={string.format('%4d m   %s',math.floor(row.dist+0.5),row.name),COLORS[row.category] or 0xFFE0E4E6}
    end
    draw.filled_rect(x-10,y-10,w,#lines*16+16,0xB0141210)
    for index,line in ipairs(lines) do
        if line[2]~=0 then draw.text(line[1],x,y+(index-1)*16,line[2]) end
    end
end
function M.Release() M.rows={};cores={} end
return M
