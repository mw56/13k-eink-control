# 13K Control

**Unofficial · not DASUNG.** Independent third-party software, written from scratch in Swift. Not affiliated with, endorsed by, or supported by DASUNG / 大上科技.

A macOS menu-bar **controller for** the [Paperlike 13K](https://shop.dasung.com/) e-ink monitor (3200×2400 @ 37 Hz). “Paperlike” and “DASUNG” are their marks; this project only uses those names to say which hardware it talks to.

[中文](#中文)

## Versions

Both builds live in the same repository. Pick a [Release](https://github.com/mw56/13k-eink-control/releases); **v1.0.1 stays available** after newer tags.

| | [v1.0.1](https://github.com/mw56/13k-eink-control/releases/tag/v1.0.1) | [v1.2.4](https://github.com/mw56/13k-eink-control/releases/tag/v1.2.4) (current) |
| --- | --- | --- |
| Panel control | Yes | Yes (same serial protocol) |
| Display mode M1–M5 | Yes | Yes |
| Contrast, front light, brightness, color temperature | Yes | Yes |
| Ghost cleanup (manual + auto) | Yes | Yes |
| GPU dithering, text enhancement, 13K wallpaper | Yes | Yes |
| Global shortcuts, open at login, local socket | Yes | Yes |
| **13K touch** | No | **Yes** — finger on the panel moves the pointer on the 13K; the real mouse on other displays is left alone |
| Accessibility | Not required | Required for **clicks** (cursor tracking works without it) |
| macOS | 13+, Apple silicon | 13+, Apple silicon |

**v1.0.1** is the first public controller: USB-serial only. Use it if you do not want touch, or if you do not want to grant Accessibility.

**v1.2.4** adds touch on top of v1.0.1. Settings → Touch can turn that mapping off; the rest of the app behaves like v1.0.1.

Ad-hoc signature changes between releases. After installing a new zip, grant **13K Control** again under System Settings → Privacy & Security → Accessibility, then Restart from the menu.

## Why this exists

The vendor Mac client often shows “disconnected” even when the panel is already an extra display. Video goes over HDMI or USB-C; **refresh, mode, and front light** go over a CH340 USB serial port (`1a86:7523`). This app talks to that port directly:

- Finds the adapter by USB VID/PID
- Sends the keepalive the panel needs (`0x20 0x01`)
- Re-opens the port if USB drops (including through a Thunderbolt dock)
- Implements the same MCU commands the vendor V2.0 clients send, in native Swift

It does not bundle, patch, or redistribute the vendor client.

macOS also loads the panel’s USB digitizer (`USB2IIC_CTP_CONTROL`, `1a86:e5e3`) but does not bind those coordinates to the 13K framebuffer. That is the vendor line “Mac cannot do touch”: missing association, not missing hardware. v1.2.4 polls the digitizer and injects pointer events onto the screen named **13K**.

## Features (v1.2.4)

| Control | Notes |
| --- | --- |
| Display mode | Web / Text / Image / Active / Heavy (M1–M5) |
| Contrast / speed | 1–9 (`Fast++++` … clear) |
| Front light | Off / Warm / Cold |
| Brightness | 0–64 |
| Color temperature | 0–100 (warm → cold) |
| Ghost cleanup | Manual + optional auto-clear (≥ 30 s) |
| GPU dithering | IOMobileFramebuffer `enableDither` |
| Text enhancement | Disables font smoothing |
| 13K wallpaper | Black / white / leave default (only the 13K screen) |
| Global shortcuts | Carbon hotkeys; default **⌃⌥R** refresh; no Accessibility prompt |
| Open at login | `SMAppService` |
| Local socket | JSON control socket at `$TMPDIR/paperlike.sock` |
| 13K touch | Polls HID tip / X / Y on `1a86:e5e3`, warps the cursor onto the 13K, posts clicks. Does **not** seize the USB pipe. Real mouse on other displays is unchanged. |

## Touch (v1.2.4)

Enable in Settings → Touch. Grant **Accessibility** to 13K Control so taps click, not only move the pointer. If the pointer is mirrored, use Invert X / Invert Y / Swap X/Y.

This is single-finger click and drag in userspace. OS-level multi-touch gestures (pinch as a system gesture) would need a signed DriverKit extension.

## Install

**Prebuilt:** download `PaperlikeControl.app.zip` from [Releases](https://github.com/mw56/13k-eink-control/releases), unzip, move the app to `/Applications`. First launch: right-click → Open (ad-hoc signed, not notarized).

**From source** (Apple silicon, macOS 13+):

```bash
./build.sh
```

Copy `build/PaperlikeControl.app` to `/Applications`. Look for the display icon in the menu bar. The window title is **13K Control**.

Do not run the vendor `PaperLikeClient` at the same time. The serial port is exclusive.

## Hardware

- 13K panel (2025), MCU protocol `0x31`
- USB-C or Mini-HDMI for video **and** a USB data path for control
- CH340 serial: `1a86:7523`, 115200 8N1, DTR/RTS off
- Packet: `5FF5` + cmd + opt + 12 hex zeros + `A0FA` (uppercase)
- Digitizer (v1.2.4): WCH `USB2IIC_CTP_CONTROL`, `1a86:e5e3`, logical 0–4096

If the picture is there but the app says disconnected, the USB data cable is missing or stuck behind too many hubs. Plug USB into the Mac, then Reconnect.

Native panel mode is 3200×2400 @ 37 Hz. Some docks fall back to 2048×1536.

## Build requirements

- Xcode Command Line Tools (`swiftc`)
- Apple silicon (the `build.sh` target is `arm64-apple-macosx13.0`)

```bash
./build.sh /path/to/PaperlikeControl.app
```

## License

[MIT](LICENSE) for the Swift sources in this repository.

DASUNG, Paperlike, and related names are their trademarks and are used here only to identify compatible hardware.

## 中文

**非官方 · 與大上科技無關。** 這是獨立用 Swift 寫成的第三方控制器，不是大上產品，也沒有獲得大上授權或背書。名稱裡的 Paperlike / DASUNG 只用來說明「這是寫給哪一台螢幕用的」。

同一個 GitHub 專案裡並存兩個發行版，舊檔不會因新版而上架後消失：

| | [v1.0.1](https://github.com/mw56/13k-eink-control/releases/tag/v1.0.1) | [v1.2.4](https://github.com/mw56/13k-eink-control/releases/tag/v1.2.4)（目前） |
| --- | --- | --- |
| 串口控制（模式／對比／前光／亮度／色溫／清殘影） | 有 | 有 |
| GPU 抖動、文字增強、13K 桌布、快捷鍵、開機啟動 | 有 | 有 |
| **13K 觸控** | 無 | **有**：手指點在 13K 上，游標與點擊落在 13K；其他螢幕的滑鼠不受影響 |
| 輔助使用 | 不需要 | **點擊**需要（只移動游標可以沒有） |

不想開輔助使用、或不需要觸控，請繼續用 v1.0.1。v1.2.4 可在「設定 → 觸控」把觸控關掉，其餘行為與 v1.0.1 相同。

換版後 ad-hoc 簽名會變，請到「系統設定 → 隱私權與安全性 → 輔助使用」再允許一次 13K Control，並從選單列「重新啟動」。

編譯好的 App 在 [Releases](https://github.com/mw56/13k-eink-control/releases) 下載 `PaperlikeControl.app.zip`，解壓後拖進「應用程式」。第一次請右鍵「打開」。

畫面走 HDMI／USB-C；刷新、模式、前光走 CH340 串口。官方 Mac 客戶端常在串口還沒好時就放棄。這個 App 用 VID:PID 找埠、定期 keepalive、斷線會重連。不附帶、也不改官方客戶端。不要跟官方客戶端同時開。

官方說 Mac 不能觸控，是因為系統沒把 USB 觸控板綁到 13K 的畫面，不是硬體不存在。v1.2.4 輪詢這塊板的 tip／X／Y，把游標與點擊送到名為 13K 的螢幕。
