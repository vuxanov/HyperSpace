# HyperSpace Issue Log

## 2026-08-10 — ReactivitySettings parser Indent error

**Issue:** Godot parser error in `autoload/reactivity_settings.gd` ~line 14: `Unexpected "Indent" in class body.` Autoload `ReactivitySettings` resolves to `<null>`.

**Cause:** `affect_emission` (and its preceding `##` doc comment) were indented with an extra tab inside the class body, which GDScript rejects outside of nested blocks.

**Plan:** Dedent those two lines to match sibling class members; scan the rest of the file for mixed-tab/indent issues.

**Resolution:** Aligned `##` comment and `var affect_emission` with other class-body members; no further indent issues found in the file.

## 2026-08-10 — Washed lighting, hero glow, missing HDRI, tiny envs, fly speed

**Issues (user-blocked visuals):**
1. Textured meshes still look washed-out under flythrough lighting.
2. Hero (and scatter) textures barely visible — strange glowing color tints.
3. HDRI skies/backgrounds not visible at all when selected in Lighting.
4. Small environment models appear tiny; flythrough does not read them.
5. No user-facing camera / fly-through speed control.
6. Camera path/framing should respect model scale.

**Causes (investigation):**
1. **Glow + fog + reactive colored lights:** `Environment.glow_*` stays aggressive from `_build_world`; fog always on and defaults affect the sky (`fog_sky_affect`); light reactivity HSV-shifts fill/sun every frame → washed albedo.
2. **Hero/scatter emission drive:** Default `affect_emission=true` + target `all` still runs `_drive_mesh_emission(..., tint_albedo=true)` on centerpiece/scatter with high energy (up to ~9×) and HSV emission colors. Even without albedo tint, emission overwhelms authored textures. Primitives also bake non-zero emission into materials.
3. **HDRI invisible:** Fog remains enabled on the HDRI success path and washes the panorama toward `fog_light_color`; SubViewport used for 3D does not set `own_world_3d`, so WorldEnvironment/sky can fail to present as an isolated world background.
4. **Tiny envs:** File environments are loaded at authored scale; path is built from raw AABB with no normalize-to-target, so small scans/props yield tiny paths and an unreadable flythrough.
5. **Fly speed:** `fly_speed` exists on the rig/env but has no sidebar UI.

**Plan:**
1. Strip hero/scatter material emission/tint drives entirely; zero primitive emission; default `affect_emission` off; light reactivity = energy only (no hue wash). Soften/disable glow; stop fog from eating the sky.
2. HDRI path: `own_world_3d` on Scene3D SubViewport; `fog_sky_affect=0` / near-zero fog; ensure `BG_SKY` + panorama energy; milder ambient so IBL does not crush textures.
3. Auto-fit file environments to a target AABB longest axis; rebuild path from scaled bounds; tune camera far / scatter spread / framing from that scale.
4. Add Fly speed SpinBox in playlist sidebar header; wire via ShowDirector → `set_cue_param("fly_speed")`.

**Resolution:**
- Removed all mesh emission/albedo-tint drives from flythrough env/hero/scatter; primitives no longer bake emission; `affect_emission` defaults off.
- Disabled glow; fog off by default / `fog_sky_affect=0`; HDRI uses visible panorama sky + milder ambient; Scene3D SubViewport `own_world_3d=true`.
- File envs auto-fit (~48u longest axis); path/framing/scatter spread follow scaled AABB; camera far scales with world.
- Playlist header **Fly speed** SpinBox → `ShowDirector.set_active_cue_param("fly_speed")`.

## 2026-08-10 — Environment `reflection_source` invalid assignment

**Issue:** Runtime error in `items/flythrough_environment.gd` ~line 238: `Invalid assignment of property or key 'reflection_source' with value of type 'int' on a base object of type 'Environment'.` Stack: main → show_director → scene3d_item → flythrough_environment. Blocks lighting/environment setup.

**Cause:** Wrong property name. Godot 4.7 Environment exposes IBL specular as `reflected_light_source` (inspector group prefix `reflected_light_`), with methods `set_reflection_source` / `get_reflection_source`. Assigning `env.reflection_source` hits a non-existent key. Constants (`REFLECTION_SOURCE_*`) are correct.

