# HyperSpace Issue Log

## 2026-08-11 ? Present Mode gray / replace with stage pop-out

**Issue:** Present Mode opens a secondary window that is solid gray (no live scene). User needs the stage/preview undocked as a real OS window that can be dragged to a second monitor while left playlist + right effects sidebars stay on the main screen.

**Root cause:** Present created a borderless fullscreen `Window` with a `TextureRect` mirroring `OutputViewport.get_texture()`. In Godot 4 Forward+, a SubViewport texture already owned/displayed by `SubViewportContainer` often fails to composite correctly when also assigned to a TextureRect in another Window ? clear color / empty feed reads as gray. Forced fullscreen compounded the failure.

**Plan:**
1. Remove broken Present texture-mirror approach.
2. Pop out by reparenting the live `SubViewportContainer` (same SubViewport / EffectStack / stage) into a normal resizable OS `Window` (`embed_subwindows=false` already set).
3. Main window keeps playlist + effects sidebars and shows a dock placeholder in the center.
4. Esc / window close / Dock button reparents the stage back; F11 toggles pop-out.

**Resolution:** Replaced Present texture-mirror with Pop Out Stage: reparents `OutputViewportContainer` into a resizable OS `Window` ("HyperSpace ? Stage"). Main keeps playlists + effects and a Dock placeholder. Esc / F11 / close / Dock Stage reparents back. Trigger: **Pop Out Stage** button (preview header) or F11.

## 2026-08-11 ? Asset switch hitch / multi-second freezes

**Issues:** Every Env / Main / Scatter / Lighting change (manual apply or Play cycling) freezes the app for seconds. Transitions are not continuous.

**Root causes (profiled):**
1. Sync `load()` / `GLTFDocument.append_from_file` on main thread in `FlythroughLayerSlot` at apply time.
2. Env apply cascades path rebuild + full scatter rebuild + AABB walks in the same frame.
3. HDRI via sync `Image.load_from_file` + WorldEnvironment sky rebuild.
4. Media: sync GIF decode / `OS.execute(ffmpeg)` video convert / ffmpeg path probe on apply.
5. No path?PackedScene / texture cache ? cycling the same assets reloads from disk.
6. Playlist UI `_rebuild_all_lists()` destroys/recreates every row on each apply (including during Play).

**Plan:**
1. Add `AssetCache` (path ? PackedScene / Texture2D) with `ResourceLoader.load_threaded_*` + worker-thread GLTF/HDRI parse; keep previous layer until ready.
2. Isolate layer swaps; skip path rebuild when env AABB unchanged; stagger env?path?scatter across frames.
3. Cache HDRI/textures; non-blocking video convert when ogv missing; cache ffmpeg path.
4. Prefetch next Play items; skip full list rebuild during cycling (selection highlight only).
5. Defer media bind when cache miss so first frame stays live.

**Resolution:**
1. Added `core/asset_cache.gd` + poll host: path?PackedScene/Texture2D cache, `ResourceLoader.load_threaded_*` for imports, WorkerThreadPool for runtime GLB/HDRI image loads.
2. Flythrough layer swaps keep previous content until the new asset is ready; env?path?scatter is staggered; path rebuild skipped when AABB unchanged; scatter clones spawn ~4/frame.
3. HDRI apply is async (no sync `Image.load_from_file` on apply); textures/GIF/ffmpeg path cached; video convert is fire-and-forget (`OS.create_process`) when ogv missing.
4. Playlist Play: prefetch next 1?2 assets; selection highlight only (no full list rebuild) while autoplaying.

**Remaining gaps:** First-ever cold load of a huge GLB can still cost a frame or two when packing finishes (then cached). Scatter still briefly empties before staggered fill. GIF decode remains main-thread (cached after first). FBX outside Godot import may still sync-fail until imported.

## 2026-08-11 ? Performance: media + FX janky / slow

**Issues:** Show runs but feels slow/janky with GIFs, video screens, post-FX, noise, particles.

**Findings (likely hotspots):**
1. Video media_prop calls `Texture2D.get_image()` every frame at 1280?720 ? full GPU readback/sync.
2. Feedback LFX does the same every `frame_post_draw` at full output resolution.
3. GIF decode uses per-pixel `set_pixel` (very slow); no cache/downscale; up to 180 full-res frames ? textures.
4. Noise deform re-collects all MeshInstance3Ds and updates shader params every audio tick; FBM uses 4 octaves ? 4 noise evals per vertex.
5. Particle `amount` rewritten every audio frame (forces GPUParticles rebuild); beat `restart()`; high caps (1600?2000).
6. ReactivityHub does SceneTree node lookups for nearly every settings read.
7. Disabled glitch/pixel_sort still `set_process(true)` forever.
8. Scatter media already shares material via clones (good); still allow up to 80 clones + full-cost master decode.

**Plan:**
1. Throttle + downscale video frame pulls; share video decode host per path.
2. Cache/downscale/cap GIF frames; faster packed-byte blit in GifDecoder.
3. Throttle/shrink feedback history capture.
4. Cache noise mesh lists; cheaper noise shader; lower mesh limit.
5. Stabilize particle amounts; lower caps; throttle beat restarts.
6. Cache ReactivitySettings node; disable FX `_process` when off; cap media scatter count.

**Resolution:**
1. Video: `MediaVideoPool` shares one 640?360 decode + ImageTexture per path; pull capped ~18 Hz (was 1280?720 every frame).
2. GIF: path cache, =512px / =90 frames, packed-byte blit in GifDecoder, min frame dur 0.04s; scatter material still shared via clones.
3. Feedback: capture every 2nd frame, history resized =640.
4. Noise: 2-octave FBM, mesh-list cache, =48 meshes.
5. Particles: lower caps, amount hysteresis, beat restart cool-down.
6. ReactivityHub node/director cache; FX `_process` off when disabled; Scene3D viewport matches panel =1600?900; media scatter =24.

## 2026-08-11 ? GIFs red / not animated; playlist delete clipped; rotation defaults

**Issues:**
1. Still images work, but GIFs show as **red** error placeholder (bind failure). Videos may also fail / stay static. Need visible **animated** GIFs and playing mp4/webm/ogv on 3D media screens.
2. Playlist row delete is clipped/unreachable when asset names are long ? cannot remove media items.
3. Rotation amount default is **20** (too strong); rotation is **on by default**. Need default amount **1**, affect_rotation = false, and a **rotation target** chooser (everything / hero / environment / scatter / lights) like noise.

**Causes / plan:**
1. MediaImport depended on ffmpeg; without it GIF bind failed (red). AnimatedTexture does not animate as a spatial shader uniform. Fix: native GifDecoder + ImageTexture frame cycling; tools/ffmpeg for video?ogv.
2. Title button expand pushed replace/delete off-row. Fix: middle-ellipsis, clip_text, fixed-width shrink-end buttons.
3. Change defaults; add rotation_target + rotation_applies_to; UI OptionButton; wire flythrough.

**Resolution:**
1. GIF/video: Added core/gif_decoder.gd. media_prop cycles frames into ImageTexture. MediaImport finds tools/ffmpeg/ffmpeg.exe for mp4/webm?ogv. Portable ffmpeg installed locally (gitignored).
2. Playlist delete: Middle-ellipsis labels, clip_text, fixed-width replace/delete buttons.
3. Rotation: Defaults affect_rotation=false, rotation_amount=1; added rotation_target chooser + rotation_applies_to in flythrough.

## 2026-08-11 ? media_prop Vector2!=Vector2i crash; media still white

**Issues:**
1. Runtime error at `media_prop.gd` ~284: `Invalid operands "Vector2" and "Vector2i" for "!=" operator`. Broke script load ? `ReactivitySettings` null.
2. Uploaded images/GIFs/videos still appear solid white/light on 3D media screens.

**Resolution:** Fixed Vector2i cast compare; emission media shader + ImageTexture video blit + error charcoal/red placeholder.

## 2026-08-11 ? Schedule Active/Inactive timing inaccurate; media still solid white

**Issues:** Schedule timing drift; media white quads.
**Resolution:** FxAutomation phase gate rewrite; dedicated media shader + root video host SubViewport.

## 2026-08-11 ? Images load but appear completely white / blown out

