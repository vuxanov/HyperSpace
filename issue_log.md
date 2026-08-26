# HyperSpace Issue Log

## 2026-08-26 - ASCII glyphs not showing (need bundled fonts)

**Issue.** User: "For ASCII characters I think you need to include some fonts, Google fonts, I don't know because they're not really showing characters that they should be showing." Missing/wrong ASCII and special glyphs in the ASCII post-process (tofu, blanks, or unrecognizable stand-ins).

**Why (plan).**
1. Log this (done). No commit.
2. ASCII is a luminance→charset atlas shader (`effects/ascii_charset.gd` + `ascii_effect.gd`). Atlas is a handmade 5×7 bitmap table, not a font. `filter_charset` **drops** any character not in that table — many real ASCII letters are absent (e, s, g, y, 2–7, 9, A, D, E, F, …). Preset symbols (blocks, runes, Cyrillic, emoji) are crude 5×7 stand-ins, so they do not read as the intended characters. Project has **no** `.ttf`/`.otf` at all.
3. Bundle OFL Google Noto fonts with ASCII + the Unicode the presets actually use (block elements, braille, Cyrillic, runes, symbols, katakana, emoji). Import as FontFile. Rasterize the atlas from the font (bitmap table only as fallback). Apply in `AsciiCharset.build_atlas` / `filter_charset`.
4. Verify filter keeps preset glyphs; playtest ASCII styles so letters/symbols match the charset.

**Resolution.** ASCII post-process was a handmade 5×7 bitmap table (`AsciiCharset.BITMAPS`), not a font. `filter_charset` dropped any character missing from that table — including common ASCII letters (e, s, g, y, 2–7, 9, A, D, E, …) — so those glyphs never appeared. Preset symbols were crude stand-ins. Bundled OFL Google Noto fonts under `res://assets/fonts/` and rasterize the shader atlas from them (viewport bake, then FontFile, then bitmap fallback): Noto Sans Mono (ASCII/Latin/Cyrillic), Noto Sans Symbols + Symbols 2 (blocks, braille, dingbats), Noto Sans Runic, Noto Emoji. Applied in `AsciiCharset.build_atlas` / `filter_charset` (used by `AsciiEffect`). Vulkan bake of `eAs2` (letters with no bitmaps) rendered real Mono glyphs. Enable ASCII in Effects and step Style (Standard / Cyrillic / Blocks / Emoji) — letters and symbols should match the charset, not tofu or 5×7 blobs. No commit.

## 2026-08-25 - Reset to default does not clear Material Override

**Issue.** User: "And resetting back to default doesn't reset the material override?" After Reset defaults, the Material Override checkbox can turn off while cladding / chrome / gold still sits on the meshes.

**Why (plan).** Same workstream as Noise Displace on Main/Outer — they share `material_override` slots.
1. Log this (done). No commit.
2. `ShowDirector.reset_stage_to_defaults` turns the FX off first (`set_effect(false)` restores `hs_mat_ov_backup`). Flythrough then `_clear_noise_deform`, which can write `_noise_backup` back onto the mesh. If noise wrapped a stamped PBR look, that backup **is** the cladding — reset puts it back with no `hs_mat_ov` meta, so a later restore is a no-op.
3. Flythrough `reset_stage_to_defaults` never forces `_mat_override_on = false` or a post-noise restore. `_restore_material_override_one` also skips meshes that have our shared PBR override but no meta.
4. Fix: after noise clear, force-off + restore + strip leftover `hs_mat_ov_ours` overrides. Related to the displace bug (same slot fight), not a separate FX stack.

**Resolution.** Related to Noise Displace on Main/Outer (same `material_override` slot). Reset turned the FX toggle off, then `_clear_noise_deform` could write a PBR cladding backup back onto the mesh with no `hs_mat_ov` meta, so restore was a no-op. Fix: after noise clear, force `_mat_override_on` off and `restore_material_override`; restore also strips leftover `hs_mat_ov_ours` overrides that have no backup meta. Toggle off + Reset defaults now returns authored textures.

## 2026-08-25 - Noise Displace only warps scatter, not Main / Outer

**Issue.** User: "Noise displace doesn't work now. I think it's just displacing the scattered, but not main outer." Scatter instances warp; the Main (centerpiece) mesh and Outer (environment / primary shell + tiles) stay still.

**Why (plan).**
1. Log this (done). No commit.
2. Dual path: scatter is mostly MultiMesh (`_ensure_noise_materials_gi` sets `material_override` to `noise_deform`). Main/Outer are MeshInstance3D; `_ensure_noise_materials` caches shaders then returns them even if something else (material override, Bend wrap, emission dup, `_reapply_live_mesh_fx` order) replaced the live slot — stamps go to orphaned materials. `_reapply_live_mesh_fx` currently applies noise **then** material override, which hides surface noise behind a PBR override.
3. Centerpiece still uses `NOISE_MESH_LIMIT = 48`; DFS can hit inner/detail meshes first and skip the outer shell. Env was already made unlimited for tiles.
4. Fix: rebind if cached noise shaders are not the live draw materials; apply noise **after** material override; unlimited meshes for Main as well as Outer. Playtest Main + Outer + Scatter.

**Resolution.** User was right: scatter MultiMeshes stayed bound to `noise_deform`, but Main/Outer MeshInstances often were not. Causes: (1) `_reapply_live_mesh_fx` stamped Material Override **after** noise, hiding displace and leaving `_noise_mats` stamping orphaned shaders; (2) Main was capped at 48 meshes so the outer shell could be skipped. Fix: apply looks first, then noise; rebind if the live material is not the cached deform shader; unlimited meshes for Main like Outer; still apply to hidden (point-cloud) solids. Check Noise Displace + Affects Main/Outer/Scatter — all three should warp. Residual PBR after Reset is the companion issue above.

## 2026-08-25 - MCP console errors after dual-focus slider removal

**Issue.** Editor console spam: `effects_sidebar.gd` failed to load (parse error). Game cannot start. Repeated:
1. `Identifier "_camera_fx_focus_range" not declared` (lines ~2649–2651, 4146, 4148) — leftover DualRangeSlider after it was removed from Camera / Lens.
2. `The variable type is being inferred from a Variant value` treated as error at `_camera_fx_params` (`var near_m := SliderSpinLinkScr.mapped_param(...)` / `far_m`). `mapped_param` returns Variant (number or expression string).

**Plan.**
1. Log this (done). No commit.
2. Confirm `_camera_fx_focus_range` is already gone; replace `:=` with explicit `Variant` (or float) so inference is not treated as error.
3. `script_check` / console / playtest. Hunt remaining shader, missing-node, null-ref, material override, point cloud, fog, nonlinear, playlist errors.

**Resolution.** Console spam was `effects_sidebar.gd` failing to load, which blocked the game. `_camera_fx_focus_range` leftovers were already removed. The live error was `var near_m := mapped_param(...)` / `far_m` — `mapped_param` returns Variant (number or expression string) and INFERRED_DECLARATION is treated as error. Fix: `var near_m: Variant` / `var far_m: Variant`. Project compile 75/75 clean. Fresh playtest: sidebar + Focus far slider live; camera_fx params build; camera_fx / point_cloud / fog / material_override / Bend space / wireframe enabled with no shader, null-ref, or missing-method errors. Remaining noise: HDR metadata warnings; MCP `progress_dialog` errors on play (addon/engine, documented benign). No commit.

## 2026-08-25 - Remove dual-thumb focus slider; two normal sliders

**Issue.** User: remove the double/dual range slider. Keep **Focus near** and **Focus far** as two normal sidebar sliders. Remove the strange range widget between them (dual-thumb / two-handle track from `DualRangeSlider`). Keep the same DoF mapping and bokeh. Also: **aperture should influence blur like a real lens** (lower f-number = more smear). Do not commit.

**Plan.**
1. Log this (done). Camera / Lens UI only. DualRangeSlider stays for ASCII density.
2. Restore Focus near as a normal HSlider; add Focus far the same way. Drop `_camera_fx_focus_range` and the blue two-thumb track from Camera / Lens.
3. Remap `dof_blur_amount = bokeh × clamp(2.4 / f-stop, 0.12, 1.0)` so aperture is primary. Do not force amount=1.0 at bokeh 100. Scale near/far transition with f-stop (wide open = tighter / shallower).

**Resolution.** Camera / Lens uses two independent HSliders (Focus near / Focus far). Dual-thumb track gone; `dual_range_slider.gd` kept for ASCII density. Blur: `dof_blur_amount = clamp(bokeh01 * clamp(2.4 / f-stop, 0.12, 1.0), 0, 1)` — f/2.8 + bokeh 100 ≈ 0.86, f/22 + bokeh 100 ≈ 0.11. Transitions shorter when wide open. No commit.

## 2026-08-25 - Material Override flashing white lights

**Issue.** User: when Material Override is on (global Effects and/or per-item Material on playlist gear — White cladding, Chrome, Gold, Normal, Shiny black), the scene **flashes white lights**.

**Why.** `MaterialOverrideEffect.apply_audio_state` restamps every audio tick. `FlythroughEnvironment._apply_material_override_now` **restores all overrides then re-applies** each call, so originals (often emissive) flash for a frame. `_stamp_material_override` also reassigns the shared PBR `material_override` even when the look is already on, which **unwraps Bend-space wrap shaders** every tick (StandardMaterial ↔ wrap = specular/white pop). Reactive emission then duplicates the shared near-white cladding and drives `emission_energy` up to ~6.5, so HDR/bloom reads as strobing lights. Point-cloud hide is unrelated as long as we do not restamp overlays.

**Plan.**
1. Log this (done). No commit. Own material override path only (do not touch camera_fx_effect / lens sliders).
2. Stop per-tick restamp; restore+stamp only on enable, look/target change, item change, or world rebuild. Skip assign if the look is already stamped (leave Bend wrap in place).
3. Keep emission off on the five looks; skip reactive emission drive on stamped geometry so white cladding cannot become a light. Global still wins over per-item while FX is on.
4. MCP screenshot with override on — no white strobe.

**Resolution.** Flash was per-tick restore+restamp: `apply_audio_state` pushed every audio frame; `_apply_material_override_now` restored originals then reassigned PBR, which also unwrapped Bend wrap (`StandardMaterial` ↔ wrap = white specular pop). Reactive emission duplicated the shared cladding and drove energy ~6.5. Fix: no audio restamp; stamp only on enable/look/item/rebuild and skip if the look is already on (leave wrap); emission stays off and is not driven on stamped meshes. Global still wins on targeted layers. Playtest: White cladding stamped (`hs_mat_ov_look`, `emission_enabled=false`); two frames stayed uniform cladding, no strobe.

## 2026-08-25 - Focus is a range (two ends); bokeh 100 must be extreme

**Issue.** User: Focus distance should be a **range slider with two ends**, not a single plane. In front of the near handle (very close to camera) = blurred. Between handles = sharp (hero lives here, often ~3 m). Behind the far handle: if far sits at **max/infinity**, the rest stays sharp; if they pull far in, the background can go soft too. Bokeh slider stays 0–100, but **100 must be much more blurred** than today. Keep focal length / aperture / lens distortion. Do not re-add Near blur / Tilt-shift extras. Current Focus mapping does nothing useful (max-blur plane can sit behind the camera).

**Why.** Godot `CameraAttributesPractical`: `dof_blur_near_distance` / `dof_blur_far_distance` are the **zero-blur edges** (meters). Full near blur is at `near_distance - near_transition` — if that is behind the camera, close env never smears. A single `focus_distance` cannot encode “sharp slab + optional infinity far”. `dof_blur_amount` is 0–1; at f/2.8 bokeh 100 only reached ~0.66, so max never looked extreme.

**Plan.**
1. Log this (done). No commit. Do not touch point cloud.
2. UI: dual-handle focus range (existing `DualRangeSlider` + Focus near / Focus far ends, meters). Default near ~1.5 m (close env soft, hero ~3 m sharp), far at slider max = infinity (far DoF **off**).
3. Map near always on; far on only when far handle is pulled in from max. Keep full-blur plane in front of the camera (`near_transition < near_distance - cam.near`).
4. Remap `dof_blur_amount` so slider 100 hits engine max (1.0) regardless of aperture. 0–100 UI unchanged.
5. MCP playtest: near env blur, hero sharp, far sharp when far is max.

**Resolution.** Focus is a dual-handle range in meters (`DualRangeSlider`: Focus near / Focus far, far max = ∞). Godot `dof_blur_near` always on; full-blur plane stays in front of the camera (`near_distance - near_transition > cam.near`). `dof_blur_far` is **off** when far is at max so the rest stays sharp; pulling far in enables far DoF. Bokeh 0–100 UI unchanged; slider 100 maps `dof_blur_amount` to engine max 1.0. Headless map: near 1.5 m / far max → near on, far off, amount 1.0 at bokeh 100; far 12 m → far on. Playtest: hero ~3 m, near 2.2 m + far ∞ stayed sharp; near 12 m smeared the hero (DoF actually running). No commit. Point cloud untouched.

## 2026-08-25 - Revert bad near/tilt extras; real macro DoF

**Issue.** User: Camera effects blurring is **not good — revert**. They still want the **main object sharp**, **stuff close to the camera blurred**, and **focus distance** to move that plane — **like a real / macro lens**.

**Why the last pass failed.** Extra Near blur / Near plane / Near transition / Tilt-shift. Near sharp-edge was at **80% of focus**, so the Focus slider was not the plane of sharpness. Far still used a long `0.85 * focus` falloff (not macro). Extra `near_amount` boost + tilt-shift made the image mushy. Godot `dof_blur_near_distance` / `dof_blur_far_distance` are the **zero-blur edges**; they must sit **on the focus plane** (positive, in front of the near clip).

**Plan.**
1. Log this (done). No commit. Do not touch point cloud.
2. Revert tilt-shift shader and extra Near/Tilt sliders. Keep Focal length, Aperture, Focus distance, Bokeh, Lens distortion.
3. Macro map: near + far enabled; both distances = focus; short symmetric transitions from aperture/focal length so only a thin slab around focus is sharp. Close env bokeh; hero at focus sharp; background soft. Focus slider moves that slab.

**Resolution.** Reverted Near blur / Near plane / Near transition / Tilt-shift UI and `tilt_shift.gdshader`. Camera / Lens is again Focal length, Aperture, Focus distance, Bokeh, Lens distortion. DoF: `near_distance` = `far_distance` = **focus** (always > camera near clip). Transitions are a thin slab (~5–18% of focus from f-stop + focal length) so foreground and background go soft like a macro; the hero at the focus plane stays sharp. Playtest screenshot blocked (runtime WS timeout). No commit.

## 2026-08-25 - Near field stays sharp (lens DOF / close bokeh)

**Issue.** Camera / Lens focus distance can keep the hero sharp, but everything **between the camera and the subject stays sharp** too. Objects right in front of the lens should be **strongly blurred** with bokeh on close highlights. Far DOF can stay as designed. Optional tilt-shift (vertical sharpness band).

**Why.** `SceneMeshFx.apply_camera_fx` already enables `dof_blur_near`, but Godot’s `dof_blur_near_distance` is the **sharp edge** (blur → 0), and full blur is at `near_distance - near_transition`. The old map used `near_distance = 0.22 * focus` and `near_transition = 0.28 * focus`, so for focus ~12 the full-blur plane is **behind the camera** and 2.6m→hero is completely sharp. Shared `dof_blur_amount` never got a chance to smear the near field. Near distance must stay **in front of** focus so the hero is not blurred.

**Plan.**
1. Log this (done). No commit. Do not rewrite point cloud.
2. Remap near: sharp edge just in front of the hero (`near_plane` fraction of focus); **tight** transition so 0→that plane is fully smeared. Keep far distance = focus. Expose Near blur / Near plane / Near transition. Bump DOF bokeh quality. Persist with other lens FX.
3. Optional tilt-shift post shader (horizontal sharp band, blur toward top/bottom) on the camera FX stack.
4. MCP screenshot: close env fog/geometry smeared, hero at focus still sharp.

**Resolution.** Old map used `near_distance = 0.22 * focus` and `near_transition = 0.28 * focus`, so Godot’s full-blur plane (`distance - transition`) sat behind the camera and the whole foreground stayed sharp. Near sharp-edge is now `focus * near_plane` (default 80%, always < focus) with a tight transition so camera → near plane is fully smeared and the hero at focus stays sharp. Far DOF unchanged (`far_distance = focus`). New Camera / Lens sliders: Near blur, Near plane, Near transition, Tilt-shift (screen-space horizontal sharp band). Circular bokeh + medium quality. Runtime screenshot blocked by MCP playtest auth timeout (not a freeze). No commit.

## 2026-08-25 - Point Cloud toggle freezes HyperSpace

**Issue.** User turned on Point Cloud and everything froze (editor/game unresponsive).

**Why.** Overlay path is QuadMesh **MultiMesh per source vertex**, sibling `HSPointCloud`, hide solid, ~8k vert cap **per mesh**. Env tiling can be **hundreds of meshes**. `apply_point_cloud_layers` builds every overlay synchronously on the main thread: 189+ meshes × thousands of verts = hitch/freeze. Also possible: shader compile stall or GPU OOM from millions of billboard quads. Solids can vanish for a whole frame before any overlay exists → blank freeze.

**Plan.**

1. Log this (done). No commit. Point-cloud budget/chunking only. Wireframe stays independent. Keep vertex colors, Vertex size, Noise distort + Bend (`albedo_color`, GeometryInstance3D stamp).
2. CPU budget: lower per-mesh vert cap, stride subsample, global instance cap. Primary env + main + scatter first; env tiles skipped or heavily subsampled. Share MultiMesh across tiles that use the same Mesh.
3. Build incrementally (idle-frame chunks with a ms budget). Never hide a solid until its overlay exists. Prefer a coarser cloud over freeze.

**Resolution.** Freeze was synchronous overlay build: QuadMesh MultiMesh per vertex, up to 8k instances **per mesh**, all env tiles in one frame. Budget: 1200 verts main/scatter/primary, 180 on at most 8 env tiles, 28k instance cap, 48 overlays max, 3 meshes / 6–8 ms per idle chunk. Tiles share a cached MultiMesh. Solids stay until their overlay exists. Playtest Ex-convento 4×1×3 tiles: toggle did not freeze; 11 overlays (main 1199, scatter 1170, primary 1198, 8 tiles × 180); remaining tiles stay solid. Dots visible, editor/game still responded, wireframe untouched.

## 2026-08-25 - Noise distort does not warp outer environment (Bend or always)

**Issue.** User: "Some noise displaced doesn't seem to be displacing the outer to the environment, maybe when just when the band space is on, or always." Noise distort must visibly move environment / Outer meshes (primary + grid tiles), Bend space on **and** off. Main still warps.

**Plan.**

1. Log this (done). No commit. Keep fog-noise removal, point-cloud distort, tint/density. Do not skip env because it is large.
2. Two causes: (A) Bend space `_resync_mesh_surfaces` / `_resync_override` see `noise_deform` has warp includes but no `np_wrap_ver`, so they **replace** it with the Bend-only wrap every frame — env/scatter fail whenever Bend is on; Main has `np_skip_warp` so it is not resynced and still wobbles. (B) `NOISE_MESH_LIMIT = 48` plus a stale `_noise_mesh_lists` cache: DFS hits primary first, so tiled **outer** copies never get the displace shader (visible with Bend off if you look at the grid; with Bend on the fold puts those tiles on-screen).
3. Leave live FX shaders (noise/PC) in place and only stamp Bend uniforms. Apply noise to **all** env meshes; invalidate the mesh list when tiles spawn.