**Plan:** Replace both `env.reflection_source = …` assignments with `env.reflected_light_source`. Scan repo for the same typo; leave other Environment props alone if they match the docs.

**Resolution:** Fixed HDRI (`REFLECTION_SOURCE_SKY`) and procedural (`REFLECTION_SOURCE_DISABLED`) paths to use `reflected_light_source`. No other `.reflection_source` usages in the repo.

## 2026-08-08 — playlist_sidebar.gd type inference (`px`)

**Issue:** Godot parser error in `ui/playlist_sidebar.gd` ~line 127: `Cannot infer the type of "px" variable because the value doesn't have a set type.` Same pattern for `py`. Blocks loading the playlist sidebar script.

**Cause:** In `_make_tab_icon` ("dots" shape), `for p in [Vector2i(...), ...]` iterates an untyped Array, so `p` is Variant. `var px := p.x + ox` / `var py := p.y + oy` cannot infer a concrete type from Variant member access.

**Plan:** Type the loop as `for p: Vector2i in [...]` and use explicit `var px: int` / `var py: int` (and harden sibling `:=` in the same helper if needed). Avoid Python `//`.

**Resolution:** Typed `p` as `Vector2i` and declared `px`/`py` as `int` in the dots icon blit loop.

## 2026-08-08 — Playlist sidebar UX overhaul (timers, Lighting, icons, effects)

**Issue:** Left playlist/sidebar needs a major UX + behavior overhaul: remove global Play envs / Step sec header; give Env/Main/Scatter (and new Lighting) independent per-tab duration timers; fix autoplay that does not change environments after 8s; icon tabs; click-to-play rows with replace button (no per-row ▶); right sidebar must hide (not disable) off sections; expand effects targeting so reactivity can affect env/main/scatter/lights.

**Cause (8s bug):** Global Step sec only wrote `ShowDirector.default_item_duration` while category cycling lived in the sidebar and required ▶ Play — and only advanced the *active* tab. Env “play” also wiped main+scatter on every step via `_play_environment`, so multi-layer stage state fought autoplay. Timing was not independent per layer.

**Plan:**
1. Strip global transport / Step sec / Active summary from playlist sidebar header.
2. Per-tab timer + Play/Stop at top of Env / Main / Scatter / Lighting; run independent `_process` timers that step each playing category.
3. Apply layer changes without clearing sibling layers; ensure `set_flythrough_layer` → `set_layer_source` rebuilds env visuals.
4. Add Lighting tab + catalog presets; wire sun/sky/ambient into `FlythroughEnvironment`.
5. Icon tabs (`set_tab_icon` + tooltips); click row applies; right-side replace/swap button opens file picker.
6. Effects sidebar: hide nested bodies when toggles off; extend ReactivitySettings target to include Lights and gate light drive via `applies_to`.

**Resolution:** Removed global transport/Step sec header. Per-tab Play + duration timers advance Env/Main/Scatter/Lighting independently via `set_flythrough_layer` without wiping sibling layers. Added Lighting tab (procedural sun/sky presets) wired through ShowDirector → FlythroughEnvironment. Icon tabs, click-to-apply rows with ↻ replace, effects accordion hide-when-off, and Reactivity target includes Lights.

## 2026-08-08 — AsciiCharset unresolved (parser error)

**Issue:** Debugger at `ascii_effect.gd:156`: `Could not resolve class "AsciiCharset", because of a parser error.` Call site: `charset = AsciiCharset.filter_charset(charset)`.

**Cause:** Prior warning fix in `effects/ascii_charset.gd` used Python-style `//` for integer division (`pad_x`/`pad_y`). GDScript does not support `//`, so the script failed to parse and `class_name AsciiCharset` never registered.

**Plan:** Replace `//` with a Godot-safe pattern (`int(a / 2.0)`) so the script parses, the class registers, and pad math stays equivalent for these positive ints.

**Resolution:** Replaced `(CELL - gw * 2) // 2` (and `gh`) with `int((CELL - …) / 2.0)` in `_blit_glyph`.

## 2026-08-08 — EffectsSidebar @onready Node not found