**Resolution:** Media screen emission shader, EXPOSURE_COMP, media_screen skip for emission/noise.

## 2026-08-11 ? Active/Inactive dual-thumb unclear; LFX white / no-op

**Issues:**
1. Active / Inactive schedule timing uses one DualRangeSlider (two thumbs on one track). Hard to see how many seconds are active vs inactive; needs two separate sliders with second readouts.
2. LFX Glitch / Chromatic Aberration / Pixel Sorting still show a solid white preview (or do nothing) when enabled.

**Causes / plan:**
1. Replace schedule DualRange (Play All + per-effect/reactivity hosts) with two labeled HSliders (`Active (sec)`, `Inactive (sec)`) + live second labels; keep wiring to `FxAutomation.set_gate_active_inactive(active_sec, inactive_sec)` / existing gate ids. Leave ASCII density DualRange alone.
2. White LFX: opaque white ColorRect + `hint_screen_texture` inside Output SubViewport often samples empty/white when no per-layer `BackBufferCopy` (or when sampler/render_mode differs from working ASCII). Fix: per-effect `BackBufferCopy` before ColorRect; transparent ColorRect fallback; align glitch/chromatic/pixel_sort samplers with ASCII (`textureLod`, same hints); drop fragile `unshaded` if it fights screen sampling.

**Resolution:**
1. Added `ui/schedule_seconds_pair.gd` ? two HSliders with live `Active: N sec` / `Inactive: N sec` labels. Wired in Effects sidebar for Play All default schedule + every per-effect / reactivity schedule host (`FxAutomation.set_gate_active_inactive`). ASCII density DualRange unchanged.
2. Root cause of white LFX: Godot 4.7 rejects `return` inside `fragment()` ? glitch/chromatic/pixel_sort shaders failed to compile, leaving opaque/failed ColorRects white. Removed fragment early-returns; kept `textureLod` screen samples; per-layer `BackBufferCopy` + transparent ColorRect fallback in `EffectLayer` / ASCII.

## 2026-08-10 ? ReactivitySettings parser Indent error

**Issue:** Godot parser error in `autoload/reactivity_settings.gd` ~line 14: `Unexpected "Indent" in class body.` Autoload `ReactivitySettings` resolves to `<null>`.

**Cause:** `affect_emission` (and its preceding `##` doc comment) were indented with an extra tab inside the class body, which GDScript rejects outside of nested blocks.

**Plan:** Dedent those two lines to match sibling class members; scan the rest of the file for mixed-tab/indent issues.

**Resolution:** Aligned `##` comment and `var affect_emission` with other class-body members; no further indent issues found in the file.

## 2026-08-10 ? Washed lighting, hero glow, missing HDRI, tiny envs, fly speed

**Issues (user-blocked visuals):**
1. Textured meshes still look washed-out under flythrough lighting.
2. Hero (and scatter) textures barely visible ? strange glowing color tints.
3. HDRI skies/backgrounds not visible at all when selected in Lighting.
4. Small environment models appear tiny; flythrough does not read them.
5. No user-facing camera / fly-through speed control.
6. Camera path/framing should respect model scale.

**Causes (investigation):**
1. **Glow + fog + reactive colored lights:** `Environment.glow_*` stays aggressive from `_build_world`; fog always on and defaults affect the sky (`fog_sky_affect`); light reactivity HSV-shifts fill/sun every frame ? washed albedo.
2. **Hero/scatter emission drive:** Default `affect_emission=true` + target `all` still runs `_drive_mesh_emission(..., tint_albedo=true)` on centerpiece/scatter with high energy (up to ~9?) and HSV emission colors. Even without albedo tint, emission overwhelms authored textures. Primitives also bake non-zero emission into materials.
3. **HDRI invisible:** Fog remains enabled on the HDRI success path and washes the panorama toward `fog_light_color`; SubViewport used for 3D does not set `own_world_3d`, so WorldEnvironment/sky can fail to present as an isolated world background.
4. **Tiny envs:** File environments are loaded at authored scale; path is built from raw AABB with no normalize-to-target, so small scans/props yield tiny paths and an unreadable flythrough.
5. **Fly speed:** `fly_speed` exists on the rig/env but has no sidebar UI.

**Plan:**
1. Strip hero/scatter material emission/tint drives entirely; zero primitive emission; default `affect_emission` off; light reactivity = energy only (no hue wash). Soften/disable glow; stop fog from eating the sky.
2. HDRI path: `own_world_3d` on Scene3D SubViewport; `fog_sky_affect=0` / near-zero fog; ensure `BG_SKY` + panorama energy; milder ambient so IBL does not crush textures.
3. Auto-fit file environments to a target AABB longest axis; rebuild path from scaled bounds; tune camera far / scatter spread / framing from that scale.
4. Add Fly speed SpinBox in playlist sidebar header; wire via ShowDirector ? `set_cue_param("fly_speed")`.

**Resolution:**
- Removed all mesh emission/albedo-tint drives from flythrough env/hero/scatter; primitives no longer bake emission; `affect_emission` defaults off.
- Disabled glow; fog off by default / `fog_sky_affect=0`; HDRI uses visible panorama sky + milder ambient; Scene3D SubViewport `own_world_3d=true`.
- File envs auto-fit (~48u longest axis); path/framing/scatter spread follow scaled AABB; camera far scales with world.
- Playlist header **Fly speed** SpinBox ? `ShowDirector.set_active_cue_param("fly_speed")`.

## 2026-08-10 ? Environment `reflection_source` invalid assignment

**Issue:** Runtime error in `items/flythrough_environment.gd` ~line 238: `Invalid assignment of property or key 'reflection_source' with value of type 'int' on a base object of type 'Environment'.` Stack: main ? show_director ? scene3d_item ? flythrough_environment. Blocks lighting/environment setup.

**Cause:** Wrong property name. Godot 4.7 Environment exposes IBL specular as `reflected_light_source` (inspector group prefix `reflected_light_`), with methods `set_reflection_source` / `get_reflection_source`. Assigning `env.reflection_source` hits a non-existent key. Constants (`REFLECTION_SOURCE_*`) are correct.

**Plan:** Replace both `env.reflection_source = ?` assignments with `env.reflected_light_source`. Scan repo for the same typo; leave other Environment props alone if they match the docs.

**Resolution:** Fixed HDRI (`REFLECTION_SOURCE_SKY`) and procedural (`REFLECTION_SOURCE_DISABLED`) paths to use `reflected_light_source`. No other `.reflection_source` usages in the repo.

## 2026-08-08 ? playlist_sidebar.gd type inference (`px`)

**Issue:** Godot parser error in `ui/playlist_sidebar.gd` ~line 127: `Cannot infer the type of "px" variable because the value doesn't have a set type.` Same pattern for `py`. Blocks loading the playlist sidebar script.

**Cause:** In `_make_tab_icon` ("dots" shape), `for p in [Vector2i(...), ...]` iterates an untyped Array, so `p` is Variant. `var px := p.x + ox` / `var py := p.y + oy` cannot infer a concrete type from Variant member access.

**Plan:** Type the loop as `for p: Vector2i in [...]` and use explicit `var px: int` / `var py: int` (and harden sibling `:=` in the same helper if needed). Avoid Python `//`.

**Resolution:** Typed `p` as `Vector2i` and declared `px`/`py` as `int` in the dots icon blit loop.

## 2026-08-08 ? Playlist sidebar UX overhaul (timers, Lighting, icons, effects)

**Issue:** Left playlist/sidebar needs a major UX + behavior overhaul: remove global Play envs / Step sec header; give Env/Main/Scatter (and new Lighting) independent per-tab duration timers; fix autoplay that does not change environments after 8s; icon tabs; click-to-play rows with replace button (no per-row ?); right sidebar must hide (not disable) off sections; expand effects targeting so reactivity can affect env/main/scatter/lights.

**Cause (8s bug):** Global Step sec only wrote `ShowDirector.default_item_duration` while category cycling lived in the sidebar and required ? Play ? and only advanced the *active* tab. Env ?play? also wiped main+scatter on every step via `_play_environment`, so multi-layer stage state fought autoplay. Timing was not independent per layer.

