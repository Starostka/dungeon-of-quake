package game

// 'Dungeon of Quake' is a simple first person shooter, heavily inspired by the Quake franchise
// using raylib

import "attrib"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "gui"
import rl "vendor:raylib"

DOQ_VERSION_STRING :: "0.1-alpha"

windowSizeX: i32 = 0
windowSizeY: i32 = 0

camera: rl.Camera = {}
viewmodelCamera: rl.Camera = {}

frame_index: i64 = 0
deltatime: f32 = 0.01
timepassed: f32 = 0.0
app_shouldExitNextFrame: bool = false
loadpath: string

renderTextureMain: rl.RenderTexture2D
postprocessShader: rl.Shader
randData: rand.Rand

playingMusic: ^rl.Music

gameIsPaused: bool = false
settings: struct {
    drawFPS:           bool,
    debugIsEnabled:    bool,
    audioMasterVolume: f32,
    audioMusicVolume:  f32,
    crosshairOpacity:  f32,
    mouseSensitivity:  f32,
    FOV:               f32,
    viewmodelFOV:      f32,
    gunXOffset:        f32,
}

screenTint: Vec3 = {1, 1, 1}

app_updatePathKind_t :: enum {
    LOADSCREEN = 0,
    MAIN_MENU,
    GAME,
}

app_updatePathKind: app_updatePathKind_t

main :: proc() {
    _doq_main()
}

// this just gets called from main
_doq_main :: proc() {
    _app_init()

    for !rl.WindowShouldClose() && !app_shouldExitNextFrame {
        //println("### frame =", frame_index, "deltatime =", deltatime)
        frame_index += 1

        // fixup
        settings.audioMasterVolume = clamp(settings.audioMasterVolume, 0.0, 1.0)
        settings.audioMusicVolume = clamp(settings.audioMusicVolume, 0.0, 1.0)
        settings.crosshairOpacity = clamp(settings.crosshairOpacity, 0.0, 1.0)
        settings.mouseSensitivity = clamp(settings.mouseSensitivity, 0.1, 5.0)
        settings.FOV = clamp(settings.FOV, 60.0, 160.0)
        settings.viewmodelFOV = clamp(settings.viewmodelFOV, 80.0, 120.0)
        settings.gunXOffset = clamp(settings.gunXOffset, -0.4, 0.4)
        rl.SetMasterVolume(settings.audioMasterVolume)

        camera.fovy = settings.FOV
        viewmodelCamera.fovy = settings.viewmodelFOV

        // rl.DisableCursor()

        gui.menuContext.windowSizeX = windowSizeX
        gui.menuContext.windowSizeY = windowSizeY
        gui.menuContext.deltatime = deltatime

        if playingMusic != nil {
            rl.UpdateMusicStream(playingMusic^)
        }

        if settings.debugIsEnabled do rl.SetTraceLogLevel(rl.TraceLogLevel.ALL)
        else do rl.SetTraceLogLevel(rl.TraceLogLevel.NONE)


        if app_updatePathKind != .GAME do gameStopSounds()

        switch app_updatePathKind {
        case .LOADSCREEN:
            menu_updateAndDrawLoadScreenUpdatePath()
        case .MAIN_MENU:
            menu_updateAndDrawMainMenuUpdatePath()
        case .GAME:
            // main game update path
            {
                rl.UpdateCamera(&camera, rl.CameraMode.CUSTOM)
                rl.UpdateCamera(&viewmodelCamera, rl.CameraMode.CUSTOM)

                _app_update()

                rl.BeginTextureMode(renderTextureMain)
                bckgcol := Vec4{map_data.skyColor.r, map_data.skyColor.g, map_data.skyColor.b, 1.0}
                rl.ClearBackground(rl.ColorFromNormalized(bckgcol))
                rl.BeginMode3D(camera)
                _app_render3d()
                if !gameIsPaused {
                    _gun_update()
                    _player_update()
                }
                // _enemy_updateDataAndRender()
                _bullet_updateDataAndRender()
                rl.EndMode3D()
                rl.BeginMode3D(viewmodelCamera)
                gun_drawModel(gun_calcViewportPos())
                rl.EndMode3D()
                rl.EndTextureMode()

                rl.BeginDrawing()
                rl.ClearBackground(rl.PINK) // for debug
                rl.SetShaderValue(
                    postprocessShader,
                    cast(rl.ShaderLocationIndex)rl.GetShaderLocation(postprocessShader, "tintColor"),
                    &screenTint,
                    rl.ShaderUniformDataType.VEC3,
                )

                rl.BeginShaderMode(postprocessShader)
                rl.DrawTextureRec(
                    renderTextureMain.texture,
                    rl.Rectangle {
                        0,
                        0,
                        cast(f32)renderTextureMain.texture.width,
                        -cast(f32)renderTextureMain.texture.height,
                    },
                    {0, 0},
                    rl.WHITE,
                )
                rl.EndShaderMode()

                if gameIsPaused {
                    menu_updateAndDrawPauseMenu()
                }

                _app_render2d()
                rl.EndDrawing()
            }
        }



        deltatime = rl.GetFrameTime()
        if !gameIsPaused {
            timepassed += deltatime // not really accurate but whatever
        }
    }

    rl.CloseWindow()
    rl.CloseAudioDevice()
}



//
// APP
//