**Issue:** Godot debugger spam: `effects_sidebar.gd` `@implicit_ready()` fails `get_node()` for many paths under `/root/Main/Root/EffectsSidebar` (e.g. `Margin/Column/AudioSection/ReactivityToggle`, `…/IntensitySlider`, Targets/ScaleSource, AxisRow, AffectLight, …). C++: `node.cpp get_node()` → nullptr. Related warnings: integer division (`ascii_charset.gd`), unused `_accent` (`flythrough_environment.gd`), param `name` shadowing `Node.name` (`effects_sidebar.gd`).

**Cause:** Scene tree was redesigned (`Margin/Scroll/Column`, param bodies under `ReactivityBody` / `AsciiBody` / etc., new driver OptionButtons) while the script still used pre-redesign `$Margin/Column/...` paths that no longer exist.

**Plan:** Align `@onready`/`$` paths with `effects_sidebar.tscn` (keep intended Scroll + gated bodies UI). Fix the three warnings with minimal edits.

**Resolution:** Script paths updated to `Margin/Scroll/Column/...` (and nested bodies); validated all 54 `@onready` paths against the `.tscn` (0 missing). Renamed `_select_camera_preset(name)` → `preset`. Wired `_accent` into flythrough light color. Integer-division warning later fixed properly (see AsciiCharset unresolved entry — `//` was invalid GDScript).

## 2026-08-08 — Left assets UI: three tabs (env / main / scatter)

**Issue:** Left sidebar mixes a default demo playlist, fly-through layer rows, and element-sequence controls into one hard-to-read panel. User wants three clear asset tabs — Environments, Main character, Scattering — each playable on its own, and the default “stuff” playlist removed.

**Plan:** Replace playlist + fly layer + element-sequence UI with a `TabContainer` of three category lists (from `FlythroughAssetCatalog` + File add). One shared fly-through stage; ▶ on a row applies that layer; tab Play cycles only that category. Stop loading demo `show.json` items on startup (empty/minimal stage). Drop element-sequence sidebar and default playlist contents.

**Resolution:** Left sidebar is now Environments / Main character / Scattering tabs. Row ▶ plays that category individually (env clears main+scatter; main clears scatter). Tab ▶ Play cycles assets in the active tab. Startup uses a blank fly-through stage — demo playlist items removed from `shows/demo/show.json` and no longer auto-loaded. Empty centerpiece/scatter configs honored in `FlythroughEnvironment`.

## 2026-08-08 — ASCII Live Visuals effects UX / play-over-time

**Issue:** HyperSpace effects sidebar always shows parameter controls and has no timed play-through. The user’s ASCII Live Visuals Engine (`vuxanov/ASCII` `index.html`) gates param UI behind ON toggles, auto-cycles style presets (“Style switch”), and uses effect schedules (cycle/active gates) so looks change over time. Also missing Glitch and extra ASCII styles from that app.

**Plan:** Study `index.html` (not just the simpler `ASCII ART GENERATOR.html`). Mirror: (1) hide effect param bodies unless enabled; (2) Style Switch = cycle ASCII presets on an interval; (3) per-effect schedule gates (cycle/active) + Play All master; (4) add Glitch post-process + Invert + a few more ASCII presets (Glitch/Pixel/Braille) that fit the glyph atlas.

**Resolution:** Mirrored ASCII Live Visuals Engine (`index.html`) patterns into HyperSpace: effect param bodies hide until toggle ON; Style Switch cycles ASCII presets on an interval (+ RND); per-effect schedule gates (cycle/active) plus Play All master; added Glitch post-process, Invert Density, and ASCII styles Dots/Glitch/Pixel/Braille. Automation lives in `FxAutomation`, ticked by `ShowDirector`.

## 2026-08-08 — Playlist element sequence (main → scatter)

**Issue:** Playlist could change backgrounds over time via item sequencing, but non-background fly-through elements (main character / scatter) lacked a timed progression and a clear chooser list. Desired UX: one main focal element, then scattered props that themselves change over the playlist timeline, picked from a list wired to real `3D models` assets.

**Plan:** Extend `FlythroughAssetCatalog` with labeled chooser entries (burger GLB + primitives). Store `params.element_sequence` on fly-through items (steps with duration + centerpiece/scatter configs). Advance steps during ShowDirector autoplay via existing `set_flythrough_layer`. Add Element Sequence UI in playlist sidebar (list + add-from-chooser). Demo show: street-city env, main burger → burger scatter → cube/sphere scatter.

