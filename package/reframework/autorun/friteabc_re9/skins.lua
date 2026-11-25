local M={list={},filter='',page=1,status=nil,current=nil,loaded=false}
local backup
local function manager() return sdk.get_managed_singleton('app.CharacterManager') end
local function name(value)
    local ok,text=pcall(function() return value:call('ToString()') end)
    if ok and type(text)=='string' then return text end
    ok,text=pcall(function() return value:call('ToString') end)
    return ok and type(text)=='string' and text or '?'
end
local function fieldValue(object,names)
    for _,name in ipairs(names) do
        local ok,value=pcall(function() return object:get_field(name) end)
        if ok and value~=nil then return value end
    end
end
local function entriesOf(dict,depth,out)
    out=out or {}
    if not dict or depth<0 then return out end
    local entries=fieldValue(dict,{'_entries','entries'})
    if entries then
        pcall(function()
            for _,entry in ipairs(entries:get_elements()) do
                local key,value=fieldValue(entry,{'key','_key','Key'}),fieldValue(entry,{'value','_value','Value'})
                if key~=nil and value~=nil then out[#out+1]={key=key,value=value} end
            end
        end)
        if #out>0 then return out end
    end
    local tables=fieldValue(dict,{'_tables','m_tables'})
    if tables then
        pcall(function()
            local buckets=fieldValue(tables,{'_buckets','m_buckets'})
            for _,node in ipairs(buckets:get_elements()) do
                local current=node
                while current do
                    local key,value=fieldValue(current,{'_key','m_key','key'}),fieldValue(current,{'_value','m_value','value'})
                    if key~=nil and value~=nil then out[#out+1]={key=key,value=value} end
                    current=fieldValue(current,{'_next','m_next','next'})
                end
            end
        end)
        if #out>0 then return out end
    end
    pcall(function()
        for _,field in ipairs(dict:get_type_definition():get_fields()) do
            if not field:is_static() and field:get_type():get_full_name():find('Dictionary') then
                entriesOf(field:get_data(dict),depth-1,out)
            end
        end
    end)
    return out
end
local function montageOf(data,depth)
    depth=depth or 2
    local ok,definition=pcall(function() return data:get_type_definition() end)
    if not ok or not definition then return nil end
    if definition:get_full_name()=='app.MontageID' then return data end
    local class=definition
    while class do
        for _,field in ipairs(class:get_fields()) do
            if not field:is_static() and field:get_type():get_full_name()=='app.MontageID' then
                local okValue,value=pcall(field.get_data,field,data)
                if okValue and value then return value end
            end
        end
        class=class:get_parent_type()
    end
    if depth>0 then
        for _,field in ipairs(definition:get_fields()) do
            if not field:is_static() then
                local okValue,value=pcall(field.get_data,field,data)
                if okValue and (type(value)=='userdata' or type(value)=='table') then
                    local found=montageOf(value,depth-1)
                    if found then return found end
                end
            end
        end
    end
end
local function shape(object,depth)
    local ok,definition=pcall(function() return object:get_type_definition() end)
    if not ok or not definition then return tostring(object) end
    local out={type=definition:get_full_name(),fields={}}
    for _,field in ipairs(definition:get_fields()) do
        if not field:is_static() then
            local entry={type=field:get_type():get_full_name()}
            if depth>0 then pcall(function()
                local value=field:get_data(object)
                if type(value)=='userdata' then
                    local okItems,items=pcall(function() return value:get_elements() end)
                    if okItems and type(items)=='table' then
                        entry.items={}
                        for i=1,math.min(#items,12) do entry.items[i]=shape(items[i],depth-1) end
                    else entry.value=shape(value,depth-1) end
                else entry.value=value end
            end) end
            out.fields[field:get_name()]=entry
        end
    end
    return out
end
local function modelOf(id)
    local text=name(id)
    return tonumber(text:match('ModelID%s*(%d+)')),tonumber(text:match('PresetID%s*(%d+)'))
end
local function displayName(detail)
    if not detail then return nil end
    local found
    pcall(function()
        local class=detail:get_type_definition()
        while class and not found do
            for _,field in ipairs(class:get_fields()) do
                if not field:is_static() then
                    local typeName=field:get_type():get_full_name()
                    local lower=field:get_name():lower()
                    if typeName=='System.String' and (lower:find('name') or lower:find('title')) then
                        local value=field:get_data(detail)
                        if type(value)=='string' and value~='' then found=value;break end
                    elseif typeName=='System.Guid' and (lower:find('name') or lower:find('title')) then
                        local guid=field:get_data(detail)
                        local ok,text=pcall(function()
                            return sdk.call_native_func(nil,sdk.find_type_definition('via.gui.message'),'get(System.Guid)',guid)
                        end)
                        if not ok or type(text)~='string' then
                            ok,text=pcall(function() return sdk.find_type_definition('via.gui.message'):get_method('get(System.Guid)'):call(nil,guid) end)
                        end
                        if ok and type(text)=='string' and text~='' then found=text;break end
                    end
                end
            end
            class=class:get_parent_type()
        end
    end)
    return found
end
local function makeMontage(model,preset)
    local definition=sdk.find_type_definition('app.MontageID')
    assert(definition,'MontageID type unavailable')
    local value
    local ok=pcall(function()
        value=ValueType.new(definition)
        value:set_field('<ModelID>k__BackingField',model)
        value:set_field('<PresetID>k__BackingField',preset)
    end)
    if not ok then
        value=sdk.create_instance('app.MontageID')
        value:set_field('<ModelID>k__BackingField',model)
        value:set_field('<PresetID>k__BackingField',preset)
    end
    return value
end
local function bonusMontages(montages)
    local map={}
    for _,entry in ipairs(entriesOf(montages:get_field('BonusMontageDictionary'),3)) do
        pcall(function()
            local data=entry.value:get_field('_Value') or entry.value
            local bonusName=data:get_field('_BonusID')
            local model,preset=data:get_field('_ModelID'),data:get_field('_DefaultPresetID')
            if type(bonusName)=='string' and type(model)=='number' and type(preset)=='number' then
                map[bonusName]={model=model,preset=preset}
            end
        end)
    end
    return map
end
local OVERRIDE={ID000='Ch0100OverrideMontageID',ID001='Ch0200OverrideMontageID'}
function M.Load(player)
    local characters=manager()
    assert(characters,'Character manager unavailable')
    local montages=characters:call('get_MontageManager')
    assert(montages,'Montage manager unavailable')
    local bonus=sdk.get_managed_singleton('app.BonusManager')
    assert(bonus,'Bonus manager unavailable')
    local currentCostume
    for _,owner in ipairs({function() return player:call('get_Updater') end,function() return player end}) do
        if currentCostume then break end
        pcall(function()
            local setting=owner():call('get_CurrentCostumeSetting')
            local value=setting:get_field('_BonusIDName')
            if type(value)~='string' then value=setting:call('get_BonusIDName') end
            if type(value)=='string' then currentCostume=value end
        end)
    end
    local montageByBonus=bonusMontages(montages)
    local list,debug={},{configs={},montageKeys={},currentCostume=currentCostume}
    for key,value in pairs(montageByBonus) do debug.montageKeys[#debug.montageKeys+1]=key..' -> model '..value.model..' preset '..value.preset end
    pcall(function()
        local dict=montages:get_field('BonusMontageDictionary')
        debug.bonusDictionary=shape(dict,2)
        local inner=dict:get_field('_Dict')
        local entries=inner:get_field('_entries')
        debug.firstEntries={}
        for i=0,math.min(4,inner:get_field('_count')-1) do debug.firstEntries[#debug.firstEntries+1]=shape(entries:get_element(i),3) end
    end)
    local contexts=bonus:call('getSpecialConfigContexts')
    for _,context in ipairs(contexts:get_elements()) do
        local config=context:get_field('_ConfigID')
        local configName=name(config)
        local selected=context:get_field('_SelectedID')
        local items={}
        local listObject=context:get_field('_ItemDataList')
        local array=listObject:get_field('_items')
        for i=0,listObject:get_field('_size')-1 do
            local item=array:get_element(i)
            local bonusID=item:get_field('_BonusID')
            local idText=name(bonusID)
            local detail=item:get_field('_DetailData')
            items[#items+1]={id=idText,label=displayName(detail),unlocked=item:get_field('_Unlocked'),detail=detail and shape(detail,2) or nil}
            local isCostume=idText:find('^bo99_00_')~=nil or montageByBonus[idText]~=nil or idText==currentCostume
            items[#items].costume=isCostume
            items[#items].object={config=config,bonusID=bonusID,item=item,linkType=item:get_field('_LinkTypeID')}
        end
        local costumeConfig=false
        for _,it in ipairs(items) do if it.costume then costumeConfig=true end end
        local dumpItems={}
        for _,it in ipairs(items) do dumpItems[#dumpItems+1]={id=it.id,label=it.label,unlocked=it.unlocked,detail=it.detail} end
        debug.configs[#debug.configs+1]={config=configName,costume=costumeConfig,items=dumpItems}
        if costumeConfig then
            for _,it in ipairs(items) do
                pcall(function() it.object.config:add_ref();it.object.bonusID:add_ref();it.object.item:add_ref() end)
                pcall(function() it.object.linkType:add_ref() end)
                local available=montageByBonus[it.id]~=nil or it.id==currentCostume or it.unlocked
                local text=(it.label or it.id)..(available and '' or '  (unavailable)')..((available and not it.unlocked) and '  (locked)' or '')..(it.id==currentCostume and '  (current)' or '')
                pcall(function() selected:add_ref() end)
                local montage=montageByBonus[it.id]
                list[#list+1]={name=configName..'  '..text,config=it.object.config,bonusID=it.object.bonusID,bonusName=it.id,
                    configName=configName,originalSelected=selected,montage=montage,current=it.id==currentCostume,
                    item=it.object.item,linkType=it.object.linkType,unlocked=it.unlocked==true,available=available}
            end
        end
    end
    pcall(function() json.dump_file('friteabc_re9_skins_debug.json',debug) end)
    M.list=list;M.loaded=true;M.page=1
    M.status=#list..' costumes'..(currentCostume and '' or ' (current costume unknown)')
    log.info('[Friteabc RE9] Costumes loaded: '..#list..' current='..tostring(currentCostume))
end
function M.Filtered()
    local out={}
    local needle=M.filter:lower()
    for _,entry in ipairs(M.list) do
        if needle=='' or entry.name:lower():find(needle,1,true) then out[#out+1]=entry end
    end
    return out
end
local function kindOf(player)
    local ok,kind=pcall(function() return player:get_field('<KindID>k__BackingField') end)
    if ok and kind~=nil then return kind end
    return player:call('get_KindID')
end
function M.Apply(player,entry)
    assert(player,'No playable character')
    local characters=manager()
    assert(characters,'Character manager unavailable')
    local object=player:call('get_GameObject')
    local kind=kindOf(player)
    if not backup or backup.address~=player:get_address() then
        local montages=characters:call('get_MontageManager')
        backup={address=player:get_address(),gameObject=object,kind=kind,montages=montages,
            preset=montages and montages:call('GetMontagePresetBackup',object)}
        if backup.preset then pcall(function() backup.preset:add_ref() end) end
    end
    assert(entry.available,'No data for this outfit (DLC not installed)')
    assert(entry.unlocked,'Locked outfit')
    if entry.config and entry.bonusID then
        local bonus=sdk.get_managed_singleton('app.BonusManager')
        backup.selections=backup.selections or {}
        if not backup.selections[entry.configName] then
            backup.selections[entry.configName]={config=entry.config,selected=entry.originalSelected}
        end
        bonus:call('setConfigSelectedID',entry.config,entry.bonusID)
        log.info('[Friteabc RE9] Bonus costume selected: '..tostring(entry.bonusName))
    end
    M.pending=nil
    M.current=entry.name
    M.status=(entry.unlockedLabel==false and 'Selected (locked costume, may be ignored): ' or 'Selected - reload your save to wear it: ')..entry.name
end
function M.Tick()
    local job=M.pending
    if not job then return end
    local characters=manager()
    if not characters then return end
    local okReady,ready=pcall(function() return characters:call('isMontagePresetReady',job.kind,job.entry.id,false) end)
    if (okReady and ready) or os.clock()>job.deadline then
        M.pending=nil
        characters:call('requestPlayerMontageChange',job.entry.id,0)
        M.current=job.entry.name
        M.status=((okReady and ready) and 'Skin: ' or 'Skin (not confirmed loaded): ')..job.entry.name
        log.info('[Friteabc RE9] Skin requested: '..job.entry.name..' ready='..tostring(okReady and ready))
    end
end
function M.Restore(player)
    assert(backup,'No original skin saved')
    assert(player and player:get_address()==backup.address,'Original skin belongs to another character')
    local bonus=sdk.get_managed_singleton('app.BonusManager')
    for _,selection in pairs(backup.selections or {}) do
        pcall(function() bonus:call('setConfigSelectedID',selection.config,selection.selected) end)
    end
    backup.selections=nil
    for slot,old in pairs(backup.overrides or {}) do pcall(function() backup.montages:call('set_'..slot,old) end) end
    backup.overrides=nil
    if not backup.preset then M.current=nil;M.status='Original costume selection restored';return end
    backup.montages:call('requestMontageChange(via.GameObject, app.CharacterKindID, app.MontageManager.MontagePresetBackup, System.Action`1<app.MontageManager.Results>, System.Boolean, System.Boolean)',backup.gameObject,backup.kind,backup.preset,nil,false,false)
    M.current=nil;M.status='Original skin restored'
    log.info('[Friteabc RE9] Skin restored')
end
function M.HasBackup(player) return backup~=nil and player~=nil and backup.address==player:get_address() end
return M
