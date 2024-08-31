package remake

import "attrib"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

GAME_NAME_NICE :: "Dungeon of Quake"
GAME_NAME :: "dungeon_of_quake"

VERSION_STRING :: "0.1-alpha"

App_State :: enum {
    Loadscreen = 0,
    Main_Menu,
    Game,
}

Global_State :: struct {
    window_size:     IVec2,
    camera:          rl.Camera,
    time_passed:     f32,
    frame_index:     i64,
    exit_next_frame: bool,
    load_dir:        string,
    save_dir:        string,
    render_texture:  rl.RenderTexture2D,
    current_music:   ^rl.Music,
    paused:          bool,
    screen_tint:     Vec3,
    app_state:       App_State,
    // settings:        Settings,
    // assets:          Assets,
    // level:           Level,
    // menu:            Menu_Data,
}

g_state: Global_State

main :: proc() {
    bootstrap()
    rl.DisableCursor()

    // for !rl.WindowShouldClose() && !g_state.exit_next_frame {
    //     g_state.frame_index += 1
    //     delta := rl.GetFrameTime()
    // }
}

bootstrap :: proc() {
    rl.SetWindowState({.WINDOW_RESIZABLE, .VSYNC_HINT, .FULLSCREEN_MODE})
    rl.InitWindow(800, 600, GAME_NAME_NICE)
    rl.SetWindowMonitor(0)
    rl.SetWindowSize(rl.GetMonitorWidth(0), rl.GetMonitorHeight(0))
    rl.ToggleFullscreen()
}