**Plan:**
1. Strip global transport / Step sec / Active summary from playlist sidebar header.
2. Per-tab timer + Play/Stop at top of Env / Main / Scatter / Lighting; run independent `_process` timers that step each playing category.
3. Apply layer changes without clearing sibling layers; ensure `set_flythrough_layer` ? `set_layer_source` rebuilds env visuals.
4. Add Lighting tab + catalog presets; wire sun/sky/ambient into `FlythroughEnvironment`.
5. Icon tabs (`set_tab_icon` + tooltips); click row applies; right-side replace/swap button opens file picker.
6. Effects sidebar: hide nested bodies when toggles off; extend ReactivitySettings target to include Lights and gate light drive via `applies_to`.

**Resolution:** Removed global transport/Step sec header. Per-tab Play + duration timers advance Env/Main/Scatter/Lighting independently via `set_flythrough_layer` without wiping sibling layers. Added Lighting tab (procedural sun/sky presets) wired through ShowDirector ? FlythroughEnvironment. Icon tabs, click-to-apply rows with ? replace, effects accordion hide-when-off, and Reactivity target includes Lights.

## 2026-08-08 ? AsciiCharset unresolved (parser error)

**Issue:** Debugger at `ascii_effect.gd:156`: `Could not resolve class "AsciiCharset", because of a parser error.` Call site: `charset = AsciiCharset.filter_charset(charset)`.

**Cause:** Prior warning fix in `effects/ascii_charset.gd` used Python-style `//` for integer division (`pad_x`/`pad_y`). GDScript does not support `//`, so the script failed to parse and `class_name AsciiCharset` never registered.

**Plan:** Replace `//` with a Godot-safe pattern (`int(a / 2.0)`) so the script parses, the class registers, and pad math stays equivalent for these positive ints.

**Resolution:** Replaced `(CELL - gw * 2) // 2` (and `gh`) with `int((CELL - ?) / 2.0)` in `_blit_glyph`.

## 2026-08-08 ? EffectsSidebar @onready Node not found

**Issue:** Godot debugger spam: `effects_sidebar.gd` `@implicit_ready()` fails `get_node()` for many paths under `/root/Main/Root/EffectsSidebar` (e.g. `Margin/Column/AudioSection/ReactivityToggle`, `?/IntensitySlider`, Targets/ScaleSource, AxisRow, AffectLight, ?). C++: `node.cpp get_node()` ? nullptr. Related warnings: integer division (`ascii_charset.gd`), unused `_accent` (`flythrough_environment.gd`), param `name` shadowing `Node.name` (`effects_sidebar.gd`).

**Cause:** Scene tree was redesigned (`Margin/Scroll/Column`, param bodies under `ReactivityBody` / `AsciiBody` / etc., new driver OptionButtons) while the script still used pre-redesign `$Margin/Column/...` paths that no longer exist.

**Plan:** Align `@onready`/`$` paths with `effects_sidebar.tscn` (keep intended Scroll + gated bodies UI). Fix the three warnings with minimal edits.

**Resolution:** Script paths updated to `Margin/Scroll/Column/...` (and nested bodies); validated all 54 `@onready` paths against the `.tscn` (0 missing). Renamed `_select_camera_preset(name)` ? `preset`. Wired `_accent` into flythrough light color. Integer-division warning later fixed properly (see AsciiCharset unresolved entry ? `//` was invalid GDScript).

## 2026-08-08 ? Left assets UI: three tabs (env / main / scatter)

**Issue:** Left sidebar mixes a default demo playlist, fly-through layer rows, and element-sequence controls into one hard-to-read panel. User wants three clear asset tabs ? Environments, Main character, Scattering ? each playable on its own, and the default ?stuff? playlist removed.

**Plan:** Replace playlist + fly layer + element-sequence UI with a `TabContainer` of three category lists (from `FlythroughAssetCatalog` + File add). One shared fly-through stage; ? on a row applies that layer; tab Play cycles only that category. Stop loading demo `show.json` items on startup (empty/minimal stage). Drop element-sequence sidebar and default playlist contents.

**Resolution:** Left sidebar is now Environments / Main character / Scattering tabs. Row ? plays that category individually (env clears main+scatter; main clears scatter). Tab ? Play cycles assets in the active tab. Startup uses a blank fly-through stage ? demo playlist items removed from `shows/demo/show.json` and no longer auto-loaded. Empty centerpiece/scatter configs honored in `FlythroughEnvironment`.

## 2026-08-08 ? ASCII Live Visuals effects UX / play-over-time

**Issue:** HyperSpace effects sidebar always shows parameter controls and has no timed play-through. The user?s ASCII Live Visuals Engine (`vuxanov/ASCII` `index.html`) gates param UI behind ON toggles, auto-cycles style presets (?Style switch?), and uses effect schedules (cycle/active gates) so looks change over time. Also missing Glitch and extra ASCII styles from that app.

**Plan:** Study `index.html` (not just the simpler `ASCII ART GENERATOR.html`). Mirror: (1) hide effect param bodies unless enabled; (2) Style Switch = cycle ASCII presets on an interval; (3) per-effect schedule gates (cycle/active) + Play All master; (4) add Glitch post-process + Invert + a few more ASCII presets (Glitch/Pixel/Braille) that fit the glyph atlas.

**Resolution:** Mirrored ASCII Live Visuals Engine (`index.html`) patterns into HyperSpace: effect param bodies hide until toggle ON; Style Switch cycles ASCII presets on an interval (+ RND); per-effect schedule gates (cycle/active) plus Play All master; added Glitch post-process, Invert Density, and ASCII styles Dots/Glitch/Pixel/Braille. Automation lives in `FxAutomation`, ticked by `ShowDirector`.

## 2026-08-08 ? Playlist element sequence (main ? scatter)

**Issue:** Playlist could change backgrounds over time via item sequencing, but non-background fly-through elements (main character / scatter) lacked a timed progression and a clear chooser list. Desired UX: one main focal element, then scattered props that themselves change over the playlist timeline, picked from a list wired to real `3D models` assets.

**Plan:** Extend `FlythroughAssetCatalog` with labeled chooser entries (burger GLB + primitives). Store `params.element_sequence` on fly-through items (steps with duration + centerpiece/scatter configs). Advance steps during ShowDirector autoplay via existing `set_flythrough_layer`. Add Element Sequence UI in playlist sidebar (list + add-from-chooser). Demo show: street-city env, main burger ? burger scatter ? cube/sphere scatter.

**Resolution:** Implemented `element_sequence` on fly-through items; ShowDirector autoplay advances main?scatter steps without changing the environment layer. Playlist sidebar has Element sequence chooser (+ Main / + Scatter from catalog, Fill main?scatter preset). Demo show uses street-city + ex-convento envs with stylized burger props.

## 2026-08-08 ? Port ASCII app character presets

**Issue:** HyperSpace ASCII presets (Classic/Dense/Sparse/Amber/Neon/?) don?t match the user?s ASCII Art Generator app (`vuxanov/ASCII`). Need the same character presets: Standard, Blocks, Minimal, Binary, Matrix.

**Plan:** Read presets from `ASCII ART GENERATOR.html` via `gh`; reverse dark?bright ramps for HyperSpace?s luminance mapping (sparse?dense); add half-width katakana bitmaps for Matrix; wire preset names into `AsciiEffect.PRESETS` (UI already lists keys).

**Resolution:** Replaced presets with Standard / Blocks / Minimal / Binary / Matrix from `vuxanov/ASCII`. Density ramps reversed for HyperSpace overlay shader; Matrix uses the same half-width katakana set with new glyph bitmaps; legacy names (Classic, Dense, ?) alias to the new set. Added missing `1` glyph for Binary.

## 2026-08-08 ? Scale still weak; use real 3D assets

**Issue:** Scale reactivity still barely visible; fly-through defaulted to primitives instead of project `3D models` (street city, ex-convento scan, stylized burger).

**Plan:** Punchier `scale_multiplier` (lift quiet mic + integer Scale Amount); default/Test menus use street-city / chiostro env + burger scatter/main; FBX load via imported PackedScene; fit GLB size to camera.

## 2026-08-08 ? Camera moments feel like bad panning

