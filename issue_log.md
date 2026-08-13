# HyperSpace Issue Log

## 2026-08-13 - Cloth crash, slow point cloud, audio amount, Auto label

**Issue:** User follow-up after cloth/point-cloud/LFO/lens:
1. Cloth does nothing — runtime error `Invalid assignment of property 'physics_enabled' on SoftBody3D` in `media_prop.gd` (Godot 4.7 has no `physics_enabled` on SoftBody3D).
2. Point cloud is very slow and only hits scatter. Need targeting (env / centerpiece / scatter / media) and a cheap path (no per-frame mesh rebuild).
3. Mode=Audio needs a shared **Audio amount** multiplier on every FX (like LFO Rate/Depth).
4. Mode=Auto is unclear; user thought it was static. Confirm behavior and label it.

**Plan:**
1. Log this issue. Do not commit. Append only.
2. Cloth: grep/remove all `physics_enabled`. Enable by creating SoftBody; disable by `queue_free` / `process_mode`. Keep shader cloth on imported meshes. Apply when Cloth FX is on even if Reactivity is off.
3. Point cloud: stop rebuilding overlays every frame; cache ArrayMesh by mesh RID; SurfaceTool fallback so imported env/centerpiece actually get vertices; apply per layer with target checkboxes (default all on). Size-only updates for audio/LFO.
4. Shared Audio amount (0–2, default 1) on every FX when Mode=Audio; persist via `FxAutomation.copy_lfo_params` (drive extras). Multiply `audio_sensitivity` into band01 / resolve_drive.
5. Auto is already “hold sliders, no audio/LFO” (`legacy manual == auto`). Rename UI to **Static** + tooltip. Keep id `auto`. Schedules still gate on/off.
6. UTF-8 no BOM, LF-only. Update Resolution. No commit.

**Resolution:** Cloth crash: removed all `physics_enabled` on SoftBody3D; enable by creating the body (`process_mode` inherit), disable by `queue_free`. Point cloud: no per-frame rebuild; cache ArrayMesh; SurfaceTool fallback for imported meshes; Main/Scatter/Outer/Media targets (default all on); size-only updates for audio/LFO. Shared Audio amount (0–2, default 1) on every FX when Mode=Audio; copied with LFO params. Mode “Auto” is Static (hold sliders) — UI label + tooltip; id still `auto`. No commit.

## 2026-08-13 - Boot loader progress jumps 0→24→17

**Issue:** Splash “loading assets” climbs 0→24, then snaps to 17, then finishes. User wants a real monotonic count (e.g. “Loading assets 7 / 42”), accurate total, and a bar that tracks actual load work — not a fake or double-counted list.

**Plan:**
1. Log this issue. Do not commit.
2. Inspect boot_loader / boot_cache / AssetCache threaded loads vs playlist media (GIF/image) lists.
3. Freeze one total up front; increment completed only when an asset finishes (or fails); bar = completed + in-flight threaded fraction; never jump backwards.
4. Labeled phases if needed (“Loading assets”, “Compiling effects”); drop the competing “N loading” number.
5. Update Resolution. No commit.

**Resolution:**
1. Root cause: splash total was `collect_critical_paths()` (24 unique playlist files, including GIFs). Detail also showed AssetCache `inflight` (17 — prefetch skips GIFs), so the UI read as 0/24 then a jump to 17. Count only moved when a whole file finished (no threaded fraction), and idle snap set done=`size()` which disagreed with the 17-job list.
2. One frozen total; completed only grows (warmed / failed / GIF miss). Bar = finished + in-flight `load_threaded` fraction + shaders + main, never backwards. Label `Loading assets N / M` plus current filename; no “N loading”.
3. Files: `ui/boot_loader.gd`, `core/asset_cache.gd` (`has_failed`, `threaded_progress`), `core/media_import.gd` (one-shot GIF/image miss). No commit.

## 2026-08-13 - Cloth fracture, point cloud no-op, LFO knobs, extreme lens

**Issue:** User feedback on the new 3D FX:
1. Cloth does not behave like cloth — objects look fractured / exploded instead of a connected sheet.
2. Point Cloud does not show at all (user said "camera cloud"; they mean the Point Cloud effect).
3. Every effect with Mode=LFO needs Rate/Speed and Depth/Amount (bandwidth) controls, not a hidden shared LFO.
4. Camera / lens focal range is too timid; they want ultra-wide through fisheye, circular/tunnel, and equirectangular-like wrap. Keep DOF/bokeh/aperture/focus, all LFO-able.

**Plan:**
1. Log this issue. Do not commit. Append only.
2. Cloth: keep SoftBody3D on tessellated media/small vertical grids (pin top, no world collision, no explode). Imported/dense meshes: rewrite `noise_deform.gdshader` cloth to world-space smooth waves (gravity sag + wind), never UV-island or per-vertex hash. Skip SoftBody on huge floors. Apply cloth even when Reactivity master is off. Never fall back to a shatter look.
3. Point cloud: debug no-op (parent transparency/layers hiding overlay, ShaderMaterial POINT_SIZE on Forward+, apply-once before meshes exist). Overlay as child with StandardMaterial3D `use_point_size`; hide original surfaces via a dedicated camera cull layer (match wireframe replace). Re-apply after rebuilds / while on. Hide originals when effect is on.
4. Shared LFO: `EffectLayer` rate/depth/wave oscillator; ShowDirector ticks per-effect LFO when Mode=LFO; sidebar shows Rate + Depth on every FX (keep ASCII waveform). Persist via params / fx_automation copy helpers.
5. Camera: widen focal length into Godot FOV 1–179; add Lens distortion 0=rectilinear → fisheye → circular → equirect wrap (screen shader). DOF stays on Camera3D.
6. UTF-8 no BOM, LF-only. Update Resolution. No commit.

**Resolution:**
1. Cloth fracture: imported meshes used UV-island / high-frequency per-vertex offsets in `noise_deform.gdshader` (looked like exploded vertices). Replaced with world-space low-frequency gravity sag + wind waves, scaled by object size. Media SoftBody: no world collision, stiffer defaults, gentler wind, pin a real top edge (skip huge floors). Cloth now applies even when Reactivity master is off.
2. Point cloud no-op: ShaderMaterial POINT_SIZE was unreliable on Forward+; overlay as a child of a fully faded mesh never showed. Now PRIMITIVE_POINTS + StandardMaterial3D `use_point_size`, originals hidden via camera cull layer 20 (children stay visible), re-applied after rebuilds and while the effect is on.
3. LFO: `EffectLayer` owns rate (Hz) + depth + optional waveform. ShowDirector ticks that oscillator when Mode=LFO. Sidebar shows Rate/Depth on every FX (ASCII keeps waveform). Params persist through Play All / style via `FxAutomation.copy_lfo_params`.
4. Camera: focal length 1–800mm (spin can go further) maps to FOV 1–179. New Lens distortion 0=rectilinear → fisheye → circular/tunnel → equirect wrap (`lens_distort.gdshader`). DOF/bokeh/aperture/focus unchanged and LFO-able.
5. Godot 4.7.1 `--script` load of changed FX/env scripts: LOAD OK. No commit.

## 2026-08-13 - Parse/compile errors after cloth / camera FX / point cloud

**Issue:** Godot console after the new FX work:
1. `res://ui/effects_sidebar.tscn:1` — Parse Error: Expected '['
2. `res://ui/playlist_sidebar.tscn:1` — Parse Error: Expected '['
3. `res://autoload/show_director.gd` — Parse error / Failed to load script (cascade)
4. `res://items/scene3d_item.gd:0` — Compile Error: Failed to compile depended scripts (cascade)
5. NEW: `core/scene_mesh_fx.gd:301` — `Cannot infer the type of 'rid' variable because the value doesn't have a set type` on `var rid := soft.get_rid()`
HTerrain UID warnings ignored.

**Plan:**
1. Log this issue. Do not commit.
2. Strip UTF-8 BOM from both .tscn files (BOM before `[gd_scene` → Expected '['). Normalize LF, no stray CR.
3. Fix `scene_mesh_fx.gd`: explicit `var rid: RID = soft.get_rid()`. Scan new cloth/point-cloud/camera scripts for the same `:=` inference failures.
4. SceneMeshFx compile fail is the Scene3DItem → ShowDirector cascade. Keep Cloth / Point Cloud / Camera-Lens UI.
5. Update Resolution. No commit.

**Resolution:**
1. Root cause for screenshot: `Object.get_rid()` has no set return type, so `var rid := soft.get_rid()` fails inference even when `soft` is `SoftBody3D`. Fixed as `var rid: RID = soft.get_rid()`. Also typed nearby `:=` on mesh arrays, overlay material, point overlay, `find_camera`, and `get_node_or_null` in cloth/point-cloud/camera FX + camera rig.
2. Root cause for Expected '[': UTF-8 BOM (`EF BB BF`) before `[gd_scene` in `effects_sidebar.tscn` and `playlist_sidebar.tscn`. Stripped BOM; converted those plus `show_director.gd` / `scene3d_item.gd` (and related FX scripts) to UTF-8 no BOM, LF-only. Cloth / Point Cloud / Camera-Lens UI and scatter/path playlist controls kept.
3. Godot 4.7.1 `--script` load of `scene_mesh_fx.gd`, `show_director.gd`, `scene3d_item.gd`, both sidebars, and new FX scripts: LOAD OK. No commit.

## 2026-08-13 - Cloth, tessellated media, camera lens FX, fake point cloud

**Issue:** Three related visual features (plus a prerequisite) for the 3D flythrough:
1. Cloth / SoftBody simulation as a global togglable effect (3D objects, media planes, environment).
2. Image/video planes are QuadMesh (2 triangles) so noise deform cannot warp them; tessellate so noise + cloth have vertices to move.
3. Animatable camera effects: depth of field, bokeh, focal length / aperture-style lens controls, wired to the flythrough Camera3D.
4. Fake point cloud mode (like wireframe): draw mesh vertices as colored dots.

**Plan:**
1. Log this issue. Do not commit.
2. Study effects architecture (EffectLayer, WireframeEffect, FxAutomation, effects_sidebar, noise deform, media_prop planes, FlythroughCameraRig).
3. Tessellate media planes in `media_prop.gd` (PlaneMesh FACE_Z + subdivisions). Drive noise/cloth uniforms on `media_screen.gdshader` so screens keep their texture (do not replace materials).
4. Cloth effect: EffectLayer `cloth` + sidebar + Play All / FX automation. SoftBody3D on tessellated media/simple grids (pinned top edge, audio wind). Vertex-shader cloth/jiggle for imported GLTFs (SoftBody is not realistic on dense meshes).
5. Camera FX: EffectLayer `camera_fx` applying CameraAttributesPractical (DOF/bokeh) + FOV from focal length + aperture-scaled blur on the flythrough Camera3D (and any Camera3D in the item viewport).
6. Point cloud: EffectLayer `point_cloud` analogous to wireframe — overlay PRIMITIVE_POINTS from mesh vertices with vertex/albedo color and point size.
7. Wire all three into effects_sidebar, ShowDirector FX_IDS, EffectStack, randomize, reset, schedules.
8. Update Resolution when done.

**Resolution:**
1. Media planes: `QuadMesh` → tessellated `PlaneMesh` (FACE_Z, 24×24) in `media_prop.gd`. Noise/cloth uniforms live on `media_screen.gdshader` so screens keep their texture. Primitive ground plane also subdivided.
2. Cloth (`cloth`): sidebar + Play All / schedules / randomize. Media/simple grids use `SoftBody3D` (pinned top edge, audio wind). Imported GLTFs and dense meshes use vertex-shader jiggle via `noise_deform.gdshader` cloth uniforms (SoftBody is not applied above ~900 verts). Billboard media stays shader-only.
3. Camera / Lens (`camera_fx`): `CameraAttributesPractical` DOF + bokeh, FOV from focal length (mm), aperture (f-stop) scales blur, focus distance. Applied to the flythrough `Camera3D` (and any Camera3D in the item viewport). Animatable like other FX.
4. Point Cloud (`point_cloud`): fake lidar from mesh vertices (`PRIMITIVE_POINTS` overlay, albedo/UV color, point size). Same wireframe-style enable/schedule/drive pattern.
5. Wired through EffectStack, ShowDirector FX_IDS, effects sidebar, reset, Play All. No commit.

## 2026-08-12 - FlythroughCameraRig parse: stray CR in camera_rig.gd