**Resolution:** Implemented `element_sequence` on fly-through items; ShowDirector autoplay advances main→scatter steps without changing the environment layer. Playlist sidebar has Element sequence chooser (+ Main / + Scatter from catalog, Fill main→scatter preset). Demo show uses street-city + ex-convento envs with stylized burger props.

## 2026-08-08 — Port ASCII app character presets

**Issue:** HyperSpace ASCII presets (Classic/Dense/Sparse/Amber/Neon/…) don’t match the user’s ASCII Art Generator app (`vuxanov/ASCII`). Need the same character presets: Standard, Blocks, Minimal, Binary, Matrix.

**Plan:** Read presets from `ASCII ART GENERATOR.html` via `gh`; reverse dark→bright ramps for HyperSpace’s luminance mapping (sparse→dense); add half-width katakana bitmaps for Matrix; wire preset names into `AsciiEffect.PRESETS` (UI already lists keys).

**Resolution:** Replaced presets with Standard / Blocks / Minimal / Binary / Matrix from `vuxanov/ASCII`. Density ramps reversed for HyperSpace overlay shader; Matrix uses the same half-width katakana set with new glyph bitmaps; legacy names (Classic, Dense, …) alias to the new set. Added missing `1` glyph for Binary.

## 2026-08-08 — Scale still weak; use real 3D assets

**Issue:** Scale reactivity still barely visible; fly-through defaulted to primitives instead of project `3D models` (street city, ex-convento scan, stylized burger).

**Plan:** Punchier `scale_multiplier` (lift quiet mic + integer Scale Amount); default/Test menus use street-city / chiostro env + burger scatter/main; FBX load via imported PackedScene; fit GLB size to camera.

## 2026-08-08 — Camera moments feel like bad panning

**Issue:** Camera modulator “moments” look bad — dominated by left/right sine pan (yaw-only), which reads as cheap panning rather than cinematic motion.

**Plan:** Replace pan-style ModulatorBus presets with varied rotation styles (pitch, roll, multi-axis tumble/spiral, kick snap). Add roll offset through camera_rig so moments can rotate on more than yaw/pitch.

**Resolution:** Replaced presets (`Pitch rock`, `Roll bank`, `Orbit tumble`, `Spiral twist`, `Kick snap`). `ModulatorBus` now drives yaw/pitch/roll; `FlythroughCameraRig` applies roll. Legacy pan preset names remap to the new rotation set.

## 2026-08-08 — Choosable reactivity + camera modulators

**Issue:** Scale/emission/rotation/lights were hard-mapped or broken; feedback trail invisible; particles mostly main-only; main character too far; needed per-property Off/audio-band/LFO drivers and camera LFO presets.

**Plan:** Kick band + `drive_value` sources; Effects sidebar “driven by” pickers; ~10× scale; fix emission/color/rotation materials; real feedback history buffer; scatter+env particles; center closer (`~2.75`) + render priority; ModulatorBus camera presets shared as `lfo`.

## 2026-08-08 — HTerrain looked like low-detail demo edges

**Issue:** Generated h-terrain felt soft/low-res (“demo edge”), flat colors, little mesh or texture detail.

**Plan:** Bump to 513 res + denser map_scale; multi-octave height + detail; remove edge bowl falloff; Classic4 shader; 256² procedural albedo/bump/normal ground maps; tighter UV scale.

## 2026-08-08 — HTerrain plugin for fly-through landscapes

**Issue:** User added zylann.hterrain; wants generated terrain environments to try in fly-throughs.

**Plan:** Enable plugin; `FlythroughHTerrainBuilder` noise presets (hills/mountains/canyon); flight path samples heightmap; wire into Background Test menu + 3D Env presets; demo starts on hills.

## 2026-08-08 — Particles target + real ASCII + emission/lights

**Issue:** Particles mostly only hit images; 3D look stuck; emission/lights barely changed; ASCII was a boxy pixelate, not characters. Feedback weak with particles.

**Plan:** `particles_target` (everything / main / environment / media); flythrough centerpiece+camera-following env particles; stronger HSV emission & light; ASCII glyph atlas + charset presets; stronger feedback smear so particle breakup trails.

## 2026-08-08 — Playlist replace/DnD + fixed centerpiece

