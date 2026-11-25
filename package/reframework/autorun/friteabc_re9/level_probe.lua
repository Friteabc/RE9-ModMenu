local M={status=nil}
local MANAGERS={'app.SceneTransitionManager','app.ScenarioManager','app.ChapterManager','app.MainGameManager','app.GameManager',
    'app.SaveDataManager','app.SavedataManager','app.GameSaveManager','app.SaveManager','app.GameSlotSaveManager','app.SceneManager',
    'app.LevelManager','app.StageManager','app.AreaManager','app.MapManager','app.GameFlowManager','app.FlowManager','app.TitleManager'}
local function value(v)
    local kind=type(v)
    if kind=='number' or kind=='boolean' or kind=='string' then return v end
    if kind=='userdata' then
        local ok,text=pcall(function() return v:call('ToString()') end)
        if ok and type(text)=='string' then return text end
        local okType,name=pcall(function() return v:get_type_definition():get_full_name() end)
        return okType and ('<'..name..'>') or '<object>'
    end
    return nil
end
local function describe(instance,definition)
    local out={methods={},fields={},getters={}}
    local class=definition
    while class do
        for _,method in ipairs(class:get_methods()) do
            local params={}
            pcall(function() for _,param in ipairs(method:get_param_types()) do params[#params+1]=param:get_full_name() end end)
            out.methods[#out.methods+1]=(method:is_static() and 'static ' or '')..method:get_name()..'('..table.concat(params,', ')..') -> '..method:get_return_type():get_full_name()
            local ret=method:get_return_type()
            local simple=false
            pcall(function() simple=ret:is_value_type() or ret:get_full_name()=='System.String' end)
            if instance and simple and method:get_num_params()==0 and method:get_name():find('^get_') and not method:is_static() then
                pcall(function() out.getters[method:get_name()]=value(method:call(instance)) end)
            end
        end
        for _,field in ipairs(class:get_fields()) do
            if not field:is_static() then
                local entry=field:get_name()..' : '..field:get_type():get_full_name()
                if instance then pcall(function() local v=value(field:get_data(instance));if v~=nil then entry=entry..' = '..tostring(v) end end) end
                out.fields[#out.fields+1]=entry
            end
        end
        class=class:get_parent_type()
    end
    return out
end
function M.Run()
    local report={managers={},enums={}}
    for _,name in ipairs(MANAGERS) do
        pcall(function()
            local definition=sdk.find_type_definition(name)
            if not definition then return end
            local instance=sdk.get_managed_singleton(name)
            local info=describe(instance,definition)
            info.singleton=instance~=nil
            report.managers[name]=info
        end)
    end
    for _,name in ipairs({'app.NewgameSetupRequestArgs','app.SaveSlotCategory','app.SaveSlotCategoryBits','app.SceneFolderController'}) do
        pcall(function()
            local definition=sdk.find_type_definition(name)
            if definition then report.managers[name]=describe(nil,definition) end
        end)
    end
    pcall(function()
        local manager=sdk.get_managed_singleton('app.SceneTransitionManager')
        local roots={}
        local dict=manager:get_field('RootScenes')
        local entries=dict:get_field('_entries')
        for i=0,dict:get_field('_count')-1 do
            local entry=entries:get_element(i)
            roots[#roots+1]=value(entry:get_field('key'))
        end
        report.rootScenes=roots
    end)
    for _,name in ipairs({'app.ChapterID','app.ScenarioID','app.SceneID','app.MainGameJumpType','app.SceneTransitionType','app.GameSlotType','app.SaveSlotCategory','app.SaveSlotCategoryBits'}) do
        pcall(function()
            local definition=sdk.find_type_definition(name)
            if not definition then return end
            local values={}
            for _,field in ipairs(definition:get_fields()) do
                if field:is_static() then pcall(function() values[field:get_name()]=value(field:get_data(nil)) end) end
            end
            report.enums[name]=values
        end)
    end
    local KEY={'Chapter','Scenario','Progress','Story','Flag','CheckPoint','Checkpoint','Flow','Stage','Area','Level','Section','Timeline','Event','Mission','Episode','Jump','Warp','Location','Room','GameData','Save','Slot','Typewriter','Inkribbon'}
    pcall(function()
        local scene=sdk.call_native_func(sdk.get_native_singleton('via.SceneManager'),sdk.find_type_definition('via.SceneManager'),'get_CurrentScene')
        local list=scene:call('findComponents(System.Type)',sdk.typeof('via.Behavior'))
        local seen,all,matched={},{},{}
        for _,component in ipairs(list:get_elements()) do
            local ok,definition=pcall(function() return component:get_type_definition() end)
            if ok and definition then
                local name=definition:get_full_name()
                if not seen[name] then
                    seen[name]=true
                    all[#all+1]=name
                    for _,word in ipairs(KEY) do
                        if name:find(word) and not name:find('^via%.') then
                            local okInfo,info=pcall(describe,component,definition)
                            if okInfo then
                                local okObject,objectName=pcall(function() return component:call('get_GameObject'):call('get_Name') end)
                                info.gameObject=okObject and objectName or nil
                                matched[name]=info
                            end
                            break
                        end
                    end
                end
            end
        end
        table.sort(all)
        report.sceneComponents=all
        report.progressComponents=matched
    end)
    for _,name in ipairs({'app.GameDataManager','app.EnvStageManager','app.CheckPointManager','app.CheckpointManager','app.ProgressManager',
        'app.GameProgressManager','app.StoryManager','app.FlagManager','app.EventFlagManager','app.ScenarioFlagManager','app.TimelineEventManager',
        'app.MainGameFlowManager','app.GameFlowController','app.RoomManager','app.LocationManager','app.ChapterSelectManager','app.SaveServiceManager','app.SaveServiceManagerApp','app.SaveDataManager','app.GameSlotSaveManager','app.SaveManager','app.GameSaveManager','app.GuiManager','app.GUIManager','app.GuiSaveLoadManager','app.SaveLoadManager'}) do
        pcall(function()
            if report.managers[name] then return end
            local definition=sdk.find_type_definition(name)
            if not definition then return end
            local instance=sdk.get_managed_singleton(name)
            local info=describe(instance,definition)
            info.singleton=instance~=nil
            report.managers[name]=info
        end)
    end
    json.dump_file('friteabc_re9_levels.json',report)
    local count=0
    for _ in pairs(report.managers) do count=count+1 end
    local found=0
    for _ in pairs(report.progressComponents or {}) do found=found+1 end
    M.status='Scanned: '..count..' managers, '..#(report.sceneComponents or {})..' component types, '..found..' progress related'
    log.info('[Friteabc RE9] Level discovery saved')
end
return M