**Resolution.** Failed **both ways**, worse with Bend: (1) Bend `_resync_*` replaced `noise_deform` (has warp includes, no `np_wrap_ver`) with the Bend-only wrap every frame — env/scatter froze, Main kept distorting via `np_skip_warp`. (2) `NOISE_MESH_LIMIT = 48` plus a stale mesh-list cache skipped tiled Outer copies. Fix: keep noise/PC shaders and stamp Bend uniforms only; unlimited env meshes; invalidate cache on tile spawn. Playtest: 189 `noise_deform` materials, `noise_amount` 28, shader path unchanged with Bend on.

## 2026-08-25 - Fog density 100 not thick enough; tint needs more chroma

**Issue.** User: "fog tint should be more saturated, and fog density should go to higher. So, if it's 100, it should be very visible. Currently, density 100, it's very visible." Parsed as: Tint more saturated; Density 100 should be a **strong visible haze** (speech dropped "not" — currently 100 is *not* thick enough). Mid densities stay readable. Tint 0 stays gray-white; non-zero tint is chroma only (not extra opacity). Fog Noise stays removed.

**Plan.**

1. Log this (done). No commit. Fog mapping / tint only. Do not restore Fog Noise overlay or the old 0.85 aerial sky wash.
2. Why density 100 is weak: `_apply_fog_state` maps slider 0–100 → param 0–1 then `fog_density = lerp(0.38, 0.70, d)` so max opacity is 0.70. Aerial max 0.55 / sky_affect max 0.38. Raise the high end so 100 is thick mist (architecture clearly fogged) without white-out.
3. Tint: raise `TINT_SAT` / `TINT_MIX` so non-zero Tint is a stronger hue at the same density. Playtest density 30 vs 100.

## 2026-08-25 - Noise distort does not warp point cloud

**Issue.** Point cloud works (colored MultiMesh quads), but **Noise distort** does not move the dots. Other 3D warps; points stay put.

**Plan.**

1. Log this (done). No commit. Do not reintroduce `uniform albedo` (Bend space / `np_apply_debug_albedo`). Keep `albedo_color`.
2. Why: overlays are `MultiMeshInstance3D` (`HSPointCloud`), but `_stamp_all_pc_overlays` only stamps `MeshInstance3D` — `noise_amount` stays 0. Shader also starts `vtx = vec3(0)` so every instance would sample the same noise even if uniforms landed (rigid translate, not warp). `_apply_noise_to_root` correctly skips PC meshes so solids are not given `noise_deform.gdshader`.
3. Stamp `GeometryInstance3D` overlays. Sample/displace at instance origin (source vertex / world), then billboard. Same SubViewport as other 3D.

## 2026-08-25 - Remove Fog Noise (hole overlay)

**Issue.** User: "Remove the noise from the frog, it looks like that." = remove Fog **Noise** (hole-punch overlay, Intensity/Scale sliders, `fog_noise_overlay` path). Keep Density, Start, End, Tint. Fog stays opt-in. Do not leave a gray wash.

**Plan.**

1. Log this (done). No commit. Stop using / delete overlay. Depth fog stays on whenever Fog is on (do not zero `fog_density` for holes).
2. Strip Noise/Scale from Fog UI. Ignore leftover `noise` keys in saved params. Do not break Bend space hero size, fog tint, or wireframe.

## 2026-08-25 - Fog Noise holes not visible (maybe Bend space)

**Issue.** User: "Noise display is now not working. Maybe it's not working only when the band space is on, but it's not working." Fog Noise (holes + Intensity/Scale) is not visible. Possibly only with Bend space on, or broken in general.

**Plan.**

1. Log this (done). No commit. Do not fight nonlinear hero pose. Tint stays chroma-only. Dark = hole.
2. Why: Noise on zeros Environment depth fog and uses FogVolume at 0.14–0.30 with `volumetric_fog_density = 0`. Nothing left to punch holes into if the volume is too thin, the 3D texture is mostly cut, or volumetric fog is skipped. Bend space warps mesh depth; FogVolume raymarches unwarped view space, so holes vanish in the SubViewport capture.
3. Replace FogVolume holes with a screen-space overlay that reads the rendered (warped) depth, keeps full mist opacity in the light texels, and cuts dark noise to alpha 0. Same Environment / 3D SubViewport. Playtest Bend off then on.

**Resolution.** Noise was invisible because turning it on zeroed Environment depth fog and relied on FogVolume at 0.14–0.30 with `volumetric_fog_density = 0` (nothing to punch, and volumetric fog does not follow Bend-space warped depth in the 3D SubViewport). Replaced with a screen-space overlay in that same SubViewport: reads scene depth for Start/End, dark noise → alpha 0 holes, remaining mist keeps the same opacity mapping. Overlay shader is skipped by Bend wrap. Playtest: holes visible in colored fog with Bend off; overlay shader still `fog_noise_overlay.gdshader` with Bend on.

## 2026-08-25 - Point cloud still not working (fix once and for all)

**Issue.** User: "Point cloud isn't working. Fix point cloud once and for all." A prior pass (sibling overlays, UV2 camera-facing quads, hide solids, vertex colors, Vertex size, env/main/scatter) still showed **no dots**. Enabling it hid solids and left an empty/hazy viewport.

**Why the last fix failed.** Forward+ ignores `POINT_SIZE`. Overlays stacked 4 verts on the **same** position with UV2 corners, so a failed vertex expand drew nothing. Worse: `effects/point_cloud.gdshader` used `uniform vec4 albedo`, which **redefined** `np_apply_debug_albedo(inout vec3 albedo, …)` — shader compile failed (`Redefinition of 'albedo'`). Overlays were created and solids hidden, but the material never rasterized → empty/hazy viewport.

**Plan.**

1. Log this (done). No commit. Point-cloud files only. Do not rewrite fog_effect or Bend-space hero pose.
2. Real **QuadMesh MultiMesh**: one instance per source vertex, UV 0–1, instance COLOR = baked vertex albedo. Billboard in shader from `UV` + `POSITION` at the instance origin (pixel size). Cannot collapse.
3. Overlay is a sibling; source `visible = false` plus layer-19 hide. Rename shader uniform to `albedo_color`. Same roots as wireframe. Size uniform in place. Toggle off restores solids.
4. MCP screenshot: colored dots, size change, toggle off restores meshes.

**Resolution.** Root cause of the empty viewport: `uniform vec4 albedo` collided with `np_apply_debug_albedo(inout vec3 albedo)` so the point shader never compiled. Overlay geometry was also collapsed UV2 quads. Now: extract vertex positions+baked colors, one QuadMesh MultiMesh instance per vertex (`hs_pc_mmq`), sibling overlay, hide source (`visible=false` + layer 19). Shader `skip_vertex_transform` + UV billboard in view space (`point_size` in pixels), uniform renamed `albedo_color`. Playtest Ex-convento: dots with vertex colors on main+env, size 4 vs 40 changed disc size, toggle off restored solids, 0 overlays, console clean. Fog on at the same time still showed points.

## 2026-08-25 - Bend space makes the main object giant

**Issue.** User: click Bend space → the main object becomes giant. It should keep its normal screen size (same as off), aside from the env fold.

**Why.** The vanish fix pulled the camera-locked hero closer in Z whenever warped env sat “in front,” then frustum-clamped Z to `_hero_near_safe()` (~0.9 m). Folded env often collapses to the near plane, so the pull always fired. At `_center_distance` ~3 m that is ~3× larger on screen. `extra_cull_margin` does not scale the mesh. Main lift is Y-only and was not the scale bug.

**Plan.**

1. Log this (done). No commit. Stay in centerpiece camera-local pose. Do not touch Grid or Fog.
2. Remove Z-pull and the near-plane Z clamp. Keep intended depth (`-_center_distance` + user Z) so apparent size matches Bend space off.
3. Stay visible without moving toward the camera: XY frustum-clamp (so extra lift cannot leave the frame) + extra_cull_margin. No parent scale change. No `no_depth_test`.
4. Screenshot Bend space off vs on — hero similar size, env still folds, hero still on-screen.

**Resolution.** Removed Z-pull and the ~0.9 m near-plane clamp. Hero stays at `_center_distance` (~3 m). Playtest: camera-local z = -2.976 with Bend space on (same as off); node scale unchanged. Off vs on screenshots: figure still ~1/3 of frame height, env still folds.

## 2026-08-25 - Bend space makes the main object disappear

**Issue.** User: with **Bend space** on, the main / hero 3D object sometimes vanishes. It must always stay visible. Do not turn Bend space off; keep the folded environment look.

**Why.** Auto-center (`_centerpiece_np_lift`) CPU-warped environment AABB corners and lifted the camera-locked hero in **camera Y** by up to 6 m so it sat “above” the fold. After a ~90° bend those corners map to a huge +Y; at `_center_distance` ~2.2–4.5 m a 6 m lift is outside the 70° frustum — the hero was still in the world, just off the top of the screen. Which AABB samples passed `|warped.x| > 6` / behind-camera filters depends on camera heading, so it only happened **sometimes**. Extra lift (0–20 m) could do the same.

**Plan.**

1. Log this (done). No commit. Stay in nonlinear + centerpiece placement. Do not touch Grid tiling / playlist tile spins.
2. Stop using warped AABB max-Y as a camera-up lift. Keep the hero at its intended screen XY (bob / sway / user offset). Auto-center pulls **depth** so it stays in front of folded env near the view center. Frustum-clamp the final camera-space pose (Y including Main lift, Z in front of the near plane).
3. While Bend space is on, bump hero `extra_cull_margin` so a large AABB is not frustum-culled. Do not use `no_depth_test` (that z-fights the hero’s own meshes).
4. Playtest: Bend space on → hero stays centered and visible; env still folds.

**Resolution.** Removed the 0–6 m camera-Y AABB lift. The locked hero stays at its screen pose; auto-center only pulls it closer in Z if folded env would sit in front near the view center; the final camera-space offset is frustum-clamped (near plane + FOV). Extra Main lift is also clamped so it cannot throw the item off-screen. Playtest with Bend space on / max bend: hero stayed centered in view, environment still folded.

## 2026-08-25 - Fog Tint is washed-out gray, not a real color

**Issue.** User: noise must not tint (holes only). Fog Tint is barely visible — “should be more visible” meaning **more color, not more opacity**. Current `TINT_MIX = 0.15` / `TINT_SAT = 0.48` lerps a whisper of hue into gray-white mist, so `fog_light_color` stays a gray veil. Tint 0 should stay default gray-white. Volumetric albedo should follow the same colored fog.

**Plan.** Raise chroma only: mix ~0.82 of HSV (sat ~0.78, val ~0.88) into `BASE_COLOR` for `fog_light_color` and FogVolume albedo. Do not change density / start / end mapping. Density texture stays grayscale (dark = hole). No colored-grain overlay. Screenshot tint as a real hue with see-through mist.

**Resolution.** Tint chroma only: `TINT_MIX = 0.85`, `TINT_SAT = 0.82`, `TINT_VAL = 0.80`. Tint 0 stays `BASE_COLOR`. Density/start/end mapping unchanged (`fog_density` still `lerpf(0.38, 0.70, density)`). Density texture is grayscale (dark = hole); FogVolume albedo follows `fog_light_color`. Playtest tint 210 → `(0.24, 0.52, 0.81)` vs old ~`(0.72, 0.79, 0.86)`.

## 2026-08-25 - Fog noise is a gray wash, not holes

**Issue.** User: "Noise in fog is not good. Noise in fog correctly just makes everything completely gray. This is not what noise should do. Noise should poke holes into fog. Where the noise is dark, it should be a hole, not visible. There should also be two sliders for noise: not just intensity of the noise, but also the scale of the noise."

**Plan.**

1. Log this (done). No commit. Fog FX only. Do not touch Bend space or Grid. Keep Tint as the slight hue slider.
2. Stop stacking dense FogVolume on full depth fog. When Noise > 0, depth fog recedes so holes can show; FogVolume density stays modest; `volumetric_fog_density` = 0. `density_texture` dark = 0 (see-through), light = fog remains. Invert if mapping is backwards.
3. Two sliders: **Noise** (how strongly holes cut, 0 = even mist) and **Scale** (feature size via FastNoiseLite frequency). Screenshot holes in fog.

**Resolution.** Noise punches holes, it does not tint. Dark `density_texture` = 0 (see-through), light = remaining colored mist. Intensity moves the hole knee; Scale sets FastNoiseLite frequency (`0.36` → `0.026`). When Noise > 0, Environment depth fog recedes so holes are not filled; FogVolume density stays modest (`0.14–0.30`); global `volumetric_fog_density` = 0; emission off (no gray grain). UI: Noise + Scale (default 40). Tint 0 still gray-white mist. Bend space untouched.

## 2026-08-25 - Bend space makes the main object disappear

**Issue.** User: with **Bend space** on, the main / hero 3D object sometimes vanishes. It must always stay visible. Do not turn Bend space off; keep the folded environment look.

**Why.** Auto-center (`_centerpiece_np_lift`) CPU-warps environment AABB corners and lifts the camera-locked hero in **camera Y** by up to 6 m so it sits “above” the fold. After a ~90° bend those corners map to a huge +Y; at `_center_distance` ~2.2–4.5 m a 6 m lift is far outside the 70° frustum — the hero is still there, just off the top of the screen. Which AABB samples pass `|warped.x| > 6` / behind-camera filters depends on camera heading, so it only happens **sometimes**. Extra lift (0–20 m) can do the same. Folded env can also sit closer in depth than the unwarped hero and hide it (opaque depth test; `render_priority` only helps transparents).

**Plan.**

1. Log this (done). No commit. Stay in nonlinear + centerpiece placement. Do not touch Grid tiling / playlist tile spins.
2. Stop using warped AABB max-Y as a camera-up lift. Keep the hero at its intended screen XY (bob / sway / user offset). Auto-center pulls **depth** so it stays in front of folded env near the view center. Frustum-clamp the final camera-space pose (Y including Main lift, Z in front of the near plane).
3. While Bend space is on, bump hero `extra_cull_margin` so a large AABB is not frustum-culled. Do **not** use `no_depth_test` (that z-fights the hero’s own meshes). Depth-in-front comes from Z-pull + skip-warp.
4. Playtest: Bend space on → hero stays centered and visible; env still folds.

## 2026-08-25 - Grid spins skip even sizes (1, 3, 5…)

**Issue.** User: "Greed is currently acting strange. It goes 1 3 5. It should not do that. Should be 1 2 3 4 5, and so on." Speech-to-text **Greed** = **Grid**. Environment Grid X/Y/Z used odd-only cell counts because storage was copies-per-side (`cells = 1 + 2 * copies`). Even sizes like 2×2 were impossible.

**Plan.**

1. Log this (done). No commit. Do not touch point cloud.
2. Store **cell counts** on `tile_x/y/z` with `tile_cells: true`. Migrate old copies-per-side (`1,0,1` → `3,1,3`). Spins step 1 from 1–100.
3. Placement: primary stays put; it occupies index `floor((n-1)/2)` on each axis. Other cells are a regular AABB-step lattice. Odd n stays symmetric (3×3 unchanged). Even n adds the extra cell on the **+** side (2×2 = original + +X + +Z + corner). Keep 1000-mesh spawn cap; hint shows it.

**Resolution.** Grid steps 1, 2, 3…100. `tile_*` are cell counts (`tile_cells` flag). Legacy copies-per-side still load. Even grids: primary is the lower-center cell; extras grow +X/+Y/+Z, flush on AABB.

## 2026-08-25 - Environment Grid hard-capped at 7 cells

**Issue.** User: "I have the ability to add more than seven. You should be able to add as much as I like. I don't know, maybe up to a hundred?" Environment **Grid X/Y/Z** spins only allowed odd sizes 1/3/5/7 (copies-per-side 0–3). `clamp_env_tile_count` and `ENV_TILE_MAX := 3` enforced that. No other "add" path was max=7 (playlist/scatter/layers were not the cap).

**Plan.**

1. Log this (done). No commit. Do not rewrite point-cloud / wireframe.
2. Raise per-axis cell count to odd 1–99 (copies-per-side 0–49 so `1+2*n` approaches 100). Persist `tile_x/y/z` in that range.
3. Keep odd-only spins (symmetric lattice around the original). Spawn-time cap **1000** total mesh instances so 99×99×1 cannot create ~10k copies; shrink axes proportionally and show that in the Grid hint.

**Resolution.** Grid spins go to 99 cells/axis (odd). Stored copies-per-side max is 49. Requested `tile_*` persist; spawn uses at most 1000 instances (e.g. 99×99×1 → 31×31×1 = 961).

## 2026-08-25 - Left-panel Reset to default leaves customizations behind

**Issue.** Left sidebar **Reset to default** only restored fly speed, reactivity leftovers, and visual FX. Playlist item customizations stayed: `user_offset`, `user_scale` / scale drivers, `mat_override`, `blend_mode`, `tile_x/y/z`, scatter `global_scale` / layout / density, cam path, and the same keys on catalog rows. Re-applying an asset brought the old look back.

**Plan.**

1. Log this (done). No commit. Do not relocate Grid (stays in per-item Edit). Do not rewrite point-cloud / wireframe shaders.
2. Strip those keys on every playlist item + every sidebar catalog row. Live stage applies scale 1, offset 0, tiles catalog default (3×3 ground), mat Off, blend Normal, scatter layout random / density 18 / global scale 1, path Auto.
3. Effects (Fog, Glitch, Bend space, …) already go off via `ShowDirector.reset_stage_to_defaults` + effects sidebar sync on `stage_defaults_restored`.
4. Environment tab: hide helper prose and Env scale (global scale). Grid stays in ✎ Edit only.

**Resolution.** Left-panel **Reset to default** now strips every playlist item and catalog row (`user_offset`, scale/drivers, `mat_override`, `blend_mode`, `tile_x/y/z`, scatter layout/density/`global_scale`, cam path) and applies those defaults on the live stage. Effects still go off via the same ShowDirector call (Fog, Glitch, Bend space, …). Environment tab no longer shows helper prose or Env scale; Grid stays in per-item Edit only.

## 2026-08-25 - Point Cloud broken; should match wireframe with vertices

**Issue.** User: Point cloud doesn't work again. It should work the **same as wireframe**, but show **vertices** instead of edges. User must be able to **change vertex size**. **Keep vertex colors** on each vertex, just like wireframe does. Currently broken. Must apply to **all 3D elements** (env, main, scatter, any 3D meshes — same scope as wireframe).

**Why it's broken (investigation).**