**Issue:** Hard to replace playlist items; unclear how to swap env/main/scatter; centerpiece flew along the path instead of staying visible on screen.

**Plan:** Click item name → same Add Media dialog as replace; ▶ to play; drag ⋮⋮ to reorder; OS file drop on row/list. Centerpiece camera-locked with slight idle motion. Clearer layer labels (Background / Scatter / Main character).

## 2026-08-08 — Fly-through system (3 uploadable layers)

**Issue:** One-off corridor was too fast/disorienting/flashy. Need a reusable walkthrough system: shared path+camera, three separately uploadable layers (environment, scatter, centerpiece), calm defaults, test primitives + real file replace.

**Plan:** `FlythroughEnvironment` + path/camera/layer helpers; playlist layer File/Test controls; reactivity targets centerpiece|scatter|environment|all; demo uses primitives at speed 2.

## 2026-08-08 — Prefer simple corridor over busy animated envs

**Issue:** User disliked the animated tunnel/city environments; wants a simple corridor fly-through first, with mouse/controller look-around. Full camera-path authoring later.

**Plan:** Add `CorridorEnvironment` (tube + auto forward motion + yaw/pitch look via mouse RMB / click-to-capture + gamepad right stick). Default env menu to Corridor; map old tunnel/city styles to corridor; simplify demo show.

## 2026-08-08 — Feedback inert; ReactivitySettings missing; richer envs

**Issue:** Feedback trail did nothing (empty viewports). Images ignored particles/reactivity. `ReactivitySettings` identifier failed to compile in some loads. User wanted animated tunnel/city with separate environment vs foreground reactivity.

**Plan:** Screen-space feedback shader; ReactivityHub typed access; ImageItem particles/reactivity; TunnelEnvironment + CityFlyEnvironment dual-layer; target = foreground|environment|all.

## 2026-08-08 — Menu blocking UI clicks (Godot node picker)

**Issue:** User couldn't click Effects sidebar; a popup listed `SensitivitySlider` / `AudioSection` / … / `Main`.

**Cause:** Godot Editor Game/Remote **Select Mode** intercepts clicks to pick scene nodes, not app input.

## 2026-08-08 — ReactivityHub / ReactivitySettings identifier not found

**Issue:** Godot 4.7 parse errors: global `class_name` / autoload identifiers not in scope for environment scripts.

**Plan:** Drop `class_name`; `preload("res://core/reactivity_hub.gd")` in each consumer; typed `scale_vec: Vector3`.

**Resolution:** Preload-based access; no global class dependency.

## 2026-08-08 — Variant inference on mesh/particles rotate

**Issue:** `var rotating := _mesh if ... else _particles` mixed `MeshInstance3D` / `GPUParticles3D`, inferred as Variant (error under Godot 4.7 strict typing).

**Plan:** Split into typed branches instead of a shared ternary.

**Resolution:** Separate rotate paths for mesh vs particles mode.

## 2026-08-08 — Playlist overlay, autoplay, import, particles-from-mesh

**Issue:** Switching playlist items crossfaded without hiding the old item (looked like overlay). Needed autoplay + per-item duration, single auto-detect import (GIF/video/3D/image), numeric scale amount, and particles emitted from 3D objects (mesh → particles).

**Plan:** Force replace/CUT on switch; ShowDirector autoplay timer; unified Add Media; SpinBox scale; DemoEnvironment dissolves mesh into GPUParticles3D when particles effect is on.

**Resolution:** Done — replace on switch, autoplay + durations, single Add Media, numeric scale, mesh→particles.

## 2026-08-08 — UI/effects/reactivity overhaul

**Issue:** ASCII couldn't turn off (disabled flag set but layer stayed visible). Particles called `set_anchors_preset` on GPUParticles2D. Demo used `look_at` before in-tree. SubViewport size conflict with stretch. User needed playlist|preview|effects layout, projector Present window, delete buttons, reactivity master + axis targets, ASCII presets.

**Plan:** Fix effect `set_active`, three-column layout, present Window sharing viewport texture, ReactivitySettings autoload, ASCII presets.

**Resolution:** Implemented; Present Mode keeps control UI while projector window shows output only.

## 2026-08-08 — Performer UI not visible

**Issue:** Control panel lived in a separate `Window` that sat behind the large main output window, so it looked like only the visuals were running.

