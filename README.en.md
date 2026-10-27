# QuickLook Manager

[Italiano](README.md) · **English**

Quick Look on macOS shows previews and thumbnails for many file types — but not for the ones you actually care about as a developer, maker or photographer. **QuickLook Manager** puts a whole set of them in a single app: press Space on code, a Markdown note, an app bundle, a ZIP, an MKV video, a RAW photo, a 3D print file, an EPS drawing or an installer package, and see what's inside.

Everything is built into the app. There is nothing to install besides the app itself: **copy it to Applications** and macOS turns its Quick Look extensions on by itself.

![The app window](docs/screenshots/window-apps.png)

The window is a control panel: a sidebar with every module and a switch next to it, and each module's settings on the right. Try a file lets you drop anything in to see exactly what Quick Look will show.

## Modules

| Module | What you get |
|---|---|
| **Text and Code** | Highlighted code (190+ languages), JSON/YAML/plist as a tree with a source view, Markdown (Typora, GitHub, CommonMark, MultiMarkdown) with math, diagrams, footnotes and importable themes; also Textile, AsciiDoc, Creole, reStructuredText, BBCode and man pages. |
| **Apps and Packages** | macOS, iOS, Android, Windows and Flatpak apps: identifier, version, architectures, minimum system, signature, entitlements, provisioning. Classic Mac programs and documents, with their original icons. |
| **Archives** | The contents of ZIP, 7z, RAR, tar, gz, bz2, xz, cpio, CAB, ISO, XAR, RPM, DEB… as a tree, without extracting. |
| **Video** | A built-in player for the formats macOS doesn't know — MKV, WebM, AVI, WMV, FLV, M2TS, VOB… It starts when Quick Look opens and stops when you close it. Thumbnails too. |
| **RAW Photos** | Previews and thumbnails for Canon, Nikon, Sony, Fujifilm, Olympus, Panasonic, Pentax, Leica, Adobe DNG and many more. |
| **3D Models** | Interactive 3D preview of 3MF files (rotate, zoom, print plates) and thumbnails. |
| **EPS** | Previews and thumbnails of EPS drawings, using the embedded image or Ghostscript. |
| **PKG Packages** | Identifier, version, scripts and signature at the top; the full list of installed files at the bottom — read from the package's bill of materials, so it's instant even for gigabyte-sized packages. |

## Screenshots

| | |
|---|---|
| ![Code](docs/screenshots/preview-code.png) | ![JSON](docs/screenshots/preview-json.png) |
| ![Markdown](docs/screenshots/preview-markdown.png) | ![App](docs/screenshots/preview-app.png) |
| ![Archive](docs/screenshots/preview-archive.png) | ![PKG](docs/screenshots/preview-pkg.png) |
| ![3D model](docs/screenshots/preview-3d.png) | ![EPS](docs/screenshots/preview-eps.png) |

![Video](docs/screenshots/preview-video.png)

## Languages

The app is available in **Italian, English, French, German, Spanish and Arabic** (right-to-left included). It follows the language of your Mac.

![Arabic](docs/screenshots/window-arabic.png)

## Requirements and installation

- macOS 14 or later, Apple Silicon.
- Download the app from the [GitHub releases](../../releases), move it to **Applications** and open it once.
- If another app already provides previews for the same file types (for example QuickTextLook, QLAppBundle, QuickLook Video, Camera RawX or Preview3MF), Quick Look picks only one of them. Remove the duplicate apps, or turn their extension off in System Settings › Login Items & Extensions. The *Activation* page in the app explains it.

## Building

```bash
python3 scripts/gen-types.py   # file types (UTIs) → project.yml and Kit/QLMTypes.swift
xcodegen generate
xcodebuild -project QuickLookManager.xcodeproj -scheme QuickLookManager \
           -configuration Debug -derivedDataPath build/DerivedData build
```

Once, before the first build: `scripts/vendor-ghostscript.sh` (EPS module) and `scripts/vendor-video.sh` (Video module) download the sources and compile them into `Vendor/` (ignored by git). The build embeds them with `scripts/embed-ghostscript.sh` and `scripts/embed-video-libs.sh`. The JavaScript bundle of the text module is already in `Modules/Text/Resources/Web`; to regenerate it: `cd tools/js && npm install && ./build.sh`.

Translations live in `scripts/traduzioni/`; after building, `scripts/gen-strings.py` regenerates the String Catalogs and reports anything untranslated.

For tests that register nothing with the system (Debug only): `QuickLookManager -QLMRender <file> <png>` and `-QLMSnapshot <png> [-QLMPane try|text|apps|archives|video|raw|models|eps|pkg|activation]`.

## License and credits

QuickLook Manager is released under the **GNU GPL v3** (see [LICENSE](LICENSE)), and distributed through GitHub only. It builds on the work of others:

- [QLAppBundle](https://github.com/relikd/QLAppBundle) by relikd (MIT) — Apps and Packages;
- [Preview3MF](https://github.com/cavoco/Preview3MF) by Cavan O'Connor (MIT) — 3D models;
- [QLVideo](https://github.com/Marginal/QLVideo) by Jonathan Harris (GPL 2+) — the ffmpeg versions and patches;
- [LibRaw](https://github.com/LibRaw/LibRaw), [Ghostscript](https://ghostscript.com) (AGPL v3), [FFmpeg](https://ffmpeg.org), [dav1d](https://code.videolan.org/videolan/dav1d), [zimg](https://github.com/sekrit-twc/zimg), ZIPFoundation, AndroidXML, highlight.js, markdown-it, KaTeX, Mermaid and others.

The complete list, with licenses, is in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
