#!/bin/zsh
# Rigenera i bundle JavaScript in Core/Resources/Web. Richiede node/npm (npm install una volta).
set -e
cd "$(dirname "$0")"
OUT=../../Core/Resources/Web
mkdir -p $OUT/fonts
E=node_modules/.bin/esbuild
common=(--bundle --minify --format=iife --legal-comments=none --log-level=warning)
$E src/hljs-entry.js    $common --platform=neutral --outfile=$OUT/hljs.js
$E src/yaml-entry.js    $common --platform=neutral --outfile=$OUT/yaml.js
$E src/preview-entry.js $common --platform=browser --outfile=$OUT/preview.js
$E src/asciidoc-entry.js $common --external:node:fs/promises --external:node:path --platform=browser --outfile=$OUT/asciidoctor.js
$E src/mermaid-entry.js $common --platform=browser --outfile=$OUT/mermaid.js
cp node_modules/katex/dist/katex.min.css $OUT/katex.min.css
cp node_modules/katex/dist/fonts/*.woff2 $OUT/fonts/
ls -la $OUT
