#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <atomic>
#include "API.h"
namespace {
const REFrameworkPluginFunctions* api=nullptr;
HWND gameWindow=nullptr;
bool active=false;
int cursorAdjustments=0;
bool foreground(){DWORD pid=0;GetWindowThreadProcessId(GetForegroundWindow(),&pid);return pid==GetCurrentProcessId();}
void releaseCursor(){
    if(!active)return;
    while(cursorAdjustments>0){ShowCursor(FALSE);--cursorAdjustments;}
    active=false;
}
void frame(){
    const bool wanted=api->is_drawing_ui() && foreground();
    if(!wanted){releaseCursor();return;}
    active=true;
    ClipCursor(nullptr);
    CURSORINFO info{sizeof(CURSORINFO)};
    if(GetCursorInfo(&info) && !(info.flags&CURSOR_SHOWING)){
        for(int i=0;i<32;++i){++cursorAdjustments;if(ShowCursor(TRUE)>=0)break;}
    }
    SetCursor(LoadCursorW(nullptr,MAKEINTRESOURCEW(32512)));
}
bool message(void* hwnd,unsigned int msg,unsigned long long,long long value){
    gameWindow=static_cast<HWND>(hwnd);
    if(!api->is_drawing_ui() || !foreground())return true;
    if(msg>=WM_MOUSEFIRST && msg<=WM_MOUSELAST)return false;
    if(msg==WM_INPUT){
        RAWINPUTHEADER header{};UINT size=sizeof(header);
        if(GetRawInputData(reinterpret_cast<HRAWINPUT>(value),RID_HEADER,&header,&size,sizeof(header))!=UINT(-1) && header.dwType==RIM_TYPEMOUSE)return false;
    }
    return true;
}
}
extern "C" __declspec(dllexport) void reframework_plugin_required_version(REFrameworkPluginVersion* version){
    version->major=REFRAMEWORK_PLUGIN_VERSION_MAJOR;
    version->minor=REFRAMEWORK_PLUGIN_VERSION_MINOR;
    version->patch=REFRAMEWORK_PLUGIN_VERSION_PATCH;
    version->game_name=nullptr;
}
extern "C" __declspec(dllexport) bool reframework_plugin_initialize(const REFrameworkPluginInitializeParam* param){
    api=param->functions;
    const bool ok=api->on_present(frame) && api->on_message(message);
    api->log_info("[FriteabcInput] Cursor release and mouse capture %s",ok?"ready":"unavailable");
    return ok;
}
