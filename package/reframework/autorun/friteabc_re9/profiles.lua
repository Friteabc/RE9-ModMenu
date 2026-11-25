local M={list={},selected=1,status=nil}
local config='friteabc_re9_profiles.json'
local data={}
local ok,saved=pcall(json.load_file,config)
if ok and type(saved)=='table' then data=saved end
local function refresh()
    local names={}
    for name in pairs(data) do names[#names+1]=name end
    table.sort(names)
    M.list=names
    M.selected=math.max(1,math.min(M.selected,#names))
end
refresh()
function M.Store(name,settings)
    assert(name and name~='','Give the profile a name')
    data[name]=settings
    pcall(json.dump_file,config,data)
    refresh()
    for i,n in ipairs(M.list) do if n==name then M.selected=i end end
    M.status='Profile saved: '..name
end
function M.Get(name) return data[name] end
function M.Remove(name)
    data[name]=nil
    pcall(json.dump_file,config,data)
    refresh()
    M.status='Profile deleted: '..tostring(name)
end
return M