_app_init :: proc() {
    loadpath = filepath.clean(string(rl.GetWorkingDirectory()))
    println("loadpath", loadpath)

    settings_setDefault()
    settings_loadFromFile()

    rl.SetWindowState({.WINDOW_RESIZABLE, .VSYNC_HINT})
    rl.InitWindow(800, 600, "Dungeon of Quake")
    // rl.ToggleFullscreen()

    windowSizeX = rl.GetScreenWidth()
    windowSizeY = rl.GetScreenHeight()

    rl.SetExitKey(rl.KeyboardKey.KEY_NULL)
    rl.SetTargetFPS(120)

    rl.InitAudioDevice()

    if !rl.IsAudioDeviceReady() || !rl.IsWindowReady() do time.sleep(10)

    rl.SetMasterVolume(settings.audioMasterVolume)


    renderTextureMain = rl.LoadRenderTexture(windowSizeX, windowSizeY)

    assets_load_persistent()

    camera.position = {0, 3, 0}
    camera.target = {}
    camera.up = Vec3{0.0, 1.0, 0.0}
    camera.projection = rl.CameraProjection.PERSPECTIVE
    //rl.SetCameraMode(camera, rl.CameraMode.CUSTOM)

    viewmodelCamera.position = {0, 0, 0}
    viewmodelCamera.target = {0, 0, 1}
    viewmodelCamera.up = {0, 1, 0}
    viewmodelCamera.projection = rl.CameraProjection.PERSPECTIVE
    //rl.SetCameraMode(viewmodelCamera, rl.CameraMode.CUSTOM)



    rand.init(&randData, cast(u64)time.now()._nsec)

    map_clearAll()
    map_data.bounds = {MAP_SIDE_TILE_COUNT, MAP_SIDE_TILE_COUNT}
    if os.is_file(asset_path("maps", "_quickload.dqm")) {
        map_loadFromFile("_quickload.dqm")
        app_setUpdatePathKind(.GAME)
    }

    player_startMap()

}

_app_update :: proc() {
    //rl.UpdateMusicStream(map_data.backgroundMusic)
    //rl.UpdateMusicStream(map_data.ambientMusic)
    //rl.SetMusicVolume(player_data.swooshMusic, clamp(linalg.length(player_data.vel * 0.05), 0.0, 1.0))

    if rl.IsKeyPressed(rl.KeyboardKey.RIGHT_ALT) do settings.debugIsEnabled = !settings.debugIsEnabled

    if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) do gameIsPaused = !gameIsPaused

    // pull elevators down
    {
        playerTilePos := map_worldToTile(player_data.pos)
        c := [2]u8{cast(u8)playerTilePos.x, cast(u8)playerTilePos.y}
        for key, val in map_data.elevatorHeights {
            if key == c do continue
            map_data.elevatorHeights[key] = clamp(val - (TILE_ELEVATOR_MOVE_FACTOR * deltatime), 0.0, 1.0)
        }
    }

    screenTint = linalg.lerp(screenTint, Vec3{1, 1, 1}, clamp(deltatime * 3.0, 0.0, 1.0))
}

_app_render2d :: proc() {
    menu_drawPlayerUI()
    menu_drawDebugUI()
}

_app_render3d :: proc() {
    when false {
        if settings.debugIsEnabled {
            LEN :: 100
            WID :: 1
            rl.DrawCube(Vec3{LEN, 0, 0}, LEN, WID, WID, rl.RED)
            rl.DrawCube(Vec3{0, LEN, 0}, WID, LEN, WID, rl.GREEN)
            rl.DrawCube(Vec3{0, 0, LEN}, WID, WID, LEN, rl.BLUE)
            rl.DrawCube(Vec3{0, 0, 0}, WID, WID, WID, rl.RAYWHITE)
        }
    }

    //rl.DrawPlane(Vec3{0.0, 0.0, 0.0}, Vec2{32.0, 32.0}, rl.LIGHTGRAY) // Draw ground

    rl.SetShaderValue(
        asset_data.tileShader,
        asset_data.tileShaderCamPosUniformIndex,
        &camera.position,
        rl.ShaderUniformDataType.VEC3,
    )
    fogColor := Vec4{map_data.skyColor.r, map_data.skyColor.g, map_data.skyColor.b, map_data.fogStrength}

    rl.SetShaderValue(
        asset_data.defaultShader,
        cast(rl.ShaderLocationIndex)rl.GetShaderLocation(asset_data.defaultShader, "camPos"),
        &camera.position,
        rl.ShaderUniformDataType.VEC3,
    )
    rl.SetShaderValue(
        asset_data.defaultShader,
        cast(rl.ShaderLocationIndex)rl.GetShaderLocation(asset_data.defaultShader, "fogColor"),
        &fogColor,
        rl.ShaderUniformDataType.VEC4,
    )

    rl.SetShaderValue(
        asset_data.tileShader,
        cast(rl.ShaderLocationIndex)rl.GetShaderLocation(asset_data.tileShader, "fogColor"),
        &fogColor,
        rl.ShaderUniformDataType.VEC4,
    )

    rl.SetShaderValue(
        asset_data.portalShader,
        cast(rl.ShaderLocationIndex)rl.GetShaderLocation(asset_data.portalShader, "timePassed"),
        &timepassed,
        rl.ShaderUniformDataType.FLOAT,
    )

    rl.SetShaderValue(
        asset_data.cloudShader,
        cast(rl.ShaderLocationIndex)rl.GetShaderLocation(asset_data.cloudShader, "timePassed"),
        &timepassed,
        rl.ShaderUniformDataType.FLOAT,
    )
    rl.SetShaderValue(
        asset_data.cloudShader,
        cast(rl.ShaderLocationIndex)rl.GetShaderLocation(asset_data.cloudShader, "camPos"),
        &camera.position,
        rl.ShaderUniformDataType.VEC3,
    )


    map_drawTilemap()
}



app_setUpdatePathKind :: proc(kind: app_updatePathKind_t) {
    app_updatePathKind = kind
    menu_resetState()
    gameIsPaused = false
}



