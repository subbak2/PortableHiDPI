# PortableHiDPI

Sharp HiDPI ("Retina") text on 14–16" portable monitors connected to a Mac. Free, open source, menu bar only.

[한국어 설명은 아래에 있습니다.](#한국어)

## The problem

Plug a 16" 2560×1600 portable monitor into a MacBook and macOS offers two kinds of settings:

- **1280×800 HiDPI** – sharp, but everything is huge.
- **1680×1050, 1920×1200, …** – a comfortable size, but *not* HiDPI. macOS draws 1680×1050 pixels and the monitor stretches them to 2560×1600, so text looks blurry.

What you actually want is "looks like 1680×1050" rendered at 3360×2100 and scaled down to the panel, which is what MacBooks do on their own screens. macOS on Apple Silicon refuses to offer HiDPI modes larger than the panel, and the old display-override plist trick no longer works there.

## How it works

1. Creates a virtual display that supports the HiDPI mode you picked (e.g. 1680×1050 at 2x = 3360×2100), using CoreGraphics' `CGVirtualDisplay`.
2. Switches the real monitor to its full panel resolution.
3. Makes the real monitor mirror the virtual display. The GPU renders at 2x and scales down to the panel, so text is sharp at the size you chose.

Turning it off (or quitting) removes the virtual display and puts the monitor back to its previous mode. Nothing is installed system-wide and no admin password is needed.

## Install

1. Download `PortableHiDPI.zip` from [Releases](../../releases) and move `PortableHiDPI.app` to Applications.
2. The app is not notarized (no paid Apple Developer account), so the first launch is blocked. Open it once with **right-click → Open**, or run:
   ```
   xattr -dr com.apple.quarantine /Applications/PortableHiDPI.app
   ```
3. A display icon appears in the menu bar.

Requires macOS 13 or later. Built and tested on Apple Silicon; the universal build also runs on Intel Macs but is untested there.

## Use

Click the menu bar icon. For each external monitor:

- **Off (macOS default)** – no virtual display.
- **1680×1050 HiDPI (recommended)**, … – pick the size you want. The choice is remembered per monitor and re-applied when you reconnect it.
- **Monitor Size** – set your monitor's diagonal. Many portable monitors report a wrong size (the one tested here claims to be 27"), and the size is used for the *recommended* mark.
- **Refresh Rate** – 60 Hz or 120 Hz on monitors that support it.
- **Launch at Login**

### Recommended settings

The recommendation targets the same text size as a MacBook's built-in screen (about 125 points per inch).

| Panel | 14" | 15.6" | 16" | Common models |
|---|---|---|---|---|
| 1920×1080 | 1504×846 | 1600×900 | 1600×900 | Most 15.6" FHD portables |
| 1920×1200 | 1504×940 | 1600×1000 | 1600×1000 | Lenovo ThinkVision M16 |
| 2240×1400 | 1504×940 | 1680×1050 | 1680×1050 | Lenovo ThinkVision M14d |
| 2560×1600 | 1504×940 | 1680×1050 | 1680×1050 | ZEUSLAP P16K, LG gram +view, ASUS MB16QHG |
| 2880×1800 | 1504×940 | 1680×1050 | 1680×1050 | 16" OLED portables |
| 3840×2160 | macOS default | macOS default | macOS default | macOS already offers 1920×1080 HiDPI |

Models are examples; check your monitor's panel resolution.

### Command line

```
PortableHiDPI.app/Contents/MacOS/PortableHiDPI --list                 # monitors and options
PortableHiDPI.app/Contents/MacOS/PortableHiDPI --inches 16 --apply 1680x1050
PortableHiDPI.app/Contents/MacOS/PortableHiDPI --apply off
```

`--inches` and `--apply` act on the first external monitor and then keep the app running.

## Limitations

- `CGVirtualDisplay` is a **private Apple API**. It has worked since macOS 11 and is used by several display tools, but a macOS update could break it.
- While mirroring, HDR is not available and the monitor runs SDR.
- 120 Hz through a mirrored virtual display can feel choppy on some setups; use 60 Hz if it does.
- Mirroring across sleep is fragile in macOS, so the app removes the virtual display before sleep and recreates it about 3 seconds after wake.
- Rendering at 2x costs some GPU time and memory (a 3360×2100 frame buffer).

## Build from source

```
git clone https://github.com/subbak2/PortableHiDPI.git
cd PortableHiDPI
scripts/build-app.sh      # build/PortableHiDPI.app and build/PortableHiDPI.zip
```

Needs Xcode command line tools (Swift 5.9+). No Xcode project.

## Alternatives

- [BetterDisplay](https://github.com/waydabber/BetterDisplay) – full-featured display manager (free tier + Pro).
- [DeskPad](https://github.com/Stengo/DeskPad) – virtual display shown in a window, handy for screen sharing.

PortableHiDPI does one thing: sharp text on a portable monitor, with nothing else to configure.

## License

MIT

---

## 한국어

맥북에 14~16인치 휴대용 모니터를 연결했을 때 글씨가 흐릿한 문제를 고치는 무료 메뉴바 앱입니다.

**왜 흐릿한가**: 16인치 2560×1600 모니터에서 macOS는 "1280×800 HiDPI"(선명하지만 너무 큼)와 "1680×1050"(크기는 적당하지만 HiDPI가 아님) 중에서만 고르게 합니다. 1680×1050을 고르면 맥은 1680×1050 픽셀로 그리고, 모니터가 그걸 2560×1600으로 늘리면서 글씨가 뭉개집니다. Apple Silicon 맥은 패널보다 큰 HiDPI 모드(3360×2100)를 열어 주지 않고, 예전 plist 방법도 더는 통하지 않습니다.

**어떻게 고치나**: 원하는 HiDPI 모드를 지원하는 가상 모니터를 만들고, 실제 모니터를 패널 해상도로 바꾼 뒤 가상 모니터를 미러링합니다. 맥북 내장 화면과 같은 방식(2배로 그린 뒤 줄여서 출력)이라 글씨가 선명해집니다. 끄거나 앱을 종료하면 원래 해상도로 돌아갑니다. 관리자 암호나 시스템 파일 수정은 필요 없습니다.

**설치**: [Releases](../../releases)에서 `PortableHiDPI.zip`을 받아 응용 프로그램 폴더로 옮긴 뒤, 처음 한 번은 **우클릭 → 열기**로 실행합니다. Apple 개발자 공증을 받지 않은 앱이라 그냥 더블클릭하면 막힙니다. 터미널에서 `xattr -dr com.apple.quarantine /Applications/PortableHiDPI.app`을 실행해도 됩니다.

**사용법**: 메뉴바 모니터 아이콘에서 해상도를 고릅니다. 모니터마다 설정을 기억하고 다시 연결하면 자동으로 적용합니다. 휴대용 모니터는 크기 정보가 틀린 경우가 많으니(테스트한 16인치 모니터는 27인치라고 보고함) **모니터 크기**를 직접 골라 주면 추천 해상도가 정확해집니다. 추천 기준은 맥북 내장 화면과 같은 글씨 크기(약 125pt/인치)이며 위 표와 같습니다.

**한계**: Apple 비공개 API(`CGVirtualDisplay`)를 써서 macOS 업데이트로 안 될 수 있습니다. 미러링 중에는 HDR이 꺼지고, 환경에 따라 120Hz가 끊겨 보일 수 있습니다(그러면 60Hz로). 잠자기 때는 가상 모니터를 껐다가 깨어나고 3초 뒤 다시 켭니다.