**Plan:** Embed performer UI in the main window (left) with live output preview (right). F11 toggles output-only fullscreen for shows.

**Resolution:** Single window split view; no separate buried control Window.

## 2026-08-08 — Mic audio duplicated through speakers

**Issue:** Microphone capture bus (`HyperSpaceAnalysis`) was still sending to Master, so Godot played the input back (echo / "duplicated" audio).

**Resolution:** Mute `HyperSpaceAnalysis` bus. New split performer UI (playlist left / effects right) with add/remove media. Mesh scale driven by bass+energy.

## 2026-08-08 — AudioEffectSpectrumAnalyzer tap_db / tap_back_pos runtime error

**Issue:** `_setup_audio_bus` assigned removed properties (`tap_db`, then `tap_back_pos`). Godot 4.7 only exposes `buffer_length` and `fft_size`.

**Plan:** Configure only those two properties.

**Resolution:** Removed invalid property assignments.

## 2026-08-08 — Autoload parse errors in Godot 4.7

**Issue:** Project failed to load autoloads:
1. `audio_analyzer.gd` — treated `get_magnitude_for_frequency_range()` return as an array; API returns a single `Vector2`, so `.size()` failed.
2. `show_director.gd` / `kinect_manager.gd` — `:=` inferred from `Variant` (`call()`, `Dictionary.get()`); Godot 4.7 treats this as an error.

**Plan:** Query FFT in per-band frequency ranges; add explicit typed casts for Variant returns.

**Resolution:** Fixed `audio_analyzer.gd` band queries; typed casts in `show_director.gd` and `kinect_manager.gd`. Enabled `audio/driver/enable_input` for mic capture.

## 2026-08-08 — Godot CLI not on PATH

**Issue:** Godot executable not found in system PATH during scaffolding.

**Plan:** Project files (`project.godot`, scripts, scenes) created manually. User opens project in Godot Editor to run/export.

**Resolution:** Document in README; no blocker for development in Cursor.

## 2026-08-10 — Playlist/asset Delete does nothing

**Issue:** ✕ Delete on Env / Main / Scatter / Lighting rows does not remove items (or appears broken).

**Cause:** In `playlist_sidebar.gd` `_rebuild_list`, delete is `disabled` unless `entry.user_added` is true. Catalog presets never set that flag, so ✕ is grayed out for almost every row. Even for user-added rows, `_remove_entry` only spliced the working list and never cleared the applied stage layer when the deleted row was active.

**Plan:**
1. Enable ✕ for all working-list rows (session remove from the tab list).
2. On remove: if the row was selected / applied, clear that layer on the fly-through stage (empty main/scatter, fallback env, default lighting) via `ShowDirector.set_flythrough_layer`.
3. Clamp selection indices after remove and rebuild UI.

**Resolution:** ✕ enabled for all rows. `_remove_entry` removes from the tab’s working list; if that row was selected, `_clear_stage_layer` clears env/main/scatter/lighting on the active fly-through stage.

## 2026-08-10 — Harsh blue / colored lighting; need real HDRIs

**Issue:** Lighting tab only offers procedural sun/sky color presets. Ambient + fill lean blue (`_accent` lerps toward blue; several presets use strong blue skies), so materials/textures look washed and color-cast instead of reading correctly under IBL.

**Plan:**
1. Download CC0 Poly Haven HDRIs (1k `.hdr`) into `assets/hdris/` with attribution note.
2. Add HDRI lighting chooser entries; apply via `PanoramaSkyMaterial` on `WorldEnvironment` (BG_SKY + AMBIENT_SOURCE_SKY, tonemap).
3. When an HDRI is active, reduce directional/fill energy and drop the blue fill bias so IBL dominates.
4. Soften default studio ambient toward neutral gray.

**Resolution:** Added five Poly Haven 1k HDRIs under `assets/hdris/` (see ATTRIBUTION.md). Lighting tab lists them; apply sets panorama sky + sky ambient IBL, softens sun/fill, uses ACES tonemap, and neutralizes fill tint. Default “Studio fill” ambient made gray. “+ File (HDRI)” enabled for custom `.hdr`/`.exr`.

## 2026-08-10 — Hero / scatter models lose textures (flat override colors)