world_reset :: proc() {
    player_initData()
    player_startMap()

    for i: i32 = 0; i < enemy_data.gruntCount; i += 1 {
        enemy_data.grunts[i].pos = enemy_data.grunts[i].spawnPos
        enemy_data.grunts[i].health = ENEMY_GRUNT_HEALTH
        enemy_data.grunts[i].attackTimer = ENEMY_GRUNT_ATTACK_TIME
        enemy_data.grunts[i].vel = {}
        enemy_data.grunts[i].target = {}
        enemy_data.grunts[i].isMoving = false
    }

    for i: i32 = 0; i < enemy_data.knightCount; i += 1 {
        enemy_data.knights[i].pos = enemy_data.knights[i].spawnPos
        enemy_data.knights[i].health = ENEMY_KNIGHT_HEALTH
        enemy_data.knights[i].attackTimer = ENEMY_KNIGHT_ATTACK_TIME
        enemy_data.knights[i].vel = {}
        enemy_data.knights[i].target = {}
        enemy_data.knights[i].isMoving = false
    }

    map_data.gunPickupCount = map_data.gunPickupSpawnCount
    map_data.healthPickupCount = map_data.healthPickupSpawnCount
}



settings_setDefault :: proc() {
    settings = {
        drawFPS           = false,
        debugIsEnabled    = false,
        audioMasterVolume = 0.5,
        audioMusicVolume  = 0.4,
        crosshairOpacity  = 0.2,
        mouseSensitivity  = 1.0,
        FOV               = 100.0,
        viewmodelFOV      = 110.0,
        gunXOffset        = 0.15,
    }
}

settings_getFilePath :: proc() -> string {
    return fmt.tprint(args = {loadpath, filepath.SEPARATOR_STRING, ".doq_settings"}, sep = "")
}

settings_saveToFile :: proc() {
    text := fmt.tprint(
        args =  {
            "drawFPS",
            attrib.SEPARATOR,
            " ",
            settings.drawFPS,
            "\n",
            "debugIsEnabled",
            attrib.SEPARATOR,
            " ",
            settings.debugIsEnabled,
            "\n",
            "audioMasterVolume",
            attrib.SEPARATOR,
            " ",
            settings.audioMasterVolume,
            "\n",
            "audioMusicVolume",
            attrib.SEPARATOR,
            " ",
            settings.audioMusicVolume,
            "\n",
            "crosshairOpacity",
            attrib.SEPARATOR,
            " ",
            settings.crosshairOpacity,
            "\n",
            "mouseSensitivity",
            attrib.SEPARATOR,
            " ",
            settings.mouseSensitivity,
            "\n",
            "FOV",
            attrib.SEPARATOR,
            " ",
            settings.FOV,
            "\n",
            "viewmodelFOV",
            attrib.SEPARATOR,
            " ",
            settings.viewmodelFOV,
            "\n",
            "gunXOffset",
            attrib.SEPARATOR,
            " ",
            settings.gunXOffset,
            "\n",
        },
        sep = "",
    )

    os.write_entire_file(settings_getFilePath(), transmute([]u8)text)
}

settings_loadFromFile :: proc() {
    buf, ok := os.read_entire_file_from_filename(settings_getFilePath())
    if !ok {
        println("! error: unable to read settings file")
        return
    }
    defer delete(buf)

    text := transmute(string)buf
    index: i32 = 0
    for index < i32(len(text)) {
        attrib.skipWhitespace(buf, &index)
        if attrib.match(buf, &index, "drawFPS") do settings.drawFPS = attrib.readBool(buf, &index)
        if attrib.match(buf, &index, "debugIsEnabled") do settings.debugIsEnabled = attrib.readBool(buf, &index)
        if attrib.match(buf, &index, "audioMasterVolume") do settings.audioMasterVolume = attrib.readF32(buf, &index)
        if attrib.match(buf, &index, "audioMusicVolume") do settings.audioMusicVolume = attrib.readF32(buf, &index)
        if attrib.match(buf, &index, "crosshairOpacity") do settings.crosshairOpacity = attrib.readF32(buf, &index)
        if attrib.match(buf, &index, "mouseSensitivity") do settings.mouseSensitivity = attrib.readF32(buf, &index)
        if attrib.match(buf, &index, "FOV") do settings.FOV = attrib.readF32(buf, &index)
        if attrib.match(buf, &index, "viewmodelFOV") do settings.viewmodelFOV = attrib.readF32(buf, &index)
        if attrib.match(buf, &index, "gunXOffset") do settings.gunXOffset = attrib.readF32(buf, &index)
    }
}



gameStopSounds :: proc() {
    rl.StopSound(asset_data.elevatorSound)
    rl.StopSound(asset_data.player.swooshSound)
}



//
// BULLETS
//

BULLET_LINEAR_EFFECT_MAX_COUNT :: 64
BULLET_LINEAR_EFFECT_MESH_QUALITY :: 5 // equal to cylinder slices

BULLET_REMOVE_THRESHOLD :: 0.04

bullet_ammoInfo_t :: struct {
    damage:    f32,
    knockback: f32,
}

bullet_data: struct {
    bulletLinesCount: i32,
    bulletLines:      [BULLET_LINEAR_EFFECT_MAX_COUNT]struct {
        start:      Vec3,
        timeToLive: f32,
        end:        Vec3,
        radius:     f32,
        color:      Vec4,
        duration:   f32,
    },
}

// @param timeToLive: in seconds
bullet_createBulletLine :: proc(start: Vec3, end: Vec3, rad: f32, col: Vec4, duration: f32) {
    if duration <= BULLET_REMOVE_THRESHOLD do return
    index := bullet_data.bulletLinesCount
    if index + 1 >= BULLET_LINEAR_EFFECT_MAX_COUNT do return
    bullet_data.bulletLinesCount += 1
    bullet_data.bulletLines[index] = {}
    bullet_data.bulletLines[index].start = start
    bullet_data.bulletLines[index].timeToLive = duration
    bullet_data.bulletLines[index].end = end
    bullet_data.bulletLines[index].radius = rad
    bullet_data.bulletLines[index].color = col
    bullet_data.bulletLines[index].duration = duration
}