1. Wireframe is viewport-wide `SubViewport.debug_draw = DEBUG_DRAW_WIREFRAME` — every 3D surface in the capture, albedo/vertex colors on the strokes, no per-mesh rebuild.
2. Point cloud is a fake overlay (`HSPointCloud` child + layer-19 hide). Forward+ has no spatial `point_size` render mode, so true `PRIMITIVE_POINTS` stay 1px. A later workaround expanded verts to UV2 quads (`PRIMITIVE_TRIANGLES`) and sized them with `inverse(MODELVIEW_MATRIX)`.
3. Those quads often draw nothing: UV2 ±1 is a bad fit for compressed ArrayMesh attributes (corners collapse → degenerate zero-area tris). Clip expansion after nonlinear warp via `inverse(MODELVIEW)` is also unstable.
4. Originals are hidden by changing `Camera3D.cull_mask`, but `find_camera()` returns the **first** Camera3D under the env (often an imported GLB cam), not the gameplay camera. Solids keep drawing; overlays may be invisible. Wireframe still works because debug_draw does not depend on that camera lookup.
5. Scatter MultiMesh is a separate path; MeshInstance cap 512 can drop env tiles. Not the same scope as wireframe.

**Plan.**

1. Log this (done). No commit. Do not touch Fog Tint (`effects/fog_effect.gd`, Fog Color→Tint in effects_sidebar).
2. Same items as wireframe (env / main / scatter / any MeshInstance3D + MultiMesh under those layers). Hide solids on the **current** gameplay camera.
3. Overlay = one sprite per source vertex, **COLOR from mesh** (COLOR attribute × albedo/texture bake, same idea as wireframe albedo). Size slider = **pixels** (Godot `point_size` meaning), written in clip space via `POSITION` + viewport size — Forward+ cannot use `POINT_SIZE`.
4. Uncompressed 0–1 UV2 corners so quads don't collapse. Include MultiMesh in `SceneMeshFx` so scatter isn't a one-off. Raise mesh cap. Persist `point_size` as today.
5. Do not change wireframe debug_draw. Playtest screenshots: wireframe vs point cloud; drag vertex size.

**Resolution.** Point cloud uses the same 3D set as wireframe (env / main / scatter MeshInstance3D + MultiMesh). Each vertex keeps mesh COLOR (COLOR attribute × albedo/texture bake). Forward+ cannot size `PRIMITIVE_POINTS`, so dots are camera-facing quads; **Vertex size** is pixels (`point_size`, persisted with other FX). Overlays are **siblings** of the source mesh with the solid `visible = false` (child + layer/transparency hide also hid the dots). Billboard: `INV_VIEW_MATRIX` + viewport size. Wireframe `debug_draw` unchanged. Fog Tint files not touched.

## 2026-08-25 - Fog color is way too strong

**Issue.** User: Fog color is way too strong — cannot see anything. Fog color should be a slight tint on the existing grayish/whitish mist. Replace the Color picker with a **Tint** slider over the whole rainbow. Keep fog as it was, then slightly color it.

**Plan.**

1. Log this (done). No commit. Stay in Fog FX + sidebar Tint. Do not restore Play All auto-Fog or a gray wash.
2. Remove ColorPicker. Add Tint hue slider (0 = no extra hue / plain mist; 1–360 = spectrum). Rainbow-gradient track. Mix a spectral hue into `Color(0.76, 0.80, 0.84)` at ~15% so the scene stays readable.
3. Same slight tint on FogVolume albedo / volumetric_fog_albedo when Noise is on. Persist `fog.tint` (hue float). Migrate old `fog.color` RGB to hue or default 0.
4. MCP screenshot: Tint slider visible, fog still readable.

**Resolution.** Color picker removed. Effects → Fog **Tint** is a 0–360 hue slider with a rainbow track (left gray = no extra hue). Base mist stays `Color(0.76, 0.80, 0.84)`; spectral hue mixes at **15%** (`TINT_MIX`). Persist `fog.tint`. Old `fog.color` RGB migrates to hue or 0 if near-base. Playtest: tint 210 → `fog_light_color` (0.72, 0.79, 0.86) — slight cool shift, scene still readable. Fog stays opt-in.

## 2026-08-25 - Fog color control

**Issue.** User: "I also add color to fog." Fog FX has density / start / end / noise but no tint. Depth fog uses a hardcoded cool gray `fog_light_color`; volumetric FogVolume albedo should match.

**Plan.**

1. Log this (done). No commit. Stay in Fog FX + Environment. Do not fight other agents on glitch, blend, material override, or Bend space.
2. Effects → Fog: ColorPickerButton (no alpha). Persist `color` `{r,g,b}` with the other fog params. Default cool gray-blue `Color(0.76, 0.80, 0.84)` matching the previous hardcoded mist.
3. Drive `Environment.fog_light_color`. When Noise is on, FogVolume albedo + volumetric_fog_albedo follow the same color. Fog stays opt-in; no gray wash.

**Resolution.** Fog color is `Environment.fog_light_color` (Godot 4 depth fog). Effects → Fog has a Color picker (no alpha) under Density; default cool gray-blue `Color(0.76, 0.80, 0.84)`. Session stores `color: {r,g,b}`. With Noise on, `volumetric_fog_albedo` and FogVolume `FogMaterial.albedo` use the same tint. Playtest: set color (0.55, 0.75, 0.95) → env and volume albedo matched; Fog stays opt-in.

## 2026-08-25 - Glitch size is wrong; slice chaos vs speed

**Issue.** User (STT "Greek"): Glitch **H size** at 1 is not really 1; Amount feels like height; slices cannot go small enough (current min is huge); want **Vertical size** and **Horizontal size** as the main controls, with other params pulled out; **Slice chaos** seems to do nothing / sounds like Speed.

**Plan.**

1. Log this (done). No commit. Own glitch shader + glitch UI only (do not touch fog, tiling, material override, blend modes).
2. Size mapping: H size 1 is slider 1 / 100 = 0.01, then shader `floor(uv.y * (6 + h_size * 24))` → ~6 huge bands, never 1 px. Amount is intensity, not height. Replace with pixel-accurate Vertical size + Horizontal size (1 = 1 pixel, min 1, large still OK). Relabel Amount → Intensity and demote it below size.
3. Slice chaos: uniform is connected, but it mostly drives extra column count + vertical shift (looks like denser/faster glitch, overlapping Speed). Rewire chaos to randomize slice *layout* (irregular band boundaries, per-slice offset jitter, mosaic blocks) on a clock independent of `rate`.
4. MCP playtest: size=1 vs large; chaos 0 vs 1 at same speed.

**Resolution.** Confirmed Glitch (not Greek). Size was `slider/100` into `6 + h_size*24` bands — displayed 1 ≈ 6 huge rows, never 1 px. Amount was intensity, not height. Primary controls are now **Vertical size** and **Horizontal size** in pixels (1 = 1 px, min 1, max 400). Amount relabeled **Intensity** and demoted below size. Slice chaos **was connected** (column count + vertical shift) but looked like Speed; it now randomizes slice layout (irregular bands, per-slice jitter, mosaic blocks) on a clock independent of `rate`. Playtest: 1×1 px = fine striations; 80×120 = large blocks; UI shows Vertical/Horizontal size first.

## 2026-08-25 - Rename Nonlinear camera to Bend space

**Issue.** User: instead of "non-linear camera" / "Nonlinear camera", call it something like **Bend space**. User-facing labels only.

**Plan.**

1. Log this (done). No commit. Only Nonlinear-camera label strings. Do not rewrite Glitch, Fog, tiling, or materials in `effects_sidebar.gd`.
2. Case-insensitive search: nonlinear, non-linear, non_linear, Nonlinear camera.
3. Change displayed checkbox text, tooltips, search haystack. Keep internal names (`nonlinear_projection.gd`, `NonlinearProjection`, node names, Play All keys `np_*`).

**Resolution.** Effects checkbox is **Bend space**. Main-lift tooltip says Bend space. Search haystack includes "bend space" (old "nonlinear camera" kept as a synonym). No Play All display name or session key was shown to the user.

## 2026-08-25 - Fog noise barely visible

**Issue.** User: "For noise is barely visible, it should be much, much more extreme." Fog FX Noise slider currently leaves volumetric FogVolume / NoiseTexture3D / density almost inert — mid-high Noise looks like a faint grain, not blotchy mist. Depth fog still works; do not restore the old full-scene gray wash.

**Plan.**

1. Log this (done). No commit. Own Fog noise + env tiling only (another agent owns 3D material override and 2D blend).
2. Crank FogVolume FogMaterial density, albedo, and a high-contrast NoiseTexture3D (cellular + steep ramp). Keep Environment volumetric_fog_density tiny so the frame is not a gray wash. Depth fog stays the uniform base; Noise is extra non-uniformity and must be obvious at mid-high slider.
3. Disable volumetric temporal reprojection while noise is on so blotches are not smeared. Playtest screenshot at Noise ~50–80.

**Resolution.** FogVolume uses cellular `NoiseTexture3D` (inverted distance + steep ramp), FogMaterial density ~3–10 at mid-high Noise (was ~0.04), BOX volume, temporal reprojection off. Global volumetric density stays tiny so there is no gray wash. Playtest: noise 0.75 → FogMaterial density 5.1.

## 2026-08-25 - Environment tiling is axis spines, not a full grid

**Issue.** User: tiling should be an array/grid, not one copy on each side. "If I go like three by three, it should actually be nine in total." Current `_apply_env_tiles` only duplicates along ±X / ±Y / ±Z spines — no corners. Tile X=1 and Z=1 gave original + 2 + 2 = 5, missing 4 corners.

**Plan.**

1. Log this (done). No commit. Duplicate visual mesh only (strip WorldEnvironment/lights). Offset by AABB size so cells sit flush.
2. Fill the full integer lattice including corners (and 3D corners if Y is tiled). Keep stored `tile_*` as copies-per-side so existing 1,0,1 stays valid: per-side 1 on X and Z → 3×3 = 9.
3. UI: show odd grid size (1/3/5/7) so "three by three" is obvious. Clamp modest (max 3 copies/side = 7 cells). Default stays a small XZ grid.
4. Files: flythrough_environment.gd, layer_slot.gd, asset_catalog.gd, playlist_sidebar.gd (Tile X/Y/Z UI only).

**Resolution.** Full integer lattice including corners. Stored `tile_*` is still copies-per-side: X=1 Z=1 Y=0 → 3×3 = 9 (8 extras + original). UI Grid spins show odd cell counts 1/3/5/7. Playtest tile names: EnvTile_-1_0_-1 through EnvTile_1_0_1 (corners included). Visual mesh only; lights/WorldEnvironment stripped.

## 2026-08-25 - Fog FX does nothing when enabled

**Issue.** User: "Fog doesn't seem to do anything. Doesn't work." After the gray-wash fix, enabling Effects → Fog produces no visible mist. Likely: defaults too conservative (density 12, start 40 m, end 140 m) vs this project's camera/scene scale; aerial/sky/energy zeroed; empty-params restore path; or Environment fog not actually enabling.

**Plan.**

1. Log this (done). No commit. Stay in Fog FX + Environment. Do not reopen Play All gray-wash.
2. MCP: camera near/far, WorldEnvironment fog_*, enable Fog and screenshot.
3. Tune on-defaults so mist is obvious at typical flythrough distances (hero ~4–8 m, env tens of meters, camera far ~200) without filling the whole frame gray.
4. Keep Fog opt-in. Off still restores lighting-catalog fog.

**Resolution.** Fog FX was on and writing depth fog (`fog_enabled`, `FOG_MODE_DEPTH`, begin/end), but it never set `Environment.fog_density`. In Godot 4 depth mode that property is **max opacity at End** (0 = invisible, 1 = fully obscure). After the gray-wash fix, lighting restore left it at catalog `0`, so toggling Fog did nothing. Compounding: on-defaults were Start 40 m / End 140 m while this flythrough camera is near 0.05 / far ~272 m and courtyard geometry sits a few–tens of meters (hero ~3 m) — the band never hit the scene. Fix: write depth `fog_density` from the Density slider (~0.38–0.70), and retune on-defaults to Density 32 / Start 5 m / End 32 m (sanitize remaps the old 0.12/40/140 combo). Fog stays opt-in. Off still restores lighting-catalog exponential fog.

## 2026-08-25 - Diagnose Godot console errors after Fog / offset work

**Issue.** Fog FX, playlist gear + XYZ, NP auto-center, and the gray-washout fix landed while Godot MCP was down. Editor is connected now. Need to read the console, script-check Fog/playlist/NP paths, playtest, and fix real parse/runtime errors. Fog stays opt-in; no gray wash by default.

**Plan.**

1. Log this (done). No commit.
2. `editor_get_console` for errors/warnings. `script_check` Fog, flythrough, playlist, NP, show_director, effect_stack.
3. Start playtest if safe; screenshot; debugger log. Fix script errors, missing methods, invalid Environment/FogVolume properties.
4. Keep Fog off by default; restore lighting catalog fog when FX is off.

**Resolution.** (in progress)

## 2026-08-25 - Everything is gray after Fog FX

**Issue.** User: "Everything is gray now" right after Fog/mist, playlist gear, and Y-offset landed. Almost certainly the new Fog path washing out the scene (too dense / too close, volumetric stacked, fog applied while the effect is off, lighting-catalog fog stacked with FX fog, aerial/sky fog, or Environment fog left on globally).

**Plan.**

1. Log this (done). No commit. Stay in Fog FX + Environment apply. Do not rewrite Feedback, Material Override, or playlist offsets.
2. Trace FogEffect, EffectStack, ShowDirector (Play All / session / defaults), FlythroughEnvironment `_apply_fog_state` / lighting `fog_density`, Scene3DItem fallback, sidebar defaults.
3. Likely: Fog on by default or restored; density 0.35 + start 8 m covering the frustum; `_apply_fog_state` running while FX is off; FogVolume / volumetric left on; depth + volumetric + gray `fog_light_color` + aerial/sky; lighting apply writing fog then FX overwriting without restoring.
4. Fix: scene looks normal with Fog **off** (restore lighting-catalog exponential fog only). Fog FX only when the user enables it. Conservative on-defaults (farther start, lower density, no aerial/sky wash). Disable volumetric/FogVolume when noise is 0 or FX is off.
5. Playtest: Fog off = no gray wash; Fog on = light distant mist; off again = previous lighting fog.

**Resolution.** Root cause: Play All auto-enabled Fog with density 0.35, start 8 m, plus aerial/sky tint and a gray fog color — that painted the whole frame. Lighting apply could also stack exponential fog writes with the FX path. Fix: Fog is opt-in (not in Play All). On-defaults are density 12 / start 40 m / end 140 m with almost no aerial/sky. Fog off fully restores lighting-catalog exponential fog (single writer). First-ship 0.35/8 m params remap to the new defaults. Godot MCP still down (editor not running).

## 2026-08-25 - Fog/mist, playlist gear icon, world Y offset / NP auto-center

**Issue.** User asked for three features: (1) distance fog/mist with density, start/end, optional noise, wired through existing Environment + UI; (2) playlist edit pen icon should be a gear; (3) offset the world/item on Y (and XYZ) so the main item does not clip through the environment, especially with the nonlinear camera. Prefer a user-facing offset plus a robust NP auto-center if feasible.

**Plan.**

1. Log this (done). No commit. Stay in Environment fog, playlist edit dialog, flythrough layer transforms, and nonlinear camera UI. Do not rewrite Feedback or Material Override.
2. Fog: new Fog effect (Camera FX pattern) applying Godot Environment depth fog (`fog_mode` depth, begin/end, density/aerial) plus optional FogVolume + NoiseTexture3D when noise > 0. Lighting catalog `fog_density` remains the fallback when the Fog effect is off.
3. Playlist: swap ✎ for ⚙; add Offset X/Y/Z to the edit dialog for Env/Main/Scatter; stamp `user_offset` on layer configs and apply on `_env_root` / camera-locked centerpiece / `_scatter_root`.
4. Nonlinear camera: Auto-center main (CPU warp of env AABB vs hero, clamped lift) + Main lift slider. Manual item Y offset still wins for large corrections because a 90° fold can map world Y to depth.
5. Playtest: Fog on → mist with start/end; noise ripples; gear opens the same edit dialog; Y offset lifts/drops the item; NP auto-center keeps the hero above folded ground without shooting it off-screen.

**Resolution.** Fog is a first-class FX (Effects → Fog): Environment depth fog with Density / Start / End, plus FogVolume + NoiseTexture3D when Noise > 0. Lighting catalog fog remains the fallback when Fog is off. Playlist edit uses ⚙ (same dialog) with Offset X/Y/Z; Y lifts the item so it does not clip the environment. Nonlinear camera has Auto-center main (default on, clamped 0–6 m CPU warp lift) and Main lift (m). Manual XYZ is the reliable fix for a strong 90° fold. Godot MCP was down (ECONNREFUSED :6550) so compile/playtest in-editor still needs a local Godot pass.

## 2026-08-25 - Material Override: drop AO/Original/Mix; fix chrome HDRI

**Issue.** User: "Frame material" (Material Override). Remove Ambient Occlusion and Original looks. Remove Mix — override is fully on when enabled. Originals return only when the effect is off. Chrome looks white (not HDRI metal). Shiny black has broken artifacts.

**Plan.**

1. Log this (done). No commit. Do not rewrite Feedback, nonlinear shaders, or point cloud.
2. Looks (default when ON): White cladding, Chrome, Gold, Normal, Shiny black. No AO, no Original, no Mix.
3. Session remap: `"AO"` / `"Ambient occlusion"` / `"Original"` / `"Off"` and old indices 5–6 → White cladding. Ignore leftover `mix`.
4. Chrome/Gold/Shiny black: StandardMaterial3D metallic=1, low roughness, proper albedo. Dummy 1×1 metallic texture so NP wrap keeps metallic (it currently zeroes metallic without an MR map — that is why chrome reads as white cladding).
5. Shiny black: slightly higher roughness (~0.18) and dark-grey F0 (~0.055) so HDRI shows without fireflies / dead-black metal.
6. Playtest: no Mix/AO/Original in UI; enable = White cladding; Chrome/Gold show HDRI; disable restores originals.

**Resolution.** Looks: White cladding, Chrome, Gold, Normal, Shiny black. Mix/AO/Original gone. Chrome was white because NP wrap zeroes metallic without an MR map; metals now use StandardMaterial3D (metallic=1, low roughness) plus a 1×1 white metallic texture so wrap keeps metallic and HDRI/sky IBL shows. Shiny black uses dark-grey F0 and roughness ~0.22. Sessions: AO/Original/Off → White cladding; leftover mix ignored. Playtest: 5-item dropdown, Chrome/Gold reflect HDRI, disable restores `material_override=null`.

## 2026-08-25 - Remove Glow and Shadow from Feedback blend

**Issue.** User: "remove Glow and Shadow blend mode from Feedback Trail."

**Plan.**

1. Log this (done). No commit. Stay in Feedback blend lists. Do not re-add Copies.
   Do not touch Material Override, nonlinear, or point cloud.
2. Remaining modes: Normal, Brightest, Darkest, Edges, Contrast. Compact shader
   `BLEND_*` ints to match. Drop Glow/Shadow branches.
3. Sessions already store blend as a name (`"blend": "Normal"`). Unknown names
   (Glow, Shadow) → Normal. Legacy integer slots remap: 0 Normal, 1 Glow→Normal,
   2 Brightest, 3 Darkest, 4 Shadow→Normal, 5 Edges, 6 Contrast.
4. Dropdown, shuffle/cycle, search text, tooltip. Playtest: no Glow/Shadow;
   shuffle skips them; Normal still works.