**Issue:** Main character (centerpiece) and scattered prop models show forced flat/overridden colors instead of the textures embedded in the GLB/FBX.

**Cause:**
1. `_raise_centerpiece_priority` always calls `_ensure_override_material`, which replaces meshes with a single `material_override`. Non-`StandardMaterial3D` imports (e.g. `ORMMaterial3D`) fall through to a flat gray-blue albedo (`0.7, 0.75, 0.85`), wiping textures. Even for Standard materials, one override collapses multi-surface textured meshes.
2. Default reactivity has emission ON + target `all`, so `_drive_mesh_emission(..., tint_albedo=true)` runs every frame on centerpiece and scatter, again forcing overrides and lerping `albedo_color` toward HSV tints (multiplies over / replaces textured look).

**Plan:**
1. Raise centerpiece draw priority via per-surface material duplicates (or existing override) — never invent a flat-color override.
2. Drive emission per surface / existing BaseMaterial3D without collapsing multi-materials; only tint albedo when there is no albedo texture (primitives still get color feedback).
3. Keep untextured fallback color only when a mesh truly has no BaseMaterial3D.

**Resolution:** Fixed in `items/flythrough_environment.gd`: `_raise_centerpiece_priority` now bumps `render_priority` on duplicated per-surface materials (or existing overrides) instead of inventing a flat `material_override`. Emission reactivity drives `BaseMaterial3D` per surface without collapsing multi-materials, and only lerps `albedo_color` when `albedo_texture` is null so textured GLB/FBX props keep their maps.

## 2026-08-10 � Env scale, dead reactivity, ASCII nesting, new FX

**Issues:**
1. Per-environment scale missing; auto-fit leaves mid-size assets inconsistent so some stay tiny/huge; reactive scale resets `_env_root.scale` to ONE and can push env out of view.
2. Noise-distort warp effect missing (with env/main/scatter/lights target chooser).
3. Sidebar Lights / Emission-Color / Rotation appear dead � emission/color drives were stripped from flythrough; rotation amounts too subtle; lights gated oddly.
4. ASCII style-switch + related settings sit outside ASCII accordion; density floor (20) too high; need min�max density range down to ~1.
5. Want stronger glitch + chromatic aberration + pixel-sort (approx OK) in effects pipeline.

**Plan:**
1. Always normalize file envs to target longest axis; store `user_scale` on env layer config; apply via `_env_root`; rebuild path/framing on scale change; Env Scale SpinBox in playlist.
2. Add `affect_noise` (+ amount/speed/source) in ReactivitySettings; FastNoiseLite offset/warp on chosen layers; light energy jitter for lights.
3. Re-enable emission/color drive when toggled (per-surface, no albedo tint if textured); amplify rotation; lights react when target includes lights/all (and Affect Light on).
4. Nest Style Switch under AsciiBody; density_min/density_max (1�200) with audio lerp; update ascii shader range.
5. Extend glitch shader; add `chromatic` + `pixel_sort` EffectLayers + sidebar toggles; register in EffectStack / Play All.

**Resolution:**
1. Auto-fit always normalizes file envs to ~48u; `user_scale` on env layer + playlist **Env scale** SpinBox; path/framing/scatter rebuild on scale; reactive env scale clamped so worlds stay in view.
2. **Noise Distort** reactivity (target/source/amount/speed) warps env/main/scatter transforms; lights get energy jitter.
3. Re-enabled per-surface emission/color when Affect Emission is on (default off; no albedo tint on textured mats); stronger rotation; lights drive when target includes Lights/Everything.
4. Style Switch nested under ASCII Preset; density min/max range (1�200) with audio lerp.
5. Glitch extended (slice chaos); added Chromatic Aberration + Pixel Sort (GPU approximate) to effect stack/sidebar.

## 2026-08-10 � Flythrough stuck, fake noise, white post-FX, sidebar scroll

**Issues:**
1. Flythrough camera/path no longer advances (feels stuck) after env-scale/path rebuild work.
2. Noise distort only jitters node transforms � not real mesh/noise deformation; UI exposes Noise Speed instead of Noise Scale (spatial feature size).
3. New post FX (glitch/chromatic/pixel sort) turn the whole preview white.
4. Effects sidebar cannot scroll far enough � last controls (e.g. Pixel Sort) clipped with no bottom padding.