**Issue:** Camera modulator ?moments? look bad ? dominated by left/right sine pan (yaw-only), which reads as cheap panning rather than cinematic motion.

**Plan:** Replace pan-style ModulatorBus presets with varied rotation styles (pitch, roll, multi-axis tumble/spiral, kick snap). Add roll offset through camera_rig so moments can rotate on more than yaw/pitch.

**Resolution:** Replaced presets (`Pitch rock`, `Roll bank`, `Orbit tumble`, `Spiral twist`, `Kick snap`). `ModulatorBus` now drives yaw/pitch/roll; `FlythroughCameraRig` applies roll. Legacy pan preset names remap to the new rotation set.

## 2026-08-08 ? Choosable reactivity + camera modulators

**Issue:** Scale/emission/rotation/lights were hard-mapped or broken; feedback trail invisible; particles mostly main-only; main character too far; needed per-property Off/audio-band/LFO drivers and camera LFO presets.

**Plan:** Kick band + `drive_value` sources; Effects sidebar ?driven by? pickers; ~10? scale; fix emission/color/rotation materials; real feedback history buffer; scatter+env particles; center closer (`~2.75`) + render priority; ModulatorBus camera presets shared as `lfo`.

## 2026-08-08 ? HTerrain looked like low-detail demo edges

**Issue:** Generated h-terrain felt soft/low-res (?demo edge?), flat colors, little mesh or texture detail.

**Plan:** Bump to 513 res + denser map_scale; multi-octave height + detail; remove edge bowl falloff; Classic4 shader; 256? procedural albedo/bump/normal ground maps; tighter UV scale.

## 2026-08-08 ? HTerrain plugin for fly-through landscapes

**Issue:** User added zylann.hterrain; wants generated terrain environments to try in fly-throughs.

**Plan:** Enable plugin; `FlythroughHTerrainBuilder` noise presets (hills/mountains/canyon); flight path samples heightmap; wire into Background Test menu + 3D Env presets; demo starts on hills.

## 2026-08-08 ? Particles target + real ASCII + emission/lights

**Issue:** Particles mostly only hit images; 3D look stuck; emission/lights barely changed; ASCII was a boxy pixelate, not characters. Feedback weak with particles.

**Plan:** `particles_target` (everything / main / environment / media); flythrough centerpiece+camera-following env particles; stronger HSV emission & light; ASCII glyph atlas + charset presets; stronger feedback smear so particle breakup trails.

## 2026-08-08 ? Playlist replace/DnD + fixed centerpiece

**Issue:** Hard to replace playlist items; unclear how to swap env/main/scatter; centerpiece flew along the path instead of staying visible on screen.

**Plan:** Click item name ? same Add Media dialog as replace; ? to play; drag ?? to reorder; OS file drop on row/list. Centerpiece camera-locked with slight idle motion. Clearer layer labels (Background / Scatter / Main character).

## 2026-08-08 ? Fly-through system (3 uploadable layers)

**Issue:** One-off corridor was too fast/disorienting/flashy. Need a reusable walkthrough system: shared path+camera, three separately uploadable layers (environment, scatter, centerpiece), calm defaults, test primitives + real file replace.

**Plan:** `FlythroughEnvironment` + path/camera/layer helpers; playlist layer File/Test controls; reactivity targets centerpiece|scatter|environment|all; demo uses primitives at speed 2.

## 2026-08-08 ? Prefer simple corridor over busy animated envs

**Issue:** User disliked the animated tunnel/city environments; wants a simple corridor fly-through first, with mouse/controller look-around. Full camera-path authoring later.

**Plan:** Add `CorridorEnvironment` (tube + auto forward motion + yaw/pitch look via mouse RMB / click-to-capture + gamepad right stick). Default env menu to Corridor; map old tunnel/city styles to corridor; simplify demo show.

## 2026-08-08 ? Feedback inert; ReactivitySettings missing; richer envs

**Issue:** Feedback trail did nothing (empty viewports). Images ignored particles/reactivity. `ReactivitySettings` identifier failed to compile in some loads. User wanted animated tunnel/city with separate environment vs foreground reactivity.

**Plan:** Screen-space feedback shader; ReactivityHub typed access; ImageItem particles/reactivity; TunnelEnvironment + CityFlyEnvironment dual-layer; target = foreground|environment|all.

## 2026-08-08 ? Menu blocking UI clicks (Godot node picker)

**Issue:** User couldn't click Effects sidebar; a popup listed `SensitivitySlider` / `AudioSection` / ? / `Main`.

**Cause:** Godot Editor Game/Remote **Select Mode** intercepts clicks to pick scene nodes, not app input.

## 2026-08-08 ? ReactivityHub / ReactivitySettings identifier not found

**Issue:** Godot 4.7 parse errors: global `class_name` / autoload identifiers not in scope for environment scripts.

**Plan:** Drop `class_name`; `preload("res://core/reactivity_hub.gd")` in each consumer; typed `scale_vec: Vector3`.

**Resolution:** Preload-based access; no global class dependency.

## 2026-08-08 ? Variant inference on mesh/particles rotate

**Issue:** `var rotating := _mesh if ... else _particles` mixed `MeshInstance3D` / `GPUParticles3D`, inferred as Variant (error under Godot 4.7 strict typing).

**Plan:** Split into typed branches instead of a shared ternary.

**Resolution:** Separate rotate paths for mesh vs particles mode.

## 2026-08-08 ? Playlist overlay, autoplay, import, particles-from-mesh

**Issue:** Switching playlist items crossfaded without hiding the old item (looked like overlay). Needed autoplay + per-item duration, single auto-detect import (GIF/video/3D/image), numeric scale amount, and particles emitted from 3D objects (mesh ? particles).

**Plan:** Force replace/CUT on switch; ShowDirector autoplay timer; unified Add Media; SpinBox scale; DemoEnvironment dissolves mesh into GPUParticles3D when particles effect is on.

**Resolution:** Done ? replace on switch, autoplay + durations, single Add Media, numeric scale, mesh?particles.

## 2026-08-08 ? UI/effects/reactivity overhaul

**Issue:** ASCII couldn't turn off (disabled flag set but layer stayed visible). Particles called `set_anchors_preset` on GPUParticles2D. Demo used `look_at` before in-tree. SubViewport size conflict with stretch. User needed playlist|preview|effects layout, projector Present window, delete buttons, reactivity master + axis targets, ASCII presets.

**Plan:** Fix effect `set_active`, three-column layout, present Window sharing viewport texture, ReactivitySettings autoload, ASCII presets.

**Resolution:** Implemented; Present Mode keeps control UI while projector window shows output only.

## 2026-08-08 ? Performer UI not visible

**Issue:** Control panel lived in a separate `Window` that sat behind the large main output window, so it looked like only the visuals were running.

**Plan:** Embed performer UI in the main window (left) with live output preview (right). F11 toggles output-only fullscreen for shows.

**Resolution:** Single window split view; no separate buried control Window.

## 2026-08-08 ? Mic audio duplicated through speakers

**Issue:** Microphone capture bus (`HyperSpaceAnalysis`) was still sending to Master, so Godot played the input back (echo / "duplicated" audio).

**Resolution:** Mute `HyperSpaceAnalysis` bus. New split performer UI (playlist left / effects right) with add/remove media. Mesh scale driven by bass+energy.

## 2026-08-08 ? AudioEffectSpectrumAnalyzer tap_db / tap_back_pos runtime error

**Issue:** `_setup_audio_bus` assigned removed properties (`tap_db`, then `tap_back_pos`). Godot 4.7 only exposes `buffer_length` and `fft_size`.

**Plan:** Configure only those two properties.

**Resolution:** Removed invalid property assignments.

## 2026-08-08 ? Autoload parse errors in Godot 4.7

**Issue:** Project failed to load autoloads:
1. `audio_analyzer.gd` ? treated `get_magnitude_for_frequency_range()` return as an array; API returns a single `Vector2`, so `.size()` failed.
2. `show_director.gd` / `kinect_manager.gd` ? `:=` inferred from `Variant` (`call()`, `Dictionary.get()`); Godot 4.7 treats this as an error.

**Plan:** Query FFT in per-band frequency ranges; add explicit typed casts for Variant returns.

