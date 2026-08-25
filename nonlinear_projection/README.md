# Nonlinear projection (camera-space vertex warp)

Single-camera nonlinear projection for HyperSpace. Isolated under this folder.
Removable: disable the autoload or set `enabled = false`.

## What it does

The existing 3D world and existing `Camera3D` are unchanged (no second camera, no duplicated world, no physics/transform edits). Vertices are warped in **camera space** before the normal projection:

```
warped_position = nonlinear_projection(camera_position)
```

Near the camera (`distance < transition_start`) the warp is identity. Farther away, points rotate around the camera X axis so forward depth lifts into an elevated / near top-down view.

## Files

| File | Role |
|------|------|
| `nonlinear_projection.gdshaderinc` | Warp function + global uniforms |
| `nonlinear_projection_spatial.gdshader` | Spatial wrapper: albedo + warp |
| `nonlinear_projection_settings.gd` | Resource of tunable parameters |
| `nonlinear_projection.gd` | Autoload: uniforms, material wrap, camera tracking |
| `nonlinear_projection_applier.gd` | Optional Node you can drop near a Camera3D |

## Enable / disable / tune

Turn it on from the **right-hand Effects** panel: **Nonlinear camera**. Nested sliders appear when it is on (strength, near, far, bend). Optional shortcut: **F4**. Default is off so original textures stay.

Autoload singleton: `NonlinearProjection` (Project Settings → Autoload). Inspector fields on that node:

```
NonlinearProjection.enabled = false
NonlinearProjection.debug_visualize = true
NonlinearProjection.distortion_strength = 1.0
NonlinearProjection.transition_start = 4.0   # meters
NonlinearProjection.transition_end = 35.0
NonlinearProjection.max_bend_angle_deg = 90.0
```

Restart play after changing these scripts so materials re-wrap.

Optional: add a `NonlinearProjectionApplier` node next to a Camera3D and edit the same fields in the inspector.

## Defaults

- Enabled: `false` (normal textured view). Turn **Nonlinear camera** on in the right-hand Effects panel.
- Distortion strength: `1.0`
- Transition start: `4 m`
- Transition end: `35 m`
- Max bend angle: `90°` (range 0–120)
- Easing: smoothstep
- Vertical / horizontal scale: `1.0`

## How warp is applied

1. Global shader uniforms (project shader globals + runtime `RenderingServer`).
2. Autoload walks `GeometryInstance3D` in the live 3D SubViewport and wraps `BaseMaterial3D` with a spatial shader that copies **albedo color + albedo texture + UV**, then warps vertices. **Off restores the original materials.**
3. Existing world spatial shaders include the warp so noise deform, point-cloud overlays, media screens, and HTerrain Classic4 still bend.
4. Orthogonal / shadow projections skip the warp (`PROJECTION_MATRIX[3][3]`).

## Limitations

**Tessellation.** This is a vertex warp. Large low-poly meshes (a 2-triangle plane, an 8-corner box) cannot curve — they shear as rigid faces. HTerrain grids and reasonably dense imported GLBs bend smoothly. This project does **not** globally subdivide meshes.

**Hidden geometry.** Spatial projection cannot reveal surfaces the camera never sees (backs of buildings, geometry behind occlusion). It is not ray marching.

**Shadows / lighting.** Shadow maps skip the warp (orthogonal projection). Far-field normals are approximate. The wrap copies albedo (texture + UV). It does not copy normal/ORM/clearcoat/SSS — those stay on the original material when the effect is off.

**Triangle flipping.** High bend can invert winding. The wrap shader uses `cull_disabled` to avoid holes; noise/terrain shaders keep their original cull mode.

**Frustum culling.** Vertices move outside the original AABB. The autoload raises `extra_cull_margin` (default 80 m) on affected instances.

**Near plane.** Warped Z is clamped in front of the camera. Geometry behind the camera is left unchanged.

**HTerrain LOD.** Distant chunks are already coarse; the warp follows that LOD.

**Sky / HDRI.** Background sky is not mesh geometry, so it does not bend.

## Architecture note (distance_along_road)

`np_source_distance()` in the include currently returns `max(-cam_pos.z, 0)`. Replace that one function later with a road-distance source. Do not import road/path types into this folder.
