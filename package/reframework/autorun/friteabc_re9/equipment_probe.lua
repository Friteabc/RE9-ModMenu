local M={}
function M.Run(player)
    if not player then return end
    local output={types={},objects={}}
    local seen={}
    local function collect(definition,depth)
        if not definition then return end
        local name=definition:get_full_name()
        if seen[name] then return end
        seen[name]=true
        local row={name=name,fields={},methods={},values={}}
        output.types[#output.types+1]=row
        local children={}
        local class=definition
        while class and class:get_full_name()~='System.Object' do
            for _,field in ipairs(class:get_fields()) do
                local ft=field:get_type()
                row.fields[#row.fields+1]={name=field:get_name(),type=ft:get_full_name()}
                if field:is_static() then pcall(function()
                    local value=field:get_data(nil)
                    if type(value)=='number' or type(value)=='boolean' then row.values[field:get_name()]=value end
                end) end
                children[#children+1]=ft
            end
            for _,method in ipairs(class:get_methods()) do
                local params={}
                for _,param in ipairs(method:get_param_types()) do params[#params+1]=param:get_full_name();children[#children+1]=param end
                local returns=method:get_return_type()
                row.methods[#row.methods+1]={name=method:get_name(),params=params,returns=returns:get_full_name(),static=method:is_static()}
                children[#children+1]=returns
            end
            class=class:get_parent_type()
        end
        if depth>0 then for _,child in ipairs(children) do
            local n=child:get_full_name()
            if n:sub(1,4)=='app.' and not n:find('<',1,true) and not n:find('[]',1,true) then collect(child,depth-1) end
        end end
    end
    for _,name in ipairs({'app.InventoryManager','app.ItemManager','app.Inventory','app.ItemID','app.ItemCategory','app.ItemStockChangedEventType','app.ItemDetailData','app.Inventory.MergeOrAddResult','via.gui.message','app.PlayerFPSCameraController','app.CameraControllerRoot','app.PlayerInputMediator','app.WarpOption'}) do
        pcall(function() collect(sdk.find_type_definition(name),0) end)
        pcall(function()
            local object=sdk.get_managed_singleton(name)
            if object then output.objects[name]=object:get_type_definition():get_full_name() end
        end)
    end
    local itemManager=sdk.get_managed_singleton('app.ItemManager')
    if itemManager then for _,field in ipairs({'_ItemCatalog','_Item2WeaponCatalog'}) do
        pcall(function()
            local object=itemManager:get_field(field)
            if object then collect(object:get_type_definition(),0) end
        end)
    end end
    local updater=player:call('get_Updater')
    for _,name in ipairs({'InputDriver','InventoryBlackboardCore','EquipWeapon','FPSPlayerCamera','TPSPlayerCamera'}) do
        pcall(function()
            local object=updater:call('get_'..name)
            if object then output.objects[name]=object:get_type_definition():get_full_name();collect(object:get_type_definition(),1) end
        end)
    end
    json.dump_file('friteabc_re9_equipment.json',output)
    log.info('[Friteabc RE9] Equipment and camera bindings recorded')
end
return M