**Resolution:** Fixed `audio_analyzer.gd` band queries; typed casts in `show_director.gd` and `kinect_manager.gd`. Enabled `audio/driver/enable_input` for mic capture.

## 2026-08-08 ? Godot CLI not on PATH

**Issue:** Godot executable not found in system PATH during scaffolding.

**Plan:** Project files (`project.godot`, scripts, scenes) created manually. User opens project in Godot Editor to run/export.

**Resolution:** Document in README; no blocker for development in Cursor.

## 2026-08-10 ? Playlist/asset Delete does nothing

**Issue:** ? Delete on Env / Main / Scatter / Lighting rows does not remove items (or appears broken).

**Cause:** In `playlist_sidebar.gd` `_rebuild_list`, delete is `disabled` unless `entry.user_added` is true. Catalog presets never set that flag, so ? is grayed out for almost every row. Even for user-added rows, `_remove_entry` only spliced the working list and never cleared the applied stage layer when the deleted row was active.

**Plan:**
1. Enable ? for all working-list rows (session remove from the tab list).
2. On remove: if the row was selected / applied, clear that layer on the fly-through stage (empty main/scatter, fallback env, default lighting) via `ShowDirector.set_flythrough_layer`.
3. Clamp selection indices after remove and rebuild UI.

**Resolution:** ? enabled for all rows. `_remove_entry` removes from the tab?s working list; if that row was selected, `_clear_stage_layer` clears env/main/scatter/lighting on the active fly-through stage.

## 2026-08-10 ? Harsh blue / colored lighting; need real HDRIs

**Issue:** Lighting tab only offers procedural sun/sky color presets. Ambient + fill lean blue (`_accent` lerps toward blue; several presets use strong blue skies), so materials/textures look washed and color-cast instead of reading correctly under IBL.

**Plan:**
1. Download CC0 Poly Haven HDRIs (1k `.hdr`) into `assets/hdris/` with attribution note.
2. Add HDRI lighting chooser entries; apply via `PanoramaSkyMaterial` on `WorldEnvironment` (BG_SKY + AMBIENT_SOURCE_SKY, tonemap).
3. When an HDRI is active, reduce directional/fill energy and drop the blue fill bias so IBL dominates.
4. Soften default studio ambient toward neutral gray.

**Resolution:** Added five Poly Haven 1k HDRIs under `assets/hdris/` (see ATTRIBUTION.md). Lighting tab lists them; apply sets panorama sky + sky ambient IBL, softens sun/fill, uses ACES tonemap, and neutralizes fill tint. Default ?Studio fill? ambient made gray. ?+ File (HDRI)? enabled for custom `.hdr`/`.exr`.

## 2026-08-10 ? Hero / scatter models lose textures (flat override colors)

**Issue:** Main character (centerpiece) and scattered prop models show forced flat/overridden colors instead of the textures embedded in the GLB/FBX.

**Cause:**
1. `_raise_centerpiece_priority` always calls `_ensure_override_material`, which replaces meshes with a single `material_override`. Non-`StandardMaterial3D` imports (e.g. `ORMMaterial3D`) fall through to a flat gray-blue albedo (`0.7, 0.75, 0.85`), wiping textures. Even for Standard materials, one override collapses multi-surface textured meshes.
2. Default reactivity has emission ON + target `all`, so `_drive_mesh_emission(..., tint_albedo=true)` runs every frame on centerpiece and scatter, again forcing overrides and lerping `albedo_color` toward HSV tints (multiplies over / replaces textured look).

**Plan:**
1. Raise centerpiece draw priority via per-surface material duplicates (or existing override) ? never invent a flat-color override.
2. Drive emission per surface / existing BaseMaterial3D without collapsing multi-materials; only tint albedo when there is no albedo texture (primitives still get color feedback).
3. Keep untextured fallback color only when a mesh truly has no BaseMaterial3D.

**Resolution:** Fixed in `items/flythrough_environment.gd`: `_raise_centerpiece_priority` now bumps `render_priority` on duplicated per-surface materials (or existing overrides) instead of inventing a flat `material_override`. Emission reactivity drives `BaseMaterial3D` per surface without collapsing multi-materials, and only lerps `albedo_color` when `albedo_texture` is null so textured GLB/FBX props keep their maps.

## 2026-08-10 ? Env scale, dead reactivity, ASCII nesting, new FX

**Issues:**
1. Per-environment scale missing; auto-fit leaves mid-size assets inconsistent so some stay tiny/huge; reactive scale resets `_env_root.scale` to ONE and can push env out of view.
2. Noise-distort warp effect missing (with env/main/scatter/lights target chooser).
3. Sidebar Lights / Emission-Color / Rotation appear dead ? emission/color drives were stripped from flythrough; rotation amounts too subtle; lights gated oddly.
4. ASCII style-switch + related settings sit outside ASCII accordion; density floor (20) too high; need min?max density range down to ~1.
5. Want stronger glitch + chromatic aberration + pixel-sort (approx OK) in effects pipeline.

**Plan:**
1. Always normalize file envs to target longest axis; store `user_scale` on env layer config; apply via `_env_root`; rebuild path/framing on scale change; Env Scale SpinBox in playlist.
2. Add `affect_noise` (+ amount/speed/source) in ReactivitySettings; FastNoiseLite offset/warp on chosen layers; light energy jitter for lights.
3. Re-enable emission/color drive when toggled (per-surface, no albedo tint if textured); amplify rotation; lights react when target includes lights/all (and Affect Light on).
4. Nest Style Switch under AsciiBody; density_min/density_max (1?200) with audio lerp; update ascii shader range.
5. Extend glitch shader; add `chromatic` + `pixel_sort` EffectLayers + sidebar toggles; register in EffectStack / Play All.

**Resolution:**
1. Auto-fit always normalizes file envs to ~48u; `user_scale` on env layer + playlist **Env scale** SpinBox; path/framing/scatter rebuild on scale; reactive env scale clamped so worlds stay in view.
2. **Noise Distort** reactivity (target/source/amount/speed) warps env/main/scatter transforms; lights get energy jitter.
3. Re-enabled per-surface emission/color when Affect Emission is on (default off; no albedo tint on textured mats); stronger rotation; lights drive when target includes Lights/Everything.
4. Style Switch nested under ASCII Preset; density min/max range (1?200) with audio lerp.
5. Glitch extended (slice chaos); added Chromatic Aberration + Pixel Sort (GPU approximate) to effect stack/sidebar.

## 2026-08-10 ? Flythrough stuck, fake noise, white post-FX, sidebar scroll

**Issues:**
1. Flythrough camera/path no longer advances (feels stuck) after env-scale/path rebuild work.
2. Noise distort only jitters node transforms ? not real mesh/noise deformation; UI exposes Noise Speed instead of Noise Scale (spatial feature size).
3. New post FX (glitch/chromatic/pixel sort) turn the whole preview white.
4. Effects sidebar cannot scroll far enough ? last controls (e.g. Pixel Sort) clipped with no bottom padding.

**Causes / plan:**
1. Path rebuild always resets progress (`set_curve(..., true)`); fly_speed is absolute while AABB/user_scale can make paths very long so motion is imperceptible. Fix: preserve path fraction on scale rebuilds; scale advance by path length vs ~40u reference; keep `camera.current`.
2. Replace transform jitter with a spatial vertex-displace shader on target meshes; rename `noise_speed` ? `noise_scale` (feature size); drive amount from audio.
3. New `.gdshader` files used GDScript `##` doc comments ? invalid in shading language ? shader fail ? opaque white ColorRect. Fix `##` ? `//`; add per-layer `BackBufferCopy` before ColorRect for reliable `hint_screen_texture`.
4. Add bottom spacer / larger scroll margin so expanded FX bodies can scroll fully into view.

**Resolution:**
1. Camera rig scales advance by path length vs ~40u; path rebuilds preserve progress on env scale; env path `min_half` capped; `camera.current` enforced; Scene3DItem re-enables process on start.
2. Replaced transform jitter with `effects/noise_deform.gdshader` vertex displace on target meshes; UI/settings `noise_speed` ? `noise_scale` (feature size).
3. Fixed invalid `##` comments in glitch/chromatic/pixel_sort shaders (compile fail ? white ColorRect); each effect layer gets `BackBufferCopy` before the screen ColorRect.
4. Effects sidebar: larger bottom margin, `BottomPad` spacer, Column `size_flags_vertical=0` so scroll content height is correct.