// @returns: tn, hitenemy
bullet_shootRaycast :: proc(
    start: Vec3,
    dir: Vec3,
    damage: f32,
    rad: f32,
    col: Vec4,
    effectDuration: f32,
) -> (
    tn: f32,
    enemykind: enemy_kind_t,
    enemyindex: i32,
) {
    hit: bool
    tn, hit, enemykind, enemyindex = phy_boxcastWorld(start, start + dir * 1e6, {0, 0, 0}) //Vec3{rad,rad,rad})
    hitpos := start + dir * tn
    hitenemy := enemykind != enemy_kind_t.NONE
    bullet_createBulletLine(
        start + dir * rad * 2.0,
        hitpos,
        hitenemy ? rad : rad * 0.65,
        hitenemy ? col : col * Vec4{0.5, 0.5, 0.5, 1.0},
        hitenemy ? effectDuration : effectDuration * 0.7,
    )
    if hit {
        switch enemykind {
        case enemy_kind_t.NONE:
        case enemy_kind_t.GRUNT:
            headshot :=
                hitpos.y >
                enemy_data.grunts[enemyindex].pos.y + ENEMY_GRUNT_SIZE.y * ENEMY_HEADSHOT_HALF_OFFSET
            enemy_data.grunts[enemyindex].health -= headshot ? damage * 2 : damage
            if headshot do playSound(asset_data.gun.headshotSound)
            playSound(asset_data.enemy.gruntHitSound)
            if enemy_data.grunts[enemyindex].health <= 0.0 do playSoundMulti(asset_data.enemy.gruntDeathSound)
            enemy_data.grunts[enemyindex].vel += dir * 10.0 * damage
        case enemy_kind_t.KNIGHT:
            headshot :=
                hitpos.y >
                enemy_data.knights[enemyindex].pos.y + ENEMY_KNIGHT_SIZE.y * ENEMY_HEADSHOT_HALF_OFFSET
            enemy_data.knights[enemyindex].health -= headshot ? damage * 2 : damage
            if headshot do playSound(asset_data.gun.headshotSound)
            playSound(asset_data.enemy.knightHitSound)
            if enemy_data.knights[enemyindex].health <= 0.0 do playSoundMulti(asset_data.enemy.knightDeathSound)
            enemy_data.knights[enemyindex].vel += dir * 10.0 * damage
        }
    }

    return tn, enemykind, enemyindex
}

bullet_shootProjectile :: proc(start: Vec3, dir: Vec3, damage: f32, rad: f32, col: Vec4) {
    // TODO
}

_bullet_updateDataAndRender :: proc() {
    assert(bullet_data.bulletLinesCount >= 0)
    assert(bullet_data.bulletLinesCount < BULLET_LINEAR_EFFECT_MAX_COUNT)

    if !gameIsPaused {
        // remove old
        loopremove: for i: i32 = 0; i < bullet_data.bulletLinesCount; i += 1 {
            bullet_data.bulletLines[i].timeToLive -= deltatime
            if bullet_data.bulletLines[i].timeToLive <= BULLET_REMOVE_THRESHOLD {     // needs to be removed
                if i + 1 >= bullet_data.bulletLinesCount {     // we're on the last one
                    bullet_data.bulletLinesCount -= 1
                    break loopremove
                }
                bullet_data.bulletLinesCount -= 1
                lastindex := bullet_data.bulletLinesCount
                bullet_data.bulletLines[i] = bullet_data.bulletLines[lastindex]
            }
        }
    }

    // draw
    rl.BeginShaderMode(asset_data.bulletLineShader)
    for i: i32 = 0; i < bullet_data.bulletLinesCount; i += 1 {
        fade := (bullet_data.bulletLines[i].timeToLive / bullet_data.bulletLines[i].duration)
        col := bullet_data.bulletLines[i].color
        sphfade := fade * fade

        // thin white
        rl.DrawSphere(
            bullet_data.bulletLines[i].end,
            sphfade * bullet_data.bulletLines[i].radius * 2.0,
            rl.ColorFromNormalized(Vec4{1, 1, 1, 0.5 + sphfade * 0.5}),
        )

        rl.DrawSphere(
            bullet_data.bulletLines[i].end,
            (sphfade + 2.0) / 3.0 * bullet_data.bulletLines[i].radius * 4.0,
            rl.ColorFromNormalized(Vec4{col.r, col.g, col.b, col.a * sphfade}),
        )

        // thin white
        rl.DrawCylinderEx(
            bullet_data.bulletLines[i].start,
            bullet_data.bulletLines[i].end,
            fade * bullet_data.bulletLines[i].radius * 0.05,
            fade * bullet_data.bulletLines[i].radius * 0.4,
            3,
            rl.ColorFromNormalized(Vec4{1, 1, 1, 0.5 + fade * 0.5}),
        )

        rl.DrawCylinderEx(
            bullet_data.bulletLines[i].start,
            bullet_data.bulletLines[i].end,
            fade * bullet_data.bulletLines[i].radius * 0.1,
            fade * bullet_data.bulletLines[i].radius,
            BULLET_LINEAR_EFFECT_MESH_QUALITY,
            rl.ColorFromNormalized(Vec4{col.r, col.g, col.b, col.a * fade}),
        )

        //rl.DrawSphere(
        //	bullet_data.bulletLines[i].start,
        //	fade * bullet_data.bulletLines[i].radius,
        //	rl.ColorFromNormalized(Vec4{col.r, col.g, col.b, col.a * fade}),
        //)
    }
    rl.EndShaderMode()
}



