# 13K Control

**Unofficial · not DASUNG.** Independent hobby software. Not affiliated with, endorsed by, or supported by DASUNG / 大上科技.

A macOS menu-bar **controller for** the [Paperlike 13K](https://shop.dasung.com/) e-ink monitor (3200×2400 @ 37 Hz). “Paperlike” and “DASUNG” are their marks; this project only uses those names to say which hardware it talks to.

[中文说明](#中文)

## Why this exists

The vendor’s Mac client often shows “disconnected” even when the panel is already an extra display. The 13K is controlled over a CH340 serial port (`1a86:7523`), not over HDMI. This app:

- Matches the CH340 by USB VID/PID (not a guessed `cu.usbserial*` name)
- Sends the `0x20 0x01` keepalive the panel needs
- Re-opens the port if USB drops (including through a Thunderbolt dock)
- Covers the serial commands the Windows/Mac V2.0 clients send to the MCU

## Features

| Control | Notes |
| --- | --- |
| Display mode | Web / Text / Image / Active / Heavy (M1–M5) |
| Contrast / speed | 1–9 (`Fast++++` … clear) |
| Front light | Off / Warm / Cold |
| Brightness | 0–64 |
| Color temperature | 0–100 (warm → cold) |
| Ghost cleanup | Manual + optional auto-clear (≥ 30 s) |
| GPU dithering | IOMobileFramebuffer `enableDither` (Stillcolor-style) |
| Text enhancement | Disables font smoothing |
| 13K wallpaper | Black / white / leave default (only the 13K screen) |
| Global shortcuts | Carbon hotkeys; default **⌃⌥R** refresh; no Accessibility prompt |
| Open at login | `SMAppService` |
| CLI socket | Compatible with `paperlike --refresh` / `--query` |

## Install

**Prebuilt:** download `PaperlikeControl.app.zip` from [Releases](https://github.com/mw56/13k-eink-control/releases), unzip, move the app to `/Applications`. First launch: right-click → Open (ad-hoc signed, not notarized).

**From source** (Apple silicon, macOS 13+):

```bash
./build.sh
```

Copy `build/PaperlikeControl.app` to `/Applications`. Look for the display icon in the menu bar. The window title is **13K Control**.

Do not run the vendor `PaperLikeClient` or `paperlike --daemon` at the same time. The serial port is exclusive.

### CLI

If you already have plateaukao's `paperlike` script, leave it on `PATH`. While this app is running it owns `$TMPDIR/paperlike.sock`, so:

```bash
paperlike --refresh
paperlike --query
```

are forwarded instead of stealing the port.

## Hardware

- 13K panel (2025), MCU protocol `0x31`
- USB-C or Mini-HDMI for video **and** a USB data path for control
- CH340 serial: `1a86:7523`, 115200 8N1, DTR/RTS off
- Packet: `5FF5` + cmd + opt + 12 hex zeros + `A0FA` (uppercase)

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

Upstream community tools that documented the serial protocol did not ship a license. This tree does not copy their files. DASUNG, Paperlike, and related names are their trademarks and are used here only to identify compatible hardware.

## 中文

**非官方 · 與大上科技無關。** 這是獨立的業餘專案，不是大上產品，也沒有獲得大上授權或背書。名稱裡的 Paperlike / DASUNG 只用來說明「這是寫給哪一台螢幕用的控制器」。

編譯好的 App 在 [Releases](https://github.com/mw56/13k-eink-control/releases) 下載 `PaperlikeControl.app.zip`，解壓後拖進「應用程式」。第一次請右鍵「打開」。

畫面走 HDMI／USB-C；**刷新、模式、前光**走 CH340 串口。官方 Mac 客戶端常在串口還沒好時就放棄。這個 App 用 VID:PID 找埠、定期 `0x20 0x01`、斷線會重連。

功能對齊 Windows／Mac V2.0 客戶端實際會送到 MCU 的部分：M1–M5 模式、對比 1–9、前光、亮度、色溫 0–100、手動／自動清殘影、GPU 抖動、文字增強、13K 桌布、全域快捷鍵（預設 ⌃⌥R 清屏）、開機啟動。

協定與 CLI socket 形狀參考了 [paperlike13k_linux](https://github.com/roflecopter/paperlike13k_linux) 與 [paperlike13k_macos](https://github.com/plateaukao/paperlike13k_macos)，但這是獨立專案，沒有複製他們的原始碼。詳見 [NOTICE](NOTICE)。

不要跟官方客戶端或 `paperlike --daemon` 同時開。