**Issue:** Godot console:
`ERROR: res://items/flythrough/camera_rig.gd:1 - Parse Error: Stray carriage return character in source code.`
Then `Could not parse global class "FlythroughCameraRig"` and `flythrough_environment.gd could not resolve FlythroughCameraRig`. WASAPI noise in the same log is secondary.

**Root cause:** `camera_rig.gd` used double-CR line endings (`CR CR LF` / `0D 0D 0A`). Godot treats the extra `CR` as a stray carriage return and fails parse at line 1.

**Plan:**
1. Log this issue.
2. Normalize `items/flythrough/camera_rig.gd` to LF-only (no BOM).
3. Quick-scan other `items/flythrough/*.gd` (and related env scripts) for the same CRCRLF / lone-CR pattern.
4. Do not commit.

**Resolution:**
1. Confirmed hex at line 1: `extends RefCounted` followed by `0D 0D 0A` (CRCRLF), repeated through the file (~250 CRCRLF pairs; 501 CR vs 250 LF).
2. Rewrote `camera_rig.gd` as UTF-8 no BOM with LF-only endings (`CR=0`, `LF=251`).
3. Sibling scan: only `camera_rig.gd` had stray/extra CR. Others are clean LF or normal CRLF (`asset_catalog`, `path_builder`, `layer_slot`, etc.). `flythrough_environment.gd` / `scene3d_item.gd` checked — no CRCRLF.
4. No commit. Reopen/reload project so Godot reimports `FlythroughCameraRig`.

## 2026-08-12 - Scatter needs layout modes + density settings

**Issue:** Scatter tab only picks assets; placement is always random along the path with a hardcoded default count (18). Users need layout modes (Random / Grid / Circular), a density control (how many / how packed), and must not awkwardly duplicate per-item scale (already in Edit item).

**Plan:**
1. Add Scatter tab UI: layout OptionButton + density SpinBox (integers).
2. Persist `layout` + `count` on scatter layer config; session autosave sidebar fields.
3. Wire placement in `flythrough_environment.gd` for random / grid / circular; include layout+count in scatter source key so changes rebuild.
4. On mode/density change, re-apply live scatter config when a scatter item is selected.
5. Keep per-item `user_scale` via Edit modal only (no second global scatter scale).
6. Do not commit.

**Resolution:**
1. Scatter tab: Layout (Random / Grid / Circular) + Density (1–80 integers). Per-item scale stays on ✎ Edit only.
2. `flythrough_environment.gd`: placement modes along the path; source key includes layout+count so changes rebuild; incremental spawn respects layout RNG.
3. `playlist_sidebar`: settings wired into apply + live re-scatter; session autosave `scatter_layout` / `scatter_density`.
4. No commit.

## 2026-08-12 - Live scale / square corners / slow fly / Outer react / EQ blank

**Issue:**
1. Env/item scale only visually updates after a cam-path (or similar) rebuild trigger.
2. Square cam path still corners too fast (circle OK).
3. Fly speed = 1 still feels too fast — needs a clear slow cruise.
4. Outer reactivity (environment What-reacts target) seems dead.
5. Graph equalizer / spectrum bars show nothing even when capture has signal.

**Plan:**
1. Remove hard 50× scale clamps; stamp `_env_root.scale` live (incl. terrain); sync `_env_source_key`; `force_update_transform`; re-stamp on path rebuild.
2. Softer square (larger corner radius, denser arcs, entry pads) + curvature speed brake + softer turn-rate in `FlythroughCameraRig`.
3. Lower path-length speed scale (÷100, was ÷35) so speed 1 is a slow cruise; keep fine decimals.
4. Alias Outer→environment; enable env scale react on terrain; label What-reacts Environment as Outer.
5. UI spectrum from pre-gate AGC bands (gate was zeroing EQ while input meter moved); ColorRect EQ columns; analysis bus volume −80 instead of mute (mute can starve FFT).

**Resolution:**
1. `flythrough_environment.gd` + playlist/main: no 50 clamp; live `_apply_env_display_scale` always stamps root (terrain too) + force transform; source key kept in sync; path rebuild re-stamps scale.
2. `path_builder.gd` square softer/denser; `camera_rig.gd` curvature brake + slower turn cap + ÷100 speed map.
3. Fly speed 1 ≈ 3× slower than prior mapping; higher speeds still scale up.
4. Outer label + `outer`/`env` normalize; env scale reactivity no longer skipped on terrain.
5. `audio_analyzer.gd` pre-gate UI bands + unmuted quiet analysis bus; `effects_sidebar` ColorRect graph equalizer.

## 2026-08-12 - WASAPI GetBufferSize / output_device invalidated (flaky audio)

**Issue:** Godot console spam while running HyperSpace (4.7.1):
`WASAPI: GetBufferSize error` then `WASAPI: Current output_device invalidated, closing output_device`. Debugging process stopped; audio reactivity drops when the device/buffer connection dies.