//
// ENEMIES
//

ENEMY_GRUNT_MAX_COUNT :: 64
ENEMY_KNIGHT_MAX_COUNT :: 64

ENEMY_HEALTH_MULTIPLIER :: 1.5
ENEMY_HEADSHOT_HALF_OFFSET :: 0.2
ENEMY_GRAVITY :: 40

ENEMY_GRUNT_SIZE :: Vec3{2.5, 3.7, 2.5}
ENEMY_GRUNT_ACCELERATION :: 10
ENEMY_GRUNT_MAX_SPEED :: 20
ENEMY_GRUNT_FRICTION :: 5
ENEMY_GRUNT_MIN_GOOD_DIST :: 30
ENEMY_GRUNT_MAX_GOOD_DIST :: 60
ENEMY_GRUNT_ATTACK_TIME :: 1.7
ENEMY_GRUNT_DAMAGE :: 1.0
ENEMY_GRUNT_HEALTH :: 1.0
ENEMY_GRUNT_SPEED_RAND :: 0.012 // NOTE: multiplier for length(player velocity) ^ 2
ENEMY_GRUNT_DIST_RAND :: 1.1
ENEMY_GRUNT_MAX_DIST :: 250.0

ENEMY_KNIGHT_SIZE :: Vec3{1.5, 3.0, 1.5}
ENEMY_KNIGHT_ACCELERATION :: 7
ENEMY_KNIGHT_MAX_SPEED :: 38
ENEMY_KNIGHT_FRICTION :: 2
ENEMY_KNIGHT_DAMAGE :: 1.0
ENEMY_KNIGHT_ATTACK_TIME :: 1.0
ENEMY_KNIGHT_HEALTH :: 1.0
ENEMY_KNIGHT_RANGE :: 5.0

ENEMY_GRUNT_ANIM_FRAMETIME :: 1.0 / 15.0
ENEMY_KNIGHT_ANIM_FRAMETIME :: 1.0 / 15.0

enemy_kind_t :: enum u8 {
    NONE = 0,
    GRUNT,
    KNIGHT,
}

enemy_data: struct {
    deadCount:   i32,
    gruntCount:  i32,
    grunts:      [ENEMY_GRUNT_MAX_COUNT]struct {
        spawnPos:       Vec3,
        attackTimer:    f32,
        pos:            Vec3,
        health:         f32,
        target:         Vec3,
        isMoving:       bool,
        vel:            Vec3,
        rot:            f32, // angle in radians around Y axis
        animFrame:      i32,
        animFrameTimer: f32,
        animState:      enum u8 {
            // also index to animation
            RUN    = 0,
            ATTACK = 1,
            IDLE   = 2,
        },
    },
    knightCount: i32,
    knights:     [ENEMY_KNIGHT_MAX_COUNT]struct {
        spawnPos:       Vec3,
        health:         f32,
        pos:            Vec3,
        attackTimer:    f32,
        vel:            Vec3,
        rot:            f32, // angle in radians around Y axis
        target:         Vec3,
        isMoving:       bool,
        animFrame:      i32,
        animFrameTimer: f32,
        animState:      enum u8 {
            // also index to animation
            RUN    = 0,
            ATTACK = 1,
            IDLE   = 2,
        },
    },
}



// guy with a gun
enemy_spawnGrunt :: proc(pos: Vec3) {
    index := enemy_data.gruntCount
    if index + 1 >= ENEMY_GRUNT_MAX_COUNT do return
    enemy_data.gruntCount += 1
    enemy_data.grunts[index] = {}
    enemy_data.grunts[index].spawnPos = pos
    enemy_data.grunts[index].pos = pos
    enemy_data.grunts[index].target = {}
    enemy_data.grunts[index].health = ENEMY_GRUNT_HEALTH * ENEMY_HEALTH_MULTIPLIER
}

// guy with a sword
enemy_spawnKnight :: proc(pos: Vec3) {
    index := enemy_data.knightCount
    if index + 1 >= ENEMY_KNIGHT_MAX_COUNT do return
    enemy_data.knightCount += 1
    enemy_data.knights[index] = {}
    enemy_data.knights[index].spawnPos = pos
    enemy_data.knights[index].pos = pos
    enemy_data.knights[index].target = {}
    enemy_data.knights[index].health = ENEMY_KNIGHT_HEALTH * ENEMY_HEALTH_MULTIPLIER
}