**Causes / plan:**
1. Path rebuild always resets progress (`set_curve(..., true)`); fly_speed is absolute while AABB/user_scale can make paths very long so motion is imperceptible. Fix: preserve path fraction on scale rebuilds; scale advance by path length vs ~40u reference; keep `camera.current`.
2. Replace transform jitter with a spatial vertex-displace shader on target meshes; rename `noise_speed` ? `noise_scale` (feature size); drive amount from audio.
3. New `.gdshader` files used GDScript `##` doc comments � invalid in shading language ? shader fail ? opaque white ColorRect. Fix `##` ? `//`; add per-layer `BackBufferCopy` before ColorRect for reliable `hint_screen_texture`.
4. Add bottom spacer / larger scroll margin so expanded FX bodies can scroll fully into view.

**Resolution:**
1. Camera rig scales advance by path length vs ~40u; path rebuilds preserve progress on env scale; env path `min_half` capped; `camera.current` enforced; Scene3DItem re-enables process on start.
2. Replaced transform jitter with `effects/noise_deform.gdshader` vertex displace on target meshes; UI/settings `noise_speed` ? `noise_scale` (feature size).
3. Fixed invalid `##` comments in glitch/chromatic/pixel_sort shaders (compile fail ? white ColorRect); each effect layer gets `BackBufferCopy` before the screen ColorRect.
4. Effects sidebar: larger bottom margin, `BottomPad` spacer, Column `size_flags_vertical=0` so scroll content height is correct.

## 2026-08-10 � Env scale noop, weak FX, fake pixel-sort/noise, particle center spawn

**Issues (user feedback):**
1. Env scale SpinBox does not visibly scale the environment.
2. UI spinboxes/sliders show decimals � want whole numbers only (step 1).
3. Effects too weak (fly speed, noise, glitch, chromatic, reactivity) � crank ranges/defaults.
4. Pixel sort is fake RGB streak smear, not real thresholded luminance sorting.
5. Noise distort barely/not warping walls � need visible vertex displace; verify materials survive rebuild.
6. Particles always spawn at hero/center regardless of target � Everything should particle-ize all targeted meshes.

**Causes / plan:**
1. `set_environment_user_scale` rebuilds path from scaled AABB (`compute_aabb` includes `_env_root.scale`), so camera path grows with the mesh and relative size stays constant. Fix: path/framing AABB ignore `user_scale` (fit-only); scale only the env mesh/root.
2. Set playlist/effects controls to step=1, integer mins/maxes; map 0�100 style UI into stronger internal drives where needed.
3. Raise fly_speed default/max and path advance responsiveness; raise noise/scale/glitch/chromatic/pixel-sort ranges and shader/drive multipliers.
4. Replace pixel-sort shader with thresholded row rank-sort (scan spans by luminance, remap by brightness rank).
5. Rewrite noise deform to multi-axis world displace with much larger amount; keep Noise Scale as feature size; stop clearing/fighting overrides; multiply amount for large env meshes.
6. Bind GPUParticles3D to mesh vertex emission for env/main/scatter; hide solid meshes when particleized; Everything = all layers emit from their geometry.

**Resolution:** (in progress)

**Resolution:**
1. Env path/framing AABB now ignores `user_scale` (`_fit_aabb_ignoring_user_scale`); scale only changes `_env_root.scale` so the mesh visibly grows/shrinks vs a fixed camera path. Scale SpinBox is integer 1�20.
2. Playlist + effects sidebar controls switched to step=1 / whole-number ranges (fly speed, durations, noise, glitch, chromatic, pixel sort, LFO, etc.).
3. Fly speed default 12 (max 100), uncapped path speed scaling; reactivity/noise/light/rotation multipliers raised; post-FX shaders + UI mapping much stronger.
4. Pixel sort replaced with thresholded horizontal luminance rank-sort (real interval sort aesthetic).
5. Noise deform: multi-axis + normal displace, amount in world units (default 18), materials reapplied each frame on target meshes; rebuilds skip particle nodes so overrides persist.
6. Particles emit from mesh vertices of targeted layers (`EMISSION_SHAPE_POINTS`); solid meshes hide when particleized; Everything = env+main+scatter; removed camera-centered box spawn.
