# Librerie e codice di terze parti / Third-party notices

QuickLook Manager è distribuito con licenza GPL v3 (vedi `LICENSE`). Contiene codice di altri progetti, tutti con licenze compatibili.

| Componente | Licenza | Dove |
|---|---|---|
| [QLAppBundle](https://github.com/relikd/QLAppBundle) di relikd (base del modulo «App e pacchetti») | MIT, © 2025 relikd | `Modules/Apps`, `AssetCarReader` |
| [AndroidXML](https://github.com/relikd/AndroidXML) 0.9.4 | MIT | dipendenza Swift Package |
| [Preview3MF](https://github.com/cavoco/Preview3MF) di Cavan O'Connor (modulo «Modelli 3D») | MIT | `Modules/Models` (testo della licenza: `Modules/Models/LICENSE-Preview3MF`) |
| [ZIPFoundation](https://github.com/cavoco/ZIPFoundation) (fork di Cavan O'Connor con correzione ZIP64) | MIT | dipendenza Swift Package |
| [LibRaw](https://github.com/LibRaw/LibRaw) 0.21.4 (modulo «Foto RAW») | LGPL 2.1 o CDDL 1.0, © LibRaw LLC | `Vendor/LibRaw`, compilata dentro `QLMNative.framework` |
| libarchive (modulo «Archivi») | BSD-2: si usa la libreria di macOS; le intestazioni `Vendor/libarchive/*.h` sono quelle del progetto | `Vendor/libarchive` |
| [Ghostscript](https://ghostscript.com) 10.x (modulo EPS, se incorporato) | AGPL v3, © Artifex Software | compilato da `scripts/vendor-ghostscript.sh` in `Vendor/ghostscript`, incorporato nel framework |
| [QLVideo](https://github.com/Marginal/QLVideo) di Jonathan Harris (le versioni di ffmpeg/dav1d/zimg e le due patch a ffmpeg in `scripts/video-patches`) | GPL 2 o successiva | `scripts/vendor-video.sh` (licenza: `Modules/Video/LICENSE-QLVideo.txt`) |
| [FFmpeg](https://ffmpeg.org) (commit 946fcce, con le due patch di QLVideo) | GPL (compilato con `--enable-gpl`) | `scripts/vendor-video.sh` → `Vendor/ffmpeg`, incorporato in `Contents/Frameworks` |
| [dav1d](https://code.videolan.org/videolan/dav1d) (commit 54706fc) | BSD-2 | idem |
| [zimg](https://github.com/sekrit-twc/zimg) (commit f819b14) | WTFPL | idem |
| Icona dell'app | Ridisegnata da zero per Icon Composer; l'idea (un occhio con una lente d'ingrandimento) viene dal mockup «New fluent design icon suggestion» di [Donnnno](https://github.com/Donnnno), pubblicato su [QL-Win/QuickLook#627](https://github.com/QL-Win/QuickLook/issues/627). Nessun file grafico dell'originale è incluso. | disegno originale di QuickLook Manager (GPL v3) | `App/AppIcon.icon` |
| QuickTextLook (modulo «Testo e codice») | GPL v3, Giovanni | `Modules/Text`, `tools/js` |
| highlight.js, js-yaml, markdown-it e plugin, KaTeX, Mermaid, Asciidoctor.js, textile-js | BSD-3 / MIT / ISC / Unlicense | `Modules/Text/Resources/Web` (vedi `tools/js/package.json`) |

Testo della licenza MIT di QLAppBundle: «Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software [...]. The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.» Software fornito «così com'è», senza garanzie.