_enemy_updateDataAndRender :: proc() {
    assert(enemy_data.gruntCount >= 0)
    assert(enemy_data.knightCount >= 0)
    assert(enemy_data.gruntCount < ENEMY_GRUNT_MAX_COUNT)
    assert(enemy_data.knightCount < ENEMY_KNIGHT_MAX_COUNT)

    if !gameIsPaused {
        //enemy_data.knightAnimFrame += 1
        //animindex := 1
        //rl.UpdateModelAnimation(asset_data.enemy.knightModel, asset_data.enemy.knightAnim[animindex], enemy_data.knightAnimFrame)
        //if enemy_data.knightAnimFrame >= asset_data.enemy.knightAnim[animindex].frameCount do enemy_data.knightAnimFrame = 0

        //if !rl.IsModelAnimationValid(asset_data.enemy.knightModel, asset_data.enemy.knightAnim[animindex]) do println("! error: KNIGHT ANIM INVALID")

        enemy_data.deadCount = 0

        // update grunts
        for i: i32 = 0; i < enemy_data.gruntCount; i += 1 {
            if enemy_data.grunts[i].health <= 0.0 {
                enemy_data.deadCount += 1
                continue
            }

            pos := enemy_data.grunts[i].pos + Vec3{0, ENEMY_GRUNT_SIZE.y * 0.5, 0}
            dir := linalg.normalize(player_data.pos - pos)
            // cast player
            p_tn, p_hit := phy_boxcastPlayer(pos, dir, {0, 0, 0})
            EPS :: 0.0
            t_tn, t_norm, t_hit := phy_boxcastTilemap(pos, pos + dir * 1e6, {EPS, EPS, EPS})
            seeplayer := p_tn < t_tn && p_hit

            if pos.y < -TILE_HEIGHT do enemy_data.knights[i].health = -1.0

            // println("p_tn", p_tn, "p_hit", p_hit, "t_tn", t_tn, "t_hit", t_hit)

            enemy_data.grunts[i].attackTimer -= deltatime


            if seeplayer {
                enemy_data.grunts[i].target = player_data.pos
                enemy_data.grunts[i].isMoving = true
            }


            flatdir := linalg.normalize((enemy_data.grunts[i].target - pos) * Vec3{1, 0, 1})

            toTargetRot: f32 = math.atan2(-flatdir.z, flatdir.x) // * math.sign(flatdir.x)
            enemy_data.grunts[i].rot = math.angle_lerp(
                enemy_data.grunts[i].rot,
                roundstep(toTargetRot, 4.0 / math.PI),
                clamp(deltatime * 1.0, 0.0, 1.0),
            )

            if p_tn < ENEMY_GRUNT_SIZE.y {
                player_data.vel = flatdir * 50.0
                player_data.slowness = 0.1
            }

            if seeplayer && p_tn < ENEMY_GRUNT_MAX_DIST {
                if enemy_data.grunts[i].attackTimer < 0.0 {     // attack
                    enemy_data.grunts[i].attackTimer = ENEMY_GRUNT_ATTACK_TIME
                    rndstrength := clamp(
                        (linalg.length2(player_data.vel) * ENEMY_GRUNT_SPEED_RAND +
                            p_tn * ENEMY_GRUNT_DIST_RAND) *
                        1e-3 *
                        0.5,
                        0.0005,
                        0.04,
                    )
                    // cast bullet
                    bulletdir := linalg.normalize(
                        dir + randVec3() * rndstrength + player_data.vel * deltatime / PLAYER_SPEED,
                    )
                    bullet_tn, bullet_norm, bullet_hit := phy_boxcastTilemap(
                        pos,
                        pos + bulletdir * 1e6,
                        {EPS, EPS, EPS},
                    )
                    bullet_createBulletLine(
                        pos,
                        pos + bulletdir * bullet_tn,
                        2.0,
                        Vec4{1.0, 0.0, 0.0, 1.0},
                        1.0,
                    )
                    bulletplayer_tn, bulletplayer_hit := phy_boxcastPlayer(pos, bulletdir, {0, 0, 0})
                    if bulletplayer_hit && bulletplayer_tn < bullet_tn {     // if the ray actually hit player first
                        player_damage(ENEMY_GRUNT_DAMAGE)
                        player_data.vel += bulletdir * 40.0
                        player_data.rotImpulse += {0.1, 0.0, 0.0}
                    }

                    enemy_data.grunts[i].animState = .ATTACK
                    enemy_data.grunts[i].animFrame = 0
                }
            } else {
                enemy_data.grunts[i].attackTimer = ENEMY_GRUNT_ATTACK_TIME * 0.5
            }



            speed := linalg.length(enemy_data.grunts[i].vel)
            enemy_data.grunts[i].vel.y -= ENEMY_GRAVITY * deltatime

            phy_pos, phy_vel, phy_hit, phy_norm := phy_simulateMovingBox(
                enemy_data.grunts[i].pos,
                enemy_data.grunts[i].vel,
                0.0,
                ENEMY_GRUNT_SIZE,
                0.1,
            )
            enemy_data.grunts[i].pos = phy_pos
            enemy_data.grunts[i].vel = phy_vel
            isOnGround := phy_hit && phy_norm.y > 0.3

            if speed > 0.1 && enemy_data.grunts[i].isMoving && isOnGround {
                forwdepth := phy_raycastDepth(pos + flatdir * ENEMY_GRUNT_SIZE.x * 1.7)
                if forwdepth > ENEMY_GRUNT_SIZE.y * 4 {
                    enemy_data.grunts[i].vel = -flatdir * ENEMY_GRUNT_MAX_SPEED * 0.5
                    enemy_data.grunts[i].animState = .IDLE
                    enemy_data.grunts[i].isMoving = false
                }
            }

            if enemy_data.grunts[i].isMoving && speed < ENEMY_GRUNT_MAX_SPEED && isOnGround {
                if !seeplayer {
                    enemy_data.grunts[i].vel += flatdir * ENEMY_GRUNT_ACCELERATION
                    enemy_data.grunts[i].animState = .RUN
                } else if p_tn < ENEMY_GRUNT_MIN_GOOD_DIST {
                    enemy_data.grunts[i].vel -= flatdir * ENEMY_GRUNT_ACCELERATION
                    enemy_data.grunts[i].animState = .RUN
                }
            }
        }



        // update knights
        for i: i32 = 0; i < enemy_data.knightCount; i += 1 {
            if enemy_data.knights[i].health <= 0.0 {
                enemy_data.deadCount += 1
                continue
            }

            pos := enemy_data.knights[i].pos + Vec3{0, ENEMY_KNIGHT_SIZE.y * 0.5, 0}
            dir := linalg.normalize(player_data.pos - pos)
            p_tn, p_hit := phy_boxcastPlayer(pos, dir, {0, 0, 0})
            t_tn, t_norm, t_hit := phy_boxcastTilemap(pos, pos + dir * 1e6, {1, 1, 1})
            seeplayer := p_tn < t_tn && p_hit

            if pos.y < -TILE_HEIGHT do enemy_data.knights[i].health = -1.0

            // println("p_tn", p_tn, "p_hit", p_hit, "t_tn", t_tn, "t_hit", t_hit)

            enemy_data.knights[i].attackTimer -= deltatime


            if seeplayer {
                enemy_data.knights[i].target = player_data.pos
                enemy_data.knights[i].isMoving = true
            }


            flatdir := linalg.normalize((enemy_data.knights[i].target - pos) * Vec3{1, 0, 1})

            toTargetRot: f32 = math.atan2(-flatdir.z, flatdir.x)
            enemy_data.knights[i].rot = math.angle_lerp(
                enemy_data.knights[i].rot,
                roundstep(toTargetRot, 4.0 / math.PI),
                clamp(deltatime * 3, 0.0, 1.0),
            )

            if seeplayer {
                if p_tn < ENEMY_KNIGHT_RANGE {
                    enemy_data.knights[i].vel = -flatdir * ENEMY_KNIGHT_MAX_SPEED * 2.0
                    player_data.vel = flatdir * 100.0
                    player_data.vel.y = 10.0
                    if enemy_data.knights[i].attackTimer < 0.0 {     // attack
                        enemy_data.knights[i].attackTimer = ENEMY_KNIGHT_ATTACK_TIME
                        player_damage(ENEMY_KNIGHT_DAMAGE)
                        player_data.vel = flatdir * 100.0
                        player_data.vel.y = 20.0
                        enemy_data.knights[i].vel = -flatdir * ENEMY_KNIGHT_MAX_SPEED * 2.0
                        enemy_data.knights[i].animState = .ATTACK
                        enemy_data.knights[i].animFrame = 0
                    }
                }
            } else {
                enemy_data.knights[i].attackTimer = ENEMY_KNIGHT_ATTACK_TIME * 0.5
            }



            speed := linalg.length(enemy_data.knights[i].vel)
            enemy_data.knights[i].vel.y -= ENEMY_GRAVITY * deltatime

            phy_pos, phy_vel, phy_hit, phy_norm := phy_simulateMovingBox(
                enemy_data.knights[i].pos,
                enemy_data.knights[i].vel,
                0.0,
                ENEMY_KNIGHT_SIZE,
                0.1,
            )
            enemy_data.knights[i].pos = phy_pos
            enemy_data.knights[i].vel = phy_vel
            isOnGround := phy_hit && phy_norm.y > 0.3

            if speed > 0.1 && enemy_data.knights[i].isMoving && isOnGround {
                forwdepth := phy_raycastDepth(pos + flatdir * ENEMY_KNIGHT_SIZE.x * 1.7)
                if forwdepth > ENEMY_KNIGHT_SIZE.y * 4 {
                    enemy_data.knights[i].vel = -enemy_data.knights[i].vel * 0.5
                    enemy_data.knights[i].animState = .IDLE
                    enemy_data.knights[i].isMoving = false
                }
            }

            if enemy_data.knights[i].isMoving &&
               speed < ENEMY_KNIGHT_MAX_SPEED &&
               isOnGround &&
               enemy_data.grunts[i].animState != .ATTACK {
                enemy_data.knights[i].vel += flatdir * ENEMY_KNIGHT_ACCELERATION
            }
        }
    } // if !gameIsPaused

    // render grunts
    for i: i32 = 0; i < enemy_data.gruntCount; i += 1 {
        if enemy_data.grunts[i].health <= 0.0 do continue

        // anim
        {
            // update state
            if !gameIsPaused {
                prevanim := enemy_data.grunts[i].animState
                if !enemy_data.grunts[i].isMoving do enemy_data.grunts[i].animState = .IDLE
                else {
                    if enemy_data.grunts[i].attackTimer < 0.0 do enemy_data.grunts[i].animState = .RUN
                }
                if enemy_data.grunts[i].animState != prevanim do enemy_data.grunts[i].animFrame = 0
            }

            animindex := i32(enemy_data.grunts[i].animState)

            if !gameIsPaused {
                enemy_data.grunts[i].animFrameTimer += deltatime
                if enemy_data.grunts[i].animFrameTimer > ENEMY_GRUNT_ANIM_FRAMETIME {
                    enemy_data.grunts[i].animFrameTimer -= ENEMY_GRUNT_ANIM_FRAMETIME
                    enemy_data.grunts[i].animFrame += 1

                    if enemy_data.grunts[i].animFrame >= asset_data.enemy.gruntAnim[animindex].frameCount {
                        enemy_data.grunts[i].animFrame = 0
                        enemy_data.grunts[i].animFrameTimer = 0
                        if enemy_data.grunts[i].animState == .ATTACK do enemy_data.grunts[i].animState = .IDLE
                    }
                }
            }

            // rl.UpdateModelAnimation(
            //     asset_data.enemy.gruntModel,
            //     asset_data.enemy.gruntAnim[animindex],
            //     enemy_data.grunts[i].animFrame,
            // )
        }

        rl.DrawModelEx(
            asset_data.enemy.gruntModel,
            enemy_data.grunts[i].pos,
            {0, 1, 0},
            enemy_data.grunts[i].rot * 180.0 / math.PI,
            1.4,
            rl.WHITE,
        )
    }

    // render knights
    for i: i32 = 0; i < enemy_data.knightCount; i += 1 {
        if enemy_data.knights[i].health <= 0.0 do continue

        // anim
        {
            // update state
            if !gameIsPaused {
                prevanim := enemy_data.knights[i].animState
                if !enemy_data.knights[i].isMoving do enemy_data.knights[i].animState = .IDLE
                else {
                    if enemy_data.knights[i].attackTimer < 0.0 do enemy_data.knights[i].animState = .RUN
                }
                if enemy_data.knights[i].animState != prevanim do enemy_data.knights[i].animFrame = 0
            }

            animindex := i32(enemy_data.knights[i].animState)

            if !gameIsPaused {
                enemy_data.knights[i].animFrameTimer += deltatime
                if enemy_data.knights[i].animFrameTimer > ENEMY_KNIGHT_ANIM_FRAMETIME {
                    enemy_data.knights[i].animFrameTimer -= ENEMY_KNIGHT_ANIM_FRAMETIME
                    enemy_data.knights[i].animFrame += 1

                    if enemy_data.knights[i].animFrame >= asset_data.enemy.knightAnim[animindex].frameCount {
                        enemy_data.knights[i].animFrame = 0
                        enemy_data.knights[i].animFrameTimer = 0
                        if enemy_data.knights[i].animState == .ATTACK do enemy_data.knights[i].animState = .RUN
                    }
                }
            }

            // rl.UpdateModelAnimation(
            //     asset_data.enemy.knightModel,
            //     asset_data.enemy.knightAnim[animindex],
            //     enemy_data.knights[i].animFrame,
            // )
        }

        rl.DrawModelEx(
            asset_data.enemy.knightModel,
            enemy_data.knights[i].pos,
            {0, 1, 0},
            enemy_data.knights[i].rot * 180.0 / math.PI, // rot
            1.0,
            rl.WHITE,
        )
    }

    if settings.debugIsEnabled {
        // render grunt physics AABBS
        for i: i32 = 0; i < enemy_data.gruntCount; i += 1 {
            if enemy_data.grunts[i].health <= 0.0 do continue
            rl.DrawCubeWires(
                enemy_data.grunts[i].pos,
                ENEMY_GRUNT_SIZE.x * 2,
                ENEMY_GRUNT_SIZE.y * 2,
                ENEMY_GRUNT_SIZE.z * 2,
                rl.GREEN,
            )
        }

        // render knight physics AABBS
        for i: i32 = 0; i < enemy_data.knightCount; i += 1 {
            if enemy_data.knights[i].health <= 0.0 do continue
            rl.DrawCubeWires(
                enemy_data.knights[i].pos,
                ENEMY_KNIGHT_SIZE.x * 2,
                ENEMY_KNIGHT_SIZE.y * 2,
                ENEMY_KNIGHT_SIZE.z * 2,
                rl.GREEN,
            )
        }
    }
}