**Root cause (hypothesis):**
1. Engine bug (Godot #104837 / #109055): WASAPI shared-mode output client is invalidated on Windows sleep, monitor power-off, USB/BT headset unplug, or default-device flips — `GetBufferSize` fails before reopen.
2. App amplifies it: auto `AudioServer.input_device` swap + frequent mic restart / spectrum retry can hammer WASAPI while the output client is closing/reopening.
3. Mic capture + spectrum instance die after invalidation; without soft reconnect + backoff the UI looks “dead” and retries can look like a death spiral (debugger may stop on repeated ERRORs).

**Plan:**
1. Harden `autoload/audio_analyzer.gd`: detect silence / lost FFT / stopped mic; soft-reconnect capture **without** spamming device switches; debounce `set_input_device`; settle delays; exponential reconnect backoff; soft status `device lost — reconnecting…`.
2. Prefer stable input path (loopback once at boot only if still Default); never change input device during soft reconnect.
3. Project audio: raise `output_latency`, set `mix_rate=48000` (common Windows shared rate) to reduce buffer thrash.
4. Keep analysis bus muted; do not add extra Master stream players that fight the mix graph.
5. Do not commit.

**Resolution:**
1. `audio_analyzer.gd`: debounced device apply, silence/spectrum-loss soft reconnect with backoff, soft-fail status string, startup settle before capture.
2. `project.godot`: `driver/mix_rate=48000`, `driver/output_latency=50` (+ existing `enable_input`).
3. Effects sidebar: debounce device OptionButton so rapid picks do not re-enter WASAPI.

## 2026-08-12 - FX Audio mode ignores audio (chromatic etc.)

**Issue:** Many post FX (chromatic aberration, glitch, pixel sort, feedback, …) look static when Drive=Audio. Sliders apply at full strength; `audio_drive` only adds a small nudge, so effects do not follow audio. Multi-slider FX do not map params to different bands.

**Plan:**
1. Audit each EffectLayer `apply_audio_state` + shader uniforms vs UI Drive=Audio/LFO/Auto.
2. Store slider values as bases; in Audio mode scale strength by audio (slider = max/mix), with a near-zero floor so silence turns FX down.
3. Multi-param FX: map distinct params to bass / mids / highs / energy / kick (match AudioState + existing resolve curves).
4. Keep Auto = static slider values; LFO = existing oscillator paths. Chromatic is the must-fix example.

**Resolution:**
1. Root cause: Drive=Audio only nudged `audio_drive` while slider uniforms stayed at full strength → static look.
2. `EffectLayer.band01` / `audio_scale`: perceptual band 0..1 + slider-as-max scaling.
3. Chromatic: amount ceiling × highs/energy; silence → off. Glitch: kick/mids/bass/highs/energy → intensity/rate/h_size/rgb/chaos. Pixel sort: mids/highs/bass → amount/threshold/stretch. Feedback: energy/bass/mids → mix/persist/zoom. ASCII: energy/highs/mids → density/punch/intensity. Wireframe: energy+kick gate.
4. Auto still uses raw slider values; LFO paths unchanged in spirit (scale from bases).

## 2026-08-11 - Sliders lack numeric fields; path jank; playlist header jumps

**Issue:**
1. UI HSliders (effects sidebar, schedule pairs, edit-item scale, etc.) had no editable numeric readout; steppers that exist nudged decimals; fly speed min/step too coarse for slow flying.
2. Circle cam path felt janky; square path turned abruptly at corners.
3. Playlist header `StatusLabel` showed long currently-playing asset names and shifted the rest of the header UI.

**Plan:**
1. Add shared `SliderSpinLink` helper: wrap each HSlider with a SpinBox (fine edit step + `custom_arrow_step=1.0`, `allow_greater`/`allow_lesser`); apply across effects sidebar, schedule pairs, density range, edit modal; loosen fly speed SpinBox.
2. Fix `FlythroughPathBuilder` circle tangents / closed loop; rebuild square as rounded-rect with continuous tangents; soften camera orientation via look-ahead + basis slerp in `FlythroughCameraRig`.
3. Permanently hide playlist `StatusLabel` so header layout stays stable.

**Resolution:**
1. Added `ui/slider_spin_link.gd`: wraps HSliders with SpinBox (edit step fine, `custom_arrow_step=1.0`, `allow_greater`/`allow_lesser`). Wired in effects sidebar + schedule pairs + dual density range + edit-item scale; fly/env/duration spins configured the same way. Fly speed min=0, step=0.01.
2. Circle: correct cubic handles + `Curve3D.closed` (no seam duplicate). Square: rounded-rect with dense arc samples. Camera: look-ahead facing + basis slerp + max turn-rate cap.
3. Playlist `StatusLabel` permanently hidden (`visible=false`) so playing names no longer shift header layout.

## 2026-08-11 - Playlist list items not editable

**Issue:** Env / Main / Scatter / Lighting list rows only had a ↻ replace control. Users need to rename items, replace the asset, and (most importantly) change per-item scale from a clean edit modal.

**Plan:**
1. Replace row ↻ with an edit (✎) button that opens a modal: Name, Replace/upload, Scale.
2. Persist `label` + `config.user_scale` on sidebar entries (session); apply rename/replace/scale to the live stage when that row is selected.
3. Add centerpiece/scatter `user_scale` support in FlythroughEnvironment (env already has it); keep lighting rename+replace only (no scale).
4. Remove dead ↻ UI; replace lives inside the modal.

**Resolution:**
1. Asset list rows (Env/Main/Scatter/Lighting) use ✎ → Edit item modal: rename, Replace… file picker, Scale slider+spin (hidden for Lighting).
2. Per-entry `user_scale` stored on entry + `config`; session autosave; live apply via `env_scale` / `centerpiece_scale` / `scatter_scale` when that row is selected.
3. FlythroughEnvironment: `set_centerpiece_user_scale` / `set_scatter_user_scale` (+ rebuild bake); env path unchanged.
4. ↻ row button removed; replace only in modal (Lighting HDRI replace enabled there).

## 2026-08-11 - Reset to default leaves effects on

**Issue:** Effects sidebar **Reset to default** (and playlist twin) only cleared reactivity affect flags + stage poses/fly speed. Visual FX (ascii/particles/feedback/glitch/chromatic/pixel_sort/wireframe), Play All, style/density automation, and schedule gates stayed on — UI toggles did not turn off.

**Plan:**
1. Extend `ShowDirector.reset_stage_to_defaults()` to disable Play All, all FX layers, style/density automation, and effect + react schedule gates; also turn master reactivity off.
2. On `stage_defaults_restored`, sync effects sidebar: master/effect/play-all/schedule/style toggles off so UI matches cleared runtime state.
3. Keep playlist assets; verify playlist reset path uses the same director call (no re-enable override).

**Resolution:**
1. `ShowDirector.reset_stage_to_defaults()` now disables Play All, all FX layers, clears FxAutomation (style/density/schedules), and turns master reactivity off — then restores poses/fly speed as before.
2. Effects sidebar syncs all related toggles off on `stage_defaults_restored` (works from either Reset button).
3. Playlist assets / cam path unchanged; session restore does not re-enable FX after reset.

## 2026-08-11 - Multi-select What reacts targets

**Issue:** "What reacts" / Rotation / Noise / Particles target controls are single-select OptionButtons (with an Everything option). Users cannot apply scale/light/emission/rotation/noise/particles to more than one layer at once.

**Plan:**
1. Replace string `target` / `*_target` enums with multi bools (`target_main`, `target_scatter`, `target_environment`, `target_lights`, plus camera/media where needed); default all unchecked.
2. Add `targets_include(layer)` (and rotation/noise/particles variants) in ReactivityHub; migrate legacy `"all"` / single-layer strings when loading old params.
3. Swap OptionButtons for checkbox rows in effects_sidebar; remove Everything; wire UI ? settings ? flythrough/demo `applies_to` paths.

**Resolution:**
1. ReactivitySettings: multi bools ``target_*`` / ``rotation_target_*`` / ``noise_target_*`` / ``particles_target_*`` (default all unchecked); no Everything string.
2. ReactivityHub: ``targets_include`` (+ rotation/noise/particles variants); ``applies_to`` / ``*_applies_to`` use them; legacy string ``target`` migrated via ``apply_legacy_target_string`` / particle params.
3. effects_sidebar: checkbox rows for What reacts, Rotation, Noise, Particles; wired end-to-end; flythrough still gates via ``RH.applies_to`` / ``rotation_applies_to`` / ``noise_applies_to`` / ``particles_applies_to``.


## 2026-08-11 - Only one camera flythrough path

**Issue:** Camera always followed a single env-fitted straight (or terrain/overland) Curve3D. No way to pick alternate shapes (circle / square / multi-plane 3D).

**Plan:**
1. Extend `FlythroughPathBuilder` with circle, square, and dive3d closed paths sized from env AABB; keep existing straight/`from_aabb` as `auto`.
2. Add `path_style` on `FlythroughEnvironment` + cue/param wiring; rebuild path (+ scatter) on change.
3. Add Cam path OptionButton in playlist sidebar (next to fly speed); persist in session.

**Resolution:**
1. Path builders: `circle`, `square`, `dive3d` (+ `build_styled`); Auto remains default.
2. Playlist header **Cam path** dropdown; `path_style` / `camera_path` params; session restore in main + sidebar.
3. Dive 3D is a closed multi-axis loop: forward → dive → right → climb home.

## 2026-08-11 - Effects sidebar search filter

**Issue:** Effects & Reactivity sidebar is long; hard to find a specific effect/setting quickly.

**Plan:**
1. Add a LineEdit at the top of ui/effects_sidebar (placeholder "Search effects...").
2. On text change, case-insensitive filter: hide non-matching effect rows/sections; empty query restores all (respecting existing accordion visibility).
3. Match by toggle/label text; keep UI style simple and fast; no commit.

**Resolution:**
1. Added SearchEdit LineEdit under the sidebar title in effects_sidebar.tscn.
2. effects_sidebar.gd filters effect/reactivity rows by label text; section chrome hides when empty; accordion bodies still respect toggles.

## 2026-08-11 ? Rotation off leaves env crooked; need Reset to default

**Issue:** After turning **rotation off**, environments (and related stage layers) stay messed up ? transforms not restored. User also wants a **Reset to default** control to recover without restarting. Caching improved but some hitching on env swaps remains.

**Root cause (likely):**
1. Reactive spin accumulates on `_env_root.rotation`; rest pose is captured via `_capture_env_rest_rotation()` on rebuild/swap **without zeroing the root first**, so a mid-spin env swap stores the crooked Euler as the new ?rest?.
2. Restore on disable is gated by `_rot_driving_*`; capture clears those flags without restoring, so later toggle-off skips restore.
3. `apply_audio_state` early-return when master reactivity is off resets scales/noise but does not always restore rotations (scatter rests never cleared in `_clear_noise_deform`).
4. Toggle-off waits for the next audio tick ? no immediate restore.

**Plan:**
1. On env rebuild/swap: zero `_env_root` rotation/position before capture; treat env rest as identity.
2. When rotation / reactivity disables: always restore env/center/scatter rests + camera `reset_reactive_spin` (idempotent, not flag-gated); restore immediately from UI toggles.
3. Add **Reset to default** (effects sidebar + playlist header): stage poses, rotation/noise/camera-motion leftovers, lighting energies, fly speed ? without wiping playlist assets.
4. Light hitch pass: defer cached env swap one frame so UI stays responsive.

**Resolution:**
1. Env rebuild/swap zeros `_env_root` rotation/position; rest is always identity (no longer captures mid-spin Euler).
2. Rotation disable always restores env/center/scatter (not gated on `_rot_driving_*`); master reactivity off calls `restore_reactive_poses()`; UI toggles restore immediately via `ShowDirector.restore_reactive_poses()`.
3. **Reset to default** on Effects sidebar (under search) and Playlist header: clears transform-corrupting reactivity flags, restores poses/noise/emission/lights, resets fly speed to 2, re-applies lighting config ? keeps playlist assets.
4. Cached env packed swaps deferred one frame to reduce swap hitch.

## 2026-08-11 ? Boot still deferred full cache until after main UI

**Issue:** User still sees playlist sidebar **"Caching 25 on 68"** after the main screen appears. Splash only warmed a subset; the big catalog warm ran post-load.

**Root cause:**
1. `BootCache.collect_critical_paths()` intentionally skipped unused env GLBs/FBX and capped media (`MAX_BOOT_MEDIA = 6`), leaving the rest for sidebar `_start_warm_all`.
2. Boot could soft-timeout at 60s and hand off to main while assets were still cold.
3. Playlist `_ready` / `_on_show_loaded` always kicked the full ~68-path warm with visible "Caching? N/M".

**Plan:**
1. Make boot collect the **same full playlist set** sidebar warms (session lists if present, else catalog env/main/scatter/lighting paths ? no media cap).
2. Show **Caching? N/M** on the splash; wait until that set is idle before `change_scene_to_packed(main)` (long safety timeout only).
3. Mark `BootCache.full_warm_completed`; sidebar fast-paths / suppresses the big Caching UI when boot already finished.
4. Prefer longer splash over early first paint.

**Resolution:**
1. `BootCache.collect_critical_paths()` now mirrors playlist warm: session sidebar lists (or catalog defaults) for env/main/scatter/lighting ? **no media cap**, includes env GLBs/FBX + all GIFs/stills/HDRIs.
2. Splash shows **Caching? N/M**, waits until that set is idle (300s safety timeout only), then `change_scene_to_packed(main)`.
3. `BootCache.full_warm_completed` gates sidebar: skip big Caching UI when boot already finished; only show for non-trivial leftovers or Play wait.
4. Headless smoke: `collect_critical_paths()` returns **68** paths (same N as prior post-main "Caching 25/68").

## 2026-08-11 ? Startup / first screen too slow

**Issue:** App startup and first screen reveal feel way too slow. Main UI mounts immediately while heavy work (catalog models, HDRIs, session layers, shaders, media) still runs, so the control surface looks frozen or hitchy on cold load.

**Root causes (likely):**
1. `run/main_scene` is `ui/main.tscn` ? sidebars + SubViewport + EffectStack + session restore all start before critical assets are cached.
2. Session restore / blank stage apply can still touch GLB/HDRI/media before `AssetCache` is warm.
3. Playlist sidebar warms catalogs *after* the UI is already visible (status ?Caching?? only in the sidebar).
4. FX shaders compile on first use during the first interactive frames.

**Plan:**
1. Add a boot/splash scene as `run/main_scene` with spinner + progress + status text.
2. Before revealing main UI: collect critical paths (catalog HDRIs/models, last-session stage paths, FX shaders) and warm via `AssetCache` / `MediaImport`; threaded-load `main.tscn`.
3. Poll with incremental progress updates; on ready (or soft timeout) `change_scene` to main.
4. Keep existing playlist full-warm for Play; it should finish fast when boot already cached hits.

**Resolution:**
1. `ui/boot_loader.tscn` is now `run/main_scene` - splash with spinner, progress bar, status/detail text.
2. `core/boot_cache.gd` collects the **full** playlist warm set (session lists / catalog) + FX shaders ? not a capped subset (see follow-up issue above).
3. Boot warms via `AssetCache` / `MediaImport`, threaded-loads `main.tscn`, then `change_scene_to_packed` after warm idle.
4. `main.gd` defers session/stage apply one frame so the control surface paints before apply.
5. Playlist `_start_warm_all` fast-paths / suppresses Caching UI when `BootCache.full_warm_completed`.
6. Headless smoke: path collection matches the prior post-main 68-asset set.

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
1. `ui/boot_loader.tscn` is now `run/main_scene` - splash with spinner, progress bar, status/detail text.
2. `core/boot_cache.gd` collects critical paths (catalog HDRIs, hero prop, active session stage, capped media) + FX shaders. Large unused env GLBs warm later in the sidebar.
3. Boot warms via `AssetCache` / `MediaImport`, threaded-loads `main.tscn`, then `change_scene_to_packed`.
4. `main.gd` defers session/stage apply one frame so the control surface paints before apply.
5. Playlist `_start_warm_all` fast-paths when boot already filled the cache.
6. Headless smoke: scripts load and asset warm starts; full GUI playtest not verified (dummy renderer crash on main scene).

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
1. `ui/boot_loader.tscn` is now `run/main_scene` - splash with spinner, progress bar, status/detail text.
2. `core/boot_cache.gd` collects critical paths (catalog HDRIs, hero prop, active session stage, capped media) + FX shaders. Large unused env GLBs warm later in the sidebar.
3. Boot warms via `AssetCache` / `MediaImport`, threaded-loads `main.tscn`, then `change_scene_to_packed`.
4. `main.gd` defers session/stage apply one frame so the control surface paints before apply.
5. Playlist `_start_warm_all` fast-paths when boot already filled the cache.
6. Headless smoke: scripts load and asset warm starts; full GUI playtest not verified (dummy renderer crash on main scene).

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
1. `ui/boot_loader.tscn` is now `run/main_scene` - splash with spinner, progress bar, status/detail text.
2. `core/boot_cache.gd` collects critical paths (catalog HDRIs, hero prop, active session stage, capped media) + FX shaders. Large unused env GLBs warm later in the sidebar.
3. Boot warms via `AssetCache` / `MediaImport`, threaded-loads `main.tscn`, then `change_scene_to_packed`.
4. `main.gd` defers session/stage apply one frame so the control surface paints before apply.
5. Playlist `_start_warm_all` fast-paths when boot already filled the cache.
6. Headless smoke: scripts load and asset warm starts; full GUI playtest not verified (dummy renderer crash on main scene).

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
1. `ui/boot_loader.tscn` is now `run/main_scene` - splash with spinner, progress bar, status/detail text.
2. `core/boot_cache.gd` collects critical paths (catalog HDRIs, hero prop, active session stage, capped media) + FX shaders. Large unused env GLBs warm later in the sidebar.
3. Boot warms via `AssetCache` / `MediaImport`, threaded-loads `main.tscn`, then `change_scene_to_packed`.
4. `main.gd` defers session/stage apply one frame so the control surface paints before apply.
5. Playlist `_start_warm_all` fast-paths when boot already filled the cache.
6. Headless smoke: scripts load and asset warm starts; full GUI playtest not verified (dummy renderer crash on main scene).

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
1. `ui/boot_loader.tscn` is now `run/main_scene` - splash with spinner, progress bar, status/detail text.
2. `core/boot_cache.gd` collects critical paths (catalog HDRIs, hero prop, active session stage, capped media) + FX shaders. Large unused env GLBs warm later in the sidebar.
3. Boot warms via `AssetCache` / `MediaImport`, threaded-loads `main.tscn`, then `change_scene_to_packed`.
4. `main.gd` defers session/stage apply one frame so the control surface paints before apply.
5. Playlist `_start_warm_all` fast-paths when boot already filled the cache.
6. Headless smoke: scripts load and asset warm starts; full GUI playtest not verified (dummy renderer crash on main scene).

## 2026-08-11 ? Rotation amount/axes + reactivity schedules

**Issue:** Rotation reactivity lacks Scale Amount?style strength and X/Y/Z axis toggles (only Y spin). Noise, Scale, Rotation, Lights, and Emission also lack Active/Inactive schedules that post-FX already have via DualRangeSlider + FxAutomation gates.

**Plan:**
1. Add `rotation_amount` + `rotation_x/y/z` to ReactivitySettings; hub accessors + `rotation_rate` / `rotation_axis_mask`; apply multi-axis rotation scaled by amount in flythrough (and demo) envs.
2. Reuse FxAutomation gates (`react_scale`, `react_rotation`, `react_noise`, `react_light`, `react_emission`) with DualRange Active/Inactive UI under each Targets section; `property_active` requires gate open so drives are off during inactive windows.
3. Keep existing post-effect schedules unchanged; integer UI for new amount/schedule controls.

**Resolution:**
1. `ui/boot_loader.tscn` is now `run/main_scene` - splash with spinner, progress bar, status/detail text.
2. `core/boot_cache.gd` collects critical paths (catalog HDRIs, hero prop, active session stage, capped media) + FX shaders. Large unused env GLBs warm later in the sidebar.
3. Boot warms via `AssetCache` / `MediaImport`, threaded-loads `main.tscn`, then `change_scene_to_packed`.
4. `main.gd` defers session/stage apply one frame so the control surface paints before apply.
5. Playlist `_start_warm_all` fast-paths when boot already filled the cache.
6. Headless smoke: scripts load and asset warm starts; full GUI playtest not verified (dummy renderer crash on main scene).

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
1. `ui/boot_loader.tscn` is now `run/main_scene` - splash with spinner, progress bar, status/detail text.
2. `core/boot_cache.gd` collects critical paths (catalog HDRIs, hero prop, active session stage, capped media) + FX shaders. Large unused env GLBs warm later in the sidebar.
3. Boot warms via `AssetCache` / `MediaImport`, threaded-loads `main.tscn`, then `change_scene_to_packed`.
4. `main.gd` defers session/stage apply one frame so the control surface paints before apply.
5. Playlist `_start_warm_all` fast-paths when boot already filled the cache.
6. Headless smoke: scripts load and asset warm starts; full GUI playtest not verified (dummy renderer crash on main scene).

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
1. `ui/boot_loader.tscn` is now `run/main_scene` - splash with spinner, progress bar, status/detail text.
2. `core/boot_cache.gd` collects critical paths (catalog HDRIs, hero prop, active session stage, capped media) + FX shaders. Large unused env GLBs warm later in the sidebar.
3. Boot warms via `AssetCache` / `MediaImport`, threaded-loads `main.tscn`, then `change_scene_to_packed`.
4. `main.gd` defers session/stage apply one frame so the control surface paints before apply.
5. Playlist `_start_warm_all` fast-paths when boot already filled the cache.
6. Headless smoke: scripts load and asset warm starts; full GUI playtest not verified (dummy renderer crash on main scene).

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
1. `ui/boot_loader.tscn` is now `run/main_scene` - splash with spinner, progress bar, status/detail text.
2. `core/boot_cache.gd` collects critical paths (catalog HDRIs, hero prop, active session stage, capped media) + FX shaders. Large unused env GLBs warm later in the sidebar.
3. Boot warms via `AssetCache` / `MediaImport`, threaded-loads `main.tscn`, then `change_scene_to_packed`.
4. `main.gd` defers session/stage apply one frame so the control surface paints before apply.
5. Playlist `_start_warm_all` fast-paths when boot already filled the cache.
6. Headless smoke: scripts load and asset warm starts; full GUI playtest not verified (dummy renderer crash on main scene).

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
1. `ui/boot_loader.tscn` is now `run/main_scene` - splash with spinner, progress bar, status/detail text.
2. `core/boot_cache.gd` collects critical paths (catalog HDRIs, hero prop, active session stage, capped media) + FX shaders. Large unused env GLBs warm later in the sidebar.
3. Boot warms via `AssetCache` / `MediaImport`, threaded-loads `main.tscn`, then `change_scene_to_packed`.
4. `main.gd` defers session/stage apply one frame so the control surface paints before apply.
5. Playlist `_start_warm_all` fast-paths when boot already filled the cache.
6. Headless smoke: scripts load and asset warm starts; full GUI playtest not verified (dummy renderer crash on main scene).

## 2026-08-11 ? Rotation leave-on crooked; playlist freeze on change

**Issues:**
1. Turning off reactivity Rotation (camera / Camera motion) or when schedule goes inactive leaves camera and env/main/scatter transforms crooked ? spin accumulates and is never restored.
2. Playlist Play / asset cycling still freezes on change (especially GIFs) because only next 1?2 neighbors are prefetched; cold GIF decode and model load still hit the apply path.

**Plan:**
1. Store rest orientations for env/centerpiece/scatter at spawn; track reactive spin as separate camera offsets; on disable / schedule inactive, restore rest (camera `reset_reactive_spin`, node `rotation = rest`). Same for demo_environment.
2. Eager warm of entire Env/Main/Scatter/Lighting playlist via AssetCache + MediaImport (GIF decode, textures, scenes, video/ogv prepare). Block Play with Caching until warm complete; raise cache caps; cycling only swaps from cache.

**Resolution:**
1. `ui/boot_loader.tscn` is now `run/main_scene` - splash with spinner, progress bar, status/detail text.
2. `core/boot_cache.gd` collects critical paths (catalog HDRIs, hero prop, active session stage, capped media) + FX shaders. Large unused env GLBs warm later in the sidebar.
3. Boot warms via `AssetCache` / `MediaImport`, threaded-loads `main.tscn`, then `change_scene_to_packed`.
4. `main.gd` defers session/stage apply one frame so the control surface paints before apply.
5. Playlist `_start_warm_all` fast-paths when boot already filled the cache.
6. Headless smoke: scripts load and asset warm starts; full GUI playtest not verified (dummy renderer crash on main scene).

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

## 2026-08-11 - Play All Random ignores Active/Inactive schedule

**Issue:** Play All mode Random does not respect the Play All Active/Inactive schedule. Effects keep running through the Inactive window; Active is only used as a subset-reroll interval.

**Root cause:**
1. `play_all` gate Active/Inactive advances, but `_apply_effect_effective` / `is_gate_open` never ANDs effect enable with the master `play_all` window.
2. Random mode uses `effective_active` only as `_play_all_random_timer` interval; Inactive is unused for mute-all.
3. Per-effect independent schedules keep opening FX during what should be a global Inactive window.
4. `gate_changed("play_all")` refreshes a non-existent effect id, so master edges never mute/unmute the stack.

**Plan:**
1. Random mode: master `play_all` gate = sole Active/Inactive clock; mute all Play-All FX while closed.
2. While Active: periodically reshuffle which effects are on + randomize their params/styles (subset mask, not per-effect phase).
3. Skip per-effect schedule phase advances for Play-All ids in Random; on master open edge, immediate reshuffle.
4. ShowDirector refreshes all Play-All FX on `play_all` gate changes and applies random params on reshuffle ticks.
5. Cycle mode keeps independent per-effect schedules (unchanged).

**Resolution:**
1. Random mode: `play_all` gate is the sole Active/Inactive clock; `is_gate_open` ANDs master window + subset mask so Inactive mutes every Play-All FX.
2. While Active, reshuffle every `clamp(active*0.2, 0.75, 2.5)` sec (and on Active edge); `play_all_randomize_tick` randomizes params/styles via ShowDirector.
3. Per-effect schedule phase advances skipped in Random; Cycle/Audio keep independent staggered schedules.
4. `gate_changed("play_all")` refreshes all Play-All FX; sidebar schedule/mode paths no longer re-roll independent schedules in Random.

## 2026-08-11 - Audio reactivity flaky / no real spectrum

**Issue:** Audio reactivity sometimes picks up sound, often doesn't. Feels like mic/FFT isn't reliably recording or analyzing. Need a proper spectrum analyzer (bass/mid/high/energy) for effects mapping, plus UI so the user can verify input.

**Root cause (likely):**
1. Spectrum instance grabbed in `_ready` immediately after `add_bus_effect` � `get_bus_effect_instance` can be null until the audio thread/mic is active; `_analyze` then early-returns forever (classic 'sometimes works').
2. No input-device selection / reconnect � wrong default mic, paused `AudioStreamPlayer`, or OS denying input looks like silence.
3. Godot has no WASAPI loopback � system playback is silent unless a loopback-capable input (Stereo Mix / VB-Cable / VoiceMeeter) is selected; analyzer only hears the mic.
4. Double application of `band_sensitivity` (raw mag * sensitivity, then again in `_perceptual`) + no noise-floor/AGC ? dead meters or random clipping.
5. UI only shows Energy/Bass bars � no device picker, level meter, or spectrum bars to verify signal.

**Plan:**
1. Harden `AudioAnalyzer`: ensure analysis bus + SpectrumAnalyzer, activate input device, start mic capture, retry spectrum instance until valid, keep player playing / reconnect on stall.
2. Prefer loopback-like device names when present; expose device list API + tunable noise floor + single-path sensitivity + light AGC.
3. Emit stable energy/bass/mids/highs/kick/bands every frame from real FFT.
4. Effects sidebar: input device picker, status, input level, spectrum bars; wire sensitivity/noise floor.
5. Do not commit.

**Resolution:**
1. Root cause confirmed: spectrum instance could stay null; no device picker/reconnect; double sensitivity; silent system audio without loopback device.
2. `audio_analyzer.gd` rebuilt: muted analysis bus + SpectrumAnalyzer FFT_2048, mic capture kept playing with reconnect, spectrum bind retry, AGC + tunable noise floor, single-path sensitivity, auto-prefer Stereo Mix/VB-Cable/VoiceMeeter when listed.
3. `AudioState.input_level` + 16 normalized bands every frame; bass/mids/highs/energy/kick drive reactivity consistently.
4. Effects sidebar: input device dropdown + refresh, capture status, input level meter, 16 spectrum bars, mids/highs meters, noise floor slider.
5. Smoke: spectrum_bound=true, mic playing=true (headless level 0 expected without real input).


## 2026-08-13 - Drivers tab, expressions, time/volume identifiers

**Issue:** Per-effect Audio/LFO/Static mode pickers should go away. Need a Drivers tab (library of named signals) and every numeric FX input must accept a driver name or math expression. Follow-up: expressions must include time and volume (and other real built-ins) so e.g. volume * time01 and bass + time work in the same language.

**Plan:**
1. Log this issue. Do not commit. Append only.
2. DriverHub autoload + safe expression AST (numbers, identifiers, + - * / parentheses). No GDScript eval.
3. Built-in identifiers from real analyzer/path data (time, time01, volume/aliases, bass/mids/highs, beat, progress, cam_speed, lfo1/lfo2, noise, rand). Drivers tab lists them with hints.
4. User-created LFO/Noise/Random via modal; tweakable default LFO/noise/rand cards.
5. Extend slider_spin_link with LineEdit + driver picker; remove Mode/LFO/Audio-amount rows.
6. Persist driver defs + per-param expressions in session JSON. UTF-8 no BOM, LF-only.

**Resolution:**
1. Drivers tab (Effects | Drivers) with Built-in identifier hints + Signals cards (lfo1/lfo2/noise/rand + user-created). Create-driver modal (LFO/Noise/Random).
2. Expression language: numbers, identifiers, + - * / ( ). Unknown id -> 0; divide by 0 -> 0. time grows; time01/frac wrap 0-1.
3. FX numeric fields (slider_spin_link attach_driven) accept number, driver name, or math. + menu sets the identifier; Add new... opens the same modal.
4. Per-effect Mode/LFO/Audio-amount UI removed. Schedules/Play All unchanged. ASCII density dual-range stays numeric.
5. Session payload now includes drivers + fx params/expressions.

## 2026-08-13 - Drivers compile + time/volume in the same evaluator

**Issue:** Headless compile failed (class_name DriverExpr not registered under --script; inferred Variant types). Follow-up: expressions must combine time with audio/LFOs in the same language (volume * time, bass + time, lfo1 * volume) — not a parallel system.

**Plan:**
1. Preload driver_expr.gd instead of relying on class_name. Reuse one parser instance on DriverHub.
2. Keep identifiers in DriverHub._values updated every frame: time, time01/frac/time_norm, dt, sin_time, real audio bands, progress, cam_speed, lfo1/lfo2/noise/rand.
3. Drivers tab Built-in section lists them with one-line hints. ASCII density dual-range stays numeric.
4. Do not commit.

**Resolution:**
1. DriverExpr preloaded; DriverHub.eval_expr reuses a parser instance. SliderSpinLink uses explicit types + preload.
2. Same + - * / ( ) evaluator. time grows unbounded; time01 wraps 0-1 so volume * time01 stays bounded.
3. Built-in hints + picker include time/time01/dt/sin_time/volume (aliases level/amp/input_level) and real analyzer names (bass, mids/mid, highs/treble, kick, energy, peak, beat, bpm, band0-15).
4. progress / cam_speed read from the current flythrough item when those methods exist. fx_on skipped. No fake audio bands. No sin()/abs()/clamp() function library.

## 2026-08-13 - DriverHub / _raw_params compile errors

**Issue:** Godot console: Identifier "DriverHub" not declared (effects_sidebar.gd, playlist_sidebar.gd -- playlist_sidebar then fails to load). Identifier not found: _raw_params (camera_fx_effect.gd, cloth_effect.gd). Drivers tab / expressions must keep working.

**Root cause (likely):**
1. Autoload DriverHub is in project.godot, but scripts reference the singleton name. That name is not in scope until the autoload script compiles and the editor reloads -- a parse failure or load-order/class-cache cycle leaves DriverHub undeclared.
2. Subclasses then cannot see EffectLayer._raw_params (Godot inherited-member parse failure when a parent/autoload in the graph is invalid).

**Plan:**
1. Keep autoload DriverHub="*res://autoload/driver_hub.gd". Do not add class_name DriverHub (conflicts with the autoload name).
2. Resolve the hub via preload + /root/DriverHub (same pattern as slider_spin_link / effect_layer), not the singleton identifier.
3. Add EffectLayer.has_raw_param() and use it from camera_fx / cloth / ascii instead of touching _raw_params.
4. Headless compile_check those scripts. Do not commit. UTF-8 no BOM, LF-only.

**Resolution:**
1. Root cause: scripts used the DriverHub autoload identifier. That name is missing from script scope when the autoload is new, the editor class cache is stale, or Godot compiles via --script -- so effects_sidebar / playlist_sidebar failed, then the class-cache cycle made EffectLayer._raw_params invisible to subclasses.
2. Autoload kept: DriverHub="*res://autoload/driver_hub.gd" (no class_name DriverHub). UI/FX resolve it with preload(driver_hub.gd) for constants and get_node_or_null("/root/DriverHub") for the instance.
3. EffectLayer.has_raw_param() added; camera_fx / cloth / ascii use that instead of _raw_params. Expression storage on EffectLayer is unchanged.
4. Headless: driver_hub, effect_layer, camera_fx, cloth, ascii load with no DriverHub/_raw_params errors. Editor --quit creates autoloads with no those errors. Remaining --script ShowDirector/AudioAnalyzer misses are the old autoload-global limitation, not this bug. Do not commit.


## 2026-08-13 - Boot loader count jumps 1 to 18

**Issue:** Splash "Loading assets" sits at 1/N then snaps to 18 (or the full unique total). User wants the completed count to tick 1, 2, 3, 4… and to see each filename — not a jump that hides the work.

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. Root cause (likely): previous fix froze N and used threaded fraction for the bar, but K = finished_keys.size() after AssetCache.poll() drains every completed job in one frame, so the integer stays at 1 (videos/cached) then jumps when the burst lands.
3. Queue newly finished paths; reveal one per ~40ms (or immediately if only one completed). Label Loading assets K / N. Cycle/show the current or just-finished filename.
4. Keep unique frozen total N. Bar stays monotonic (floor + shown + in-flight fraction). Do not finish splash until the reveal queue drains (unless timeout).
5. Update Resolution. No commit.

**Resolution:**
1. Root cause: AssetCache.poll() drains every completed threaded job in one frame. Boot loader then set K = finished_keys.size(), so the label sat at 1 (video/cached already warm) while the bar moved on threaded fraction, then snapped to 18 when the burst landed.
2. Newly finished paths go into a FIFO reveal queue. K increments by 1 every ~40ms (immediately for the first). Splash waits until the queue is empty. Timeout flushes.
3. Detail cycles in-flight filenames, then shows each file as its count ticks. Frozen unique N unchanged. Bar = shown K + in-flight fraction, never backwards (floor).
4. Files: ui/boot_loader.gd. Headless load OK. No commit.

## 2026-08-13 - Drivers picker, live audio, ASCII density

**Issue:**
1. No clear way to attach a driver to FX value fields (Drivers tab exists; fields do not expose a usable picker).
2. Built-in audio identifiers (volume, bass, mids, highs, energy, ...) stay at 0 / do not react.
3. ASCII density is a numeric dual-range only -- cannot drive it with bass * 80 or lfo1.

**Plan:**
1. Make attach_driven's picker a visible + Button + PopupMenu (not a tiny MenuButton), listing built-ins even if the hub lookup fails; Add new... still opens the create modal and assigns. Use it on all FX params including a new ASCII Density field.
2. DriverHub: ingest live analyzer properties via Object.get (no AudioState cast) and AudioAnalyzer.state_updated; process after the analyzer. ShowDirector already re-evals expressions in apply_audio_state; keep that. Drivers tab live labels stay hooked to values_updated.
3. ASCII: one Density expression field (number or bass * 80 / + picker). Dual-range remains the numeric/random window and is ignored for the live value while Density is an expression.
4. No DriverHub.foo identifier. Do not commit. UTF-8 no BOM, LF-only.

**Resolution:**
1. FX value rows use a LineEdit plus a visible + Button. + opens a PopupMenu of built-in and user drivers (fallback list if the hub is missing). Choosing one sets the field; Add new... opens the create modal and assigns. ASCII Density has the same row.
2. Audio was dead because DriverHub did `current_state as AudioState`, which is null after class-cache/reload, so every band stayed 0. It now reads live fields via Object.get, also on AudioAnalyzer.state_updated. volume = max(energy, input_level). Same /root/DriverHub instance as effects. ShowDirector still re-evals expressions every apply_audio_state.
3. ASCII Density is an expression field (e.g. bass * 80 or + lfo1). The old min-max range is only for numeric/random. Density wins every frame when set.
4. Do not commit.


## 2026-08-13 - Drivers audio still dead, slim time, visible Driver dropdown

**Issue:**
1. Drivers tab: time/time01/sin_time move, but volume/bass/mids/highs/energy stay at 0. EQ graph in the Effects sidebar does move.
2. Too many time-like built-ins (time01, frac, sin_time, dt, progress). User only wants time.
3. Still cannot get bass/volume into FX value fields. + is unusable; need a visible dropdown and paste/copy.

**Plan:**
1. Audio: DriverHub must use the same pre-gate ui_bands the EQ uses (audio_analyzer.gd), not gated AudioState.bass/energy (noise gate zeros those). Add AudioAnalyzer.get_driver_audio() Dictionary. No AudioState casts.
2. Slim builtins to time + audio + lfo1/lfo2/noise/rand. Drop time01/frac/sin_time/dt/progress/cam_speed from UI and picker.
3. Replace + PopupMenu with a labeled OptionButton "Driver" on every attach_driven row (including ASCII Density). LineEdit stays for type/paste. Drivers tab names click-to-copy.
4. Do not commit. UTF-8 no BOM, LF-only.

**Resolution:**
1. Audio was dead because DriverHub read gated AudioState.bass/energy/volume (noise gate zeros those) while the EQ graph uses pre-gate ui_bands. DriverHub now calls AudioAnalyzer.get_driver_audio() and derives volume/bass/mids/highs/energy/peak from those same 16 bins. No AudioState casts.
2. Built-in list/picker: time, volume, energy, peak, bass, mids, highs, kick, beat, bpm, lfo1, lfo2, noise, rand, band0. Dropped time01, frac, time_norm, dt, sin_time, progress, cam_speed from UI and picker.
3. FX rows (including ASCII Density) have a LineEdit (type/paste, Ctrl+V) plus a visible Driver OptionButton. Drivers tab names are click-to-copy with a Copy button.
4. Headless compile_check: picker slimmed, scripts load. Do not commit.


## 2026-08-13 - Driver dropdown only on Density; hide old Reactivity

**Issue:**
1. User only sees a Driver dropdown next to ASCII Density. Every FX numeric input must take a driver name and math (bass, -bass, bass * 10).
2. Old Audio Reactivity / What reacts UI still sits on the Effects tab and competes with Drivers.

**Plan:**
1. Fix attach_driven layout (two-row: slider, then LineEdit + visible Driver) so the dropdown cannot clip off the 340px sidebar. Use that helper on all FX numeric rows.
2. Confirm unary minus and + * / eval; effects already re-eval via apply_audio_state.
3. Hide Audio Reactivity + What reacts from Effects. Move input device + EQ + analyzer sliders onto the Drivers tab. Keep per-effect Affects checkboxes (particles/point-cloud).
4. Do not commit. UTF-8 no BOM, LF-only.

**Resolution:**
1. Driver dropdown was clipped on tscn HSliders in the 340px sidebar; ASCII Density showed it because that row was built at runtime. attach_driven is now a two-row wrap (slider, then LineEdit + visible Driver) used on every FX numeric row (glitch, chromatic, feedback, pixel sort, cloth, point cloud, camera/lens, ASCII density, play speed, style interval). Dual-range stays numeric for random; Density is the expression. Schedules stay durations.
2. Parser already did unary minus and + * / ( ). Tests: -bass, bass * 10, volume + 1, lfo1 * 2 + 0.1. ShowDirector.apply_audio_state re-evals stored expressions every frame.
3. Audio Reactivity toggle + What reacts (scale/light/emission/rotation/noise/camera motion) are hidden from Effects. Input device + EQ + analyzer sliders moved onto the Drivers tab. Particles/point-cloud Affects checkboxes stay on those effects.
4. Do not commit.


## 2026-08-13 - Restore deform FX, wide expression clamp, audio ~1

**Issue:**
1. Noise/scale/rotation/camera disappeared with the old Reactivity panel. Bring them back as driver-capable FX rows.
2. bass * 10000 is clamped to the slider max.
3. Audio driver values sit around 0.001 instead of ~1.

**Plan:**
1. Show Deform section (scale/rotation/noise/camera) on Effects with LineEdit + Driver. Keep Affects checkboxes. Hide band pickers and Audio Reactivity master. Ungate apply path from RH.enabled() master; amount IS the expression (no second bass multiply).
2. eval_num: expressions clamp to +/-1e6, not slider max. Slider range is drag-only. Parser: 10000 and 1e4.
3. get_driver_audio: max-of-group + peak AGC so loud music ~1 (0-2).
4. Do not commit. UTF-8 no BOM, LF-only.

**Resolution:**
1. Deform (Scale / Rotation / Noise / Camera) is back on Effects as driver rows. Amount is the expression; no second bass multiply. Affects stay Main / Scatter / Outer.
2. eval_num and slider_spin_link keep expressions at ±1e6 (bass * 10000 / 1e4). Slider range is drag-only.
3. Audio drivers use the same 0–1 EQ bins as the graph (~1 when loud).
4. Add-ons: Lights/Media removed from Affects. ASCII Random Density + Invert Density hidden/disabled. New ASCII presets (Emoji, Faces, Runes, Cyrillic, Crosses, Stars) in the dropdown and Play All style cycle. Point cloud bakes per-vertex texture color. Cloth is hang/wind/gravity, not fbm. Cloth Gravity is a driver field.


## 2026-08-13 - Every numeric input must accept drivers

**Issue:**
1. User: almost no inputs accept drivers. ASCII Active/Inactive schedule and most other fields were still plain SpinBox / HSlider.
2. schedule_seconds_pair.gd and playlist SpinBoxes were never wrapped with LineEdit + Driver.
3. Rule: every numeric input in the app (Effects, Drivers, Playlist, schedules, flythrough, scatter, ASCII, cloth) must take bass / -bass / bass * 10, re-eval every frame, not clamp to slider max.

**Plan:**
1. Audit ui/*.gd ui/*.tscn for SpinBox/HSlider/schedule/dual_range.
2. Wrap all of them with SliderSpinLink.attach_driven (or replace_spin_with_driven for .tscn SpinBoxes).
3. ScheduleSecondsPair and DualRangeSlider: each end is a driver row; FxAutomation no longer clamps gates to 120s / speed to 4.
4. Playlist: fly speed, env scale, durations, scatter density, edit scale, row duration.
5. Do not commit. UTF-8 no BOM, LF-only.

**Resolution:**
1. Shared widget is slider + LineEdit + visible Driver on every numeric field. Expressions eval every frame via DriverHub.eval_value; slider max is visual-only (±1e6).
2. ASCII and every other effect schedule (Active/Inactive), Play All speed, style interval, analyzer intensity/sensitivity/noise floor, driver-card params, and create-driver modal numbers all use that widget.
3. Playlist fly speed, env scale, tab durations, scatter density, per-item edit scale, and PlaylistRow duration use the same widget. Live expressions push fly/scale every frame; scatter count rebuilds when the rounded int changes.
4. Left as non-numbers: checkboxes, OptionButtons (path style, scatter layout, ASCII preset, camera preset, play mode), color/file pickers, third-party hterrain editor, unused performer_panel.tscn.
5. Do not commit.


## 2026-08-13 - Object.get two-arg compile error

**Issue:**
1. Godot Errors (20). Screenshot: reactivity_hub.gd:45 `n.get("camera_preset", "Off")` — Too many arguments for get(). Expected at most 1 but received 2.
2. `n` is Node/Object. Object.get(property) takes one arg; Dictionary.get(key, default) takes two. One parse error cascades to every script that uses the hub.

**Plan:**
1. Use one-arg Object.get plus null default. get_field already exists — make it coalesce null to fallback.
2. Grep two-arg .get on Objects; fix := inference leftovers in effects_sidebar.
3. Headless compile_check + editor --quit. Do not commit. UTF-8 LF.

**Resolution:**
1. Root cause: Dictionary-style get(key, default) called on the ReactivitySettings Node. Object.get() takes one argument. That parse error cascaded (editor Errors ~20).
2. enabled() now does `n.get("camera_preset")` then defaults to "Off" if null. get_field coalesces null to fallback.
3. Typed Node/int on effects_sidebar get_parent/get_index so Godot 4.7 can infer.
4. effects_sidebar.tscn had a UTF-8 BOM so the tscn parser saw "Expected '['" at line 1. BOM stripped.
5. Headless compile_check: reactivity_hub LOAD OK. Editor --quit: no script parse errors (hterrain UID warnings only). Do not commit.


## 2026-08-13 - Cast freed HSlider in refresh_all_previews

**Issue:**
1. Runtime: "Trying to cast a freed object" at slider_spin_link.gd:318 `_driven[id_any] as HSlider`.
2. `_process` → refresh_all_previews every frame. Driver-card rebuild / queue_free leaves instance IDs in `_driven`. Godot 4 errors on `as HSlider` before `is_instance_valid` runs.

**Plan:**
1. Read Variant, `is_instance_valid` first, then cast. Unregister on tree_exiting. Sweep meta casts and effects_sidebar driver-card writes.
2. Do not commit. UTF-8 no BOM, LF-only.

**Resolution:**
1. `refresh_all_previews` reads the dict Variant, skips unless `is_instance_valid`, then `as HSlider`. Dead ids leave `_driven` and `_busy`.
2. `attach_driven` connects `tree_exiting` with the instance id (not the node). Meta LineEdit/OptionButton/SpinBox casts go through the same live check.
3. Drivers tab: `_on_driver_values` (live readouts) and `_driver_card_writes` (per-frame expression writes) use the same pattern and unregister on `tree_exiting`. LFO row / drive-option dicts too.
4. Dual-range and schedule `_process` skip freed sliders/labels. Driver UX unchanged. Do not commit.


## 2026-08-13 - Scatter density and layout do nothing (grid ≈ random)

**Issue:** Scatter tab Density and Layout controls do not meaningfully change placement. Grid vs Random look the same; Circular is only slightly different. Expected:
- Grid: regular 3D lattice filling a volume cube (not a 2D plane, not beads on the fly path).
- Random: truly random positions in that same volume.
- Circular: keep/improve so it is clearly distinct (rings / cylinder).
- Density: must change how many items spawn and how tightly they pack.
- Layout: must actually switch those modes.

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. Root cause (likely): items are always spaced along the camera Curve3D; layout only adds a tiny side/up offset (`_scatter_side_range` ≈ 8% of env width, 1.2–10 m). Grid is a 2D path-local lattice (max 6×3), so from the camera it matches random beads. Density only adds more beads on the same line, so packing barely changes.
3. Place in a volume cube from the path/env AABB. Grid = 3D lattice (nx×ny×nz from count). Random = uniform in the cube. Circular = stacked concentric XZ rings. Density = count → spacing in the fixed cube.
4. Keep UI wiring; stamp layout on empty scatter config; update Scatter tab copy. No commit.

**Resolution:**
1. Root cause: every clone was placed on the camera Curve3D (`sample_baked_with_rotation`). Layout only added a tiny path-local side/up offset (`_scatter_side_range` 1.2–10 m). Grid was a 2D lattice in that plane (max 6 cols × 3 levels), so Grid ≈ Random beads along the path. Density only added more beads on the same line.
2. Placement is now a volume cube from the path/env AABB (side clamped 10–80 m). Grid = 3D nx×ny×nz lattice. Random = uniform XYZ in the cube. Circular = stacked concentric XZ rings (cylinder). Same cube, so density (count 1–80) changes packing tightness.
3. Files: `items/flythrough_environment.gd` (placement), `ui/playlist_sidebar.gd` (copy + stamp layout on empty config without spawning). Scripts compile. No commit.
4. Limits: density still 1–80; GIF/video scatter still capped at 24 clones; huge terrains use a capped cube around the AABB center.

## 2026-08-13 - Item property drivers die when Edit popup closes

**Issue:** Editing an item (e.g. Scale) and attaching a driver only animates while the Edit item popup is open. Closing the window bakes the current number; the property becomes a static value instead of staying driven.

**Plan:**
1. Log this issue. Do not commit. Append only (do not overwrite the scatter/density/layout entry). UTF-8 no BOM, LF-only.
2. Root cause (likely): live eval is gated on `_edit_dialog.visible`; `_apply_edit_scale` / `_set_entry_user_scale` store only a float `user_scale`; reopen uses `str(snappedf(scale_val))`, wiping the expression.
3. Persist `user_scale_expr` on the playlist entry (+ config). Keep evaluating selected items every frame after close. Restore the expression when reopening Edit. Closing must not replace a driver with a snapshot number.
4. Touch driver-persistence paths in `playlist_sidebar.gd` only. Avoid scatter/layout work in `flythrough_environment.gd`.
5. Update Resolution. No commit.

**Resolution:**
1. Root cause: live eval ran only while `_edit_dialog.visible`. `_set_entry_user_scale` stored a float snapshot; reopen did `set_expr(str(snappedf(scale_val)))`, so closing the popup baked the driver into a number.
2. Persist `user_scale_expr` on the playlist entry and layer config. Closing Edit commits the expression (not just the eval). Selected Env/Main/Scatter items re-eval every frame after close and keep pushing live scale. Reopening Edit restores the expression. Header Env scale shows the same driver when it is the selected env.
3. File: `ui/playlist_sidebar.gd` only (no scatter/layout changes in `flythrough_environment.gd`). `script_check` valid. No commit.

**Limits:** The driver stays on that playlist item. It animates while the item is the applied selection. A static number in Edit still clears the driver. Session autosave keeps `user_scale_expr` on the entry list.

## 2026-08-13 - Drivers panel tiny values, fake BPM, LFO/noise/random stuck at 0

**Issue:** Drivers tab:
1. Live values are tiny (0.000x) instead of a usable default around 1.
2. BPM shows 120 — looks hardcoded; user does not want fake BPM.
3. LFO / LFO1 / LFO2, Noise, and Random readouts show 0 while the signals actually drive properties.

**Plan:**
1. Log this issue. Do not commit. Append only (do not overwrite scatter/layout or item-driver-persistence entries). UTF-8 no BOM, LF-only.
2. If BPM is a hardcoded 120 fallback (not real tempo detection), remove it from UI, picker, hub, and unused analyzer paths. Keep real beat/kick.
3. Live labels: builtin rows and signal cards share ids (lfo1/lfo2/noise/rand), so the dict keeps only the last Label and the builtin row stays at "0". Track every label per id and write the real hub value.
4. Normalize usable driver outputs so typical magnitude is ~1 (audio peak-follow; LFO/noise/random centered around 1). Do not only scale the display string. Do not touch playlist_sidebar persistence.
5. Update Resolution. No commit.

**Resolution:**
1. Root cause of 0.000x: audio identifiers were raw/weak FFT magnitudes (often 1e-3) even when the EQ looked alive. LFO/noise/rand readouts showed 0 because builtin rows and signal cards shared the same id in `_driver_live_labels`, so only one Label was updated and the visible builtin row stayed at the initial "0".
2. BPM was hardcoded 120 whenever beat intervals were empty (no real tempo detector). Removed from Drivers UI, picker, DriverHub, AudioAnalyzer, and AudioState. Beat/kick stay.
3. Usable values now sit around 1: audio peak-follow (loud ≈ 1, silence ≈ 0); LFO mean 1 (depth 1 sweeps ~0–2); noise 0–2; rand default 0–2. Display shows the live hub value on every label for that id.
4. Files: `autoload/driver_hub.gd`, `ui/effects_sidebar.gd`, `ui/slider_spin_link.gd`, `autoload/audio_analyzer.gd`, `core/audio_state.gd`. Did not touch `playlist_sidebar.gd`. script_check valid. No commit.

## 2026-08-13 - Godot debugger / output errors

**Issue:** User reports a bunch of errors in the Godot Output / debugger. MCP console + playtest log:

1. Parse errors on flythrough scatter reload: `_scatter_offset_for_index()` not found; cannot infer `offset`; `length` / `path_xf` / `_scatter_side_range` undeclared. Cascade type-inference errors on the same lines.
2. Editor: `Node not found: /root/DriverHub` from the edited Main viewport.
3. Playtest warnings: Radiance HDR extra headers (GAMMA / PRIMARIES / EXPOSURE) from `AssetCache._worker_load_image`.
4. Playtest warning: shader requires tangents on chiostro `ArrayMesh_3obsq` (normal-mapped imported GLB).

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. Do not revert scatter volume cube, `user_scale_expr`, or driver normalization.
3. Scatter parse errors: leftover path-offset helpers after the volume-cube rewrite. Confirm disk scripts already use `_scatter_volume_*`; reload so the Errors dock drops stale `gdscript://` reloads. Fix any remaining call sites if present.
4. DriverHub: project code already uses `get_node_or_null`. Treat as editor-preview / stale autoload after a failed reload unless a hard `get_node` remains.
5. HDR: `request_texture` falls through to `Image.load_from_file` when `load_threaded_request` fails even if `ResourceLoader.exists` — re-parses .hdr and warns. Use imported Texture2D only for res:// HDRIs.
6. Tangents: chiostro import has `ensure_tangents=true` but one surface still lacks them (normal map). Generate tangents (or disable normal maps) at instantiate.
7. Re-read console. Update Resolution. No commit.

**Resolution:**
1. Scatter parse errors were stale `gdscript://` reloads from the volume-cube rewrite. Disk already uses `_scatter_volume_*` / `_scatter_position_for_index` (no `_scatter_offset_for_index` / `_scatter_side_range`). `editor_refresh` cleared 20 Errors-dock entries. LSP: 68/68 scripts compile. Did not revert scatter volume, `user_scale_expr`, or driver normalization.
2. DriverHub `get_node` miss was editor-preview / leftover after a failed reload. Project code uses `get_node_or_null`. Gone after reload.
3. HDR warnings: `request_texture` fell through to `Image.load_from_file` when threaded import request failed, re-parsing Radiance headers. Imported `res://` textures now sync-load instead. `normalize_key` maps Windows absolute paths (incl. drive-letter case) back to `res://`.
4. Tangent warning: chiostro import has `ensure_tangents=true` but one normal-mapped surface still lacks tangents. `SceneMeshFx.ensure_mesh_tangents` generates them (or disables the normal map) on instantiate. Wired from layer_slot, env/center/scatter swaps, AssetCache, Scene3DItem.
5. Editor console errors after refresh: 0. Playtest HDR/tangent lines are from the session started before the fix; they will not recur on the next Play. User-uploaded HDRIs outside `res://` can still warn (engine HDR loader). No commit.



## 2026-08-13 - Point cloud hides noise; images ignore effects; scatter density/layout still dead

**Issue:** Related flythrough FX / scatter bugs:
1. Point Cloud + Noise Displace: only the point cloud is visible. Noise does not displace the mesh. Point cloud should be an extra visualization; the underlying mesh must still deform.
2. Scattered images ignore mesh-deforming FX. Images should be subdivided planes so noise (and other vertex FX) warp them like other geometry.
3. Scatter Density + Layout still look the same (grid/random/circular, density 1–80). Previous volume-cube rewrite may be unused, overwritten, or too small. Re-investigate from scratch; do not assume that fix works.
4. Clothing overlaps noise deform conceptually. User is unsure they should keep it. Do NOT remove clothing unless a trivial crash. Note the overlap.

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. Diagnose: point-cloud overlay vs original mesh (cull layers / hide / skip noise); media_prop plane tessellation + scatter clone materials; scatter placement at runtime (source key, live apply, volume size).
3. Keep noise deforming originals while point cloud overlays vertices (overlay should follow displaced verts if possible). Subdivide image planes; apply FX to scatter clones.
4. Make density/layout visually obvious: 3D lattice / uniform cube / stacked rings; density = count and packing in a real volume.
5. Leave cloth. Update Resolution. No commit.

**Resolution:**
1. Point cloud hid originals on cull layer 19, so noise could warp the mesh but the camera only saw a static rest-pose point overlay. Originals stay visible; leftover hide-layers/camera cull are restored. Overlay gets the same noise/cloth vertex displace (`point_size` + vertex colors on `noise_deform.gdshader`).
2. `_apply_noise_distort` never called `_apply_media_deform` — it cleared media uniforms and SoftBodies every tick. Image scatter skipped the mesh noise path (`media_screen` meta). Now media deform runs with amount × 0.55 (was × 0.012). Planes are 32×32 subdivided (`PlaneMesh` FACE_Z); clones share that mesh + shader so they warp too.
3. Volume-cube code was live, but the cube was 10–80 m (often ~43–54 m). 18 vs 80 items of 0.85 m looked the same. New packing cube at path/env center: cell lerps 5.5 m → 1.15 m with density; side = cell × lattice span, clamped 3–22 m. Grid = 3D nx×ny×nz lattice; Random = uniform XYZ; Circular = stacked concentric XZ rings (more rings). Still images use full count 1–80; GIF/video still cap at 24. Layout+count stay in the scatter source key.
4. Cloth left in place. It shares `noise_deform.gdshader` cloth uniforms (and SoftBody on media grids) with noise — same vertex-warp family, not a second unrelated system.
5. Files: `scene_mesh_fx.gd`, `noise_deform.gdshader`, `media_screen.gdshader`, `media_prop.gd`, `flythrough_environment.gd`, `playlist_sidebar.tscn`. script_check valid. No commit.

## 2026-08-13 - Reset to default skips left side of Effects

**Issue:** Effects **Reset to default** only restores the right column (FxSection: Play All / ASCII / glitch / etc. toggles off). The left column (Deform: Scale / Rotation / Noise / Camera, amounts, Affects, axes, driver expressions) stays dirty. Reset should restore every Effects control on both sides to true defaults.

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. Diagnose: reset turns off FX layer toggles + a few RH affect_* flags; it does not reset Deform amounts/expressions/targets/axes, nor FX slider/driver values.
3. Add ReactivitySettings.reset_to_defaults(); clear ShowDirector FX params; expand sidebar sync to restore all Deform + FxSection widgets (toggles, sliders, expressions, dropdowns, schedules, Affects).
4. Prefer effects reset UI path only. Do not touch scatter/noise/point-cloud coexistence work.
5. Update Resolution. No commit.

**Resolution:**
1. Reset previously: disabled Play All + visual FX toggles (right/FxSection), cleared automation, set affect_* false, restored poses. Skipped: Deform amounts/drivers/Affects/axes, FX slider expressions, presets, schedules, point-cloud Affects.
2. Root cause: `_sync_all_widgets_after_defaults_reset` only mirrored a few RH toggles; RH itself never restored numeric/target defaults; `_push_driven_reactivity` kept pushing leftover left-side expressions.
3. Files: `autoload/reactivity_settings.gd` (`reset_to_defaults`), `autoload/show_director.gd` (call it + clear FX params), `ui/effects_sidebar.gd` (full left+right widget restore), `ui/slider_spin_link.gd` / `ui/schedule_seconds_pair.gd` / `ui/dual_range_slider.gd` (force-overwrite expressions). No commit.

## 2026-08-13 - Scatter density still capped; need thousands

**Issue:** Scatter density still produces too few instances. Prior caps: slider 1–80, still images 1–80, GIF/video 24. Volume cube was shrunk to ~3–22 m so packing looked different — do not go back to a huge empty cube, but count must scale to thousands. Changing density must actually spawn that many clones (not clamp silently). Keep Grid / Random / Circular distinct.

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. Raise density UI + spawn clamps to 2000. Remove silent 80/24 clamps in source key, volume, rebuild, and sidebar eval.
3. GPU instancing: MultiMesh for still images, primitives, imported meshes, and GIF/video (one decoder + shared material). Skip SoftBody on scatter instances (shader cloth/noise stay). Cube grows modestly above 80 so thousands are dense, not an 80 m void.
4. Keep layout modes, point-cloud+noise coexistence, image-plane subdivision, driver persistence/normalization, reset-to-default, HDR/tangent fixes.
5. Update Resolution. No commit.

**Resolution:**
1. Density range is now 1–2000 (was 1–80). Sidebar eval, source key, volume, and rebuild no longer clamp to 80 or 24. Changing density spawns that many instances.
2. Scatter uses MultiMesh (GPU instancing) for still images, primitives, imported meshes, and GIF/video. One hidden media host drives a shared material so GIF/video can also reach 2000 (one decoder; all instances show the same frame). SoftBody is skipped on scatter MultiMesh (shader cloth/noise stay).
3. Volume cube: 1–80 keeps the prior 3–22 m packing. Above 80 the cube grows modestly (cap 22→36 m, cell 1.15→1.55 m) so thousands stay dense, not an 80 m void. Grid / Random / Circular unchanged (circular ring cap 8→48).
4. Files: `items/flythrough_environment.gd`, `ui/playlist_sidebar.gd`, `ui/playlist_sidebar.tscn`, `core/scene_mesh_fx.gd`. script_check valid. No commit.


## 2026-08-13 - Point cloud must hide mesh but keep deforming points

**Issue:** When Point Cloud is ON, the base mesh must not be visible (no shaded surface). Deformations (noise, cloth, scale, rotation) must still run and show on the dots. Dots should sit on the deforming geometry, not a rest-pose copy. A previous fix left the original mesh visible so noise could be seen — wrong for visibility.

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. Hide originals via camera cull layer (bit 19 / editor layer 20) so the HSPointCloud child stays drawn. Do not use Node.visible — that would hide the overlay too.
3. Keep applying noise/cloth shader uniforms to the overlay (same seed / amount / cloth as the source mesh). Copy source normals into the points mesh so displace matches. Re-stamp deform after overlay build.
4. When Point Cloud is off: restore mesh layers, shadows, and camera cull. Do not revert scatter density work.
5. Update Resolution. No commit.

**Resolution:**
1. Point Cloud ON hides the shaded mesh via camera cull layer 20 (bit 19). Overlay child stays on layer 1, so dots still draw. `Node.visible` is left on so noise/cloth keep stamping and the overlay is not inherited-hidden. Shadows on originals are off while hidden.
2. Overlay is still a points mesh, but it gets the same noise/cloth vertex uniforms (same seed/amount/axes/time) as the source. Source normals are copied into the points mesh so displace matches. Re-stamp after overlay build/clear/size update.
3. Point Cloud OFF restores mesh layers, shadow casting, and camera cull.
4. Files: `core/scene_mesh_fx.gd`, `items/flythrough_environment.gd` (point-cloud hide/deform only). Scatter density/layout untouched. `script_check` valid. No commit.

## 2026-08-13 - ASCII: remove Random Interval, keep Density, drive styles

**Issue:** User wants **Random Interval** gone from ASCII (the Style Switch "RND interval" jitter). Do **not** remove Density. Density must stay a driver-capable slider. Follow-up: the ASCII **Style** dropdown must also accept a driver/expression that switches charsets over time (map a signal to style index). Do not revert scatter / point-cloud / reset / other parallel work.

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. Remove StyleJitterToggle ("RND interval") and style_jitter scheduling. Keep Interval (sec) and Style Switch. Keep Density slider + attach_driven. Unhide the Density label if it was hidden.
3. No existing enum-driver widget — add attach_driven_choice (OptionButton + LineEdit + Driver). Eval maps to preset index with wrap. ASCII reapplies charset each frame from style_index. Density stays animatable.
4. Update Resolution. No commit.

**Resolution:**
1. Random Interval was the Style Switch **RND interval** toggle (`style_jitter`): it randomized the preset-cycle period. Removed the control and that jitter path. Style Switch still uses a fixed Interval. Density was never deleted; its label had been hidden. Label is visible again. Density stays `attach_driven` (number / bass * 80 / Driver) and still feeds the ASCII shader every frame.
2. Style dropdown is now driver-capable: LineEdit + Driver under the preset picker. Expression → wrapped integer index into the preset list (e.g. `lfo1 * 15`, `time`, `bass * 10`). Live eval in `AsciiEffect` swaps charset/tint/cell_aspect without overwriting Density. Manual picks still set a numeric index.
3. Files: `ui/effects_sidebar.tscn`, `ui/effects_sidebar.gd`, `ui/slider_spin_link.gd`, `effects/fx_automation.gd`, `effects/ascii_effect.gd`, `autoload/show_director.gd`. No commit.

## 2026-08-13 - Crash: freed overlay `is` on playlist main-item change

**Issue:** Playing/changing a playlist of main items crashes: `Left operand of 'is' is a previously freed instance` at `scene_mesh_fx.gd:174` `update_overlay_point_size`, called from `flythrough_environment.gd:244`. `_pc_overlays` still holds HSPointCloud refs from the previous centerpiece after it was `free()`d. Godot forbids `is` on a freed Object; `is_instance_valid` was checked too late.

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. In `update_overlay_point_size`, check `!= null` + `is_instance_valid` BEFORE any `is` / cast. Prune freed refs from the overlays array.
3. Invalidate/rebuild overlay lists when the main item (and env/scatter) is swapped, freed, or replaced. `_swap_centerpiece_packed` currently frees children without `_reapply_live_mesh_fx`.
4. Fix the same `is`-before-valid pattern on overlay metas in `scene_mesh_fx.gd` and `flythrough_environment.gd`. Do not touch Feedback/ASCII / effects_sidebar work.
5. Update Resolution. No commit.

**Resolution:**
1. Root cause: playlist main-item change goes through `_swap_centerpiece_packed`, which `free()`s the old centerpiece (and its HSPointCloud children) but left `_pc_overlays` / `_pc_built` intact. The next `set_point_cloud` size-update hit `ov_any is MeshInstance3D` on a freed instance. Env packed-swap had the same hole.
2. `update_overlay_point_size` now checks `!= null` + `is_instance_valid` before any `is` / cast, prunes dead refs in-place, and returns whether it pruned so the caller rebuilds. Same order on overlay metas and other `is` loops in these two files.
3. Layer free/swap invalidates `_pc_overlays` first; packed centerpiece/env swaps then call `_reapply_live_mesh_fx()` so overlays are rebuilt for the new item.
4. Files: `core/scene_mesh_fx.gd`, `items/flythrough_environment.gd`. `script_check` valid. No commit.

## 2026-08-13 - Feedback + ASCII goes black; trails should sit on top

**Issue:** With ASCII on, Feedback turns the image very dark/black. Feedback should composite **on top** of ASCII (additive / overlay color trail), not darken or replace the frame with black. Need a no-fade option and an opacity/persistence slider so trails can stay fully visible (opaque) instead of always decaying.

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. Diagnose: Feedback is CanvasLayer 2 (under ASCII 10), `mix()` toward a post-draw capture that already includes ASCII's black glyph gaps, and persistence is clamped below 1.0.
3. Draw Feedback after ASCII; overlay color trails (alpha-gated, no lerp-to-black). Persistence max = no fade. Add/repurpose Opacity slider with driver support.
4. Keep ASCII Density, style drivers, and removed Random Interval. Do not revert scatter / point-cloud / reset-to-default / driver work.
5. Update Resolution. No commit.

**Resolution:**
1. ASCII punches empty glyph cells to black. Feedback was CanvasLayer 2 (under ASCII 10) and `mix()`'d the live frame toward a post-draw capture of that dark ASCII buffer. Persistence was also clamped below 1.0 (slider 50–98, shader 0.55–0.97), so the loop always decayed toward black.
2. Feedback now draws at layer 12 (on top of ASCII). It does not BackBufferCopy, so `screen_texture` stays the pre-ASCII color scene. Overlay is alpha-gated: dark history is transparent (ASCII shows through); bright trail color sits on top. No lerp-to-black.
3. **Opacity** (was Mix): 0 = no overlay, 100 = full-strength trail. Driver-capable. **Persistence**: 0 = fade immediately, 100 = no fade. Both 0–100.
4. Files: `effects/feedback_effect.gdshader`, `effects/feedback_effect.gd`, `ui/effects_sidebar.tscn`, `ui/effects_sidebar.gd`, `autoload/show_director.gd`. `script_check` valid. No commit.

## 2026-08-13 - Noise distort does not warp point cloud

**Issue:** When Point Cloud is ON, noise distort does not move the dots. Shaded mesh is correctly hidden (cull layer 20). Dots must still warp with noise (and cloth/other vertex deforms). Prior overlay-uniform path in `scene_mesh_fx.gd` / `flythrough_environment.gd` / `noise_deform.gdshader` is not working — diagnose from current code, do not assume it does. Keep mesh hidden. Do not revert playlist overlay `is` crash fix, scatter MultiMesh density, feedback/ASCII, drivers.

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. Trace noise amount → `_apply_noise_distort` / overlay materials → visible point mesh. Check: overlay shader without vertex displace; uniforms only on hidden originals; rest-pose rebuild; stamp order; scatter MultiMesh; media skipped.
3. Put the deform shader on the visible overlay (unshaded points + same noise/cloth vertex math), stamp overlays directly every tick (not via hidden-parent walk / `_noise_mats` prune). Scatter MM overlays too. Mesh stays cull-hidden.
4. Update Resolution. No commit.

**Resolution:**
1. Overlay used `StandardMaterial3D` (no vertex displace). A secondary path swapped in shaded `noise_deform.gdshader` via `_ensure_noise_materials`, which put overlays in `_noise_mats`. `_prune_noise_materials` then restored `StandardMaterial3D` whenever the hidden parent was skipped (48-mesh cap, amount dip). Visible dots, no warp.
2. Overlay native material is now unshaded `point_cloud.gdshader` with the same noise/cloth vertex math. Uniforms are stamped on `_pc_overlays` and scatter MultiMesh overlays every tick, after prune, not through hidden-parent materials. Mesh stays cull-hidden on layer 20. Media planes still skipped. Playlist `is_live` before `is` kept.
3. Files: `effects/point_cloud.gdshader`, `core/scene_mesh_fx.gd`, `items/flythrough_environment.gd`. `script_check` valid. No commit.

## 2026-08-13 - Debugger errors + noise deform does nothing

**Issue:** Godot debugger/output has errors. Noise distort deforms nothing (meshes, scatter, point cloud). Likely related to recent point-cloud + noise work (`effects/point_cloud.gdshader`, `core/scene_mesh_fx.gd`, `items/flythrough_environment.gd`, `effects/noise_deform.gdshader`).

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. Collect ALL distinct errors via Godot MCP `editor_get_console` + `debugger_get_log` (paginate).
3. Diagnose noise no-op: shader compile, uniforms, prune/restore, amount~0, point-cloud path, Affects gating, overlay shader swap vs `_apply_noise_distort`.
4. Fix errors and restore visible deform: normal mesh when Point Cloud OFF; dots when ON (mesh hidden); scatter/image planes as before. Do not revert playlist overlay `is`, scatter MM 2000, feedback/ASCII, drivers, reset-to-default.
5. Re-read console. Update Resolution. No commit.

**Resolution:**
1. Distinct errors: (a) `noise_deform.gdshader` — `return` in `fragment()` → compile fail; (b) `Parameter "material" is null` flood — `set_shader_parameter` on failed ShaderMaterials every tick; (c) `!is_inside_tree()` Transform3D — scatter packed `instantiate()` then `global_transform`; (d) HDR GAMMA/PRIMARIES/EXPOSURE warnings — asset headers, unchanged. Editor progress-dialog errors were from MCP playtest stop/start, not game code.
2. Noise did nothing because the deform shader never compiled. Overlay `point_cloud.gdshader` was already valid; originals/scatter/MM used the broken shader. Affects gating and amount mapping were not the compile failure (live amount was ~2 world units once compiled).
3. Fixes: `fragment()` if/else (no `return`); `_xform_in_space` for off-tree scatter/point collect; skip stamp if `shader == null`; centerpiece transform requires in-tree. After restart: no shader/`material`/`is_inside_tree` errors. Skull material is `noise_deform.gdshader` with live `noise_amount`. Point Cloud OFF → mesh shader; ON → overlay shader, mesh cull-hidden. No commit.




## 2026-08-13 - Graph Equalizer barely visible; Input Level bar dead

**Issue:** Graph Equalizer on Drivers shows very little activity (tiny FFT magnitudes, not the audible range). Input Level bar is completely dead. Need peak-normalized EQ display (same idea as DriverHub audio peak-follow to ~1), a working input/master level meter or removal, and a clear explanation of Noise Floor Gate.

**Plan:**
1. Log this issue. Do not commit. Append only. UTF-8 no BOM, LF-only.
2. Find EQ UI, input level bar, noise floor (effects_sidebar, audio_analyzer, AudioState, DriverHub).
3. Peak-follow normalize EQ bands so typical music fills the graph; silence stays ~0. Use real audio, no fake motion.
4. Wire Input Level to real capture/volume (normalized) or remove the dead control.
5. Do not revert noise shader, point-cloud, scatter, feedback, ASCII, driver, or playlist crash fixes.
6. Update Resolution. No commit.

**Resolution:**
1. EQ looked dead because MicCapture played at -80 dB (starved FFT) and UI bands used raw AGC crumbs instead of peak-follow. Player is now 0 dB (bus still -80 so mic does not leak). ui_bands are peak-followed like DriverHub (loudest recent bin ~1, silence decays to 0). Real spectrum only.
2. Input Level was the same crushed peak * 0.35 (near 0) plus a themeless ProgressBar that often paints blank. It now shows peak-normalized capture level (mean/peak of those EQ bins) with an explicit StyleBox + ColorRect fill.
3. Noise Floor Gate subtracts a threshold from AGC-scaled FFT before bass/mids/highs/energy/kick (reactivity), not the EQ graph. Slider 0..0.12 (default 0.018), linear magnitude. 0 = almost no gate; high = only loud bands drive effects.
4. Files: autoload/audio_analyzer.gd, ui/effects_sidebar.gd, ui/effects_sidebar.tscn, core/audio_state.gd. script_check valid. No commit.

## 2026-08-13 - Scatter global formation scale

**Issue:** User wants a control that scales the whole scatter formation (grid / random volume / circular) as one cluster — spacing + volume cube — not per-item `user_scale` / Edit popup scale. Example: a 3D grid of 2000 items should grow or shrink like scaling the parent cube. Live update, no full re-import. Driver support if scatter sliders already use slider_spin_link. Works for stills, meshes, GIF/video MultiMesh.

**Plan:**
1. Log this issue. Do not commit. Append only.
2. Add a Global Scale slider on the Scatter tab (beside density/layout), range 0.1–5, default 1. Wire with slider_spin_link like density.
3. Place MultiMesh instances relative to the volume-cube center; scale the ScatterCluster root by global_scale so the formation grows/shrinks live. Keep per-item `user_scale` on instance extra_scale (Edit popup), independent.
4. Persist `global_scale` on scatter config + session. Do not revert density 1–2000 MultiMesh, point-cloud noise, noise shader, EQ, feedback, ASCII, or playlist overlay fixes.
5. Update Resolution. No commit.

**Resolution:**
1. Added **Global scale** on the Scatter tab (slider 0.1–5, default 1, driver via slider_spin_link). Scales the ScatterCluster around the volume-cube center so Grid / Random / Circular grow or shrink as one formation. Live — no asset re-import.
2. Per-item `user_scale` (✎ Edit) stays on MultiMesh instance extra_scale and does not move positions. Global scale must not replace item scale drivers.
3. Persisted as scatter `global_scale` + session. Density 1–2000 MultiMesh, point-cloud, noise, EQ, feedback, ASCII, playlist overlay fixes kept.
4. Files: `ui/playlist_sidebar.tscn`, `ui/playlist_sidebar.gd`, `items/flythrough_environment.gd`, `ui/main.gd`. script_check valid. No commit.

## 2026-08-13 - Debugger errors + preset shuffle + random affects

**Issue:** Godot debugger/output still shows errors. Every preset dropdown (camera pad, ASCII style, playlist path/layout, and similar lists) needs shuffle + a fixed interval (ASCII Style Switch pattern — no RND interval). Influence toggle groups (Affects Main/Scatter/Outer, axes, rotation vs other targets, camera influence) need a Random checkbox that flips those toggles over time when ON.

**Plan:**
1. Log this issue. Do not commit until asked. Append only. UTF-8 no BOM, LF-only.
2. Collect distinct errors via Godot MCP `editor_get_console` + `debugger_get_log`. Fix real bugs (skip HDRI header warnings unless easy). Re-read console after.
3. Add shuffle + interval to every preset dropdown (camera pad, ASCII already has Style Switch, path style, scatter layout, play mode). Fixed interval, optional driver on interval.
4. Add Random on influence toggle groups; interval 0.5–2s (or nearby shuffle interval). Do not flicker every frame. When Random is OFF, leave user settings.
5. Do not revert scatter global scale, density 2000 MultiMesh, point-cloud hide+noise, noise shader compile, EQ normalize, feedback-on-top, playlist overlay crash, ASCII density/style drivers, reset-to-default.
6. Update Resolution. Then commit and push this session’s project source (no secrets, no huge binaries, skip untracked MCP addon).

**Resolution:**
1. Distinct errors: (a) `playlist_sidebar.gd` parse — `_on_scatter_global_scale_changed` / `_scatter_global_scale_value` missing during a mid-write; functions are present now and `script_check` is valid. (b) `Parameter "material" is null` flood — `set_shader_parameter` on ShaderMaterials whose shader RID is unusable (failed compile or unset). (c) MCP progress-dialog / `!tasks.has(p_task)` — editor playtest stop, not game code. (d) HDRI GAMMA/PRIMARIES/EXPOSURE — asset headers, unchanged.
2. Hardened stamp paths: skip `set_shader_parameter` / `get_shader_parameter` unless the ShaderMaterial has a live shader. Playlist parse is already fixed.
3. Shuffle + Interval (fixed seconds, Style Switch model) on: Camera pad presets (skips Off), Play All mode, Cam path, Scatter layout. ASCII Style Switch kept as-is.
4. Random + Interval (default 1s, 0.5–5) on: Scale Affects, Scale XYZ, Rotation affects, Rotation XYZ, Noise affects, Noise XYZ, Point Cloud Affects, Particles affect, Camera rotation influence. At least one stay-on for multi-toggles. Random OFF leaves user checks.
5. Files: `ui/cycle_random.gd`, `ui/effects_sidebar.gd`, `ui/playlist_sidebar.gd`, `core/scene_mesh_fx.gd`, `items/flythrough_environment.gd`, `issue_log.md`.

## 2026-08-13 - Remove unused FX; add reaction-diffusion

**Issue:** Pixel sort, cloth, and particles are unused and should be removed (UI, scripts, automation). Cloth mesh deform is the Cloth FX — remove it; keep noise deform. Add a first working Gray-Scott reaction-diffusion post effect with toggle, sliders, optional presets+shuffle. Then finish shuffle/random/error fixes and commit/push.

**Plan:**
1. Append this issue. Do not commit until RD + removals + shuffle/random + error fixes are in.
2. Remove particles / cloth / pixel_sort from Effects UI, EffectStack, ShowDirector, fx_automation, flythrough particle/cloth push. Delete unused shaders/scripts. Do not break noise deform.
3. Add Reaction Diffusion post (Gray-Scott): toggle, feed/kill/speed/mix, preset dropdown with shuffle+interval. Composite under ASCII/feedback without going black. Driver-capable sliders.
4. Finish preset shuffle + influence Random. Re-read console. Commit and push project source.

**Resolution:**
1. Removed Particles, Cloth, and Pixel Sort from the Effects sidebar, Play All, EffectStack, and ShowDirector. Deleted `particle_audio_effect.gd`, `cloth_effect.gd`, `pixel_sort_effect.gd` + shader. Flythrough no longer spawns breakup GPU particles or applies cloth SoftBody; noise deform uniforms stay at 0 for cloth and still warp meshes/points.
2. Added **Reaction Diffusion** (Gray-Scott) post under ASCII: presets Coral/Mitosis/Spots/Worms/Waves with shuffle+interval; Feed, Kill, Speed, Mix sliders (driver-capable). Overlay tints the live frame from V concentration — does not replace or crush to black.
3. Shuffle+interval on camera pad, play mode, RD preset, cam path, scatter layout (ASCII Style Switch kept). Random+interval on Scale/Rotation/Noise affects + axes, Point Cloud Affects, camera rotation influence.
4. Material-null stamp guards kept. Files include `effects/reaction_diffusion*.gd(shader)`, `ui/cycle_random.gd`, sidebar/director/stack/flythrough, `issue_log.md`.
5. Follow-up: leftover `performer_panel` Particles toggle removed. compile_check loads RD instead of missing cloth script. Sidebar no longer registers particles/cloth/pixel_sort schedule hosts or calls `set_effect` for those ids.


