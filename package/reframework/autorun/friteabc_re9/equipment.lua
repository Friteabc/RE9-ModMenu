local M={infinite=false,weapons={},page=1,status=nil,scanning=false}
local manager,original,hooked,scan,queue
local catalogRequested=false
local checks={}
local retained={}
local function retain(object)
    if not object then return nil end
    local key=object:get_address()
    if not retained[key] then object:add_ref();retained[key]=object end
    return object
end
local infinityFields={'_InfinityGun','_InfinityRocketLauncher'}
local function static(typeName,name)
    local definition=sdk.find_type_definition(typeName)
    assert(definition,'Unavailable: '..typeName)
    for _,field in ipairs(definition:get_fields()) do
        if field:is_static() and field:get_name()==name then return retain(field:get_data(nil)) end
    end
    error('Unavailable: '..typeName..'.'..name)
end
local function itemManager()
    return assert(sdk.get_managed_singleton('app.ItemManager'),'Item manager unavailable')
end
local function restore()
    if manager and original then for name,value in pairs(original) do pcall(function() manager:set_field(name,value) end) end end
    manager,original=nil,nil
end
local function applyInfinity()
    if M.infinite and manager then
        for _,name in ipairs(infinityFields) do manager:set_field(name,true) end
    end
end
function M.SetInfinite(value)
    if not value then M.infinite=false;restore();return end
    local current=itemManager()
    if not manager or manager:get_address()~=current:get_address() then
        restore()
        local snapshot={}
        for _,name in ipairs(infinityFields) do
            local actual=current:get_field(name)
            assert(type(actual)=='boolean','Unsupported infinite ammunition setting: '..name)
            snapshot[name]=actual
        end
        manager,original=current,snapshot
    end
    if not hooked then
        local method=current:get_type_definition():get_method('updateInfiniteness')
        assert(method,'Infinite ammunition update unavailable')
        sdk.hook(method,function() return sdk.PreHookResult.CALL_ORIGINAL end,function(value)
            applyInfinity()
            return value
        end)
        hooked=true
    end
    M.infinite=true;applyInfinity()