//
// HELPERS PROCEDURES
//

asset_path :: proc(subdir: string, path: string, allocator := context.temp_allocator) -> string {
    return filepath.join({loadpath, subdir, path}, allocator)
}

// ctx temp alloc
asset_path_cstr :: proc(subdir: string, path: string, allocator := context.temp_allocator) -> cstring {
    return strings.clone_to_cstring(asset_path(subdir, path), allocator)
}

loadTexture :: proc(path: string) -> rl.Texture {
    fullpath := asset_path_cstr("textures", path)
    println("! loading texture: ", fullpath)
    return rl.LoadTexture(fullpath)
}

loadSound :: proc(path: string) -> rl.Sound {
    //if !rl.IsAudioDeviceReady() do return {}
    fullpath := asset_path_cstr("audio", path)
    println("! loading sound: ", fullpath)
    return rl.LoadSound(fullpath)
}

loadMusic :: proc(path: string) -> rl.Music {
    //if !rl.IsAudioDeviceReady() do return {}
    fullpath := asset_path_cstr("audio", path)
    println("! loading music: ", fullpath)
    return rl.LoadMusicStream(fullpath)
}

loadFont :: proc(path: string) -> rl.Font {
    fullpath := asset_path_cstr("fonts", path)
    println("! loading font: ", fullpath)
    return rl.LoadFontEx(fullpath, 32, nil, 0)
    //return rl.LoadFont(fullpath)
}