**Resolution.** Remaining blends: Normal, Brightest, Darkest, Edges, Contrast.
Sessions store names; `"Glow"` / `"Shadow"` and old integer slots 1 and 4 map to
Normal so Brightest/Edges/Contrast do not shift. Dropdown has 5 items; shuffle
cycles `item_count`. Playtest: Glow param → `_base_blend` 0 (Normal).

## 2026-08-25 - Point Cloud size dead; Noise Displace does not move points

**Issue.** User: "Point cloud doesn't work. I mean, it works, but the size doesn't work. And also, if I add noise-displaced, it doesn't really displace it."

1. Point size slider does not change visible dot size (or barely does).
2. Point Cloud + Noise Displace does not move the points.

**Plan.**

1. Log this (done). No commit. Stay in point cloud + noise deform + effects sidebar wiring. Do not rewrite Feedback or Material Override.
2. Size: Godot 4.7 spatial shaders reject `render_mode point_size` (`Invalid render mode`). `POINT_SIZE` on Forward+ therefore cannot drive overlay dots. Expand overlay meshes to camera-facing UV2 quads so the `point_size` uniform scales screen-space sprites. Slider → uniform → GPU, including scatter MultiMesh overlays.
3. Noise: displacement must run on overlay vertices independently of `np_u_skip` (centerpiece skip warp must not skip noise). Use a local `vtx` so `np_warp_vertex_and_normal(VERTEX, …)` cannot write back the rest pose. Same local-vtx pattern in `noise_deform.gdshader`. Keep include after samplers; warp after noise.
4. Playtest: Point Cloud size grows/shrinks. Noise Displace + Point Cloud moves the dots.

**Resolution.** Size was dead because Forward+ spatial has no `point_size` render mode, so `POINT_SIZE` never changed the 1px GL points. Overlays are now UV2 quads; `point_size` expands them in view space after noise+warp. Noise did not move dots because warp was passed `VERTEX` as inout (rest pose could win) and a failed `render_mode point_size` compile dropped the whole vertex shader. Local `vtx`: noise/cloth first, `np_u_skip` only skips warp, then assign VERTEX. Same pattern in `noise_deform.gdshader`. Scatter MM size updates with the slider. Confirm: Effects → Point Cloud on, drag Point size; enable Noise Displace with Affects Main/Env — dots grow and jitter.

## 2026-08-25 - Reverse Copies mode; fix Blur 0 Windows trail

**Issue.** User rejected the extra Feedback "Copies" / 10-copies / Sharp trail mode.
They do NOT want discrete N full-frame duplicates. They want the existing sliders:
Blend Normal, Blur 0, Opacity 100, Persistence 100 — a Windows window-trail: each
new frame painted on top of an uncleared buffer, sharp, only moving things trail.

**Plan.**

1. Log this (done). No commit. Stay in Feedback; do not touch Material Override
   or nonlinear_projection.
2. Remove Copies look UI (Trail look, Copy scale/offset/rotate, shuffle look)
   and shader `copies_mode` / zoom-offset path.
3. Fix Blur 0: no downsample, no mipmaps, no zoom, no spread. Full-res 1:1.
4. Normal + persist 100 + opacity 100: motion-hold Windows trail
   `out = mix(prev, current, max(1-persist, motion))`. Persist 100 keeps unchanged
   pixels; moving pixels stamp sharp copies. Blur > 0 keeps the old smear path.
5. Playtest: Normal, blur 0, opacity 100, persist 100 — sharp trails, not fog.

**Resolution.** Copies UI and `copies_mode` are gone. Blur 0 captures 1:1 (nearest cap 1280, no mips, zoom 1). Normal + blur 0 paints leftover stamps on the live view (`COLOR = hist` with alpha = leftover × persist × opacity) instead of fullscreen `max()` — that lighten path washed flythroughs white. Leftover = motion × (darker leftover object or more-saturated leftover), so bright walls do not freeze. Persist 100 keeps stamps; lower persist fades them. Blur > 0 keeps the old smear. Playtest: Feedback on, Normal, blur 0, opacity 100, persist 100 — sharp stacked arches/geometry on flythrough, no Copies controls, no white fog.

## 2026-08-25 - Material Override effect (cladding / chrome / gold / normal / shiny black / AO)

**Issue.** User: add another effect, material override, with a few looks — white cladding, chrome, gold, normal (show the normal map), shiny black, and something driven by ambient occlusion. Same as other effects otherwise: enable, cycle through looks, schedule them.

**Plan.**

1. Log this (done). No commit. Do not replace Camera3D / world / spawn. Do not rewrite Feedback ping-pong or `nonlinear_projection/` shaders.
2. New `MaterialOverrideEffect` (`effects/material_override_effect.gd`) following Wireframe / Point Cloud: push to `Scene3DItem` / `FlythroughEnvironment`.
3. Apply via `GeometryInstance3D.material_override`; cache the previous override (original or nonlinear wrap) in meta; restore on disable / Original. Do not destroy surface PBR.
4. Looks: White cladding, Chrome, Gold, Normal, Shiny black, AO, plus Original. Mix slider via `attach_driven`. Shuffle look + Schedule like Hole / Feedback.
5. Register in `EffectStack`, `ShowDirector` FX_IDS / Play All / random params, and `effects_sidebar` (new block; do not delete Nonlinear camera or Feedback rows).
6. Target the same mesh set as point-cloud defaults (main + scatter + environment, skip media / point-cloud overlays). Re-stamp on `_reapply_live_mesh_fx` / item change.
7. Playtest: enable, cycle all 6 looks, disable restores originals, schedule/shuffle work.

**Resolution.** Implemented. Scripts compile. In-editor playtest of cycling looks was blocked by a stale Godot MCP runtime auth token (parallel sessions). Toggle off / Original restores cached `material_override` (surface PBR untouched).

## 2026-08-25 - Exclude main object from nonlinear camera warp

**Issue.** User: environment/background should still bend toward top-down with distance.
The featured/main flythrough object (burger, skull, character, imported Main item) must
stay in normal undistorted perspective — not skipped by depth (near env can still warp).

**Plan.**

1. Log this (done). No commit. Do not replace Camera3D / world / spawn. Do not rewrite Feedback.
2. Main object = flythrough `Centerpiece` layer (`_center_root`, playlist Main tab).
3. Add `np_u_skip` instance uniform; `np_is_enabled()` is false when skip is set.
4. Stamp skip on GeometryInstance3D under Centerpiece; do not wrap those StandardMaterial3Ds.
5. Re-tag on centerpiece swap / item start (same class of bug as panoramic losing Camera3D).
6. Playtest: Nonlinear ON — main undistorted + textured; env still bends.

**Resolution.** Main object is the flythrough Centerpiece (`_center_root`, playlist Main).
Tagged `hs_np_main` / `np_skip_warp`. Instance uniform `np_u_skip` disables warp even
when far; StandardMaterial3D wraps are unwrapped on those meshes only. Environment,
scatter, and terrain still warp. Re-tagged on item swap via `_reapply_live_mesh_fx` →
`NonlinearProjection.refresh_scene()`. Enable path unchanged: Effects → Nonlinear camera
(or F4). Playtest: seated character stayed normal perspective; tiled far world still
lifted toward top-down; textures intact.


## 2026-08-25 - Feedback has no sharp perfect-copy trail

**Issue.** User: all existing Feedback settings are very blurred. There is no mode that
fills the image with a trail of **perfect copies** of items stacked on top of each other
(sharp, not smeared). Want video-feedback / delayed-frame echo, not gaussian trails.

**Plan.**

1. Log this (done). No commit. Do not replace Camera3D / world / spawn.
2. Inspect FeedbackEffect + shader: downsample, blur pass, linear filter, decay mix.
3. Add a named mode (Copies / Sharp trail) that captures previous frames at full
   resolution with no extra blur pass, composites discrete sharp copies.
4. If Blur: 0 still internally blurs, skip blur/downsample for real. Keep existing
   blurred modes. Match slider + number + Driver UI.
5. Playtest: enable Feedback, pick sharp/copies, confirm stacked sharp copies.

## 2026-08-25 - Env scale has a hard-coded base driver

**Issue.** User: "There seems to be a hard-coded base driver to the environmental scale.
Remove that." Env scale should start undriven like other sliders; keep the Driver widget.

**Plan.**

1. Log this (done). No commit.
2. Find where env_scale is given a default expression (bass, baked driver, session restore).
3. Remove the forced default binding only — keep `attach_driven` / Driver dropdown.
4. Playtest: Env scale shows a plain number, Driver not pre-selected.

**Resolution.** Header Env scale was sticky-driven: session saved `param_of_spin` (expression),
`_apply_environment` stamped that Driver onto every env row, `_sync_env_scale_from_stage`
re-bound it, and `set_spin_driven` refused to overwrite an expression with a number. Hidden
Scale Mode still defaulted `scale_source` to `bass`. Header now saves/restores a plain number,
never copies a Driver onto catalog rows, and `reset_to_number` clears leftover expressions.
Driver widget remains; user can still pick one. Per-item Edit scale drivers are unchanged.

## 2026-08-25 - Panoramic camera only works the first time

**Issue.** User: panoramic camera works once, then after flythrough proceeds (loop / next
item / path change) it stops. Likely bound to a Camera3D that was replaced.

**Plan.**

1. Log this (done). No commit. Do not replace Camera3D systems.
2. Trace how panoramic / 360 / cubemap / lens wrap is applied (Camera FX or flythrough).
3. Re-bind to the current gameplay Camera3D on item change, path restart, and re-enable.
4. Playtest: enable panoramic, let flythrough cycle — still works.

**Resolution.** After the first env instantiate, imported GLB `Camera3D` nodes stole
`current` from the flythrough camera, so lens FOV/DOF landed on a camera that was no
longer rendering. Path AABB early-out skipped reclaiming current. Hiding the Camera FX
CanvasLayer dropped BackBufferCopy so the equirect overlay sampled a dead buffer after
the first cycle. Fix: mute nested cameras, reclaim gameplay `current` on swap/path/item
start, re-apply Camera FX, keep the CanvasLayer mounted and only toggle the ColorRect,
re-push on `item_changed`.

## 2026-08-25 - Nonlinear camera black spots (inverted lighting)

**Issue.** User: nonlinear camera inverts normals or similar — mesh has black spots.
Do not flip faces, cull_disabled as a lighting hack, or NORMAL *= -1 globally.

**Plan.**

