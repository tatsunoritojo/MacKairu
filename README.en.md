<div align="center">

<img src="docs/images/dolphin.svg" width="76" alt="dolphin">&nbsp;&nbsp;<img src="docs/images/cat.svg" width="76" alt="cat">&nbsp;&nbsp;<img src="docs/images/penguin.svg" width="76" alt="penguin">&nbsp;&nbsp;<img src="docs/images/chick.svg" width="76" alt="chick">

# MacKairu

**Desktop Mascot Assistant**

A slightly clever, slightly annoying mascot that lives in the corner of your Mac.

[日本語](README.md) ・ `English` ・ [`secret`](docs/secret.en.md)

<br>

![Swift](https://img.shields.io/badge/Swift-6.3-orange?logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![SwiftPM](https://img.shields.io/badge/SwiftPM-native-blue)
![Tests](https://img.shields.io/badge/tests-57%20passing-brightgreen)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

</div>

---

## Overview

**MacKairu** is a native macOS desktop mascot that lives in the corner of your screen.
Transparent, always-on-top, no Dock icon — click it and it becomes a concierge that **answers your "how do I do X on a Mac?" questions** anytime.

Great for Windows switchers. Ask "how do I screenshot?" or "how do I switch apps?" and it answers while looking at your screen.
It also swims around your screen whenever it feels like it.

<div align="center">
<img src="docs/images/chat.svg" width="300" alt="Chat">
</div>

## Characters

Pick your buddy from the menu bar → "キャラクター", or in Settings.

| | Character | Personality |
|:--:|---|---|
| 🐬 | **Dolphin** | The original. Heir to *that* Windows assistant |
| 🐱 | **Cat** | Capricious. Wanders off constantly |
| 🐧 | **Penguin** | Calm and dependable |
| 🐤 | **Chick** | Tiny and light. Cheep cheep |

## Features

| | Feature | Description |
|:--:|---|---|
| 💬 | **Ask the AI** | Switch between Claude / OpenAI / Gemini. Just paste a key in Settings |
| 📋 | **Capture & ask** | Hand it your clipboard or a **screenshot** — "translate this", "how do I use this screen?" (Vision) |
| 🎛 | **Fully tweakable** | Drag to move, pinch to scale (up to 10×), switch characters |
| 🌊 | **Has a mind of its own** | Left alone, it swims across your screen and occasionally chats |
| 🔒 | **Safe key storage** | `~/.config/mac-concierge/credentials.json` (chmod 600). No plaintext anywhere else |

> Want peace and quiet? Turn off "おせっかいモード" (annoyance mode) in Settings.

## Install

Native SwiftPM project. No extra runtime.

```sh
git clone https://github.com/tatsunoritojo/MacKairu.git
cd MacKairu
swift test        # 57 tests
./build.sh        # builds Kairu.app
open Kairu.app    # it moves in
```

Then: menu-bar emoji → "設定…" → paste your API key. Done.

## Architecture

Testable logic and UI are kept separate.

```
Sources/
  KairuCore/   pure logic (config, providers, characters) + 57 tests
  Kairu/       UI (floating panel, vector drawing, state)
Resources/     character image assets
```

- Native SwiftUI / AppKit (no Electron, lightweight)
- Animal characters are **drawn in code as vectors** — no raster assets, crisp at any size

---

<div align="center">

> They say that if you whisper a certain word, another resident appears.
> Its door hides among the unfamiliar "languages" in the nav above.

</div>

## License

MIT License © tatsunoritojo

<div align="center">
<sub>You can run, but you can't delete.</sub>
</div>
