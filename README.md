# HyperSpace

Live AV installation player built with **Godot 4**. Audio-reactive 3D environments, video/image/GIF playlists, stackable effects (ASCII, particles, feedback), performer control UI, and Kinect v2 input via OSC.

## Requirements

- [Godot 4.3+](https://godotengine.org/download)
- Microphone or line-in for audio reactivity
- Optional: Kinect v2 + Windows OSC bridge (see [docs/kinect_setup.md](docs/kinect_setup.md))

## Quick start

1. Open this folder in Godot: **Project → Import → select `project.godot`**
2. Press **F5** to run
3. **Output window** shows visuals (fullscreen on secondary display if available)
4. **Performer Control** window: cues, playlist, effect toggles, intensity sliders

### Keyboard shortcuts (output window)

| Key | Action |
|-----|--------|
| F11 | Toggle fullscreen |
| → | Next playlist item |
| ← | Previous playlist item |
| Space | Next item |

## Project structure

```
HyperSpace/
├── autoload/       # AudioAnalyzer, ShowDirector, OSCBus, KinectManager
├── core/           # Show loader, playlist model, transitions, state resources
├── items/          # scene3d, video, image, composite playlist item nodes
├── effects/        # ASCII, particles, feedback effect layers
├── ui/             # Main output + performer panel
├── shows/          # Show manifests (JSON playlists + cues)
└── docs/           # Kinect OSC setup guide
```

## Creating a show

Each show lives in `shows/<name>/show.json`:

```json
{
  "name": "My Installation",
  "items": [
    { "id": "env", "type": "scene3d", "path": "content/room.glb" },
    { "id": "loop", "type": "video", "path": "content/loop.webm", "loop": true }
  ],
  "cues": [
    { "id": "go", "trigger": "manual", "actions": [{ "op": "play", "item": "env" }] }
  ]
}
```

Drop `.glb`/`.gltf`/`.tscn` files into your show's `content/` folder. For GIFs, convert first:

```powershell
.\tools\import_gif.ps1 -InputGif "shows\my_show\content\anim.gif"
```

## Audio input

By default HyperSpace captures the **microphone** for FFT analysis. For DJ mixer or system audio, route audio to an input device or use a virtual cable (e.g. VB-Audio on Windows).

