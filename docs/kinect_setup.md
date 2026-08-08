# Kinect v2 OSC Setup for HyperSpace

HyperSpace receives skeleton data over **OSC**. The Kinect sensor itself must run on **Windows** with the Kinect SDK 2.0; the main HyperSpace app can run on Windows or macOS.

## Requirements (Windows bridge machine)

- Windows 8.1 or later
- USB 3.0 port
- Kinect for Xbox One / Kinect v2 sensor
- [Kinect for Windows SDK 2.0](https://www.microsoft.com/en-us/download/details.aspx?id=44561)

## Option A: KinectV2-OSC (recommended — simplest)

1. Download [KinectV2-OSC release](https://github.com/microcosm/KinectV2-OSC/releases)
2. Run `KinectV2-OSC.exe` on the Windows machine with the Kinect connected
3. By default it sends to `127.0.0.1:12345` — matches HyperSpace's default `OSCBus.listen_port`
4. For a Mac on the same LAN, create `ip.txt` next to the executable with the Mac's IP address

### OSC addresses (parsed by HyperSpace)

```
/bodies/{bodyId}/joints/{jointId}  → float x, y, z, string trackingState
/bodies/{bodyId}/hands/{handId}    → string handState, string confidence
```

## Option B: OSCeleton-KinectSDK2

1. Build or download [OSCeleton-KinectSDK2](https://github.com/Zillode/OSCeleton-KinectSDK2)
2. Default port: **7110** — change HyperSpace port in `autoload/osc_bus.gd` or project settings
3. Sends `/osceleton2/joint` messages (also supported by HyperSpace)

## Option C: kinect2share (skeleton + video)

Use [kinect2share](https://github.com/rwebber/kinect2share) if you also need depth/RGB via Spout or NDI.

## HyperSpace configuration

Default OSC listen port: **12345** (`autoload/osc_bus.gd`, `@export var listen_port`).

Kinect data flows:

```
Kinect v2 → Windows bridge app → OSC (UDP) → OSCBus → KinectManager → ShowDirector / 3D environments
```

## Testing without Kinect

Send test OSC messages with [oscsend](https://github.com/networktransport/oscsend) or any OSC tool:

```bash
oscsend localhost 12345 /bodies/0/joints/HandRight ffss 0.5 1.2 2.0 Tracked
```

## macOS + Windows two-machine setup

```
[Windows PC + Kinect]  --OSC over LAN-->  [Mac running HyperSpace]
         KinectV2-OSC                         listen_port 12345
         ip.txt → Mac IP
```

Ensure firewall allows UDP on the chosen port.
