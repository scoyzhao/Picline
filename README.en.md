<p align="center">
  <img src="Sources/Tendedero/Resources/Artwork/Picline-AppIcon.png" width="128" alt="Picline">
</p>

<h1 align="center">Picline</h1>

> **macOS fork note:** This is [scoyzhao/Picline](https://github.com/scoyzhao/Picline), based on [Xinguangcuican/Picline](https://github.com/Xinguangcuican/Picline). It adds Copy All Images, an optional nine-item limit, non-destructive capacity handling, and compact feedback. See the [Chinese README](README.md#本分支更新) for usage, screenshots, build instructions, and verification limits. The upstream release downloads below do not include these custom changes. Windows is unchanged.

<p align="center">
Take five screenshots in a row and the clipboard keeps only the last one. Picline hangs them on a line at the top of the screen, so you pick the one you want.<br>
A photo line in the macOS menu bar, with a sibling build for Windows.<br>
Works on every Space · pick several out and drag them together · 11 interface languages
</p>

<p align="center">
macOS 14+ · Windows 10 / 11 · free and open source
</p>

<p align="center">
<a href="https://github.com/Xinguangcuican/Picline/releases/latest"><b>↓ Download</b></a> ·
<a href="README.md">中文</a>
</p>

<p align="center">
  <img src="docs/demo/picline-demo.gif" width="880" alt="The pointer reaches the top of the screen, the line comes down, new screenshots hang on it one by one">
</p>

---

## What this is

Picline is a fork of [Tendedero](https://github.com/alejandrobujan/tendedero) by Alejandro Buján. The Picline branch (by 老张) strengthened how pictures are taken in: it reads third-party screenshot tools off the clipboard, merges duplicates across sources, and lets you choose which app opens a picture. This repository fixed the multi-Space bug and added AirDrop, press-and-hold Quick Look, a Finder entry, and picking several photos out to use them together.

Two platforms, the same set of gestures:

| | macOS | Windows |
| --- | --- | --- |
| Lives in | Menu bar icon + a line at the top of the screen | Tray icon + a line at the top of the screen |
| Installs as | `Picline-0.2.7.dmg`, dragged into Applications | A single exe, no installer |
| Add to selection | `Command` | `Ctrl` |
| Interface languages | 11, switchable | Chinese |

---

## Downloads

Everything is on the [Releases](https://github.com/Xinguangcuican/Picline/releases/latest) page.

| Platform | File | Notes |
| --- | --- | --- |
| macOS | `Picline-0.2.9.dmg` | Universal binary: Apple silicon and Intel in one package |
| macOS | `Picline-0.2.9.zip` | Same, for people who prefer a zip |
| Windows x64 | `Picline-0.1.1-win-x64.exe` | Nearly every 64-bit Windows |
| Windows ARM64 | `Picline-0.1.1-win-arm64.exe` | Snapdragon laptops and other ARM machines |
| Windows | `Picline-0.1.1-win.zip` | Both exes and the readme |

Neither build is code signed. On macOS, allow it once in Privacy & Security. On Windows, SmartScreen asks for "More info → Run anyway".

---

# macOS

## Install

1. Open `Picline-0.2.9.dmg` and drag `Picline` into Applications.
2. The first launch is blocked by Gatekeeper (no notarisation). Either allow it in System Settings → Privacy & Security, or run:
   `xattr -dr com.apple.quarantine /Applications/Picline.app`
3. The menu bar icon appears. Tick "Hang copied images" in the menu to start collecting.

## Bringing the line down

| Gesture | What happens | Since |
| --- | --- | --- |
| Pointer touches the menu bar | The line comes down at once, with a 0.06 s buffer so a pointer merely passing through does not pull it out | 0.1.x; instant as of 0.2.6 |
| Hold a key, then touch the menu bar | Bring the line down → "Only with a key held", choose `⌘` / `⌥` / `⌃` / `⇧`. Without the key nothing happens | **0.2.7** |
| An empty line stays away | With nothing hanging, touching the top does nothing, so reaching for the Wi-Fi menu is not blocked; the shortcut and the menu still open it | 0.2.8 (0.2.5–0.2.7 came down) |
| Click anywhere in the menu bar | Puts it away | 0.1.x |
| Pointer leaves for 0.5 s | Tucks itself away | 0.1.x |
| `Control + Option + T` | Show / hide; change it under Shortcut → Change Shortcut | 0.1.9 |

It comes down on whichever screen you touched the top of, drawn at that screen's scale. It stays out of the way over full screen apps unless you ask for it with the shortcut or the menu.

## The photos on the line

| Gesture | What happens | Since |
| --- | --- | --- |
| Click | Picks that photo out, with a ring around it | 0.2.6 |
| `Shift` + click | Picks the run between the last pick and this one | 0.2.6 |
| `Command` + click | Adds or removes one | 0.2.6 |
| Drag a picked photo | The whole group travels: several pictures sent to a chat, several files copied into a folder | 0.2.6 |
| Double click | Opens with the app chosen under "Double click opens with", system default by default | 0.1.9 |
| Hold for 0.45 s, or force click | Quick Look, arrow keys page through the whole line | 0.2.1 |
| Middle button | Markup | 0.1.9 |
| Drag into an app | It gets a copy; the photo stays on the line | 0.1.x |
| Drag into a folder or the Desktop | The file goes there and leaves the line | 0.1.x |
| Drag onto the Trash | Deleted | 0.1.x |
| Click the corner cross | Takes down that one photo | 0.1.x |

## The right-click menu

Every item acts on what is picked out: three photos picked and one of them right-clicked means three of everything. Titles carry the count, e.g. "Save to Desktop · 3 photos".

| Item | What it does | Since |
| --- | --- | --- |
| Copy / Open / Quick Look / Markup | Copying lives only here now; a group is written as several files | 0.1.9; group-wide and click-no-longer-copies as of 0.2.6 |
| Show in Finder | Reveals the file, the whole group selected | 0.1.9 |
| Send via AirDrop | The system window lists nearby devices; a group goes in one go | 0.2.1 |
| Save to Desktop | Saves each one: photos from the line's own folder move, anything else is copied | 0.1.9 |
| Discard / Take down / Move to Trash | Off the line, and the file deleted only when it was the app's own copy | 0.1.9 |
| Take down everything to the left / right | Clears one side; greyed out while a group is picked | 0.1.9; greyed as of 0.2.7 |
| Take everything down | Empties the whole line | 0.2.6 |

## Taking pictures in

- **Clipboard**: pictures copied by a screenshot tool, from a browser, or image files copied in Finder, with no folder to add. Tick "Hang copied images" to enable.
- **Watched folders**: menu → "Also watch folders" → "Add Folder…". A screenshot tool's save folder or its temporary folder both work; dated subfolders are watched too.
- **System screenshots**: "Handle screenshots" points the macOS screenshot tool at the app's own folder and turns off the floating thumbnail; it is restored when you turn the option off or quit.
- **Duplicates**: matched on decoded pixels and orientation, so the same picture arriving from a folder, the clipboard or two tools hangs once. Cropped, annotated or recompressed counts as different.

## Hanging a picture from Finder

Select one or more pictures, right-click → Open With → Picline. The picture is copied into the app and hangs on the line. Third-party file managers that offer Open With work the same way, and you can drag pictures onto the app icon.

## Building from source

```sh
scripts/build-picline.sh release    # universal binary (arm64 + x86_64) in build/Picline.app
scripts/package-dmg.sh              # build/Picline-<version>.dmg
swift test --disable-sandbox        # 88 tests
swift scripts/check-strings.swift   # 83 strings × 11 languages
```

---

# Windows

> Every Windows release adds one to the last number, and carries into the middle one at 9 — `0.1.9` is followed by `0.2.0`, so nothing is ever as wide as `0.1.13`. Counting that way, this release is **0.2.4**; the four two-digit numbers before it (`0.1.10`–`0.1.13`) are `0.2.0`–`0.2.3`.

The Windows half has a repository of its own — [`Xinguangcuican/Picline-Windows`](https://github.com/Xinguangcuican/Picline-Windows) — where its history can be read on its own. `windows/` here is a mirror of it.

## Install

1. Download `Picline-0.2.4-win-x64.exe` (most machines) or `Picline-0.2.4-win-arm64.exe` (ARM laptops).
2. Double-click it. Nothing is installed and no registry keys are written, apart from the optional Explorer right-click entry, which can be switched off and removes its own key.
3. SmartScreen stops the first run (unsigned): More info → Run anyway.

## Bringing the line down

| Gesture | What happens | Since |
| --- | --- | --- |
| Pointer rests at the very top of the screen | The line comes down (0.09 s buffer); with nothing hanging it stays away | 0.1.0; empty line ignored as of 0.2.0 |
| Hold a key, then touch the top | Tray menu → "贴顶唤出" → no key / `Ctrl` / `Alt` / `Shift`; the choice is remembered | 0.1.8 |
| Pointer leaves for 0.5 s | Tucks itself away | 0.1.0 |
| `Ctrl + Alt + T` | Show / hide, **changeable**: tray → "快捷键：…", press the new combination (`Esc` cancels, `Delete` clears it) | 0.1.0; changeable as of 0.1.9 |
| `Ctrl + Alt + Shift + Q` | Quit | 0.1.0 |

## The cards on the line

| Gesture | What happens | Since |
| --- | --- | --- |
| Click | Picks the card out, with a blue ring | 0.1.5 |
| `Shift` + click | Picks everything between the two | 0.1.5 |
| `Ctrl` + click | Adds or removes one | 0.1.5 |
| Drag a picked card | The whole group travels; dropping it in a chat window sends them all | 0.1.5 |
| Double click | Full screen preview: desktop dimmed, picture as large as possible, name and pixel size underneath | 0.1.5 |
| Arrow keys in the preview | `←` `→` step through the line, `Home` / `End` jump to the ends, the caption reads "3 / 7 · name · size"; `Esc`, space or a click closes it | 0.2.3 |
| Hover | A small cross appears in the corner; it takes that one card down | 0.1.3 |
| Drag a card out | Into WeChat or QQ to send it, onto the Desktop or a folder to keep a png | 0.1.4 |
| Right-click | See below | 0.1.3 |

## The right-click menu

| Item | What it does | Since |
| --- | --- | --- |
| Preview / Copy picture / Copy as file | Copy picture writes `CF_DIB`, so `Ctrl + V` in WeChat sends it; copy as file writes `CF_HDROP` | 0.1.3 |
| Save to Desktop / Show in Explorer / Open with default viewer | Saves a png, reveals the file, hands it to the default viewer | 0.1.3 |
| **Markup** | Opens the file in Paint; the card follows the save, and a missing Paint is reported instead of doing nothing | 0.2.3 |
| Take down this / everything to the left / to the right / everything | Off the line; both side items grey out while a group is picked | 0.1.3; greyed as of 0.1.7 |
| **Group-wide** | Three cards picked, right-click any one: "Save to Desktop (3)" saves three | 0.1.6 |

"Copy picture" is the exception: a clipboard holds one bitmap, so it copies the card that was right-clicked. Use "Copy as file" or a drag for several.

## Taking pictures in, and the rest

| Feature | Notes | Since |
| --- | --- | --- |
| Clipboard | DIB from screenshot tools, PNG from browsers and tools, image files copied in Explorer | 0.1.1 |
| Explorer right-click "挂到 Picline" | Select pictures, right-click, they hang on the line; no need to start the app first (Windows 11: "Show more options") | 0.1.2 |
| Tray menu | Show / hide, take everything down, reveal key, Explorer entry on/off, quit | 0.1.2 |
| Several screens and scaling | Comes down on the screen you touched, drawn at that screen's scale | 0.1.2 |
| Full screen and single instance | Stays away over full screen apps; double-clicking twice does not make two lines | 0.1.2 |
| **Launch at login** | One tick in the tray menu, one value under `HKCU\\...\\Run`, removed when unticked | 0.2.3 |
| **Check for updates** | Tray → "检查更新…"; asks GitHub in the background and compares the Windows version read from the asset names, not the macOS tag | 0.2.3 |
| **Tray icon** | Its own icon instead of the generic system one; follows light and dark, fades when the line is empty | 0.2.1; one colour as of 0.2.2 |
| **WebP / HEIC / AVIF** | Falls back to the system WIC when GDI+ cannot read it (HEIC needs the HEIF extension installed) | 0.2.3 |

## Building from source

The source is in [`windows/`](windows/): Rust with hand-written Win32 and GDI+ bindings, no runtime to install. Both architectures are cross-compiled from a Mac with llvm-mingw:

```sh
cd windows
scripts/build-win.sh both     # dist/Picline-<version>-win-{x64,arm64}.exe
```

---

## How macOS and Windows differ

The two builds are aligned item by item, but some gestures are native to one platform. This is the whole list, nothing hidden:

| | macOS | Windows |
| --- | --- | --- |
| Double click | Opens the file in the default or chosen app | Full screen preview window |
| Quick Look / Markup | Yes: hold or force click to look, middle button for Markup | Markup yes (right-click → "标记", through Paint, saved back to the file); Quick Look no, the double-click preview stands in |
| AirDrop | Yes | No; copy the picture and paste it, or drag the card out |
| Add to selection | `Command` | `Ctrl` |
| Reveal shortcut | Editable, default `⌃⌥T` (menu bar → Shortcut → Change Shortcut) | Editable, default `Ctrl + Alt + T` (tray → 快捷键：…, press the new combination) |
| Hanging a picture | Finder → Open With → Picline | Explorer right-click → 挂到 Picline |
| Interface language | 11 languages | Chinese |
| Image formats | Anything ImageIO decodes, webp and heic included | Anything GDI+ or the system WIC decodes (webp and heic depend on the codecs installed) |
| Virtual desktops | Works on every Space | The window does not follow a desktop switch |
| Launch at login | A menu tick | A tick in the tray menu (writes one HKCU Run value) |

---

## Recent versions

The full history is in [`CHANGELOG.md`](CHANGELOG.md) (Chinese).

- **0.2.9 — 2026-11-04 (macOS) / 0.2.4 (Windows)** The Windows build catches up: arrow keys page through the preview, the tray icon fades when the line is empty, launch at login, check for updates, "mark up" through Paint with the card following the save, and WebP / HEIC / AVIF loading. macOS code unchanged. The Windows build also moved to single-digit numbering — after `0.1.9` comes `0.2.0` — which puts this release at `0.2.4`.
- **0.2.8 — 2026-11-04** An empty line no longer drops when the pointer reaches the top, so the Wi-Fi menu is no longer covered by a bare rope. With photos hanging nothing changed; the shortcut, the menu and a new screenshot still bring it down. The Windows build also got its own icon, instead of the generic system one; the tray uses a one-colour version that flips with a light or dark taskbar.
- **0.2.7 — 2026-11-02** Bringing the line down can require a key to be held (`⌘` / `⌥` / `⌃` / `⇧`; `Ctrl` / `Alt` / `Shift` on Windows). The Windows shortcut is no longer fixed either: press a new one in the tray.   Both side items grey out while a group is picked. The Windows source now lives in this repository.
- **0.2.6 — 2026-11-02** Pick several photos out: `Shift` to extend, drag the group, right-click a group and the menu acts on all of it with the count in the title. A click no longer copies. The line comes down the instant the pointer touches the menu bar. "Take everything down" joins the card menu.
- **0.2.5 — 2026-11-02** An empty line comes down too, so the app never looks dead.
- **0.2.4 — 2026-11-02** Finder entry moved to Open With, which is reliable, instead of the Services menu.
- **0.2.3 — 2026-11-02** Finder service and intake fixes.
- **0.2.2 — 2026-11-01** Release-pipeline check; identical to 0.2.1.
- **0.2.1 — 2026-11-01** AirDrop and press-and-hold Quick Look.

## How the multi-Space bug was fixed

An `NSPanel` with `canJoinAllSpaces` can get pinned to one Space for good after an `orderOut` / `orderFront` cycle — that is upstream [issue #80](https://github.com/alejandrobujan/tendedero/issues/80). The fix is not to repair that window but to **rebuild it when it turns out not to be on the current desktop**. All of it lives in `Sources/Tendedero/AppDelegate.swift`, 31 lines; everything since is built on it.

## Lineage

```
Tendedero (Alejandro Buján, MIT)
  └── Picline 0.1.9 (老张: clipboard and intake)
        └── Picline 0.2.0 (multi-Space fix)
              ├── Picline 0.2.1 (AirDrop, press-and-hold Quick Look)
              │     └── Picline 0.2.2 (release pipeline check, same as 0.2.1)
              │           └── Picline 0.2.3 (Finder service)
              │                 └── Picline 0.2.4 (Open With instead of Services)
              │                       └── Picline 0.2.5 (an empty line comes down)
              │                             └── Picline 0.2.6 (pick several, act on all)
              │                                   └── Picline 0.2.7 (reveal can require a key)
              │                                         └── Picline 0.2.8 (an empty line stays away)
              │                                               └── Picline 0.2.9 (the Windows build catches up)
              └── Picline for Windows 0.1.x (Rust + Win32, aligned with macOS)
```

This repository only adds features and the multi-Space fix. The names and icons are not covered by the MIT licence; see [`NOTICE`](NOTICE).

## Licence

MIT, original copyright Alejandro Buján. The Tendedero and Picline **names and icons are not part of the MIT grant**. This project keeps the Picline name and its own icon and is not an official release or endorsement by upstream or the original author.