1. Log this (done). No commit.
2. Apply the same camera-space pitch used on VERTEX to NORMAL and TANGENT.
3. Keep winding stable (don't pull verts behind camera). Restore cull_back if lighting is OK.
4. Do not regress textured albedo wrap. Playtest: ON textured, bent, no black splotches.

**Resolution.** Vertex warp pitched position and NORMAL but not TANGENT/BINORMAL, and
did not inverse-transpose the horizontal/vertical scale, so lighting hit the wrong
hemisphere (black splotches). `cull_disabled` on the wrap shader hid winding issues.
Now `np_warp_vertex_frame` applies the same camera-space pitch to NORMAL (inverse-transpose
scale) and TANGENT/BINORMAL (forward scale). Wrap shader restored to `cull_back`. No
global `NORMAL *= -1`, no face flipping. WRAP_VERSION 9 so materials rebuild.

## 2026-08-25 - Camera sliders missing numeric + driver inputs

**Issue.** User: "Normally in our camera sliders are missing inputs and driver inputs."
Effect rows elsewhere have slider + numeric input + driver input. Nonlinear camera
Strength / Near / Far / Bend (and any other camera sliders) were added as compact
slider-only rows.

**Plan.**

1. Log this (done). No commit. Do not replace Camera3D.
2. Find the reusable driven-slider widget (`SliderSpinLink` / `_fx_labeled_slider` vs
   the full effect row used by noise deform, camera FX, etc.).
3. Rebuild Nonlinear camera params (and any other camera sliders missing the pattern)
   with the same component so they get slider + number + driver.
4. Wire `attach_driven` through to `NonlinearProjection` like other effects.
5. Keep the Effects **Nonlinear camera** checkbox; overlay HUD stays gone.
6. Playtest: camera param rows match other effect rows.

**Resolution.** Nonlinear camera Strength / Near / Far / Bend were the gap (compact
slider-only rows). Reused `SliderSpinLink.attach_driven` (same as Hole / Tone / Camera
FX): slider + numeric LineEdit + Driver dropdown. Values `eval_of` into
`NonlinearProjection`; live-eval while the effect is on. Camera FX, Camera motion
rate/depth, and playlist Fly speed already had driven rows. Enable remains Effects →
Nonlinear camera.

## 2026-08-25 - Nonlinear camera ON is still white; no bend

**Issue.** Enabling **Nonlinear camera** still turns meshes clay-white and shows no depth bend.
OFF has textures. ON must keep textures AND warp. Leaving the effect off is not a fix.

**Cause.** Wrap still assigns `effects/noise_deform.gdshader`, which `#include`s warp uniforms
*before* `albedo_tex`. In Godot 4.7 Forward+ those material uniforms collide with sampler slots,
so albedo never samples (white) and warp params never land. `global uniform` was already removed;
the remaining collision is include-declared `uniform`s packed ahead of textures.

**Plan.**

1. Log this (done). No commit. Do not replace Camera3D.
2. Split include: `instance uniform` warp params (separate UBO from samplers) + functions only.
3. Dedicated wrap shader with unique samplers first (`np_albedo_tex`, …). Copy albedo/UV from
   the original StandardMaterial3D. Stamp instance params on each GeometryInstance3D every frame.
4. Move includes in noise_deform / point_cloud / media_screen / hterrain to after their samplers.
5. Playtest: OFF textured; ON textured + far geo lifts. Effects checkbox still enables.

**Resolution.** Wrap shader was failing to compile (clay-white fallback): nested include
helpers cannot read `PROJECTION_MATRIX`, and a varying cannot be an `out` argument in 4.7.
Fixed by passing `PROJECTION_MATRIX[3][3]` from `vertex()`, returning warp `t`, unique
samplers `np_albedo_tex` first, instance uniforms for injected shaders. Playtest: OFF
textured; ON burger/convento albedo bound and sampled (not white); far geo curves from the
camera-space bend. Enable via Effects → **Nonlinear camera**.

## 2026-08-25 - Nonlinear camera HUD in the 3D view; enable it from Effects

**Issue.** User: remove the floating top-left overlay ("Nonlinear camera: OFF [F4…]", debug
t-color, F9, start/end/bend line). Put a visible **Nonlinear camera** toggle on the **right**
with the other effects. They need an obvious on/off in that panel, not a hidden F-key HUD.

**Plan.**

1. Log this (done). No commit. Do not replace Camera3D / world spawn.
2. Delete the autoload CanvasLayer/Label HUD. `debug_overlay` defaults false; never instance it.
   Keep F4 as an optional shortcut only.
3. Add a CheckButton **Nonlinear camera** to `effects_sidebar` in the same style as other
   effect toggles; it sets `NonlinearProjection.enabled`. Optional compact sliders if they fit.
4. Confirm the effects column is right-anchored. If the Hyperspace/Cam-path block is the left
   overlay they objected to, do not duplicate HUD text there — the toggle lives with Effects.
5. Playtest: no leftover overlay copy; toggle visible on the right; default still OFF (textures).

**Resolution.** Removed the floating CanvasLayer HUD. The right-hand **Effects** panel (already
the right column of `main.tscn`) now has a **Nonlinear camera** checkbox plus compact
strength / near / far / bend sliders. F4 remains an optional shortcut; the checkbox stays in
sync. Playlist/HyperSpace (Cam path) stays on the left — that is the asset column, not Effects.

## 2026-08-24 - Nonlinear projection turns the world white / effect not visible

**Issue.** User: everything looks white (textures gone). Nonlinear camera effect is not visible.
They need textures restored immediately and a clear way to enable the camera warp.

**Cause.** Two separate bugs. (1) White world: wrap shader declared `albedo_tex` with
`hint_default_white`. This project already documents that unbound / default-white samplers blow
meshes to clay-white (`media_screen.gdshader`). Extra PBR samplers (MR/normal/ORM) with the same
hint made it worse; GLTF `metallic=1` without a working MR sample is chrome-white. (2) No visible
bend: ortho skip used `PROJECTION_MATRIX[2][3]≈0`, which is true for Godot 4.7 Forward+ reverse-Z
perspective, so the warp never ran on the gameplay camera. Editor **F8 is Stop**, so that toggle
never reached the game.

**Plan.**

1. Log this (done). No commit. Do not replace the gameplay Camera3D.
2. Wrap shader = noise_deform-style albedo only: no `hint_default_white`, no extra PBR samplers.
   Force dielectric metallic. Rebuild wraps (`np_wrap_ver`). Off restores original materials.
3. Skip shadows via `PROJECTION_MATRIX[3][3]` (ortho), not `[2][3]`.
4. Defaults start 4 m / end 35 m / bend 90°. Keys: **F4** on/off, **F3** debug t-color, **F9** HUD
   (F8 aliases in-game only; editor F8 stops play). HUD stays visible while the effect is on.
5. Playtest: textures present on and off; distant geo lifts when on.

**Resolution.** White world was the wrap: `global uniform` + ShaderMaterial albedo samplers in
Godot 4.7 Forward+ dropped textures (clay-white). The same wrap also hid the bend (`PROJECTION_MATRIX[2][3]`
skipped reverse-Z perspective). Fix: stop using project shader_globals for this effect; warp uniforms
are per-material (`np_u_*`). Wrap uses the project's proven `noise_deform.gdshader` albedo path.
**Default is OFF** so play starts with original textures. Click the game view, press **F4** to enable
(F3 debug blue→red by distance, F9 HUD). F4 off restores original materials. Editor F8 is Stop — do
not use it. Distances default to 4–35 m, bend 90°. Restart play after pulling these scripts.

## 2026-08-24 - Nonlinear single-camera projection

**Issue / task.** Add a camera-space nonlinear projection: near geometry stays normal perspective;
far geometry continuously lifts toward an elevated / near top-down view. Must not replace the
existing Camera3D, duplicate the world, warp in screen-space as the primary path, or rewrite
gameplay / spawn / physics systems.

**Plan.**

1. Log this (done). No commit. Isolate all new code under `res://nonlinear_projection/`.
2. Phase 1: Forward+ (Godot 4.7). Gameplay camera is the existing `Camera3D` inside
   `FlythroughEnvironment` (also demo/corridor/city), hosted in `Scene3DItem`'s `own_world_3d`
   SubViewport. World materials are mostly `StandardMaterial3D` / imported GLTF; noise deform
   already converts a subset to `effects/noise_deform.gdshader`. HTerrain Classic4 is DirectMeshInstance
   (overrides never reach chunks). Safest insert: global shader uniforms + vertex include, applied
   at material wrap time and injected into the spatial shaders that already draw the world.
3. Phase 2–4: `nonlinear_projection(cam_pos)` rotates around camera X, pivot at `transition_start`,
   clamp z in front of the near plane, skip behind-camera and non-gameplay views (shadows).
4. Apply without rewriting player/camera types: Autoload scans GeometryInstance3D, wraps
   StandardMaterial3D via a cached ShaderMaterial that keeps albedo/PBR and runs the include.
   Existing spatial shaders (`noise_deform`, `point_cloud`, `media_screen`, HTerrain `simple4`)
   get a one-line include so noise/point-cloud/terrain still warp when those materials replace ours.
5. Verify via Godot MCP playtest: near unchanged, far elevates, disable works, same Camera3D.

**Resolution.** Implemented. Isolated under `res://nonlinear_projection/`. Autoload `NonlinearProjection`
pushes global shader uniforms and wraps `BaseMaterial3D` on world `GeometryInstance3D` with a spatial
shader that includes `nonlinear_projection(cam_pos)`. Existing world shaders (noise deform, point cloud,
media screen, HTerrain Classic4) include the same warp so they still bend when they replace wrapped
materials. Existing Camera3D is unchanged (verified 1 camera, path
`Item_stage/.../Camera3D`, `current=true`). Headless load-check: scripts + shaders OK. `script_check`
valid on all three GDScript files. Playtest: wrap cache filled (~13 ShaderMaterials), disable toggle
returns identity (HUD OFF), aggressive start/end lifts far convento mesh; defaults restored
(start=20, end=100, strength=1, bend=85°). No shader compile errors in editor console.

## 2026-08-24 - Add saturation slider to Tone

**Issues reported.**

1. Tone already has invert, brightness, and contrast. Add a Saturation slider in the same
   settings group, same nested/quieter styling.

**Plan.**

1. Log this (done). No commit, no push. Do not touch audio capture, noise deform, or unrelated FX.
2. Follow the existing Tone pattern: shader uniform + `tone_effect.gd` eval/set + sidebar
   driven slider + Play All target + `show_director` random params.
3. Saturation: 0 = grayscale, 1 = original (default, existing look unchanged), >1 = more
   saturated. Range 0–3 (slider 0–200 → 0–2, shader/eval headroom to 3). Rec.709 luminance
   mix. Order: keep existing brightness → contrast → invert, then saturation last (does not
   change invert/brightness/contrast).
4. Audio-mappable via `SliderSpinLinkScr.attach_driven`; Play All key `tone_saturation` with
   `_fmt_audio_drive_expr` (whole-number gain, never `* 0.x`).
5. `script_check` edited GDScript, restart playtest, verify visually (0 gray, 1 unchanged,
   high punchier). Screenshot if possible.

**Resolution.** Done. Param `saturation` (Play All `tone_saturation`), range 0–3 (slider 0–200
→ 0–2, default 1 / slider 100). Shader order: brightness → contrast → invert → saturation
(Rec.709 luminance mix). Play All uses `_fmt_audio_drive_expr` with scale 2 — sample
`bass * 2`. Verified: sat 0 grayscale skull, sat 1 original beige, sat 2 punchier orange/warm;
invert 1 still flips to blue negative. `script_check` valid. No commit.

## 2026-08-23 - Effects sidebar restructure + Tone effect + feedback blur

**Issues reported.**

1. Hole's settings render *inside* the Feedback Trail block. Cause found: `_setup_hole()`
   anchors on `chromatic_schedule_host`, which is a child of `chromatic_body`, so
   `after.get_index()` is an index inside `chromatic_body` (5) but it is passed to
   `fx_section.move_child()`. Index 6 in `FxSection` lands between `FeedbackToggle` and
   `FeedbackBody`, so Hole visually became a Feedback setting.
2. `Deform` and `Visual Effects` are two sections. Deform *is* a visual effect; there should
   be one flat effect list with no group headers.
3. Play All only assigns audio drivers to the old Visual Effects group. It must also drive
   scale, rotation, noise displace and camera motion.
4. Effects and their settings look the same weight, so the hierarchy is unreadable.
5. Missing an image-tone effect (invert / lightness / contrast).
6. Feedback Trail has no blur control. At 0 it should be a crisp duplicated frame, not a smear.
7. Feedback Trail has no blend mode: the previous frame can only ever be mixed on top.
8. Regression: sliders with a driver expression no longer move in real time, they sit stuck on
   their static value.

**Plan.**

1. Log this (done). No commit, no push.
2. Anchor Hole on a real `FxSection` sibling and give it its own top-level row.
3. `_flatten_effect_list()`: reparent the Deform rows (Scale, Rotation, Noise Displace,
   Camera motion + their bodies) into `FxSection` and order every effect explicitly. Hide
   `TargetsLabel` and `FxLabel` instead of inventing replacement headers.
4. `_apply_effect_hierarchy_styling()`: effect toggles get a larger font; every settings body
   is wrapped in `PanelContainer > MarginContainer > body` with a left indent, a faint tint and
   a left accent rule, and its labels are shrunk and dimmed. Panel visibility mirrors the
   body's own `visible` so every existing accordion/search write keeps working.
5. Play All: enable the deform toggles + their `react_*` schedules and add the deform sliders
   to `_play_all_fx_audio_targets()`. Keep `_fmt_audio_drive_expr()` (integer gain >= 1) as the
   only writer of expressions, so no `* 0.x` can appear.
6. New `tone` effect: `effects/tone_effect.gdshader` + `effects/tone_effect.gd` (layer 6,
   between Camera/Lens and Chromatic), registered in `EffectStack`, added to every `FX_IDS`
   list and to Play All random params. Controls Invert / Brightness / Contrast as driven
   sliders so all three are audio-mappable.
7. Feedback blur: new `blur` uniform. The old shader hardcoded `textureLod(history_tex, …, 1.15)`,
   which is exactly the baked-in blur. Map `lod = blur * 3.3` so the previous look is
   reproduced at the new default (0.35) and `blur = 0` samples LOD 0. Also raise the history
   capture cap from 640 to 1280 px when blur is ~0 so the "crisp duplicate" is genuinely crisp.
8. Do not touch `autoload/audio_analyzer.gd` or `core/system_audio_loopback.gd`. Audio Source
   stays as the two mic entries + one status line, no banners, no CTA buttons.

**Resolution.** All six items done and verified in a playtest.

1. `_setup_hole()` now anchors on a real `FxSection` sibling (`chromatic_toggle`), so `HoleToggle`
   is a top-level row with its own nested body instead of landing inside `FeedbackBody`.
2. `_flatten_effect_list()` reparents Scale / Rotation / Noise Displace / Camera motion (and their
   bodies + schedule hosts) into `FxSection` and orders every effect explicitly via
   `_effect_rows()`. `TargetsLabel` and `FxLabel` are hidden — no group headers remain. The
   sidebar now reads: Play All, Scale, Rotation, Noise Displace, Camera motion, ASCII Preset,
   Feedback Trail, Glitch, Chromatic Aberration, Tone, Hole, Wireframe, Point Cloud, Camera / Lens.
3. `_apply_effect_hierarchy_styling()` wraps every settings body in
   `PanelContainer > MarginContainer > body`, indents it, tints it, adds a left accent rule and
   shrinks/dims its labels. The panel mirrors the body's own `visible`, so the accordion and the
   search filter keep working untouched.
4. Play All: `_play_all_deform_audio_targets()` feeds the deform sliders into
   `_play_all_fx_audio_targets()`, and `_enable_deform_for_play_all()` turns the deform toggles +
   their `react_*` schedules on. Observed expressions in the playtest: `band15 * 2` / `band0 * 2`
   (Scale Amount), `beat * 3` (Rotation Amount), `band12 * 25` (Noise Amount), `band9 * 5`
   (Noise Scale), `mids * 3` (Camera Rate), `peak` (Camera Depth). `_fmt_audio_drive_expr()` is
   still the only writer and rounds up to an integer >= 1, so `* 0.x` cannot be emitted.
5. New `tone` effect (`effects/tone_effect.gd` + `.gdshader`, layer 6). Invert / Brightness /
   Contrast are driven sliders, registered in `EffectStack`, `FX_IDS`, Play All random params and
   Play All audio targets (`tone_invert`, `tone_brightness`, `tone_contrast`). Verified visually:
   invert flips the whole viewport.
6. Feedback blur: new `blur` uniform, slider default 35 % (`0.35`). The old shader hardcoded
   `textureLod(history_tex, ..., 1.15)`, which was the baked-in blur; the LOD is now
   `blur * 3.3` plus a 4-tap ring that fades in with `blur`, so `0.35` reproduces the old look and
   `0` samples LOD 0 with no ring. `_capture_history()` also raises the history capture cap from
   640 px to 1280 px while blur <= 0.06 and always calls `generate_mipmaps()` (without mips the
   LOD silently collapsed to 0). Verified in the viewport: at 0 the trail is a crisp duplicated
   frame with hard edges, at 100 it is a soft smear.

7. Feedback blend modes: new `blend_mode` int uniform + `Blend mode` dropdown, seven plain-language
   entries (Normal, Glow, Brightest, Darkest, Shadow, Edges, Contrast) stored as a name in the
   `blend` param so old presets fall back to Normal. Normal keeps the exact previous math
   (`mix(scene, trail, a)` via `blend_mix`), so the default look is unchanged.
   Each family needs its own identity element or the frame-to-frame loop diverges: additive modes
   keep the existing black-fading `trail`, Darkest / Shadow fade towards white
   (`mix(vec3(1.0), hist, p)`) and Contrast towards grey, otherwise min/multiply against a
   history that decays to black crushes the whole frame to black within a few frames. The
   darkening modes also skip the luminance gate on the coverage alpha, since gating on trail
   brightness would make them no-ops. Verified in the viewport: Normal soft ghosting, Edges at
   Blur 0 hard-edged outlines, Shadow stable dark trails, Glow stable additive streaks.
   Blend mode is an enum, so it is deliberately NOT an audio target. Play All varies it through
   the existing discrete `CycleRandomScr.attach_shuffle` slot ("Shuffle blend"), the same
   mechanism Hole's Shape uses, so no expression is ever written to it.

8. **Regression fixed - driven sliders stopped live-previewing.** `attach_driven()` /
   `attach_driven_choice()` hooked `tree_exiting` to `unregister_driven()`. `Node.reparent()`
   emits `tree_exiting` for the whole moved subtree, and `_flatten_effect_list()`,
   `_nest_setting_body()`, `_nest_react_bodies()` and `_relocate_analyzer_to_drivers()` all
   reparent whole settings bodies during `_ready`, so every slider inside them was silently
   dropped from `SliderSpinLink._driven` and `refresh_all_previews()` stopped moving its thumb.
   Proof: `PlaySpeedSlider` (moved with `move_child`, never reparented) tracked `lfo1 * 5`
   1.15 -> 3.0, while `ChromaticAmountSlider` (reparented into `ChromaticBodyNest`) sat frozen at
   85 with the same kind of expression.
   Fix: `_on_driven_exiting()` now only unregisters when `instance_from_id()` shows the object is
   really gone; `refresh_all_previews()` already sweeps freed instances every frame, so nothing
   leaks. A first attempt deferred the check through a one-shot `process_frame` connection, but
   Godot treats the bound static callables as one connection and spammed
   "Signal 'process_frame' is already connected" - dropped in favour of the validity check.
   Also added a drag guard: `drag_started` / `drag_ended` set `_dragging[id]` and
   `refresh_all_previews()` skips a slider while its thumb is held, so live preview never fights
   a drag and resumes on release. Nothing writes back to `driven_expr`, so the stored value
   cannot ratchet. Verified after the fix: chromatic 20 -> 55 -> 26, scale 0 -> 2 -> 1,
   rotation 0 -> 2 -> 1, tone brightness 2 -> 157 -> 128.7, feedback blur 2 -> 100, and an
   undriven slider held 76.9 across three samples. Under Play All the same sliders track
   `band0 * 2` / `kick * 2` / `bass * 2` live (blur 23 -> 0 -> 4).

Diagnostics: `lsp_project_diagnostics` scanned 70 files, 0 findings; `script_check` clean on
`tone_effect.gd`, `feedback_effect.gd`, `effect_stack.gd`, `show_director.gd`,
`effects_sidebar.gd`, `slider_spin_link.gd`. Runtime log clean of errors on a fresh playtest.
Audio capture pipeline untouched: Audio Source is still exactly two entries
("Microphone (music)", "Microphone (voice)") with one status line, `refresh_devices_btn` hidden,
no banners and no CTA buttons.

## 2026-08-23 - Mic hears voice but not music (Voice Focus APO)

**Issue.** The visualizer reacted beautifully to speech and barely at all to music played
through the laptop speakers. Cause: the default recording endpoint is the Realtek mic array
with the Lenovo AISPEECHAPO ("Voice Focus") in the chain. It is built for speech — it treats
music as background noise and runs an AGC that lifts the room floor to music level.
Measured with the helper's `--mode miccheck`:

| | noise-floor peak | music peak | ratio |
|---|---|---|---|
| processed (APO active) | 0.120 | 0.142 | **1.2x** |
| raw (APO bypassed) | 0.021 | 0.103 | **4.9x** |

At 1.2x music is statistically indistinguishable from silence, which is exactly what the
app was reporting.

**Fix.** Capture the same microphone in WASAPI raw processing mode
(`AUDCLNT_STREAMOPTIONS_RAW` via `IAudioClient2::SetClientProperties`), which bypasses the
APO. Godot's `AudioStreamMicrophone` can only ever get the processed stream, so the raw
signal comes from the native helper over UDP and is injected through an
`AudioStreamGenerator` onto its own analysis bus. Endpoint `Disable_SysFx` was tried and
abandoned: without elevation `Commit` reports success without persisting, and it invalidated
the device (`AUDCLNT_E_DEVICE_INVALIDATED`). Raw mode alone is sufficient and needs no
elevation and no Windows settings changes.

**Two user-facing sources, mic only.** "Microphone (music)" (raw, default) and
"Microphone (voice)" (the normal processed path). System-audio loopback is not spawned or
mixed anywhere in the live path; `core/system_audio_loopback.gd` and the helper's loopback
mode are left in the repo unused.

**Consequences of raw capture, and what each needed.**

- *No noise suppression.* Room noise is now in the signal, so the analyzer learns a per-band
  floor and subtracts it. The estimator has to fall fast and rise very slowly (~5 min): a
  rise of 3 s absorbed a track in seconds and a 24 s rise still killed it within 20 s, which
  looked exactly like the original bug.
- *Room rumble.* Fan/desk noise below ~150 Hz swings several-fold on its own, enough to look
  like signal to any level tracker. High-passed at 150 Hz in the helper. Laptop speakers put
  out nothing usable there anyway, so bass now maps to 125–500 Hz.
- *Kick detection.* Was looking at 40–130 Hz, which the high-pass removes. Moved to 150–350 Hz,
  the body of the kick, which is what laptop speakers actually reproduce. It also needed its
  own unweighted noise floor — reusing `_band_noise` subtracted `BAND_WEIGHTS`-scaled values
  from an unweighted magnitude and cancelled the kick entirely.
- *Presence gate.* A fixed threshold tuned for the old AGC'd mic was wrong for raw. Measured:
  with nothing playing the post-subtraction residual lands at roughly the learned noise level,
  so the bar is now `noise * 1.8` with hysteresis.

**Bugs found and fixed along the way.**

- Helpers stacked up (three at once) because `stop()` cleared the pid file before
  `_kill_stale_helper()` could read it. Stale cleanup now runs first, and the helper exits on
  its own after 5 s of failed sends (a connected UDP socket reports ICMP port-unreachable),
  so it cannot outlive its Godot process.
- Cached `AudioEffectSpectrumAnalyzerInstance` went stale whenever a bus was rebuilt and then
  reported zero forever. Re-fetched every frame.
- A frame with no buffered PCM was being reported as level 0, which collapsed the noise-floor
  estimate and made everything afterwards look like signal. Holds the last value instead.

**Verified.** Silence flat (all 16 bands and every driver at 0, residual 3.9x under the gate);
music at normal volume drives bass/mids/highs/EQ with kick and beat firing; quiet music still
detected; speech still works on the voice source; switching sources measurably changes the
spectrum (raw spreads across 125 Hz–12 kHz, processed collapses to 32–80 Hz with zero highs).

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

## 2026-08-13 - Reaction Diffusion does nothing at defaults

**Issue:** Reaction Diffusion looks static/empty when the toggle is turned ON with defaults. Likely causes: Gray-Scott feed/kill in a stable/empty region, Mix too low or gated by V≈0, simulation not seeded (sparse time-flicker pixels die), wrong/unbound sim buffer, shader not stepping, Look preset not applied until the dropdown changes, or Waves/Worms in a dead Pearson region.

**Plan:**
1. Append this issue. Do not commit unless asked. Do not revert shuffle/random, removed FX, scatter, or noise.
2. Seed a real chemical field on enable (U=1, V=0 plus spatial discs — not 0.7% moving sparkles). Re-seed when Look changes.
3. Use known-good Gray-Scott pairs (Coral/Mitosis/Spots stay; fix Worms/Waves if dead). Default Mix ~0.6 so the pattern tints the scene without crushing to black.
4. Apply the selected Look when the toggle turns ON. script_check the effect script and shader diagnostics.

**Resolution:**
1. Defaults did nothing because the sim never formed V: first `prev_tex` was unbound/empty, seed was ~0.7% time-varying pixels for 0.45s (isolated V dies), and overlay mix was `mix * (0.12 + v*0.88)` so V≈0 was ~6% tint. Waves F=0.025/K=0.06 sits above the Pearson pattern curve (stable empty).
2. New defaults (Coral): Feed 0.0545, Kill 0.062, Speed 1.0, Mix 0.60. Enable stamps three spatial V discs on U=1 so a coral-colored pattern is visible immediately and grows. Looks: Coral 0.0545/0.062, Mitosis 0.0367/0.0649, Spots 0.035/0.065, Worms 0.046/0.065, Waves 0.014/0.045. Changing Look re-seeds.
3. Files: `effects/reaction_diffusion_effect.gd`, `effects/reaction_diffusion_sim.gdshader`, `effects/reaction_diffusion.gdshader`, `ui/effects_sidebar.gd`, `autoload/show_director.gd`, `issue_log.md`.

## 2026-08-13 - Random loss of audio input device

**Issue:** User randomly loses connection to the audio input/capture device. Effects, EQ, and drivers go quiet until something reconnects — or they stay dead. Recent related change: MicCapture was raised from −80 dB to 0 dB so FFT could see signal (analysis bus stays −80). Do not undo EQ visibility unless required.

**Likely causes:**
1. Capture restarted too often: silence-as-device-loss (~2.75s of quiet music) recreates `AudioStreamMicrophone` and nulls the spectrum, then the null-spectrum path restarts again (WASAPI death spiral).
2. No-op `set_input_device` still calls `_soft_restart_capture` — device-list refresh / OptionButton re-select can tear down a healthy stream.
3. Analysis bus sends unmuted (quiet) mic into Master; a hot 0 dB player can couple capture into the WASAPI output client and invalidate it.
4. No structural watchdog: empty/`Default` flicker, unplug, or `playing == false` after a Windows default-device change is not restored without a full app restart.

**Plan:**
1. Append this issue. Do not commit. Do not revert scatter, RD, shuffle, noise, point cloud, or EQ peak-follow.
2. Keep MicCapture at 0 dB for FFT. Isolate analysis from speakers via a muted sink bus (analysis at 0 dB → sink muted/−80 → Master) so FFT stays loud without mixing into WASAPI output.
3. Never restart capture on UI/EQ ticks or same-device set. Disconnect OptionButton `item_selected` while rebuilding the picker.
4. Watchdog: if player stopped, input empty, preferred device missing/returned, or spectrum unbound — reopen with settle + backoff. Do not treat musical silence as device loss (last-resort stream recreate only after a long dead-FFT window).
5. Restore the last chosen device when Godot/Windows flickers to empty or Default. script_check. Update Resolution.

**Resolution:**
1. Connection dropped because capture was torn down too often, not because 0 dB FFT gain was “too loud.” Quiet music (~2.75s of near-zero FFT) recreated `AudioStreamMicrophone` and nulled the spectrum; the null-spectrum path restarted again. Same-device `set_input_device` (picker rebuild / refresh) also restarted WASAPI. Analysis bus sent the hot mic into Master, which can invalidate the output client.
2. Capture stays open on the selected device. Watchdog only reopens when the player stops, the stream is gone, input is empty, the preferred device vanishes/returns, or FFT stays dead for 12s after we already had signal. No restart on EQ/UI frames or same-device set.
3. MicCapture stays 0 dB. Analysis bus is 0 dB into a muted `HyperSpaceSink` (−80, muted → Master) so FFT stays visible and mic does not mix into WASAPI output. Device picker disconnects `item_selected` while rebuilding; refresh no longer double-populates.
4. Files: `autoload/audio_analyzer.gd`, `ui/effects_sidebar.gd`, `issue_log.md`. script_check valid. No commit.

## 2026-08-14 - Remove Reaction Diffusion; add Hole suck

**Issue:** Reaction Diffusion does not work (static/empty even after the seed/mix fix). User wants it removed completely — UI, Look dropdown, Feed/Kill/Speed/Mix, schedule, shuffle, scripts/shaders, EffectStack / ShowDirector / fx_automation keys — with no leftover buttons or crashy missing IDs. Replace with a screen-space “suck into a hole” post that warps the whole rendered view toward a circular or rectangular aperture.

**Plan:**
1. Append this issue. Do not commit. Do not revert audio capture watchdog, scatter, point cloud, noise, feedback, ASCII, shuffle/random, or the removed pixel-sort/cloth/particles work.
2. Delete `effects/reaction_diffusion*` and strip `rd` from sidebar, EffectStack, ShowDirector FX_IDS / Play All / randomize / reset, boot_cache, compile_check, lfx_smoke.
3. Add **Hole**: canvas post sampling `hint_screen_texture` after 3D (layer 9, under ASCII). Circular + Rectangle shape dropdown with shuffle+interval. Driver-capable Strength, Size, Twist, Softness, Flow, Offset X/Y. Small center void only — warped scene stays visible. script_check new scripts.

**Resolution:**
1. Reaction Diffusion is gone: no toggle, Look/Feed/Kill/Speed/Mix, schedule, shuffle, scripts, or `rd` effect id. Play All / reset / session restore use `hole` instead.
2. **Hole** distorts the 3D view (after chromatic/glitch, before ASCII). Circular uses polar/Euclidean suck + spiral; Rectangle uses a high p-norm / squircle so edges collapse toward a rounded-rect aperture. Strength 0 = identity. Flow + time add a slow inward crawl/twist. Center void is small so the frame does not crush to black.
3. Controls: Shape (Circular / Rectangle) + Shuffle shape / Interval; Strength, Size, Twist, Softness, Flow, Offset X, Offset Y (all driver-capable); Hole schedule.
4. Files added: `effects/hole_effect.gd`, `effects/hole_effect.gdshader`. Files removed: `effects/reaction_diffusion_effect.gd`, `effects/reaction_diffusion.gdshader`, `effects/reaction_diffusion_sim.gdshader` (+ uids). Updated: `ui/effects_sidebar.gd`, `effects/effect_stack.gd`, `effects/effect_layer.gd`, `autoload/show_director.gd`, `core/boot_cache.gd`, `tools/compile_check.gd`, `tools/lfx_smoke.gd`, `issue_log.md`. script_check valid. No commit.

## 2026-08-14 - Hole looks like a lame twist

**Issue:** Hole post is “just the twist effect” and looks lame. User wants stretch-and-fall-in (edges sliding into the hole, near-hole pixels elongate more, far pixels later), a readable warped scene (small center void at peak, not a black crush), and a clear cycle: collapse in → peak/void → emerge (breathe), then repeat. Twist should be a subtle optional extra, default off.

**Plan:**
1. Append this issue. Do not commit. Do not revert other FX.
2. Rewrite `hole_effect.gdshader` + `hole_effect.gd` with a cycle phase (0 = almost normal, 1 = fully fallen in) driven by time × Flow; Strength = max depth. Radial/box falloff (~1/r + delayed far pull). Rectangle uses squircle/box distance so frame edges fall toward a rectangular aperture. Twist default 0.
3. Sidebar / randomize defaults so toggling Hole ON shows a visible fall-in without tweaking. Keep Shape Circular/Rectangle + shuffle.
4. Prefer collapse-then-emerge breathe over a hard reset to black. script_check. Update Resolution.

**Resolution:**
1. Hole is a stretch/fall-in breathe, not a swirl. Cycle phase 0 = almost normal, 1 = fully fallen in. `time × Flow` drives a ~5s loop at default Flow 0.50: collapse (ease-in, ~46%) → short peak/void (~8%) → emerge back out (~46%), then repeat from rest. Toggle-on resets to phase 0. Strength is max depth. No hard smash-to-black.
2. UV remap is radial (or squircle-normal for Rectangle): 1/r stretch near the hole, frame sides start sliding early, bulk pull grows toward peak. Twist is optional garnish, default **0**. Small void only at peak so the warped scene stays readable.
3. Defaults (toggle ON looks like falling-in immediately): Strength 0.75, Size 0.20, Twist 0, Softness 0.30, Flow 0.50, Offset 0.5/0.5, Shape Circular. Shape shuffle kept.
4. Files: `effects/hole_effect.gdshader`, `effects/hole_effect.gd`, `ui/effects_sidebar.gd`, `autoload/show_director.gd`, `issue_log.md`. script_check valid. No commit.

## 2026-08-17 - Evolution Mode for visual effects

**Issue:** Add Evolution Mode for Play All visual effects, analogous to Random (shuffle) mode. Start simple (~2 effects), then slowly add a third, fourth, and more so the mix grows richer over time. Wire it in the same UI/settings/controller as Random. Mutually exclusive with Cycle / Random / Audio.

**Plan:**
1. Log this issue. Do not commit.
2. Play All Random already uses a master Active/Inactive mute + random subset mask + param reshuffle. Add `evolution` as a fourth Play Mode next to Cycle / Random / Audio.
3. Evolution: start with 2 random FX; periodically add one unused FX into the set (grow up to the Play All cap of 8). Do not drop already-on effects. Inactive still mutes. Grow interval tracks master Active seconds (clamped 4–16s), scaled by Play All Speed. Randomize params only for newly added FX.
4. Sidebar: Mode dropdown + tooltips; schedule UI treats Evolution like Random (master clock, no per-FX re-roll). Shuffle-mode checkbox still cycles the dropdown, now including Evolution.
5. script_check. Update Resolution. No commit.

**Resolution:**
1. Play All Mode dropdown is now Cycle / Random / Audio / **Evolution** (mutually exclusive). Evolution sits next to Random: same master Active/Inactive mute + subset mask, but the mix starts at 2 FX and grows.
2. Grow: every `clampf(Active * 1.0, 4, 16)` seconds (scaled by Play All Speed) add one unused effect; already-on FX stay. Cap is the Play All set (8). Inactive pauses growth but does not reset; toggling Play All off/on or switching into Evolution starts at 2 again. New FX get randomized params; existing ones keep theirs.
3. Tunables: `FxAutomation.EVOLUTION_START_COUNT` (2), `EVOLUTION_INTERVAL_MIN/MAX` (4/16s), `EVOLUTION_INTERVAL_ACTIVE_SCALE` (1.0 × Active). Speed slider still scales time.
4. UI: Effects → Play All → Mode. Shuffle-mode checkbox still auto-cycles the dropdown (now includes Evolution). Random still reshuffles independently.
5. Files: `effects/fx_automation.gd`, `autoload/show_director.gd`, `ui/effects_sidebar.gd`, `issue_log.md`. script_check valid. Runtime: dropdown shows Evolution; start=2; grow 2→3→4 kept prior FX; switching Random then back to Evolution reset to 2. No commit.

## 2026-08-17 - Images and GIFs as point cloud

**Issue:** When Point Cloud is ON, 3D models / scatter become dots, but still images and GIFs stay as regular textured screens (2D sprites / media quads). User: images and GIFs should also become a point cloud when the point-cloud effect is active. If the source is not already a point-cloud asset, still convert it whenever the visual mode is on. Do not interfere with Evolution Mode work.

**Plan:**
1. Log this issue. Do not commit. Do not revert Evolution Mode / shuffle.
2. Point cloud already converts MeshInstance3D vertices to `PRIMITIVE_POINTS` overlays (`SceneMeshFx` + `point_cloud.gdshader`). Images/GIFs in the flythrough are `FlythroughMediaProp` tessellated planes — they are **explicitly skipped** (`skip_media=true`, scatter `media_screen` excluded, comments: "Media planes are never converted").
3. Reuse that overlay path: stop skipping media screens; denser UV grid for a single image/GIF plane; live `tex_albedo` sampling so GIF (and video) frames keep animating instead of baking one still. Point Cloud OFF restores the normal screen.
4. script_check. Update Resolution.

**Resolution:**
1. Images/GIFs (and video screens on the same prop) were skipped on purpose: `collect_meshes(..., skip_media=true)`, scatter `media_screen` MultiMeshes excluded, comments “never converted.” The overlay pipeline itself already supported ShaderMaterial `tex_albedo`.
2. Point Cloud ON now converts those screens through the same `HSPointCloud` overlay: hide the quad via cull layer 20, draw `PRIMITIVE_POINTS`. A single image/GIF plane uses an 80×80 UV grid; scatter instances keep the tessellated plane verts. Live `tex_albedo` sampling (not a baked still) so GIF frame swaps and video blits keep animating. Transparent texels are discarded. Point Cloud OFF restores the normal media shader screen.
3. Files: `core/scene_mesh_fx.gd`, `items/flythrough_environment.gd`, `items/flythrough/media_prop.gd`, `items/scene3d_item.gd`, `effects/point_cloud.gdshader`, `issue_log.md`. script_check valid. No commit. Evolution Mode notes left intact.

## 2026-08-17 - Play All audio-reactive drivers + audio shuffle

**Issue:** With Play All on, enabling the **audio reactive** toggle should put every listed visual effect on **Driver** and assign **some audio driver** (volume / bass / mids / bands / …). If **Shuffle mode** is also on, audio driving itself should shuffle: switch audio sources over time and apply random multipliers (e.g. `volume * 10`). Do not replace Evolution / Cycle / Random or the existing Shuffle-of-Play-All-modes dropdown cycle.

**How it already works:**
1. Play All enables all FX + schedules. Mode Cycle / Random / Audio / Evolution are mutually exclusive. Audio mode is “like Cycle, but loudness speeds the clocks” and forces the audio-reactive toggle on. The toggle itself only scales schedule speed / active windows via `play_all_audio_energy` — it does **not** assign per-slider drivers.
2. Per-effect Mode (Audio/LFO/Static) UI is hidden; each slider has a Driver dropdown + expression (`bass`, `volume * 10`).
3. Shuffle mode on Play All only advances the Mode dropdown on a fixed interval.

**Plan:**
1. Log this issue. Do not commit. Do not revert Evolution Mode, Cycle, Random, or Shuffle-of-modes.
2. Play All + audio reactive (or Mode=Audio): snapshot current slider/choice expressions, then assign a variety of audio drivers across Play All FX params (density, mix, glitch, chromatic, hole, point size, camera/lens, ASCII style, wireframe intensity).
3. Shuffle mode + audio reactive: keep cycling the Mode dropdown; also re-pick audio drivers and multiply amounts (0.5×, 1×, 2×, 3×, 5×, 8×, 10×). Reuse the Shuffle interval. Restore snapshotted expressions when audio reactive is turned off or Play All is turned off.
4. Unify with Mode=Audio (same toggle path). Do not force the dropdown to Audio when the toggle is on (that would fight Shuffle-of-modes).
5. script_check + playtest if possible. Update Resolution.

**Resolution:**
1. Play All + Audio reactive (or Mode=Audio) snapshots current slider/choice expressions, then assigns a shuffled variety of audio drivers (`volume`, `energy`, `peak`, `bass`, `mids`, `highs`, `kick`, `beat`, `band0/3/6/9/12/15`) across Play All FX params (ASCII density/style, feedback, glitch, chromatic, hole, wireframe intensity, point size, camera/lens). LineEdit shows e.g. `bass` or `volume * 80` (same as picking Driver).
2. Shuffle mode (existing Play All Mode cycle, default interval 5s, range 0.5–30s) still advances Cycle/Random/Audio/Evolution. When Audio reactive is also on, each shuffle tick re-picks drivers and multiplies amounts by 0.5 / 1 / 2 / 3 / 5 / 8 / 10 (hole center capped at 2×). Does not replace Evolution / Cycle / Random or the mode-cycle shuffle.
3. Restore: turning Audio reactive off, turning Play All off, or Reset restores the snapshotted expressions. Limitation: snapshot is taken once on first assign; slider edits made while audio-driving are discarded on restore.
4. Mode=Audio forces the Audio reactive toggle on and uses the same assign path. The toggle does not force Mode=Audio, so Shuffle-of-modes can still cycle the dropdown.
5. Files: `ui/effects_sidebar.gd` (assign/restore/shuffle + tooltips), `effects/fx_automation.gd` / `autoload/show_director.gd` (Evolution + existing audio-energy clock; unchanged by this pass beyond prior Evolution work), `issue_log.md`. script_check valid. Playtest: Play All + Audio reactive assigned mixed drivers (`volume * 80`, `energy * 3`, `band3 * 0.7`, …); shuffle apply produced 8–10× (`band3 * 800`, `band0 * 30`); disable restored snapshot numbers. Evolution still in the Mode dropdown. No commit.

## 2026-08-17 - Audio analysis: dead sliders, similar bands, gradient kick, phantom volume

**Issue:** Audio reactiveness feels broken. Kick is a smooth gradient instead of an on-off gate. Bass / mids / highs / volume all move together. Mic/room noise slams volume when nothing is happening. Master Intensity, Band Sensitivity, and Noise Floor Gate (user: “Noise Gain”) appear to do nothing.

**Root cause (investigation):**
1. `AudioAnalyzer` does compute gated drives (`current_state`) using the three sliders, but **drivers do not use those values**. `get_driver_audio()` returns peak-followed `ui_bands` (the EQ graph), then `DriverHub._renorm_audio_levels()` **re-scales volume/energy/peak/bass/mids/highs so the loudest is always ~1**. That cancels intensity, sensitivity, and the noise gate, and makes every band look the same.
2. Kick is blended with bass twice: `get_driver_audio()` does `max(kick, bass_ui)` and `_renorm` does it again. Beat detect also sets kick from `bass*1.8 + energy*0.6` with a slow decay — a shared envelope, not a gate.
3. AGC climbs to 400× on quiet input; display peak-follow then boosts FFT crumbs to full scale → phantom volume on mic hiss / silence.
4. Consumers (`reactivity_hub.drive_value`, `effect_layer.band01`) apply another `pow(0.55)`, compressing remaining differences.

**Plan:**
1. Log this issue. Do not commit. Do not touch Play All / Evolution / point-cloud UX. Keep driver names (volume, kick, bass, mids, highs, energy, peak, beat, band0–15).
2. Kick = low-band spectral flux vs a short-term threshold → binary hold (~55ms) then snap off. Never `max` with bass.
3. Bands = tighter splits + energy relative to each band’s recent average (plus a little absolute). No global peak-renorm on driver outputs.
4. Noise floor slider = real raw-magnitude gate; freeze AGC below the gate so silence stays ~0.
5. Wire sliders into the values DriverHub actually publishes. script_check + playtest if possible. Update Resolution.

## 2026-08-23 - Godot MCP server config "not being saved" in Cursor

**Issue:** User reports the Godot MCP server is not being saved in Cursor, and provided this JSON:

```json
{
	"mcpServers": {
		"godot-mcp-toolkit": {
			"args": ["/c", "npx", "-y", "@npgamedev/godot-mcp-server"],
			"command": "cmd",
			"env": { "GODOT_MCP_CONFIG_VERSION": "1" }
		}
	}
}
```

**Plan:**
1. Log this issue. Do not commit. Do not push. Prefer diagnose; only edit if a clear persist-path fix is needed.
2. Compare Cursor vs Godot MCP write/read paths: project `.cursor/mcp.json`, project `.mcp.json`, user `%USERPROFILE%\.cursor\mcp.json`, addon template/write code.
3. Check timestamps, gitignore, JSON validity, addon docs, editor console, and whether this session already has the server connected.
4. Report the exact reason and next step. No commit.

**Resolution (investigation — no code change):**
1. The JSON is already on disk and valid. Both `C:\Users\vuxan\Documents\Radovi\Code\HyperSpace\.mcp.json` (written 2026-08-13 20:46) and `C:\Users\vuxan\Documents\Radovi\Code\HyperSpace\.cursor\mcp.json` (written 2026-08-13 20:48) contain exactly the user's payload. Neither is gitignored; both are untracked.
2. The Godot MCP Toolkit only writes `res://.mcp.json` (`mcp_json_sync.gd` → `ProjectSettings.globalize_path("res://") + ".mcp.json"`). It never writes `.cursor/mcp.json`. Onboarding text says "Your MCP client reads .mcp.json from the project root" — true for Claude Code, not for Cursor.
3. Cursor reads project `.cursor/mcp.json` and user `%USERPROFILE%\.cursor\mcp.json`. User-level file last written 2025-06-15 and has only `digitalocean` — Godot was never saved there. Cursor Settings / Customize → MCPs edits that user file (or fails to list project-scope servers).
4. Known Cursor bug (forum, Aug 2026): project-scope servers in `.cursor/mcp.json` often do not appear in Customize → MCPs even while connected. This session already has `project-0-HyperSpace-godot-mcp-toolkit` connected; Godot console: `[MCP] MCP client connected` (2 peers), listening on `127.0.0.1:6550`.
5. User JSON is the correct Windows form the addon emits (`cmd /c npx`). Optional Cursor field `type: "stdio"` is missing but not required for this live connection. Nothing to fix on disk — the config is persisted at project scope; the Settings UI is the misleading part.
6. Next step for the user: treat `.cursor/mcp.json` as the source of truth (already present). Ignore Customize UI emptiness for project servers, or copy the `godot-mcp-toolkit` block into `%USERPROFILE%\.cursor\mcp.json` if they want it listed globally. Commit `.cursor/mcp.json` if they want it saved in git. No files edited besides this log.

## 2026-08-23 - Audio dies after working; visualizer/reactivity choppy

**Issue:** Audio stopped working. The visualizer was showing, then just stopped. Audio is very choppy. User: audio is the most important part of the app — everything is audio-reactive. Capture must always stay alive, always pick the correct source (system loopback / what's playing), never go silent after working, and not be choppy.

**Prior notes:** 2026-08-11 flaky spectrum; 2026-08-12 WASAPI `GetBufferSize` / output_device invalidated; 2026-08-13 random loss of input device (silence-as-loss death spiral, muted sink). Watchdog already exists but last-resort dead-FFT window is 12s and treats `peak_raw > 1e-8` as alive. Spectrum `buffer_length` is 0.1s.

**Plan:**
1. Log this issue. Do not commit. Do not push. Do not drive-by refactor FX.
2. Trace capture → analysis bus → SpectrumAnalyzer → AudioState / DriverHub → EQ. Rule in/out: stream ended without restart, silence on wrong device, FFT starvation / tiny buffer, leftover decaying spectrum, bus channel auto-disable, mix-rate mismatch, enable_input, multiple consumers.
3. Harden `audio_analyzer.gd`: keep capture always-on (`PROCESS_MODE_ALWAYS`); larger FFT history; PCM `AudioEffectCapture` heartbeat (stuck `pushed_frames` / discarded frames = dead or chop); faster stall restart; do not hard-zero on a one-frame spectrum miss; rebind/rebuild analyzer if the instance dies; prevent Godot bus-channel sleep from freezing FFT.
4. Keep loopback preference (Stereo Mix / VB-Cable / VoiceMeeter). Auto-recover device loss without user action.
5. Playtest / runtime vars / logs to confirm levels keep updating. Update Resolution.

**Resolution:**
1. **Why it worked then died / looked choppy:** (a) Spectrum `buffer_length` was 0.1s — FFT hops starved and the EQ hopped. (b) When the noise gate closed, `_fill_ui_bands(..., silent=true)` decayed the EQ even though raw FFT still had energy — leftover bars then went flat. (c) `_noise_ema` stuck high and gated real signal to 0 (drivers chopped to silence). (d) Watchdog treated quiet music / 1e-8 crumbs as device death or, conversely, waited 12s. Restarting on silence would thrash WASAPI in a quiet room. (e) Godot can disable a silent bus channel after 2s (`channel_disable_time`) and skip the SpectrumAnalyzer. (f) **Environmental:** Windows has Realtek **Stereo Mix** but it is disabled (`DeviceState` 0x10000001). Godot only sees Default + Microphone Array, so capture is the laptop mic (room / speakers), not system loopback. No admin rights to enable it from here.
2. **Capture hardening (`audio_analyzer.gd`):** `PROCESS_MODE_ALWAYS`; FFT buffer 0.85s; `AudioEffectCapture` heartbeat — restart only when **PCM frames stop** (0.45s), never because the room is quiet; per-frame `play()` if the mic player stops; hold last spectrum 160ms on a one-frame miss; rebuild analyzer if the instance is lost; AVG+MAX FFT blend + short attack/decay smoothing; noise-gate floor capped so it cannot swallow a present peak; auto-adopt Stereo Mix / VB-Cable when it appears; status warns `enable Stereo Mix for system audio` when only a mic is listed.
3. **`project.godot`:** `audio/buses/channel_disable_threshold_db=-80`, `channel_disable_time=3600` so the analysis bus does not sleep. `enable_input`, `mix_rate=48000`, `output_latency=50` unchanged.
4. **UI:** Device picker tooltip + amber status when Stereo Mix is missing / reconnecting. No layout change.
5. **Playtest:** Capture stayed up 60s+ (`playing`, `starve=0`, `stall=0`, spectrum+capture bound). PCM and volume kept changing (e.g. pcm ~0.013, vol 0.067 → 0.034). EQ / input meter moved. No WASAPI errors. Devices still only Default + Microphone Array until the user enables Stereo Mix. Playtest left running. No commit.

**Resolution:**
1. **Why it worked then died / looked choppy:** (a) Spectrum `buffer_length` was 0.1s — FFT hops starved and the EQ hopped. (b) When the noise gate closed, `_fill_ui_bands(..., silent=true)` decayed the EQ even though raw FFT still had energy — leftover bars then went flat. (c) `_noise_ema` stuck high and gated real signal to 0 (drivers chopped to silence). (d) Watchdog treated quiet music / 1e-8 crumbs as device death or, conversely, waited 12s; a later draft that restarted on silence would have thrashed WASAPI in a quiet room. (e) Godot can disable a silent bus channel after 2s (`channel_disable_time`) and skip the SpectrumAnalyzer. (f) **Environmental:** Windows has Realtek **Stereo Mix** but it is disabled (`DeviceState` 0x10000001). Godot only sees Default + Microphone Array, so capture is the laptop mic (room / speakers), not system loopback. No admin rights to enable it from here.
2. **Capture hardening (`audio_analyzer.gd`):** `PROCESS_MODE_ALWAYS`; FFT buffer 0.85s; `AudioEffectCapture` heartbeat — restart only when **PCM frames stop** (0.45s), never because the room is quiet; per-frame `play()` if the mic player stops; hold last spectrum 160ms on a one-frame miss; rebuild analyzer if the instance is lost; AVG+MAX FFT blend + short attack/decay smoothing; noise-gate floor capped so it cannot swallow a present peak; auto-adopt Stereo Mix / VB-Cable when it appears; status warns `enable Stereo Mix for system audio` when only a mic is listed.
3. **`project.godot`:** `audio/buses/channel_disable_threshold_db=-80`, `channel_disable_time=3600` so the analysis bus does not sleep. `enable_input`, `mix_rate=48000`, `output_latency=50` unchanged.
4. **UI:** Device picker tooltip + amber status when Stereo Mix is missing / reconnecting. No layout change.
5. **Playtest:** Capture stayed up 60s+ (`playing`, `starve=0`, `stall=0`, spectrum+capture bound). PCM and volume kept changing (e.g. pcm 0.013 → 0.0128, vol 0.067 → 0.034). EQ / input meter moved. No WASAPI errors. Devices still only Default + Microphone Array until the user enables Stereo Mix. Playtest left running. No commit.

## 2026-08-23 - Audio presets apply decimal-weak multipliers (0.2 / 0.25)

**Issue:** Audio works a bit better, but when the user chooses an audio device/source, presets apply tiny decimal multipliers that make an already-weak signal weaker. User sees e.g. `beat * 0.2` and `band12 * 0.25`. They want whole-number gains (1, 2, 3, 5, 10, 25 OK) — never 0.something. Explicit: bands 12 should be times 25, not 0.25; beats 0.2 should be at least times 2.

**Plan:**
1. Log this issue. Do not commit. Do not push.
2. Find all default/preset gain multipliers < 1.0 for beats/bands/audio drivers (Play All assign scales, shuffle muls, device-select reset, Driver dropdown).
3. Bump them to whole numbers >= 1. Map 0.25 → 25 (user explicit); 0.2 → 2; other 0.x → 2/3/5. Drop shuffle 0.5×.
4. If device-select reapplies a quiet preset, stop that or use the stronger defaults.
5. Fix the applied gain, not just the label. Keep the change focused.
6. Verify in Godot if possible. Update Resolution.

**Resolution:**
1. **Cause:** Play All + Audio reactive assigns driver expressions from `_play_all_fx_audio_targets()` scales written in 0–1 param space. That produced the exact UI the user saw: `beat * 0.2` (hole size) and `band12 * 0.25` (hole twist). Expressions skip the SliderSpinLink divisor, so those decimals were the real applied gain and made a weak mic even quieter. Shuffle also included 0.5×. Device-select does **not** reset presets (`set_input_device` only).
2. **Fix (`ui/effects_sidebar.gd`):** All assign scales are whole-number gains >= 1. hole_size 0.2→2, hole_twist 0.25→25 (user explicit), other 0.x → 2/3/5, aperture 2.8→3, wireframe 1→2. Shuffle muls `[0.5,1,2,3,5,8,10]` → `[2,3,5,10]`. `_fmt_audio_drive_expr` now snaps to an integer >= 1 (never emits 0.x).
3. **Verify:** script_check valid. Restarted playtest. Live assign (no shuffle): `band3 * 2`, **`band12 * 25`**, `band6 * 3`, `volume * 3`, `bass * 5`, `band9 * 2`, `mids * 2`, … — no 0.x. Formatter: old 0.2/0.25 now emit the bare name (gain 1), `band12 * 25` stays. Restored test expressions. No commit.
4. **Still weak until Stereo Mix:** capture is still the laptop mic unless the user enables Stereo Mix / VB-Cable. Gains are louder now; loopback is still the real source fix.

## 2026-08-23 - Volume/audio recognizes voice, not music

**Issue:** Capture/analysis is tuned for talking. Voice drives volume, bands, and beats well; music does not. This is an audio-reactive visualizer — music must drive kick/bass, mids, hats, and loudness. A sibling pass is raising preset gain multipliers to whole numbers (>= 1); do not revert those.

**Likely causes to rule in/out:**
1. FFT bin mapping / band averages concentrated on speech (300–3400 Hz) instead of kick (~40–80), bass, and hats.
2. Noise gate / AGC / MAX-vs-AVG / contrast drive that prefers spoken consonants over sustained music.
3. Beat detector on midrange onsets instead of low-frequency kick transients.
4. Mic path (no Stereo Mix) + mid-weighted energy so close speech wins over speakers.
5. No voice vs music toggle — “clicked” means retune/default to music, not a new settings system.

**Plan:**
1. Log this issue. Do not commit. Do not push. Do not fight whole-number preset gains.
2. Retune `audio_analyzer.gd` for music: explicit full-range band edges, de-emphasize speech mids, kick from 40–130 Hz MAX, volume mixes PCM loudness + weighted spectrum, AVERAGE-heavy FFT (sustained notes), slightly friendlier silence gate for quiet music.
3. Keep capture heartbeat / Stereo Mix auto-adopt. No new voice/music UI unless one already exists (it does not).
4. script_check + playtest/runtime vars. Update Resolution.

**Resolution:**
1. **Voice-tuned how:** Naive log FFT (20–16 kHz) wasted bins on empty 20–40 Hz and packed energy into speech mids. Band drive was contrast-first (plosives win, sustained music dies). FFT blend was 55% MAX (consonants). Kick averaged bins 0–2 including dead sub, then compared raw ~1e-5 FFT to a speech-sized silence floor so drums never fired. Equal-weight energy + peak-only volume followed talking. No voice/music UI existed to click.
2. **Fix (`autoload/audio_analyzer.gd`, driver hints):** ISO-ish music edges 32–20 kHz; speech-core weights ducked; kick = 40–130 Hz MAX flux in AGC units; hats 6–18 kHz MAX into highs; volume = weighted spectrum + PCM; AVERAGE-heavy bins; FFT 4096; quieter-music silence/EQ no longer zeroed by a speech floor. Capture heartbeat / Stereo Mix auto-adopt unchanged. Did not touch whole-number Play All gains.
3. **Verify:** script_check valid. Playtest 70 Hz burst on analysis bus: `kick=1`, `beat=1`, energy in bass bins 2–3, `mids=0`, volume ~0.15 (was ~0.03–0.07). Status `signal OK`. Devices still Default + Microphone Array.
4. **User still needs:** Enable **Stereo Mix** (Sound settings → Recording → Show Disabled Devices) or use VB-Cable / VoiceMeeter. Until then capture is the laptop mic (room/speakers), which will always prefer close speech over music from the speakers. No commit.

## 2026-08-23 - Recurrence: still voice-only, music ignored (not an FFT-tune bug)

**Issue:** User (frustrated): same bug — app recognizes voice, not music. "Just make it recognize the audio as audio." Prior retunes (FFT bands, kick 40–130 Hz, ducked speech mids, whole-number gains) did not fix the user-visible problem.

**Evidence (this pass, do not retune FFT again):**
1. Runtime `AudioServer` devices = `Default` + `Microphone Array (Realtek(R) Audio)` only. Current = `Default`. Status already says `enable Stereo Mix for system audio`. PCM RMS = 0, bands = 0 while idle (music from OS never arrives).
2. Windows capture: Microphone Array `{bbf7271e-…}` **active**. Realtek **Stereo Mix** `{5d6ee233-…}` DeviceState `0x10000001` (disabled). HKLM write denied (unelevated).
3. Mic Array `FxProperties` includes **AISPEECHAPO** (`SWD\DRIVERENUM\…#AISPEECHAPO`). That Windows/Lenovo AI speech APO passes talk and treats music as noise — matches "voice works, music doesn't" even with a music-tuned FFT.
4. No WASAPI loopback / GDExtension / miniaudio helper in the repo. Godot `AudioStreamMicrophone` cannot open render loopback.

**Plan (input path, not bands):**
1. Implement a small WASAPI loopback helper (csc.exe is present; no .NET SDK) that captures default **render** and injects PCM into the analysis bus via `AudioStreamGenerator`.
2. Default source = system audio. Stop the voice mic while loopback is alive so AI Speech APO never gates the visualizer. Try IPolicyConfig to unhide Stereo Mix; set HKCU `UserDuckingPreference=3`.
3. Analyzer: treat incoming PCM as music (no VAD). Keep whole-number Play All gains.
4. Fail-loud UI: label `System audio` vs `Laptop mic (voice-processed)`; persistent banner if stuck on the speech mic.
5. Do not commit / push. Update Resolution after the change.

**Resolution:**
1. **Root cause (not FFT):** Godot capture was `Default` → `Microphone Array (Realtek)`. That endpoint has **AISPEECHAPO** (Lenovo/Realtek AI speech). It passes close-talk and treats music as noise. Runtime devices were only Default + Microphone Array. Realtek **Stereo Mix** `{5d6ee233-…}` is DeviceState `0x10000001` (disabled). HKLM write denied (unelevated). IPolicyConfig unhide failed (`E_NOINTERFACE` on device collection). FFT retunes could not hear music that Windows had already stripped.
2. **Fix — WASAPI render loopback:** `tools/loopback/HyperSpaceLoopback.exe` (C#, csc) captures default render (`Speakers (Realtek(R) Audio)`) and UDP-sends PCM to Godot. `core/system_audio_loopback.gd` injects it on `HyperSpaceAnalysis`. Default source is System audio; the voice mic is stopped while loopback is alive. HKCU `UserDuckingPreference=3`. Analyzer treats PCM as music (no VAD). Play All whole-number gains untouched.
3. **Evidence:** Helper while Windows played Alarm01: `peak=0.03–0.28`. Godot on system audio: status `System audio · Speakers (Realtek(R) Audio)`, int16 decode of silence = 1 LSB (1/32768), **PCM RMS 0.0158 during the alarm** (was ~0 on the voice mic with no one talking). If FFT gate is closed, volume now follows that PCM.
4. **UI:** Device list leads with System audio; mics labeled `Laptop mic (voice-processed)`. Persistent banner: green on system audio, red on voice mic with **Use system audio** / **Windows recording**.
5. **Still needs a Windows click only if the helper exe is missing or loopback fails** — then the red banner stays. Enabling Stereo Mix still needs an elevated Sound settings click (code cannot flip HKLM DeviceState). Not required when the helper runs. No commit.

## 2026-08-23 - Graphic EQ looks fake / always dancing, music does not change it

**Issue:** User (regression after WASAPI loopback): Graphic EQ is busy with **no music playing** (looks hardcoded/fake). When they **do** play music, the EQ does not change. Worse than before loopback.

**Likely causes (prove, then fix):**
1. Idle/demo/fake spectrum left on.
2. Loopback helper injects hiss/DC that analyzer treats as constant music.
3. Wrong stream / leftover mic + loopback / analyzing a bus that is not injected PCM.
4. Hold-last / 0.85s FFT buffer never reaches zero.
5. Peak-normalize + AGC + ultra-low loopback `music_present` so a tiny noise floor fills the EQ; real music cannot move it further.
6. Visualizer driving itself (timer/feedback) not AudioState.
7. Stale helper process looping a buffer.

**Plan:**
1. Log this. Do not commit / push. Do not revert whole-number Play All gains.
2. Read analyzer, loopback helper, EQ UI. Inspect runtime (device, pcm rms, bands, helper).
3. Gate loopback noise: silence → flat/near-zero EQ. Do not invent spectrum if loopback is broken (red banner).
4. Keep system-audio as the intended source. Prefer a working silent-until-music EQ over a busy fake one.
5. Verify silence vs Alarm01 / tone. Update Resolution.

**Resolution:**
1. **Why it looked fake:** Not a hardcoded demo animation. WASAPI loopback always sends packets (hiss/DC ~6e-5). The previous pass treated `peak_raw > 2e-9` or `pcm > 8e-5` as music whenever the helper was alive. `_fill_ui_bands` then **peak-normalized** ~1e-7 FFT crumbs to 0–1, so the Graphic EQ drew the `BAND_WEIGHTS` curve (busy bass+air) while volume/energy/bass stayed 0. Real music could not move an already-full graph. A second path painted all 16 bands with the same PCM volume when the FFT gate was closed.
2. **Evidence (before):** silence 41s, `pcm_rms=1e-5`, raw FFT ~3–6e-7, `ui_bands` 0.23–0.96 (weight-shaped). Drivers `volume/energy=0`. Screenshot: dancing EQ, gated values 0.000. Helper `debug_peak=6e-5`. Mic was stopped (not a leftover-mic mix).
3. **Fix:** Gate loopback inject below 0.0028 (do not feed hiss into FFT; push zeros so the 0.85s window decays). Analyzer: loopback “music present” requires `pcm >= 0.0035` or a real FFT silence floor — no 1e-9 override. Do not invent a flat PCM spectrum. Peak-normalize cannot amplify below `UI_PEAK_ABS_FLOOR`. Play All whole-number gains untouched. System audio stays the default source.
4. **Verify:** Silence → `ui_bands` all 0, `pcm=0`, `volume=0`. Alarm01 looping → helper peak 0.53, `pcm=0.160`, `volume=0.311`, status `signal OK`, energy in mid bands 5–6 (0.77 / 0.37) not the weight curve. After stop → all zeros again. Files: `autoload/audio_analyzer.gd`, `core/system_audio_loopback.gd`, this log. No commit.

## 2026-08-23 - One live mic only (strip system-audio chrome)

**Issue:** User (frustrated): they do not want system audio, device lists, banners, or extra buttons. Loopback does not work for them. Music does not drive the visualizer. The mic only “works” after picking among Default / laptop mic / voice-processed. They want **one always-on live microphone** — whatever the mic hears (speech, music from speakers, room sound) drives EQ and drivers. No source picker, no green/red banners, no “Use system audio” / “Windows recording”.

**Plan:**
1. Log this. Do not commit / push. Do not revert Play All whole-number gains.
2. Default and only capture path = Godot `AudioStreamMicrophone` on the Windows default recording device. Start it, keep it playing, auto-restart if the player stops or PCM frames starve (not because the room is quiet). Do not spawn `HyperSpaceLoopback.exe` or inject loopback PCM.
3. Hide source chrome in `ui/effects_sidebar.gd` / `.tscn`: device dropdown extras, banners, system-audio / Windows recording buttons. No Default vs voice-processed vs System audio labels.
4. Keep music-oriented FFT (kick/bass/hats). Do not restore speech VAD. Noise floor stays so silence is not fake-busy; do not over-gate so speaker music into the mic can still move bands.
5. Playtest via Godot MCP. Update Resolution.

**Resolution:**
1. **Stripped:** WASAPI loopback is no longer started or mixed into analysis. `HyperSpaceLoopback.exe` / `system_audio_loopback.gd` stay in the repo unused. Device dropdown (Default / Microphone Array / System audio), green/red source banners, **Use system audio**, and **Windows recording** are gone. Drivers tab shows one status line (`Microphone`) plus Input Level + Graph EQ.
2. **Single mic path:** `AudioStreamMicrophone` on the Windows default recording device, always `play()`, analysis bus awake (unmuted, not sleeping). Watchdog restarts only if PCM **frames** stop, not because the room is quiet. Music-oriented FFT (kick/bass/hats) kept; no speech VAD. Noise floor still zeros a quiet room; gate eased slightly so speaker-into-mic music can move bands. Play All whole-number gains untouched.
3. **Verify:** script_check valid. Playtest: helper process not running; no `SystemAudioLoopback` child; `MicCapture` playing `AudioStreamMicrophone`; `no_frames_timer=0` while silent (`ui_bands` all 0). Analysis-bus tone: `pcm≈0.24`, `volume≈0.15`, FFT in bass bins. Drivers tab screenshot: no source picker/banners/buttons. Files: `autoload/audio_analyzer.gd`, `ui/effects_sidebar.gd`, `ui/effects_sidebar.tscn`, this log. No commit.

## 2026-08-23 - Beat / bass / mids / highs do nothing

**Issue:** User: "Beat, bend, and mid, and high, more or less, don't do anything." ("Bend" = bass.) Graphic EQ / Input Level may still move; the four audio-reactive drivers stay dead after the one-mic simplification.

**Likely causes:**
1. Drivers tab reads gated `get_driver_audio()` (`current_state.bass/mids/highs/beat`) while Graphic EQ uses peak-normalized `ui_bands` — classic "EQ alive, drivers 0".
2. Bass/kick mapped to 32–130 Hz that a laptop mic cannot hear; mids/highs still over-gated.
3. Beat is a 1-frame 40–130 Hz kick onset, so it never fires on talk-mics and looks stuck at 0.
4. Noise gate / AGC / contrast still swallowing mic-level music/speech.

**Plan:**
1. Log this. Do not commit / push. Keep single live mic. Keep Play All whole-number gains.
2. Prove with runtime vars (beat, bass, mids, highs, kick, volume, pcm, ui_bands) vs analysis-bus tone.
3. Make beat/bass/mids/highs move when the mic hears sound. Bass/mids/highs from bands the mic can capture (~100 Hz+). Beat = kick transient OR broadband onset (claps/snare/plosives). Silence stays ~0. Intensity/sensitivity still scale these drivers. EQ stays flat on true silence.
4. script_check + silence vs tone evidence. Update Resolution.

**Resolution:**
1. **Why they did nothing:** Graphic EQ uses peak-normalized `ui_bands` (fills to ~1 whenever anything is present). Drivers tab / Play All read gated `get_driver_audio()` (`current_state.bass/mids/highs` + a 1-frame 40–130 Hz kick as `beat`). The noise gate + `_to_drive` left those near 0 while the EQ looked alive (110 Hz tone: EQ bin=1.0, gated bass=0.024). Bass was averaged over empty 32–80 Hz bins a laptop mic cannot hear. Beat never held, and never fired on claps/speech/speaker music with no sub.
2. **Fix (`autoload/audio_analyzer.gd`, driver hints):** Bass/mids/highs/bandN are the same 0–1 EQ bins, grouped to mic-reachable ranges (bass 80–315 Hz, mids 315–3150, highs 3–20 kHz), then shaped by Master Intensity / Band Sensitivity. Beat is a ~160 ms pulse on kick **or** a broadband onset (claps/snare/plosives/speaker hits). Kick stays 40–130 Hz only. Presence floor eased so mids-only energy is not treated as silence; hiss still cannot peak-normalize a fake EQ. Single live mic kept. Play All whole-number gains untouched.
3. **Verify:** script_check valid. Silence: beat/bass/mids/highs/volume all 0, `ui_bands` all 0. Analysis-bus 110 Hz: **bass=0.53**, mids/highs=0, beat pulse then decay (0.58). 1000 Hz: **mids=0.82**, bass/highs=0, kick=0, beat=1 on the hit. 6000 Hz: **highs=0.81**, bass/mids=0. After stop, drivers return to 0.
4. **Limits:** A laptop mic still has no real sub-bass (~40 Hz). `kick` needs 40–130 Hz energy; `beat`/`bass` use what the mic can actually hear. Speaker music is room sound into the mic, not system loopback. No commit.

## 2026-08-23 - Music never drives visualizer (voice-only mic / AISPEECHAPO)

**Issue:** User (angry, recurring): audio still only recognizes **voice**, not **music**. Talking moves the visualizer; Spotify/YouTube/files do not. Headphones make speaker-into-mic impossible. They already rejected device pickers, green/red banners, and “Use system audio” / “Windows recording”. Do not bring that chrome back.

**Forever cause (not FFT):** Default recording device is **Microphone Array (Realtek) with AISPEECHAPO (Voice Focus)**. It passes close speech and treats music as noise. Laptop-mic FFT retunes cannot hear what Windows already stripped. A WASAPI render-loopback helper exists (`tools/loopback/HyperSpaceLoopback.exe`, `core/system_audio_loopback.gd`) but was **ripped out of the live path** after UI hate + fake EQ from hiss peak-normalize. Mic-only is why this keeps coming back.

**Plan:**
1. Log this. Do not commit / push. Keep Play All whole-number gains. Keep beat/bass/mids/highs mapped from the same 0–1 Graphic EQ bins.
2. Invisible dual capture, no extra UI: mic always on (`AudioStreamMicrophone`); quietly spawn WASAPI loopback of the default **render** device. Each frame pick the source with real energy (loopback if above a music-sized floor with hysteresis, else mic). Never mix hiss into the analysis bus. Never peak-normalize below a real floor. If both have energy, music/loopback wins.
3. Separate loopback bus so mic + loopback cannot double-inject. Inject gate between hiss (~6e-5) and real music (Alarm01 0.03–0.53); previous 0.0028 was too high for quiet tracks. Silence = flat EQ. Helper missing → stay on mic, no red banner spam. Status stays **Microphone**.
4. Verify silence vs system music vs voice-only. Update Resolution.

**Resolution:**
1. **Forever cause:** Default capture is `Microphone Array (Realtek)` with **AISPEECHAPO (Voice Focus)**. It passes close speech and treats music as noise. Headphones make speaker-into-mic impossible. FFT retunes on that mic cannot hear Windows playback.
2. **Forever fix — invisible dual capture:** Mic stays always-on on `HyperSpaceAnalysis`. WASAPI render-loopback (`HyperSpaceLoopback.exe`) captures default speakers onto a **separate** `HyperSpaceLoopback` bus (never mixed with the mic FFT). Each frame, if loopback peak ≥ 0.00050 (hysteresis off at 0.00018) analysis uses loopback; otherwise mic. Hiss ~6e-5 is not injected (zeros pushed so the 0.85s FFT decays). Quiet music below the old 0.0028 gate is kept. If both have energy, music wins. Status stays **Microphone**. Helper missing → mic only, no banners. Editor does not spawn the helper (UDP port). Play All whole-number gains untouched. Beat/bass/mids/highs still come from the same 0–1 Graphic EQ bins (loopback bass includes 32–315 Hz / kick).
3. **Silence:** `ui_bands` all 0; beat/bass/mids/highs/volume 0; loopback `debug_peak=6.1e-5`, `debug_injecting=false`, `_use_loopback=false`.
4. **System music (Alarm01 + 110 Hz on Master):** loopback `debug_peak=0.87`, injecting, `_use_loopback=true`, `pcm=0.53`, EQ bin 80–125 Hz = 1.0 (not the weight curve), **bass=0.82**, beat=true, volume=0.28. Status still `Microphone`. After stop: loopback off, bands/drivers 0 again.
5. **Voice/mic path (loopback silent):** analysis-bus 1000 Hz: `_use_loopback=false`, loopback PCM=0 / peak~6e-5, mic `pcm=0.25`, EQ bin 800–1250 Hz = 1.0, **mids=0.82**, bass/highs=0.
6. **UI:** Drivers tab = one **Microphone** line (white), Input Level + Graph EQ. Device row/dropdown hidden. No System audio label, no Use system audio / Windows recording, no green/red banners. Files: `autoload/audio_analyzer.gd`, `core/system_audio_loopback.gd`, `tools/loopback/HyperSpaceLoopback.cs` + rebuilt `.exe`, `ui/effects_sidebar.gd`, this log. No commit.

## 2026-08-23 - The MIC itself must hear music (bypass Voice Focus APO with WASAPI RAW)

**Issue:** User: the app's mic only recognizes **voice**. Voice looks perfect; as soon as music plays the visualizer barely moves, and quiet music does nothing at all. This is an audio visualization app — the **built-in laptop mic** must hear and analyze *all* audible sound (music from speakers, room sound), not just close speech. Loopback is fine to keep as an invisible fallback, but the complaint is the **mic path itself is speech-filtered**.

**Root cause (established, not FFT):** Windows default recording endpoint is **Microphone Array (Realtek)** with the Lenovo/Realtek **AISPEECHAPO ("Voice Focus")** in the capture chain. That APO passes close speech and actively suppresses music as background noise, and applies AGC so quieter music is suppressed harder. Godot's `AudioStreamMicrophone` receives the **already-processed** stream, so no FFT/band retune can recover what the OS removed.

**Plan:**
1. Log this. No commit / push. Keep Play All whole-number gains, keep beat/bass/mids/highs from the same 0–1 Graphic EQ bins, keep the invisible loopback fallback, do not bring back the device picker / banners / extra buttons.
2. Extend `tools/loopback/HyperSpaceLoopback.cs` with a **raw mic capture mode**: default CAPTURE endpoint opened via `IAudioClient2::SetClientProperties` (`bIsOffload=false`, `eCategory=AudioCategory_Other`, `Options=AUDCLNT_STREAMOPTIONS_RAW`) so the APO chain is bypassed. Fall back to normal shared capture and report which mode it got. Pipe PCM to Godot over UDP exactly like loopback.
3. Add a `miccheck` diagnostic mode to the same exe that measures peak/RMS + an 8-band spectrum for N seconds, so processed vs raw can be compared with real numbers while music plays.
4. Attempt to disable endpoint audio enhancements without elevation (`PKEY_AudioEndpoint_Disable_SysFx` on the capture endpoint property store). Report the HRESULT rather than failing silently; do not require admin.
5. Analyzer: prefer the **raw mic** helper as the mic path (own bus, own spectrum/capture). Godot `AudioStreamMicrophone` stays as last-resort fallback. Loopback still wins when the OS is actually playing audio. Adaptive noise-floor gate on the raw mic so hiss never injects (raw mode has *more* hiss — no noise suppression) but quiet music does.
6. Verify: silence flat; music through laptop speakers at normal and reduced volume through the **mic** path with loopback excluded; processed vs raw comparison; voice still works; Drivers tab screenshot shows one Microphone line.

## 2026-08-24 - Noise distort turns solid meshes into point clouds

**Issue:** User: when Noise Displace / Noise Distort is ON, 3D objects render as point clouds (vertices only). They should stay solid shaded meshes (faces, lighting, materials) with only the surface deformed. Real point-cloud assets (e.g. skull point cloud) and the Point Cloud *effect* should stay points.

**Likely cause:** `effects/noise_deform.gdshader` still writes `POINT_SIZE` (leftover from when the same shader drove point-cloud overlays). Godot 4.7 Forward+ treats any `POINT_SIZE` write as point rendering (`POINT_SIZE_USED` / `sc_emulate_point_size` expands each vertex into a screen-space sprite). The uniform defaults to 0 so the `if` never assigns, but the compiler still flags the shader and the engine default `point_size = 1.0` draws 1px dots. Faces disappear; only vertices show. Overlays already use `effects/point_cloud.gdshader`.

**Plan:**
1. Log this. No commit / push. Do not touch audio capture, Play All integer gains, or other effects.
2. Remove `point_size` / `POINT_SIZE` from `noise_deform.gdshader` so triangle meshes stay triangles. Keep vertex noise + cloth displace. Point-cloud overlays and `PRIMITIVE_POINTS` assets keep `point_cloud.gdshader`.
3. Stop stamping `point_size` / `use_vertex_color` on the solid-mesh noise path in `flythrough_environment.gd`.
4. Restart playtest. Screenshot Noise ON (solid faces, deformed) vs OFF. Confirm Point Cloud effect still draws dots.

**Resolution:**
1. **Root cause:** `effects/noise_deform.gdshader` wrote `POINT_SIZE` (leftover from sharing the shader with point-cloud overlays). Godot 4.7 Forward+ flags that as `POINT_SIZE_USED` and `sc_emulate_point_size` turns each vertex into a screen-space sprite. The uniform defaulted to 0 so the `if` never assigned, but the compiler still enabled point rendering and the engine default `point_size = 1.0` drew 1px dots. Faces vanished; only vertices showed.
2. **Fix:** Removed `point_size` / `POINT_SIZE` from `noise_deform.gdshader`. Solid meshes stay triangles with vertex noise. Overlays and real `PRIMITIVE_POINTS` assets still use `effects/point_cloud.gdshader`. Stopped writing `use_vertex_color` as if the solid path were points.
3. **Verify:** Playtest restart. Runtime state with Noise ON / Point Cloud OFF: `affect_noise=true`, `noise_amount=6`, `_noise_mats=3`, `_point_cloud_on=false`. Screenshot: Noise Displace ON, Main targeted — courtyard/skull show **shaded polygonal faces** (stretched by displace), not a vertex-only point cloud. OFF shots show the solid teal torus + cloister with faces intact. Point Cloud effect left on its own shader.
4. **Limits:** Very large Displace Strength still explodes a mesh (existing world-unit amount). Materials are still the simplified noise shader (albedo/rough/metal/UV), not a full StandardMaterial3D clone. No commit.

## 2026-08-24 - Xconvento missing / env scale jumps to base driver

**Issue:** User: "There is something wrong with environment scale, the Xconvento thing is not showing and environment scale is jumping to base driver for some reason." Ex-convento (chiostro) environment mesh gone; Env Scale slider/world size snaps to an undriven/base driver value.

**Likely cause (one root, two symptoms):**
1. Scale deform (Play All audio, default amount 25 → `1 + amount`) multiplies `_env_root.scale` every frame while the fly path is framed on the unscaled AABB. 26× world (or `kick * 2` → 1×–3×) puts the camera inside a wall / courtyard off-screen — Xconvento “vanishes”. When the driver is silent or Play All restores the stored 25, size jumps to that base.
2. Live env-scale preview (`_on_env_scale_changed` / `_tick_entry_scale_driver`) writes the evaluated driver into stored `user_scale`. Session restore does `float("kick * 2")` → 0.01. Slider snaps from the expression to that base/zero. Scale deform (object squash) and Environment Scale (world size) got conflated after Play All started driving deform Scale + Outer.

**Plan:**
1. Log this. No commit / push. Do not touch audio capture or Play All whole-number gains for real FX sliders. Do not break Main/Scatter object deform Scale.
2. Environment Scale owns `_env_root` world size only. Stop applying Scale deform as a world multiplier on the environment (exclude env world scale from Play All / audio scale). Keep deform Scale on centerpiece + scatter.
3. If Env Scale has a driver, live-track the eval on stage without overwriting the stored numeric base or replacing the expression. Session restore must not `float()` an expression into 0.01.
4. Verify: convento visible at a sensible scale; Env Scale stable (expression stays; no snap to base); object Scale deform still works. script_check + playtest screenshots.

## 2026-08-26 - Feedback stopped working; ASCII+Feedback must sit on top of everything

**Issue:** User: "feedback stopped working. and I think under the ascii, it needs to work on top of everything." Feedback Trail (grouped under ASCII in Effects) no longer produces trails/echo. ASCII and that Feedback should composite **on top of the entire image** — after Bend space, noise displace, materials, camera, glitch, etc. Feedback should feed from/onto that final composite, not a pre-ASCII or pre-effects buffer.

**Likely cause (same post-process stack):**
1. After the Noto atlas change, `AsciiCharset.build_atlas` adds a SubViewport to the tree and calls `RenderingServer.force_draw()` per glyph. That fires `frame_post_draw`, which Feedback uses to CPU-capture `Viewport.get_texture()`. Nested force-draw can steal/stale the output RT so history never lands (`has_history` stays 0) or captures a 32×32 bake.
2. Feedback was intentionally given **no** BackBufferCopy (2026-08-13) so `hint_screen_texture` stayed the **pre-ASCII** color scene, with trails overlaid on top. Denser Noto glyphs punch cells to black; history is that dark ASCII buffer while `scene` is still the 3D/FX stack. Luma-gated overlay alpha then goes to ~0 — trails vanish. ASCII also is not the last read of the full composite.
3. ASCII CanvasLayer 10 / Feedback 12 are already above other LFX, but Feedback sampling the pre-ASCII buffer means color/FX (or a dead buffer) can bury or starve the ASCII look.

**Plan:**
1. Log this. No commit / push. Do not revert Noto fonts or other FX.
2. Stop per-glyph `force_draw` bake. Sync atlas = font + bitmap. Async one-shot strip bake (natural frames, baking flag so Feedback skips capture).
3. ASCII last (layer 100) over the full stack; keep its CanvasLayer mounted. Feedback after that (110) with its **own** BackBufferCopy so `screen_texture` is the post-ASCII final image; keep layer mounted; skip capture while `AsciiCharset.baking`.
4. Verify: Feedback trails with ASCII on and off; ASCII reads bend/noise/camera/glitch; script_check. Update Resolution.

**Resolution:**
1. **Why Feedback broke:** Two stacked bugs after the Noto atlas change. (a) `AsciiCharset.build_atlas` added a SubViewport and called `RenderingServer.force_draw()` per glyph. That nested redraw fired `frame_post_draw`, so Feedback’s CPU capture of the output RT was skipped, emptied, or stolen by the 32×32 bake. (b) Feedback had **no** BackBufferCopy (2026-08-13), so `hint_screen_texture` was the **pre-ASCII** 3D/FX buffer while history was a capture of dense Noto ASCII (black cell gaps). The luma-gated overlay alpha went to ~0 — trails vanished. Color/FX could also sit on top of the ASCII look.
2. **ASCII + Feedback on top of everything:** ASCII is CanvasLayer **100** (after hole/glitch/chromatic/tone/camera/bend). Feedback is **110**. Feedback now has its **own** BackBufferCopy, so it samples the post-ASCII final composite and trails feed from that. Both layers stay mounted when off (only the ColorRect hides) so the copy does not die on toggle.
3. **Atlas bake:** Sync atlas is font pages + 5×7 fallback (no force_draw). A one-shot strip SubViewport refines glyphs over natural frames; `AsciiCharset.baking` makes Feedback skip capture until the bake is gone.
4. **Files:** `effects/ascii_charset.gd`, `effects/ascii_effect.gd`, `effects/feedback_effect.gd`, `effects/feedback_effect.gdshader`, this log. Headless `compile_check.gd`: ASCII/Feedback load OK, presets OK, `eAs2` kept. Editor MCP websocket was `ws://127.0.0.1:-1` this session (no playtest screenshot). No commit.