## 2026-08-10 ? Env scale noop, weak FX, fake pixel-sort/noise, particle center spawn

**Issues (user feedback):**
1. Env scale SpinBox does not visibly scale the environment.
2. UI spinboxes/sliders show decimals ? want whole numbers only (step 1).
3. Effects too weak (fly speed, noise, glitch, chromatic, reactivity) ? crank ranges/defaults.
4. Pixel sort is fake RGB streak smear, not real thresholded luminance sorting.
5. Noise distort barely/not warping walls ? need visible vertex displace; verify materials survive rebuild.
6. Particles always spawn at hero/center regardless of target ? Everything should particle-ize all targeted meshes.

**Causes / plan:**
1. `set_environment_user_scale` rebuilds path from scaled AABB (`compute_aabb` includes `_env_root.scale`), so camera path grows with the mesh and relative size stays constant. Fix: path/framing AABB ignore `user_scale` (fit-only); scale only the env mesh/root.
2. Set playlist/effects controls to step=1, integer mins/maxes; map 0?100 style UI into stronger internal drives where needed.
3. Raise fly_speed default/max and path advance responsiveness; raise noise/scale/glitch/chromatic/pixel-sort ranges and shader/drive multipliers.
4. Replace pixel-sort shader with thresholded row rank-sort (scan spans by luminance, remap by brightness rank).
5. Rewrite noise deform to multi-axis world displace with much larger amount; keep Noise Scale as feature size; stop clearing/fighting overrides; multiply amount for large env meshes.
6. Bind GPUParticles3D to mesh vertex emission for env/main/scatter; hide solid meshes when particleized; Everything = all layers emit from their geometry.

**Resolution:**
1. `rotation_amount` + `rotation_x/y/z` in ReactivitySettings; hub `rotation_rate` / `rotation_axis_mask`; flythrough + demo apply multi-axis spin scaled by amount.
2. Active/Inactive DualRange schedules under Scale, Lights, Emission, Rotation, Noise via FxAutomation gates `react_*`; `property_active` requires `schedule_open`.
3. Post-FX schedules unchanged; Play All disable skips `react_*` gates.

**Resolution:**
1. Env path/framing AABB now ignores `user_scale` (`_fit_aabb_ignoring_user_scale`); scale only changes `_env_root.scale` so the mesh visibly grows/shrinks vs a fixed camera path. Scale SpinBox is integer 1?20.
2. Playlist + effects sidebar controls switched to step=1 / whole-number ranges (fly speed, durations, noise, glitch, chromatic, pixel sort, LFO, etc.).
3. Fly speed default 12 (max 100), uncapped path speed scaling; reactivity/noise/light/rotation multipliers raised; post-FX shaders + UI mapping much stronger.
4. Pixel sort replaced with thresholded horizontal luminance rank-sort (real interval sort aesthetic).
5. Noise deform: multi-axis + normal displace, amount in world units (default 18), materials reapplied each frame on target meshes; rebuilds skip particle nodes so overrides persist.
6. Particles emit from mesh vertices of targeted layers (`EMISSION_SHAPE_POINTS`); solid meshes hide when particleized; Everything = env+main+scatter; removed camera-centered box spawn.

## 2026-08-10 ? Post-FX / reactivity polish (pixel sort white, lights, noise, wireframe)

**Issues:**
1. Pixel sort washes the whole screen white instead of sorting pixels.
2. Glitch + chromatic still too subtle at mid slider values.
3. Lights energy does nothing meaningful ? lighting is HDRI-driven.
4. Rotation / Emission color appear to do nothing.
5. Noise naming confusing; weak audio reactivity; need Noise X/Y/Z like Scale.
6. Need a wireframe view effect toggle.
7. Every effect should be driveable by Audio or LFO (not just always-weak audio).

**Plan:**
1. Rewrite pixel-sort shader to a lighter, reliable threshold streak/sort with BackBufferCopy + blend that never falls back to solid white ColorRect.
2. Raise glitch/chromatic shader offsets and UI?param mapping so mid settings are obvious.
3. Wire Affect Lights / light energy to WorldEnvironment sky/panorama/ambient/background energy (HDRI brightness), not only Omni/Directional lights.
4. Fix rotation with much higher angular drive; make emission visibly drive mesh emission + ambient tint, or remove if still pointless.
5. Rename noise strength; boost AudioAnalyzer band mapping + noise drive; add noise_x/y/z axis toggles into deform shader.
6. Add wireframe effect via SubViewport DEBUG_DRAW_WIREFRAME on Scene3DItem.
7. Add per-effect drive mode (Audio / LFO / Manual) OptionButtons that actually modulate intensity.

**Resolution:**
1. Pixel sort rewritten (lighter MAX_SPAN=48 loops, unshaded, backbuffer guard) so failed/heavy shaders no longer leave a white ColorRect.
2. Glitch/chromatic shaders + UI mapping cranked (larger RGB offsets / row shifts; stronger defaults).
3. Affect Lights now scales HDRI panorama/sky energy, ambient, and background energy (plus sun/fill).
4. Rotation rates raised; Emission/Color also tints ambient and boosts mesh emission energy.
5. Noise renamed to Displace Strength; Noise X/Y/Z axes; stronger audio mapping via perceptual FFT lift + drive_value curve.
6. Wireframe effect toggles SubViewport DEBUG_DRAW_WIREFRAME on Scene3DItem.
7. Per-effect Drive = Audio / LFO / Manual OptionButtons wired through EffectLayer.resolve_drive.

## 2026-08-11 ? Part B polish: white FX, ASCII density, schedules, feedback, noise/terrain

**Issues:**
1. Style Switch cycles overwrite ASCII density min/max; need density independence + Random density toggle; dual-handle density range.
2. Per-effect schedules incomplete (no Active/Inactive intervals, wireframe missing schedule).
3. Glitch / chromatic / pixel-sort still whitewash the preview (shader/backbuffer/ColorRect).
4. Feedback: Manual mix/persistence ignored (audio path overwrites); LFO mode dead when camera LFO is Off; Audio too sensitive; confusing Drive labeling.
5. Noise distort skips hterrain; rotation too strong off-terrain / disabled on terrain; need clear amount control.
6. Shared audio reactivity oversensitive ? need usable sensitivity.

**Plan:**
1. Add reusable `DualRangeSlider`; ASCII density uses it; style cycle preserves user min/max; Random toggle randomizes on ticks.
2. Extend FxAutomation + per-effect Active/Inactive dual ranges (incl. wireframe); Play All uses same model.
3. Post-FX: transparent ColorRect fallback, remove fragile BackBufferCopy, harden shaders to always pass through scene.
4. Feedback stores base mix/persistence; Manual/LFO/Audio respect mode + sensitivity; rename Drive?Mode; keep LFO mod01 alive without camera preset.
5. Terrain: transform-based displace + slow orbit; tone down mesh rotation multipliers; strengthen noise amount mapping.
6. Keep Band Sensitivity + feedback audio sensitivity wired into analyzer/effect drives.

**Resolution:**
1. `DualRangeSlider` widget for ASCII density + per-effect Active/Inactive schedules (incl. wireframe); Style Switch preserves density; Random density toggle randomizes on ticks.
2. Post-FX: removed BackBufferCopy; transparent ColorRect fallback; glitch/chromatic/pixel_sort shaders hardened to always pass through scene.
3. Feedback: Manual keeps mix/persistence; LFO modulates from user bases (LFO always runs even if camera Off); Audio uses sensitivity slider; Drive labels renamed to Mode.
4. Terrain noise via root wobble (HTerrain has no MeshInstance3D); slow terrain orbit; toned-down hero/scatter rotation; Displace Strength = how much.
5. Band Sensitivity scaled down; shared drive_value curve softened.

## 2026-08-11 ? Rotation amount/axes + reactivity schedules

**Issue:** Rotation reactivity lacks Scale Amount?style strength and X/Y/Z axis toggles (only Y spin). Noise, Scale, Rotation, Lights, and Emission also lack Active/Inactive schedules that post-FX already have via DualRangeSlider + FxAutomation gates.

