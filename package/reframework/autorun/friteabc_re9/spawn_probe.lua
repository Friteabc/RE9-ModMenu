local M={status=nil}
local NAMES={'app.EnemyManager','app.EnemySpawnManager','app.SpawnManager','app.CharacterSpawnManager','app.EnemyGenerateManager',
    'app.GenerateManager','app.CharacterGenerateManager','app.EnemyCharacterManager','app.SpawnController','app.EnemySpawnController',
    'app.CharacterSpawner','app.EnemySpawner','app.SpawnPointManager','app.PrefabManager','app.CharacterPrefabManager',
    'app.EnemyContext','app.EnemyUpdater','app.CharacterContext','app.SpawnRequest','app.EnemySpawnRequest','app.CharacterSpawnRequest'}
local KEYWORDS={'Spawn','spawn','Generate','generate','Enemy','enemy','Instantiate','instantiate','Prefab','Create','create','Request','request'}
local function signatures(definition)
    local out={}
    local class=definition
    while class do
        for _,method in ipairs(class:get_methods()) do
            local name=method:get_name()
            for _,word in ipairs(KEYWORDS) do
                if name:find(word,1,true) then
                    local params={}
                    pcall(function() for _,param in ipairs(method:get_param_types()) do params[#params+1]=param:get_full_name() end end)
                    out[#out+1]=(method:is_static() and 'static ' or '')..name..'('..table.concat(params,', ')..') -> '..method:get_return_type():get_full_name()
                    break
                end
            end
        end
        class=class:get_parent_type()
    end
    return out
end
function M.Run()
    local report={types={},characterManager={},enemies={}}
    for _,name in ipairs(NAMES) do
        pcall(function()
            local definition=sdk.find_type_definition(name)
            if not definition then return end
            local fields={}
            for _,field in ipairs(definition:get_fields()) do
                if not field:is_static() then fields[#fields+1]=field:get_name()..' : '..field:get_type():get_full_name() end
            end
            report.types[name]={singleton=sdk.get_managed_singleton(name)~=nil,methods=signatures(definition),fields=fields}
        end)
    end
    pcall(function()
        local manager=sdk.get_managed_singleton('app.CharacterManager')
        report.characterManager=signatures(manager:get_type_definition())
        for _,getter in ipairs({'get_EnemyContextList','get_EnemyList','get_CharacterContextList','get_ContextList'}) do
            pcall(function()
                local list=manager:call(getter)
                if not list then return end
                local items=list:call('ToArray'):get_elements()
                local rows={}
                for i=1,math.min(#items,40) do
                    local context=items[i]
                    local row={type=context:get_type_definition():get_full_name()}
                    pcall(function() row.kind=context:get_field('<KindID>k__BackingField'):call('ToString()') end)
                    pcall(function() row.name=context:call('get_GameObject'):call('get_Name') end)
                    rows[#rows+1]=row
                end
                report.enemies[getter]=rows
            end)
        end
    end)
    json.dump_file('friteabc_re9_spawn.json',report)
    local count=0
    for _ in pairs(report.types) do count=count+1 end
    M.status='Enemy system scanned ('..count..' types) - send the result to the developer'
    log.info('[Friteabc RE9] Spawn discovery saved')
end
return M
