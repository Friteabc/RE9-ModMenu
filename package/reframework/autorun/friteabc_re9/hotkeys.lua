local M={binds={},waiting=nil,status=nil}
local config='friteabc_re9_hotkeys.json'
M.actions={
    {id='god',label='God mode',key=0x74},
    {id='noclip',label='Noclip',key=0x75},
    {id='freecam',label='Free camera',key=0x76},
    {id='oneshot',label='One-shot kills',key=0x77},
    {id='reload',label='Reload last save',key=0x78},
    {id='save',label='Typewriter: go / back',key=0x79},
    {id='fly',label='Fly',key=0},
    {id='hud',label='Hide game interface',key=0},
    {id='freeze',label='Freeze enemies',key=0},
    {id='kill',label='Kill enemies nearby',key=0},
    {id='nuke',label='Nuclear explosion',key=0},
}
local NAMES={[0x05]='Mouse 4',[0x06]='Mouse 5',[0x08]='Backspace',[0x09]='Tab',[0x0D]='Enter',[0x10]='Shift',[0x11]='Ctrl',[0x12]='Alt',
    [0x13]='Pause',[0x14]='Caps Lock',[0x20]='Space',[0x21]='Page Up',[0x22]='Page Down',[0x23]='End',[0x24]='Home',[0x25]='Left',[0x26]='Up',
    [0x27]='Right',[0x28]='Down',[0x2E]='Delete',[0x6A]='Num *',[0x6B]='Num +',[0x6D]='Num -',[0x6E]='Num .',[0x6F]='Num /',
    [0xBA]=';',[0xBB]='=',[0xBC]=',',[0xBD]='-',[0xBE]='.',[0xBF]='/',[0xC0]='`',[0xDB]='[',[0xDC]='\\',[0xDD]=']',[0xDE]="'"}
for i=0,9 do NAMES[0x30+i]=tostring(i);NAMES[0x60+i]='Num '..i end
for i=0,25 do NAMES[0x41+i]=string.char(65+i) end
for i=1,24 do NAMES[0x6F+i]='F'..i end
local SKIP={[0x01]=true,[0x02]=true,[0x03]=true,[0x04]=true,[0x1B]=true,[0x2D]=true,[0x10]=true,[0x11]=true,[0x12]=true,[0xA0]=true,[0xA1]=true,[0xA2]=true,[0xA3]=true,[0xA4]=true,[0xA5]=true}
function M.Name(code)
    if not code or code==0 then return 'None' end
    return NAMES[code] or string.format('Key %02X',code)
end
local function down(code)
    local ok,value=pcall(function() return reframework:is_key_down(code) end)
    return ok and value==true
end
function M.Save()
    local out={}
    for _,a in ipairs(M.actions) do out[a.id]=M.binds[a.id] or 0 end
    pcall(json.dump_file,config,out)
end
local loaded,saved=pcall(json.load_file,config)
for _,a in ipairs(M.actions) do
    local value=loaded and type(saved)=='table' and saved[a.id]
    M.binds[a.id]=type(value)=='number' and value or a.key
end
function M.Default(id)
    for _,a in ipairs(M.actions) do if a.id==id then M.binds[id]=a.key end end
    M.Save()
end
function M.Clear(id) M.binds[id]=0;M.Save() end
function M.Capture(id) M.waiting=id;M.held={};for code=0x05,0xFE do if down(code) then M.held[code]=true end end;M.status='Press a key for '..id..' (Esc to cancel)' end
local previous={}
local function capture()
    if down(0x1B) then M.waiting=nil;M.status='Cancelled';return end
    for code=0x05,0xFE do
        if not SKIP[code] then
            local isDown=down(code)
            if isDown and not M.held[code] then
                local id=M.waiting
                for other,key in pairs(M.binds) do
                    if other~=id and key==code then M.binds[other]=0 end
                end
                M.binds[id]=code;M.waiting=nil
                M.status=M.Name(code)..' set'
                previous[code]=true
                M.Save()
                return
            end
            if not isDown then M.held[code]=nil end
        end
    end
end
function M.Tick(menuOpen,run)
    if M.waiting then capture();return end
    for id,code in pairs(M.binds) do
        if code and code~=0 then
            local isDown=down(code)
            if isDown and not previous[code] and not menuOpen then run(id) end
            previous[code]=isDown
        end
    end
end
return M