**Plan:**
1. Add `rotation_amount` + `rotation_x/y/z` to ReactivitySettings; hub accessors + `rotation_rate` / `rotation_axis_mask`; apply multi-axis rotation scaled by amount in flythrough (and demo) envs.
2. Reuse FxAutomation gates (`react_scale`, `react_rotation`, `react_noise`, `react_light`, `react_emission`) with DualRange Active/Inactive UI under each Targets section; `property_active` requires gate open so drives are off during inactive windows.
3. Keep existing post-effect schedules unchanged; integer UI for new amount/schedule controls.

**Resolution:**
1. `rotation_amount` + `rotation_x/y/z` in ReactivitySettings; hub `rotation_rate` / `rotation_axis_mask`; flythrough + demo apply multi-axis spin scaled by amount.
2. Active/Inactive DualRange schedules under Scale, Lights, Emission, Rotation, Noise via FxAutomation gates `react_*`; `property_active` requires `schedule_open`.
3. Post-FX schedules unchanged; Play All disable skips `react_*` gates.

## 2026-08-11 ? Present mode secondary window + Xbox playlist cycling

**Issue:**
1. Present mode does not let the user exit cleanly (Escape). Present should open a UI-less projector window while the main editor keeps its UI for live tweaks; Escape / close should leave present and restore focus.
2. Xbox/gamepad should also cycle playlist layers (not only camera look): D-pad L/R = Main, D-pad U/D = Environments, LB/RB = Scatter, edge-triggered.

**Cause:**
1. Present Window may not show/handle Escape when it has focus (input only on main Control); subwindows may be embedded instead of real OS windows; close path does not re-focus editor.
2. Camera rig reads right stick only; no joypad button handlers wired to playlist layer apply APIs.

**Plan:**
1. Harden present window: non-embedded OS Window, second screen, fullscreen/borderless, mirror SubViewport texture, Escape + close_requested exit, re-focus main.
2. Add playlist_sidebar cycle_* APIs mirroring click-to-apply; edge-trigger D-pad + shoulders in main.gd (works while presenting).

**Resolution:**
1. Present: real OS Window (embed_subwindows=false), borderless fullscreen on secondary screen, mirrors OutputViewport texture; Escape/F11 + close_requested exit and re-focus editor; button toggles Close Present.
2. Xbox: edge-triggered D-pad L/R ? Main, U/D ? Env, LB/RB ? Scatter via playlist_sidebar.cycle_* ? _step_tab / click-to-apply path; polled in _process so it works while Present is focused.

## 2026-08-11 ? Schedules mute fail, rotation axes, post-FX, ASCII LFO, Manual?Auto, Play All

**Issues (user-reported):**
1. Noise/scale/rotation/etc. schedules do nothing ? effects stay always on; rotation schedule ignored (spin continues). Dual-range Active/Inactive may be missing/unusable.
2. Rotation X/Y/Z toggles do not change which axes spin.
3. Glitch / chromatic / pixel-sort broken again (white or no-op).
4. ASCII density needs LFO between user min/max with waveform types (sine/tri/saw/square).
5. Rename effect Mode "Manual" ? "Auto" (compat for saved "manual").
6. "Play All (style + schedules)" does nothing meaningful.

**Causes:**
1. When rotation schedule gate closes, `property_active("rotation")` is false so idle `rotate_y` kicks in ? inactive windows still spin. Schedule DualRanges exist at runtime but need expand sizing.
2. Absolute Euler accum + idle-Y fallback masks axis masks; demo always falls back to Y spin when inactive.
3. Post-FX shaders use `texture()` on `hint_screen_texture` (mip/white risk) vs ASCII `textureLod(..., 0.0)`.
4. Density LFO uses shared sine `mod01` only ? no wave types / dedicated density oscillator.
5. Labels/ids still `Manual` / `manual`.
6. Play All sets style toggle under `_syncing_ui` (handler no-ops); orphan cycle/active HSliders unused; if no FX on, gates arm but nothing shows.

**Plan:**
1. Mute idle spin whenever `affect_rotation`; gate-closed = freeze. Ensure DualRange hosts visible/expand. Harden `schedule_open` path.
2. Apply `rotate_x/y/z` from `rotation_axis_mask` end-to-end (flythrough + demo).
3. Rewrite glitch/chromatic/pixel_sort to `textureLod` + `repeat_disable`; match ASCII ColorRect setup.
4. ASCII density LFO between min/max with sine/triangle/saw/square OptionButton.
5. FX drive id `auto` / label Auto; accept legacy `manual`.
6. Play All: force style+schedules for enabled FX (bootstrap ASCII if none), wire DualRange times, ignore stale HSliders.

**Resolution:**
1. Schedules: DualRange Active/Inactive expand-fill under each react/FX schedule host (default 4s/4s). Rotation inactive no longer falls back to idle Y ? mute when `affect_rotation` is on / schedule closed. `property_active` still requires `schedule_open`.
2. Rotation axes: flythrough/demo apply `rotate_x/y/z` from `rotation_axis_mask` with a quiet-band floor so toggles are obvious.
3. Post-FX: glitch/chromatic/pixel_sort use `textureLod(..., 0.0)` + `repeat_disable`; ColorRect matches ASCII (opaque + full replace).
4. ASCII Mode=LFO: density oscillates between user min/max; wave OptionButton (sine/triangle/saw/square) + rate Hz.
5. Mode label/id `Auto` / `auto`; legacy `manual` normalized to auto in `EffectLayer`.
6. Play All: bootstraps ASCII if nothing on; explicitly enables style switch + per-effect gates/DualRanges; ignores unused HSliders; refreshes effects on toggle.

## 2026-08-11 ? Autosave / restore playlist session

**Issue:** Playlist sidebar state (env/main/scatter/lighting lists, selections, scales, timers, applied layers) is lost on restart. Only blank stage boots; user expects the project to reopen looking like the last session.

**Cause:** Startup always calls `_start_blank_stage()`; catalog lists reload from defaults; no persist path for sidebar working lists or stage params beyond optional show.json (demo items empty, not written on change).

**Plan:**
1. Add `core/session_store.gd` writing `user://hyperspace_session.json` (sidebar lists + selections + timers/scale/speed + stage PlaylistItem params).
2. Autosave from playlist sidebar on meaningful changes (debounced) and on exit.
3. On start: restore session after bind/defaults so last session overrides blank/demo catalog; keep demo `show.json` loadable separately.
4. `PlaylistItem.to_dict()` for round-trip serialization.

**Resolution:** Autosave + restore via ``user://hyperspace_session.json`` (``SessionStore``). Playlist sidebar debounces saves on list/layer/timer/scale changes and on window close; Main restores stage items after bind (overriding blank defaults). Demo ``show.json`` untouched. Files: ``core/session_store.gd``, ``core/playlist_item.gd``, ``ui/playlist_sidebar.gd``, ``ui/main.gd``, ``autoload/show_director.gd``.

## 2026-08-11 ? GIF/video as 3D playlist layers + multi-select uploads

**Issue:** Playlist Env / Main / Scatter only accepted 3D models; GIFs and videos could not be added as flythrough props. File dialogs were single-select only.

**Cause:** `LayerFileDialog` filters and `FlythroughLayerSlot.is_file_path` only covered glb/gltf/fbx/tscn; no reusable 3D media screen for image/GIF/video textures.

**Plan:**
1. `FILE_MODE_OPEN_FILES` + `files_selected` on playlist (and performer) file dialogs; expand filters to images/GIF/video.
2. Add `FlythroughMediaProp` (quad + still texture or SubViewport `VideoStreamPlayer`); spawn via `FlythroughLayerSlot` for media paths on env/main/scatter (shared video texture for scatter clones).
3. `MediaImport`: detect media, convert GIF/non-ogv video to ogv via ffmpeg when available; persist paths in existing session entry configs.

**Resolution:** Multi-select add/replace for Env/Main/Scatter/Lighting (+ performer image/video). GIF/video/image spawn as looping 3D screens through existing layer paths; session autosave already stores entry `config.path` + applied layers.

## 2026-08-11 ? Playlist stuck on same item (tab Play / advancement)

