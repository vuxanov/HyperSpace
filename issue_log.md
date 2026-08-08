# HyperSpace Issue Log

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