end
M.noReload=false
local consumeHooked=false
function M.SetNoReload(value)
    if value and not consumeHooked then
        local definition=sdk.find_type_definition('app.PlayerEquipment')
        assert(definition,'Player equipment unavailable')
        local signatures,installed={},0
        local class=definition
        while class do
            for _,method in ipairs(class:get_methods()) do
                if method:get_name()=='consumeLoading' then
                    local params={}
                    pcall(function() for _,param in ipairs(method:get_param_types()) do params[#params+1]=param:get_full_name() end end)
                    local ret=method:get_return_type():get_full_name()
                    signatures[#signatures+1]='consumeLoading('..table.concat(params,', ')..') -> '..ret
                    if ret=='System.Void' then
                        sdk.hook(method,function()
                            if M.noReload then
                                if not M.noReloadSeen then M.noReloadSeen=true;log.info('[Friteabc RE9] No reload: magazine kept full') end
                                return sdk.PreHookResult.SKIP_ORIGINAL
                            end
                            return sdk.PreHookResult.CALL_ORIGINAL
                        end,function(result) return result end)
                        installed=installed+1
                    end
                end
            end
            class=class:get_parent_type()
        end
        local inventoryType=sdk.find_type_definition('app.Inventory')
        if inventoryType then
            for _,method in ipairs(inventoryType:get_methods()) do
                if method:get_name()=='consumeLoading' and method:get_num_params()==3 and method:get_return_type():get_full_name()=='System.Boolean' then
                    sdk.hook(method,function(args)
                        local skip=M.noReload and M.handAddress~=nil and sdk.to_int64(args[2])==M.handAddress
                        thread.get_hook_storage().keepLoaded=skip
                        if skip then
                            if not M.inventoryReloadSeen then M.inventoryReloadSeen=true;log.info('[Friteabc RE9] No reload: special weapon magazine kept full') end
                            return sdk.PreHookResult.SKIP_ORIGINAL
                        end
                        return sdk.PreHookResult.CALL_ORIGINAL
                    end,function(result)
                        if thread.get_hook_storage().keepLoaded then return sdk.to_ptr(1) end
                        return result
                    end)
                    signatures[#signatures+1]='Inventory.consumeLoading(PanelKey, Int32, ItemID)'
                end
            end
        end
        log.info('[Friteabc RE9] Ammo consumption methods: '..table.concat(signatures,' | '))
        assert(installed>0,'Unsupported ammo consumption: '..table.concat(signatures,' | '))
        consumeHooked=true
    end
    M.noReload=value==true
end
function M.Reset()
    M.infinite=false;M.noReload=false;restore();queue=nil;scan=nil;checks={};M.weapons={};M.scanning=false;catalogRequested=false
    retained={}
end
M.items={};M.categories={'All'}
local HIDDEN={Flag=true,Procedure=true}
local function categoryNames()
    local names={}
    for _,field in ipairs(sdk.find_type_definition('app.ItemCategory'):get_fields()) do
        if field:is_static() then
            local ok,isCategory=pcall(function() return field:get_type():get_full_name()=='app.ItemCategory' end)
            if ok and isCategory then
                local value=retain(field:get_data(nil))
                if value then names[value:get_address()]=field:get_name() end
            end
        end
    end
    return names
end
function M.Refresh()
    local catalog=itemManager():get_field('_ItemCatalog')
    assert(catalog,'Item catalogue unavailable')
    local ids={}
    for _,field in ipairs(sdk.find_type_definition('app.ItemID'):get_fields()) do
        if field:is_static() and field:get_type():get_full_name()=='app.ItemID' then
            local id=retain(field:get_data(nil))
            if id then ids[#ids+1]={id=id,code=field:get_name()} end
        end
    end
    scan={ids=ids,index=1,items={},catalog=catalog,names=categoryNames()}
    M.scanning=true;catalogRequested=true
    M.status='Loading items...'
end
function M.EnsureCatalog()
    if not catalogRequested then M.Refresh() end
end
local function scanBatch()
    local s=scan
    if not s then return end
    for _=1,16 do
        local entry=s.ids[s.index]
        if not entry then
            table.sort(s.items,function(a,b) if a.name==b.name then return a.code<b.code end;return a.name<b.name end)
            local weapons,seen,categories={},{},{'All'}
            for _,item in ipairs(s.items) do
                if item.weapon then weapons[#weapons+1]=item end
                if not seen[item.category] then seen[item.category]=true;categories[#categories+1]=item.category end
            end
            table.sort(categories,function(a,b) if a=='All' then return true end if b=='All' then return false end return a<b end)
            M.items=s.items;M.weapons=weapons;M.categories=categories;M.page=1;M.itemPage=1
            M.status=tostring(#weapons)..' weapons, '..tostring(#s.items)..' items';scan=nil;M.scanning=false
            return
        end
        s.index=s.index+1
        local detail=s.catalog:call('getValue(app.ItemID, app.ItemDetailData)',entry.id,nil)
        if detail then
            local category=detail:call('get_ItemCategory')
            local categoryName=category and s.names[category:get_address()] or 'Other'
            if not HIDDEN[categoryName] then
                local name=entry.code
                pcall(function()
                    local method=sdk.find_type_definition('via.gui.message'):get_method('get(System.Guid)')
                    local text=method:call(nil,detail:call('get_NameMessageId'))
                    if text and tostring(text)~='' then name=tostring(text) end
                end)
                s.items[#s.items+1]={id=entry.id,code=entry.code,name=name,category=categoryName,
                    weapon=categoryName=='Weapon' or categoryName=='SubWeapon'}
            end
        end
    end
end
M.itemCategory=1;M.itemFilter='';M.itemPage=1;M.quantity=10
function M.FilteredItems()
    local wanted=M.categories[M.itemCategory] or 'All'
    local needle=(M.itemFilter or ''):lower()
    local out={}
    for _,item in ipairs(M.items) do
        if (wanted=='All' or item.category==wanted) and (needle=='' or item.name:lower():find(needle,1,true) or item.code:lower():find(needle,1,true)) then
            out[#out+1]=item
        end
    end
    return out
end
local function inventory(player,kind)
    local owner=player:call('get_InventoryUserID')
    local inventories=assert(sdk.get_managed_singleton('app.InventoryManager'),'Inventory manager unavailable')
    return inventories:call('getInventory(app.InventoryUser, app.InventoryType)',owner,kind)
end
local memoryFile='friteabc_re9_weapons.json'
local memory={proven=false,unusable={}}
pcall(function()
    local saved=json.load_file(memoryFile)
    if type(saved)=='table' then
        memory.proven=saved.proven==true
        if type(saved.unusable)=='table' then memory.unusable=saved.unusable end
    end
end)
local function saveMemory() pcall(function() json.dump_file(memoryFile,memory) end) end
M.character='unknown'
local function characterKey(player)
    local ok,name=pcall(function() return player:call('get_Updater'):get_type_definition():get_full_name() end)
    return ok and type(name)=='string' and name or 'unknown'
end
local function unusable(entry)
    local list=memory.unusable[M.character]
    return list~=nil and list[entry.code]==true
end
function M.Visible()
    local shown={}
    for _,entry in ipairs(M.weapons) do if not unusable(entry) then shown[#shown+1]=entry end end
    return shown
end
function M.HiddenCount() return #M.weapons-#M.Visible() end
function M.ForgetUnusable()
    memory.unusable[M.character]=nil;saveMemory()
    M.status='Hidden weapons shown again'
end
local function giveItem(player,entry,count)
    local hand=assert(inventory(player,0),'Player inventory unavailable')
    local allowedOK,allowed=pcall(function() return hand:call('canContain(app.ItemID)',entry.id) end)
    if allowedOK and allowed==false then return 'unusable' end
    local event=static('app.ItemStockChangedEventType','Default')
    local amount=count
    while amount>0 and not hand:call('canMergeOrAdd(app.ItemID, System.Int32, System.Boolean)',entry.id,amount,false) do
        amount=amount>8 and math.floor(amount/2) or amount-1
    end
    if amount<=0 then return 'full' end
    local before=hand:call('countTotal(app.ItemID)',entry.id)
    retain(hand:call('mergeOrAdd(app.ItemID, System.Int32, System.Boolean, app.Inventory.AcquireItemOptions, app.ItemStockChangedEventType)',entry.id,amount,false,0,event))
    local after=hand:call('countTotal(app.ItemID)',entry.id)
    if after>before then M.lastAmount=after-before;return 'added' end
    return 'full'
end
local function give(player,entry)
    if entry.weapon==false then return giveItem(player,entry,entry.count or 1) end
    local hand=assert(inventory(player,0),'Player inventory unavailable')
    if hand:call('countTotal(app.ItemID)',entry.id)>0 then return 'owned' end
    local box=inventory(player,1)
    if box and box:call('countTotal(app.ItemID)',entry.id)>0 then return 'owned' end
    local allowedOK,allowed=pcall(function() return hand:call('canContain(app.ItemID)',entry.id) end)
    if allowedOK and allowed==false then return 'unusable' end
    local event=static('app.ItemStockChangedEventType','Default')
    log.info('[Friteabc RE9] Giving weapon '..entry.code)
    if hand:call('canMergeOrAdd(app.ItemID, System.Int32, System.Boolean)',entry.id,1,false) then
        local before=hand:call('countTotal(app.ItemID)',entry.id)
        local result=hand:call('mergeOrAdd(app.ItemID, System.Int32, System.Boolean, app.Inventory.AcquireItemOptions, app.ItemStockChangedEventType)',entry.id,1,false,0,event)
        retain(result)
        if hand:call('countTotal(app.ItemID)',entry.id)>before then
            log.info('[Friteabc RE9] Weapon added '..entry.code)
            return 'added'
        end
    end
    return 'full'
end
local function registered(player,entry)
    local ok,result=pcall(function()
        local equipment=player:call('get_Updater'):call('get_Equipment')
        local map=equipment:get_field('_AddWeaponKeyItemIDReverse')
        return map:call('ContainsKey',entry.id)
    end)
    if ok and type(result)=='boolean' then return result end
    return nil
end
local function takeBack(player,entry)
    local hand=inventory(player,0)
    local key=hand:call('findPanelKey(app.ItemID)',entry.id)
    local discard=static('app.ItemStockChangedEventType','Discard')
    return hand:call('removePanel(app.Inventory.PanelKey, app.ItemStockChangedEventType)',key,discard)==true
end
local function markUnusable(entry)
    memory.unusable[M.character]=memory.unusable[M.character] or {}
    memory.unusable[M.character][entry.code]=true
    saveMemory()
end
local function verify(player)
    local now=os.clock()
    for index=#checks,1,-1 do
        local check=checks[index]
        local state=nil
        if check.address==player:get_address() then state=registered(player,check.entry) end
        if state==true then
            if not memory.proven then memory.proven=true;saveMemory() end
            table.remove(checks,index)
        elseif state==nil then
            table.remove(checks,index)
        elseif now-check.time>4 then
            table.remove(checks,index)
            if memory.proven then
                local removed=pcall(takeBack,player,check.entry)
                markUnusable(check.entry)
                log.info('[Friteabc RE9] Weapon not usable by '..M.character..': '..check.entry.code..(removed and ' (removed)' or ''))
                M.status=check.entry.name..': cannot be equipped by this character'..(removed and ' (removed)' or '')
            else
                log.info('[Friteabc RE9] Weapon not registered yet: '..check.entry.code)
            end
        end
    end
end
local function deliver(player,items)
    assert(player,'No playable character')
    assert(not queue,'Weapon delivery in progress')
    queue={items=items,index=1,address=player:get_address(),added=0,stored=0,owned=0,full=0,unusable=0}
end
function M.Give(entry,player) deliver(player,{entry}) end
function M.GiveItem(entry,player,count)
    if entry.weapon then return M.Give(entry,player) end
    local copy={id=entry.id,code=entry.code,name=entry.name,category=entry.category,weapon=false,count=math.max(1,math.floor(count or 1))}
    deliver(player,{copy})
end
M.infiniteMoney=false;M.money=nil
local MONEY_TARGET=999999
local function moneyInventory(player)
    for _,kind in ipairs({0,1}) do
        local target=inventory(player,kind)
        if target then
            local ok,value=pcall(function() return target:call('get_Moneys') end)
            if ok and type(value)=='number' then return target,value end
        end
    end
    error('Money unavailable for this character')
end
local MONEY_MAX=9999999
local function writeMoney(target,value)
    value=math.max(0,math.min(MONEY_MAX,math.floor(value)))
    target:set_field('_Moneys',value)
    return target:get_field('_Moneys')
end
function M.AddMoney(player,amount)
    assert(player,'No playable character')
    local target,value=moneyInventory(player)
    local now=writeMoney(target,value+amount)
    M.money=now
    M.status='Money: '..tostring(now)..(now==value and ' (unchanged)' or '')
end
function M.MaxInventory(player)
    assert(player,'No playable character')
    local hand=assert(inventory(player,0),'Player inventory unavailable')
    local before=hand:call('get_Level')
    local levels=hand:get_field('_UnlockLevelParams')
    local top=levels and levels:get_size() or 0
    assert(top>0,'This inventory cannot be expanded')
    for level=top,0,-1 do
        local ok,done=pcall(function() return hand:call('setLevel(System.Int32)',level) end)
        if ok and done==true then break end
    end
    local after=hand:call('get_Level')
    M.status=after~=before and ('Inventory expanded: level '..tostring(before)..' -> '..tostring(after)) or ('Inventory already at its largest size (level '..tostring(after)..')')
end
local nextMoney=0
local function keepMoney(player)
    if not M.infiniteMoney or os.clock()<nextMoney then return end
    nextMoney=os.clock()+1
    local ok,target,value=pcall(moneyInventory,player)
    if not ok then M.infiniteMoney=false;M.status=tostring(target);return end
    M.money=value
    if value<MONEY_TARGET then M.money=writeMoney(target,MONEY_TARGET) end
end
function M.GiveAll(player)
    assert(#M.weapons>0,'Refresh the weapon list first')
    deliver(player,M.Visible())
end
function M.Tick(player)
    if not player then restore();queue=nil;checks={};return end
    M.character=characterKey(player)
    if M.noReload then
        local ok,hand=pcall(inventory,player,0)
        M.handAddress=ok and hand and hand:get_address() or nil
    end
    if M.infinite then M.SetInfinite(true) end
    scanBatch()
    keepMoney(player)
    if #checks>0 then verify(player) end
    local q=queue
    if not q then return end
    if q.address~=player:get_address() then queue=nil;M.status='Character changed; delivery stopped';return end
    local entry=q.items[q.index]
    if entry then
        local result=give(player,entry);q[result]=q[result]+1;q.index=q.index+1
        if result=='added' and entry.weapon~=false then checks[#checks+1]={entry=entry,time=os.clock(),address=q.address} end
        if result=='unusable' and entry.weapon~=false then markUnusable(entry) end
        M.status='Weapons: '..(q.index-1)..' / '..#q.items
    else
        M.status=string.format('Added %d | Owned %d | Other character %d | No space %d',q.added,q.owned,q.unusable,q.full)
        queue=nil
    end
end
function M.Fail(why)
    M.infinite=false;restore()
    queue=nil;scan=nil;M.scanning=false;M.status=tostring(why)
    log.error('[Friteabc RE9] Equipment: '..M.status)
end
return M
