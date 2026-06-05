<div align="center">

<img src="images/banner.png" width="900" alt="POIN — Desktop Mascot Assistant">

# `secret` — POIN

**A clingy, slightly annoying, impossible-to-hate desktop companion who is in love with your cursor.**

[日本語](secret.md) · English · [← back to main](../README.en.md)

</div>

---

## How to summon

Just call her name in the chat box.

```
POIN
```

The dolphin switches to **POIN (the girl)**. Type it again to switch back.
(The old spell `裏モード` still works too.)

## Behavior

- **100% cursor chaser** — she loves your cursor and **dashes** across the screen to reach it.
- **Looks for you when far** — when the cursor is far away she glances around searching for it, then *spots it* and runs over.
- **Head pats** — move the cursor slowly over her head: she notices, leans in happily, and looks wistful when you stop.
- **Pick her up** — grab and drag her: she's startled at first, then happy while being carried. The drawn cursor lines up with your real one.
- **Thinks out loud** — while the AI is writing a reply she puts on a thinking face; when presenting the answer she switches to a teaching pose (with the occasional wink).
- **Gets dizzy** — whirl her around hard while dragging and she'll stagger with spinning eyes.
- **Says hi** — the very first time she appears, she waves hello.

<div align="center">

<!-- For reliable inline playback, use a GitHub user-attachments URL (raw/main is flaky).
     Source file: docs/videos/girl-petting.mp4 -->
<video
  src="https://github.com/user-attachments/assets/bf7d41ab-3aa2-4839-a86e-b0ff11ebf64b"
  poster="images/girl-petting-poster.png"
  controls muted loop playsinline width="380">
</video>

<br>

<sub>If it doesn't play, <a href="videos/girl-petting.mp4">open it here</a>.</sub>

</div>

## States

She reads cursor distance, a head hit-box, dwell time, speed, side-to-side wobble, grab and motion to move between expressions.

| State | Trigger | Look |
|---|---|---|
| **Search** | Cursor is far | Glances around looking for the cursor |
| **Found → Run** | About to move | Spots the cursor (facing its direction), then dashes over |
| **Idle** | Cursor is near | "Hm…?", alert and watching |
| **Notice** | Cursor drifts near her head | "Wait, is it… over there?" |
| **Amae** | Cursor moves on her head | "Ehehe…" leaning in (petting loop) |
| **Afterglow** | Cursor leaves | "…is that all?", reluctant |
| **Hold / Drag** | Grabbed / carried | Startled when grabbed, happy while carried |
| **Dizzy** | Whirled around | Staggers with spinning eyes |

> She ignores fast fly-bys. There's hysteresis so petting doesn't cut out on a brief slip, and a short cooldown so she isn't clingy to a fault.
> If the reactions get noisy, turn off "head-pat reaction" in Settings.
> Grab & drag work even with head-pat reaction off (carrying is a separate system).

### Animations

<table align="center">
  <tr>
    <td align="center"><img src="images/anim/far-wait.gif" width="150"><br><sub>waiting far away</sub></td>
    <td align="center"><img src="images/anim/run.gif" width="150"><br><sub>dashing over</sub></td>
    <td align="center"><img src="images/anim/nade.gif" width="150"><br><sub>head pats</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="images/anim/carry.gif" width="150"><br><sub>carried around</sub></td>
    <td align="center"><img src="images/anim/teaching.gif" width="150"><br><sub>explaining (wink)</sub></td>
    <td align="center"><img src="images/anim/dizzy.gif" width="150"><br><sub>dizzy when whirled</sub></td>
  </tr>
</table>

## And when you delete her

Type "**how to delete you**" (`お前を消す方法`) in the chat, and POIN —
with a sad face — **trembles for about 5 seconds and quietly fades away**.

…but if resurrection mode is on, she comes back 15 minutes later.

## Swapping the artwork

POIN is made of up to a couple dozen transparent PNG frames.
You can replace them with your own art (e.g. ChatGPT / Gemini generated).

Settings → "裏キャラ" → "Import images". Frames are auto-sorted by filename
(`idle` / `search` / `run` / `notice` / `pamper` / `hold` / `drag` / `thinking` /
`teaching` / `greeting` / `confused` / `sad`, and their `2` variants).
Missing states fall back to the closest existing frame, so even just `idle` works.

<div align="center">
<br>
<sub>You can run, you can pet, but you can't delete.</sub>
</div>