**Issue:** Playlist / flythrough tab Play appears to stop advancing ? stays stuck on the same env/main/scatter/light instead of cycling.

**Causes (investigation):**
1. After each `_step_tab` apply, `_apply_*` reassigns selection via `_index_of_config` / `_index_of_lighting`. Match failure ? `sel = -1` ? next tick always plays index 0 (stuck). Wrong match ? selection snaps back to an earlier entry so the next step re-applies the same asset.
2. `_on_item_changed` ignores `_suppress_playlist_ui` and always `_sync_selection_from_stage()`, which can overwrite the intentional autoplay index mid-apply (e.g. `_ensure_stage` ? `play_index`).
3. Session-restored durations via `set_value_no_signal` can bypass SpinBox min/max; unclamped / absurd step times make cycling look frozen.
4. ShowDirector `autoplay` is never enabled from UI (tab Play forces it off); single-item `next_item` would full-rebuild the stage if it were on.

**Plan:**
1. Trust the intentional list index on apply/step; do not overwrite selection with a failed config rematch.
2. Skip stage?selection sync while suppressing UI or any tab autoplay is running.
3. Clamp per-tab durations; on Play start, step once immediately so advancement is visible.
4. Soft-loop ShowDirector autoplay when only one playlist item (reset timers / element sequence without `next_item` rebuild).

**Resolution:**
1. Tab apply/step trusts intentional list index (`force_sel`); config rematch no longer clears selection to `-1`.
2. `_on_item_changed` / `_on_playlist_changed` skip stage?selection sync while suppressing UI or any tab autoplay is running.
3. Per-tab durations clamped to 1?600s (including session restore); Play starts by stepping once immediately.
4. ShowDirector autoplay soft-loops a single playlist item / element sequence without `next_item` stage rebuild.


## 2026-08-11 ? Effects sidebar layout / Play All / camera rotation / defaults (investigation)

**Issues:**
1. Targets (Scale/Lights/Emission/Rotation/Noise/Camera) are flat siblings under `Targets` ? no `*Body` accordion nesting like FxSection; controls stay visible via `_sync_conditional_ui` hide/show only.
2. Play All bootstraps only ASCII when nothing is on; `set_play_all_effects` only schedules already-enabled FX ? so only ASCII plays.
3. Rotation target has no Camera option; flythrough never applies `rotation_applies_to("camera")` ? camera motion is separate ModulatorBus presets only.
4. Defaults: `enabled`, `affect_scale`, `affect_light` are true (tscn + ReactivitySettings); user wants all off.
5. Camera section lacks amount/speed naming consistency; Feedback LFO rate cross-writes `camera_rate`.

**Plan:** See Effects sidebar implementation checklist (nest Bodies; add camera rotation target + apply; defaults off; Camera motion amount/speed + nested rotation; Play All enables all FX + random/audio/speed/own scheduler).

## 2026-08-11 ? Effects panel: terrain noise, sidebar consistency, Play All, defaults

**Issues:**
1. Noise Displace does not visibly warp HTerrain hills ? only root wobble; MeshInstance ShaderMaterial overrides never reach DirectMeshInstance chunks.
2. Right sidebar effects/reactivity controls are flat siblings (not nested under each effect accordion); Scale Amount orphaned under Audio Reactivity; Camera motion not a uniform section; patterns differ across effects.
3. Rotation target lacks Camera; camera motion has no amount/speed + nested rotation drive.
4. Defaults: Scale / Lights / Audio Reactivity start ON ? should all be OFF for new installs / default settings.
5. Play All only bootstraps ASCII (and schedules already-on effects) ? must enable all visual FX + random/audio/speed + own Active/Inactive schedule.

**Plan:**
1. Custom HTerrain shader (Classic4 + vertex noise uniforms); drive via `set_shader_param` from flythrough `_apply_noise_distort`.
2. Nest each Targets effect's controls under Body VBoxes; move Scale Amount under Scale; Camera motion section with rate/depth/amount + camera rotation nested; align Mode/schedule patterns.
3. Add `camera` to `rotation_target` / `rotation_applies_to`; apply via camera_rig / flythrough.
4. Defaults: `enabled`, `affect_scale`, `affect_light` = false in `reactivity_settings.gd` + tscn checkboxes.
5. Play All: force-enable all FX_IDS, random + audio-reactive + speed controls, dedicated schedule gate; wire `fx_automation` / ShowDirector.

**Resolution:**
1. Terrain noise: Classic4 `simple4.gdshader` gains `u_hs_noise_*` vertex displace; flythrough drives via `set_shader_param` (no root wobble).
2. Sidebar: Scale/Light/Emission/Rotation/Noise nest under Body accordions; Scale Amount under Scale; Camera motion section with Speed/Amount + nested Rotation (camera); Mode labels aligned.
3. Rotation target includes Camera; `camera_rig.apply_reactive_spin` + `affect_camera_rotation`.
4. Defaults: `enabled`, `affect_scale`, `affect_light` = false (tscn + settings + hub fallbacks).
5. Play All: enables all FX_IDS + schedules; Mode Cycle/Random/Audio, Speed, Audio reactive, own DualRange / `play_all` gate; fx_automation speed/random/audio energy.

## 2026-08-11 ? Rotation leave-on crooked; playlist freeze on change

**Issues:**
1. Turning off reactivity Rotation (camera / Camera motion) or when schedule goes inactive leaves camera and env/main/scatter transforms crooked ? spin accumulates and is never restored.
2. Playlist Play / asset cycling still freezes on change (especially GIFs) because only next 1?2 neighbors are prefetched; cold GIF decode and model load still hit the apply path.

**Plan:**
1. Store rest orientations for env/centerpiece/scatter at spawn; track reactive spin as separate camera offsets; on disable / schedule inactive, restore rest (camera `reset_reactive_spin`, node `rotation = rest`). Same for demo_environment.
2. Eager warm of entire Env/Main/Scatter/Lighting playlist via AssetCache + MediaImport (GIF decode, textures, scenes, video/ogv prepare). Block Play with Caching until warm complete; raise cache caps; cycling only swaps from cache.

**Resolution:**
1. Rotation reset: camera_rig keeps reactive yaw/pitch/roll separate from mouse look; reset_reactive_spin on disable. Flythrough stores env/center/scatter rest rotations at spawn and restores when drive turns off or schedule closes. Demo environment same edge restore.
2. Full playlist precache: AssetCache.warm_paths + MediaImport.warm_path / warm_paths_sync_media; playlist sidebar warms all tabs on load/show/file-add; Play shows Caching and waits until ready; GIFs bind cache-only (no sync decode on apply); cache caps raised to 256.

## 2026-08-11 ? Play All identical Active/Inactive; effects overlap

**Issue:** Play All assigns the same Active/Inactive seconds to every effect gate and resets all phases to 0, so schedules lockstep. Effects stack; only the first ~two are visibly distinct.

**Root cause:**
1. `_on_play_all_toggled` / `_on_play_schedule_range` / `enable_play_all` clone one active/inactive pair onto every FX id.
2. `set_gate_enabled` always starts `phase = 0`, so all gates open together.
3. Independent jitter only in Random mode and only ?40% of the shared base ? not enough to desync.

**Plan:**
1. Play All assigns per-effect randomized Active/Inactive within sensible ranges (around the Play All schedule base, min ~2s).
2. Stagger each gate's start phase so on/off windows do not sync.
3. Keep jitter on for Play All so windows keep varying; stop cloning identical values from the Play All schedule onto every effect.
4. Sync per-effect schedule UI to the rolled values; leave manual per-effect schedule edits working.

**Resolution:**
1. `FxAutomation.pick_independent_schedule` / `apply_independent_gate_schedule` / `stagger_gate_phase`: each Play All effect gets its own Active/Inactive (around the Play All base, min 2s) plus a random phase offset.
2. `enable_play_all` no longer clones one pair onto every id; always enables gate jitter and staggers after `set_gate_enabled`.
3. Play All schedule slider is a base hint only; adjusting it re-rolls independent schedules (does not clone). Per-effect schedule UI syncs to rolled values; manual per-effect edits still work.
4. Tick jitter reroll runs whenever Play All is running (not only Random mode).