loadModel :: proc(path: string) -> rl.Model {
    fullpath := asset_path_cstr("models", path)
    println("! loading model: ", fullpath)
    return rl.LoadModel(fullpath)
}

loadModelAnim :: proc(path: string, outCount: ^u32) -> [^]rl.ModelAnimation {
    fullpath := asset_path_cstr("anim", path)
    println("! loading anim: ", fullpath)
    return rl.LoadModelAnimations(fullpath, outCount)
}

loadShader :: proc(vertpath: string, fragpath: string) -> rl.Shader {
    vertfullpath := asset_path_cstr("shaders", vertpath)
    fragfullpath := asset_path_cstr("shaders", fragpath)
    println("! loading shader: vert: ", vertfullpath, "frag:", fragfullpath)
    return rl.LoadShader(vertfullpath, fragfullpath)
}

// uses default vertex shader
loadFragShader :: proc(path: string) -> rl.Shader {
    fullpath := asset_path_cstr("shaders", path)
    println("! loading shader: ", fullpath)
    return rl.LoadShader(nil, fullpath)
}



playSound :: proc(sound: rl.Sound) {
    if !rl.IsAudioDeviceReady() do return
    rl.PlaySound(sound)
}

playSoundMulti :: proc(sound: rl.Sound) {
    if !rl.IsAudioDeviceReady() do return
    //rl.PlaySoundMulti(sound)
}

// rand vector with elements in -1..1
randVec3 :: proc() -> Vec3 {
    return(
        Vec3 {
            rand.float32_range(-1.0, 1.0, &randData),
            rand.float32_range(-1.0, 1.0, &randData),
            rand.float32_range(-1.0, 1.0, &randData),
        } \
    )
}

roundstep :: proc(a: f32, step: f32) -> f32 {
    return math.round(a * step) / step
}
