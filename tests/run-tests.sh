#!/bin/bash
# Test che girano a ogni build. Ognuno corrisponde a un guasto già successo.
set -uo pipefail
# Le prove cercano testi per nome: la lingua e' fissa, qualunque sia quella del Mac.
export QLAPPBUNDLE_LINGUA=it
cd "$(dirname "$0")/.."
FAILED=0; PASSED=0
ok()   { PASSED=$((PASSED+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAILED=$((FAILED+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }

# `grep -q` esce alla prima corrispondenza: con pipefail, il sed a monte puo'
# morire di SIGPIPE e la pipeline risulta fallita a caso. Qui si legge tutto.
cerca() { grep "$@" >/dev/null; }

echo "── Test ──────────────────────────────────────────────"

# 1. Le icone classiche coi colori giusti e ritagliate. Compila davvero: il
#    guasto stava nei pixel, non in una riga che si possa cercare.
if command -v swiftc >/dev/null 2>&1; then
    b=$(mktemp -t icona)
    if swiftc -O -o "$b" tests/icona/main.swift "Modules/Apps/Sources/Data - Classic Mac/ClassicIcon.swift" 2>/dev/null \
       && "$b" >/dev/null 2>&1; then
        ok "icone classiche: colori dal membro giusto, maschera applicata"
    else
        "$b" 2>&1 | sed 's/^/      /'
        fail "le icone classiche escono sbagliate"
    fi
    rm -f "$b"
else
    printf '  \033[33m·\033[0m test delle icone saltato (manca swiftc)\n'
fi

# 2bis. Gli eseguibili Windows non si modificano: la loro icona il Finder la
#    mostra gia' come miniatura, e non vale toccare un file che viene da un
#    altro sistema operativo.
if ! sed 's://.*::' "Modules/Apps/Sources/Data - Classic Mac/ClassicIconWriter.swift" | cerca "WindowsIcon"; then
    ok "gli eseguibili Windows non vengono modificati"
else
    fail "il writer tocca anche gli .exe: dovrebbero restare come sono"
fi

# 2. Del FinderInfo si tocca un bit solo. Il type e' del file, non della sua
#    visualizzazione: cambiarlo romperebbe il programma su Mac OS 9.
scritture=$(sed 's://.*::' "Modules/Apps/Sources/Data - Classic Mac/ClassicIconWriter.swift" \
            | grep -nE 'info\[[0-9]+\]' | grep -v 'customIconFlagByte')
if [ -z "$scritture" ] && ! cerca -r 'privateApplicationType' Modules/Apps/Sources Agent App; then
    ok "del FinderInfo si tocca solo il bit dell'icona: type e creator restano"
else
    fail "qualcuno riscrive il FinderInfo oltre il bit dell'icona" "$scritture"
fi

# 3. Il FinderInfo va creato se manca, se no l'icona scritta non si vede: il
#    fork viene scritto e il Finder non ci guarda. Capita ai documenti copiati
#    su un disco moderno che il type l'hanno perso per strada.
if sed 's://.*::' "Modules/Apps/Sources/Data - Classic Mac/ClassicIconWriter.swift" \
   | cerca 'getxattrData(url, "com.apple.FinderInfo") ?? Data(repeating: 0, count: 32)'; then
    ok "il FinderInfo viene creato se manca"
else
    fail "il flag dell'icona si accende solo su un FinderInfo esistente"
fi

# 4. Voci ICO da 16 byte, con gli 8 iniziali presi dal gruppo. Copiandone 12 e
#    scrivendone 20 uscivano icone da 168x48.
w="Modules/Apps/Sources/Data - Windows/WindowsIcon.swift"
if sed 's://.*::' "$w" | cerca "at + 8)\]" && sed 's://.*::' "$w" | cerca "images.count \* 16"; then
    ok "voci ICO da 16 byte, con gli 8 byte iniziali presi dal gruppo"
else
    fail "aritmetica delle voci ICO cambiata: misure sbagliate"
fi

# Prove vere, al posto di controlli che cercavano parole nel testo del codice.
# Ognuna compila un programmino che usa il codice vero e lo fa girare.
#
# 5/6/13. Il giro del volume (tetto, interruzione), la scelta dei volumi
#         (sola lettura, rete) e i percorsi non fidati del magazzino.
# 8.      Un attributo vuoto non e' un attributo assente: lo prova il test del
#         ripristino (n. 16), sul file che un fork non ce l'aveva.
# 13.     Del fork originale si conserva tutto, non solo le risorse.
# ---------------------------------------------------------------------------
prova() {   # prova <programma> <messaggio ok> <messaggio fail> <file...>
    local main="$1" okmsg="$2" failmsg="$3"; shift 3
    if ! command -v swiftc >/dev/null 2>&1; then
        printf '  \033[33m·\033[0m %s saltata (manca swiftc)\n' "$okmsg"; return
    fi
    local bin; bin=$(mktemp -t prova)
    if swiftc -O -o "$bin" "$main" tests/support/Testi.swift "$@" 2>/dev/null; then
        local uscita; uscita=$("$bin" 2>&1)
        if [ $? -eq 0 ]; then ok "$okmsg"; else fail "$failmsg" "$uscita"; fi
    else
        fail "la prova non si compila: $main"
    fi
    rm -f "$bin"
}
CM="Modules/Apps/Sources/Data - Classic Mac"
prova tests/percorso/main.swift \
    "il giro del volume ha un tetto e si ferma, la radice di sistema e' di sola lettura, i percorsi non escono dal volume" \
    "il giro del volume, la scelta dei volumi o i percorsi non fidati non fanno quello che devono" \
    "$CM/IconeAutomatiche.swift" "$CM/VolumeClassico.swift" "$CM/ClassicIcon.swift" \
    "$CM/ClassicIconWriter.swift" "$CM/ForkBackup.swift"
prova tests/fork/main.swift \
    "area riservata, testa della mappa e attributi passano intatti, ogni risorsa originale torna identica" \
    "l'icona accodata altera parti del fork originale" \
    "$CM/ClassicIcon.swift" "$CM/ClassicIconWriter.swift" "$CM/ForkBackup.swift"
prova tests/consensi/main.swift \
    "i permessi disco per disco si scrivono, si rileggono e si dimenticano" \
    "i permessi disco per disco non funzionano" \
    "$CM/ConsensiDischi.swift"

# 9. I documenti hanno bisogno del Desktop del volume.
#
# Un documento l'icona non ce l'ha addosso: ha un creator e un type, e il
# Finder di allora li risolveva contro il file `Desktop` del disco. Passando
# `nil` al posto di quello, la Finder Sync guardava soltanto le applicazioni --
# metà del lavoro, in silenzio. (Valeva per l'estensione del Finder, che c'era prima
# dell'agente: la regola resta.)
# ---------------------------------------------------------------------------
if sed 's://.*::' "Modules/Apps/Sources/Data - Classic Mac/IconeAutomatiche.swift" | cerca "desktop: scrivania"; then
    ok "si passa il Desktop del volume, quindi si vedono anche i documenti"
else
    fail "i documenti restano fuori: non si passa il Desktop del volume"
fi

# 10. L'agente sente i dischi che arrivano.
#
# Prima le icone le scriveva un'estensione del Finder, avvisata cartella per
# cartella. Quell'estensione non c'e' piu': per ricevere gli avvisi doveva
# dichiarare i dischi che osservava, e il Finder metteva nella barra laterale
# l'icona dell'applicazione **al posto di quella del disco**. Adesso il lavoro
# lo fa un agente, che deve ascoltare i montaggi: senza, non si accorgerebbe di
# niente.
# ---------------------------------------------------------------------------
if sed 's://.*::' Modules/Apps/Sources/Agent/Agente.swift | cerca "didMountNotification" \
   && sed 's://.*::' Modules/Apps/Sources/Agent/Agente.swift | cerca "mountedVolumeURLs"; then
    ok "l'agente guarda i volumi gia' montati e ascolta quelli che arrivano"
else
    fail "l'agente non si accorgerebbe dei dischi"
fi

# 10bis. E nell'applicazione non c'e' piu' nessuna estensione del Finder.
#
# E' la richiesta esplicita: l'icona dell'applicazione non deve comparire nella
# barra laterale **nemmeno** mentre si lavora su quel disco. Con un'estensione
# Finder Sync non si puo' evitare -- la sostituzione dell'icona e' una funzione
# documentata e non ha interruttore -- quindi l'estensione non deve proprio
# esserci.
# ---------------------------------------------------------------------------
resti=$(ruby -e '
require "xcodeproj"
p_ = Xcodeproj::Project.open("QLAppBundle.xcodeproj")
puts p_.targets.map(&:name).select { |n| n =~ /Finder/i }.join(" ")
' 2>/dev/null)
if [ -z "$resti" ] && [ ! -d FinderSync ]; then
    ok "nessuna estensione del Finder: la barra laterale resta com'era"
else
    fail "c'e' ancora un'estensione Finder Sync: il Finder rimettera' la nostra icona sui dischi" "$resti"
fi

# 11. Dopo aver scritto, si rilegge dal disco.
#
# Il guasto: quattro applicazioni di un Mac OS 9 sono uscite dalla scrittura
# con la mappa delle risorse illeggibile da un certo tipo in poi -- mentre la
# stessa funzione, sugli stessi byte, produceva in memoria un fork corretto che
# superava la verifica. Fra «i byte giusti in mano» e «i byte giusti sul disco»
# c'e' di mezzo il filesystem. Se la rilettura non torna, il file viene rimesso
# com'era.
# ---------------------------------------------------------------------------
if sed 's://.*::' "Modules/Apps/Sources/Data - Classic Mac/ClassicIconWriter.swift" \
   | cerca "riletto == merged"; then
    ok "dopo la scrittura il fork si rilegge dal disco e si confronta"
else
    fail "ci si fida di quello che si e' scritto senza rileggerlo"
fi

# 12. Il ripristino accorcia il fork.
#
# Il guasto: `setxattr` con un valore piu' corto non accorcia il fork, gli
# sovrascrive l'inizio. Dopo un ripristino restavano 4.893 byte di avanzo e il
# file non era piu' quello di prima.
#
# Il gesto sta in `rimetti`, che e' il punto unico da cui passano sia il
# ripristino di un file solo sia quello di un disco intero.
# ---------------------------------------------------------------------------
if sed 's://.*::' "Modules/Apps/Sources/Data - Classic Mac/ClassicIconWriter.swift" \
   | sed -n '/static func rimetti/,/^    }/p' | cerca 'removexattr($0, "com.apple.ResourceFork"'; then
    ok "il ripristino toglie l'attributo prima di riscriverlo, cosi' il fork si accorcia"
else
    fail "il ripristino sovrascrive senza accorciare: il fork resta piu' lungo dell'originale"
fi

# 14. Sui volumi dei driver FUSE non si scrive.
#
# Lì l'icona il driver la sintetizza già da sé, senza toccare l'immagine. E
# scriverci sarebbe irreversibile: quei driver espongono due soli attributi
# estesi, FinderInfo e ResourceFork, quindi la copia del fork originale non
# verrebbe conservata. Misurato su un'immagine vera: il file aveva l'icona e
# nessun backup.
# ---------------------------------------------------------------------------
if sed 's://.*::' "Modules/Apps/Sources/Data - Classic Mac/VolumeClassico.swift" | cerca 'hasPrefix("macfuse")'; then
    ok "i volumi FUSE si saltano: lì il driver fa già tutto"
else
    fail "si scriverebbe sui volumi FUSE, e senza poter tornare indietro"
fi

# 15. I tipi dell'icns che il servizio icone sa davvero leggere.
#
# Il guasto: si scrivevano PNG sotto `ic04`/`ic05`, che il formato definisce come
# ARGB grezzo -- macOS ne leggeva i byte come pixel e disegnava rumore colorato,
# a 16 e 32 una tempesta di pixel blu e rossi. In visualizzazione a elenco si
# vedeva benissimo.
#
# La correzione non e' passare a `icp4`/`icp5`: quelli un PNG lo accettano, e
# `NSImage` infatti li apre bene, ma il **servizio icone** -- quello che disegna
# le icone nel Finder -- no, e il rumore resta. Misurato con lo stesso file nelle
# tre forme, reso a 16, 32 e 64 pixel passando da NSWorkspace.
#
# Vanno usati i tipi a 24 bit con la maschera separata, che sono anche quelli che
# il driver produce: una forma sola da conoscere invece di due.
# ---------------------------------------------------------------------------
c="Modules/Apps/Sources/Data - Classic Mac/ClassicIcon.swift"
if sed 's://.*::' "$c" | cerca '"il32"' && sed 's://.*::' "$c" | cerca '"s8mk"' \
   && ! sed 's://.*::' "$c" | cerca -E '"ic0[45]"|"icp[45]"'; then
    ok "l'icns usa i tipi a 24 bit con maschera, gli stessi del driver"
else
    fail "l'icns usa tipi PNG: il servizio icone del Finder disegnera' rumore"
fi

# 16. Il ripristino, su un volume vero.
#
# Gli altri test guardano il testo del codice; questo scrive davvero. Si monta
# un'immagine HFS+, si conserva il fork di due file — uno che ce l'ha e uno che
# non ce l'ha, che è il caso delicato — si sostituisce il fork come fa la Finder
# Sync, e si pretende che `restoreAll` riporti tutto al byte di partenza.
#
# Serve un filesystem vero perché il guasto da cui nasce ci vive: `setxattr` con
# un valore più corto non accorcia il fork, gli sovrascrive l'inizio. In memoria
# non si vede.
# ---------------------------------------------------------------------------
if command -v swiftc >/dev/null 2>&1 && command -v hdiutil >/dev/null 2>&1; then
    immagine=$(mktemp -t provafork).dmg
    b=$(mktemp -t ripristino)
    if swiftc -O -o "$b" tests/ripristino/main.swift tests/support/Testi.swift \
            "Modules/Apps/Sources/Data - Classic Mac/ClassicIcon.swift" \
            "Modules/Apps/Sources/Data - Classic Mac/ClassicIconWriter.swift" \
            "Modules/Apps/Sources/Data - Classic Mac/ForkBackup.swift" 2>/dev/null \
       && hdiutil create -size 20m -fs HFS+ -volname ProvaFork -ov "$immagine" >/dev/null 2>&1; then
        punto=$(hdiutil attach "$immagine" -nobrowse 2>/dev/null | awk '/\/Volumes\//{ $1=""; $2=""; sub(/^  */,""); print }')
        if [ -n "$punto" ]; then
            uscita=$("$b" "$punto" 2>&1)
            if [ $? -eq 0 ]; then
                ok "il ripristino rimette i fork com'erano, su un volume vero"
            else
                fail "il ripristino non riporta i file al fork di partenza" "$uscita"
            fi
            hdiutil detach "$punto" >/dev/null 2>&1
        else
            printf '  \033[33m·\033[0m test del ripristino saltato (immagine non montata)\n'
        fi
    else
        fail "il test del ripristino non si compila"
    fi
    rm -f "$b" "$immagine"
else
    printf '  \033[33m·\033[0m test del ripristino saltato (manca swiftc o hdiutil)\n'
fi



# 19. La guardia di formato: oltre i limiti del fork non si scrive.
#
# Gli offset delle risorse stanno in tre byte, quelli dentro la mappa in due.
# Superarli non dà nessun errore: `emitIconRef` scrive l'offset in tre byte e
# `put16` gli offset della mappa in due, e i bit in eccesso spariscono in
# silenzio. Il fork che ne esce si scrive benissimo e indirizza il posto
# sbagliato -- su un programma del 1992 che magari è l'unica copia rimasta.
#
# Il test costruisce i casi veri (dati oltre i 16 MB, mappa oltre i 64 KB) e
# pretende il rifiuto; e pretende anche che un fork normale passi, perché una
# guardia che rifiuta tutto lascerebbe i file senza icona in silenzio.
# ---------------------------------------------------------------------------
if command -v swiftc >/dev/null 2>&1; then
    b=$(mktemp -t limiti)
    if swiftc -O -o "$b" tests/limiti/main.swift tests/support/Testi.swift \
            "Modules/Apps/Sources/Data - Classic Mac/ClassicIcon.swift" \
            "Modules/Apps/Sources/Data - Classic Mac/ClassicIconWriter.swift" \
            "Modules/Apps/Sources/Data - Classic Mac/ForkBackup.swift" 2>/dev/null; then
        uscita=$("$b" 2>&1)
        if [ $? -eq 0 ]; then
            ok "oltre i limiti del formato non si scrive, dentro sì"
        else
            fail "la guardia di formato non tiene" "$uscita"
        fi
    else
        fail "il test dei limiti non si compila"
    fi
    rm -f "$b"
else
    printf '  \033[33m·\033[0m test dei limiti saltato (manca swiftc)\n'
fi

# 20. Quello che si dice di un programma macOS, confrontato con `lipo` e `otool`.
#
# Architetture, sistema minimo e firma sono letti a mano dalle intestazioni
# Mach-O e dal modulo `SecCode`. Se una di quelle letture si sposta di quattro
# byte il pannello continua a comparire, solo con dentro dei numeri finti: un
# guasto che non si vede. Qui si confronta con gli strumenti di sistema, e si
# manomette una firma vera per pretendere che venga vista come manomessa.
# ---------------------------------------------------------------------------
if command -v swiftc >/dev/null 2>&1 && command -v lipo >/dev/null 2>&1; then
    b=$(mktemp -t macos)
    copia=$(mktemp -d -t firma)

    # Il campione delle architetture e' un binario di sistema, universale e
    # vero. Il minimo si chiede a `otool` per la fetta nativa e non per la
    # prima che capita: le fette di /bin/ls dichiarano minimi diversi (11.0 su
    # arm64e, 10.14 su x86_64), e la riga del pannello risponde a «gira sul mio
    # Mac?», quindi e' quella nativa che conta.
    campione=/bin/ls
    archi=$(lipo -archs "$campione")
    nativa=$(printf '%s\n' $archi | grep -E '^arm64' | head -1)
    [ -z "$nativa" ] && nativa=$(printf '%s\n' $archi | head -1)
    minos=$(otool -l -arch "$nativa" "$campione" | awk '/LC_BUILD_VERSION/{t=1} t&&/minos/{print $2; exit}')

    # Per la firma serve invece un binario nostro, di una architettura sola:
    # manomettere una fetta di un universale altrui rompe la struttura invece
    # della firma, e allora anche `codesign` risponde «internal error» --
    # provato su /bin/ls. Un file piccolo e monoarchitettura fa dire a tutti e
    # due la stessa cosa.
    printf 'print("ciao")\n' > "$copia/ciao.swift"
    swiftc -o "$copia/firmata" "$copia/ciao.swift" 2>/dev/null
    cp "$copia/firmata" "$copia/manomessa"
    codesign -f -s - "$copia/firmata" 2>/dev/null
    codesign -f -s - "$copia/manomessa" 2>/dev/null
    python3 -c "
import sys
p = sys.argv[1]
with open(p, 'r+b') as f:
    f.seek(0x4000); b = f.read(1); f.seek(0x4000); f.write(bytes([b[0] ^ 0xFF]))
" "$copia/manomessa"

    if swiftc -O -o "$b" tests/macos/main.swift tests/support/Testi.swift \
            "Modules/Apps/Sources/Data - macOS/MachO.swift" "Modules/Apps/Sources/Data - macOS/FirmaCodice.swift" 2>/dev/null; then
        uscita=$("$b" "$campione" "$archi" "$minos" "$copia/firmata" "$copia/manomessa" 2>&1)
        if [ $? -eq 0 ]; then
            ok "architetture, sistema minimo e firma: come li vedono lipo, otool e codesign"
        else
            fail "quello che il pannello dice di un programma macOS non torna" "$uscita"
        fi
    else
        fail "il test dei programmi macOS non si compila"
    fi
    rm -rf "$b" "$copia"
else
    printf '  \033[33m·\033[0m test dei programmi macOS saltato (manca swiftc o lipo)\n'
fi

# 21. Il lettore dei pacchetti Flatpak, contro byte prodotti da GLib.
#
# Un `.flatpak` non e' un archivio: e' un valore GVariant, e dove sta ogni cosa
# lo dice la forma del valore -- niente numeri magici, niente campi a posizione
# fissa. Il file di prova lo costruisce `finto-bundle.c` con GLib, cioe' con
# l'implementazione di riferimento: se avessimo capito male la specifica si vede
# qui, mentre un file costruito da noi ci darebbe ragione per sbaglio.
#
# Due misure, non una: GVariant cambia la larghezza degli scostamenti a 256 e a
# 65.536 byte, e un lettore che sbaglia quella regola funziona sui file piccoli
# e si rompe su quelli veri, che sono tutti grandi.
# ---------------------------------------------------------------------------
if command -v swiftc >/dev/null 2>&1 && pkg-config --exists glib-2.0 2>/dev/null; then
    d=$(mktemp -d -t flatpak)
    if cc tests/flatpak/finto-bundle.c $(pkg-config --cflags --libs glib-2.0) -o "$d/finto-bundle" 2>/dev/null \
       && sips -z 128 128 Modules/Apps/AppsResources/defaultIcon.png --out "$d/icona.png" >/dev/null 2>&1 \
       && "$d/finto-bundle" "$d/piccolo.flatpak" "$d/icona.png" >/dev/null 2>&1 \
       && "$d/finto-bundle" "$d/grande.flatpak" "$d/icona.png" 300000 >/dev/null 2>&1 \
       && swiftc -O -o "$d/prova" tests/flatpak/main.swift tests/support/Testi.swift \
            "Modules/Apps/Sources/Data - Flatpak/GVariant.swift" "Modules/Apps/Sources/Data - Flatpak/FlatpakBundle.swift" \
            Modules/Apps/Sources/Common/Riga.swift 2>/dev/null; then
        u1=$("$d/prova" "$d/piccolo.flatpak" "$d/icona.png" 2>&1); e1=$?
        u2=$("$d/prova" "$d/grande.flatpak" "$d/icona.png" 2>&1); e2=$?
        if [ $e1 -eq 0 ] && [ $e2 -eq 0 ]; then
            ok "i pacchetti Flatpak si leggono: icona e metadati, in tutte e due le misure"
        else
            fail "il lettore dei pacchetti Flatpak non torna" "$u1 $u2"
        fi
    else
        fail "il test dei pacchetti Flatpak non si costruisce"
    fi
    rm -rf "$d"
else
    printf '  \033[33m·\033[0m test dei Flatpak saltato (manca swiftc o glib)\n'
fi

# 22. Gli identificativi di tipo si confrontano in minuscolo.
#
# Il guasto: LaunchServices normalizza gli UTI, e a un file `.macapp` risponde
# `de.relikd.qlappbundleextended.classic-application`, mentre nel codice c'era scritto
# `QLAppBundle` con le maiuscole. Quel `case` non ha mai preso, e un file
# rinominato finiva nel `fatalError` in fondo allo switch: l'estensione moriva
# invece di mostrare l'anteprima. Misurato chiedendo il tipo a `resourceValues`
# su un file vero, che e' l'unico modo di accorgersene.
# ---------------------------------------------------------------------------
if sed 's://.*::' Modules/Apps/Sources/Common/MetaInfo.swift | cerca "switch self.UTI.lowercased()" \
   && ! sed 's://.*::' Modules/Apps/Sources/Common/MetaInfo.swift | cerca 'case "de.relikd.QLAppBundleExtended'; then
    ok "i tipi si confrontano in minuscolo, come li scrive LaunchServices"
else
    fail "un tipo dichiarato da noi non verrebbe riconosciuto: l'estensione morirebbe"
fi


# 24. L'agente prende in carico solo i volumi che hanno roba classica sopra.
#     (Il guasto era dell'estensione del Finder, che c'era prima dell'agente;
#     la regola di scelta dei volumi e' rimasta la stessa.)
#
# Il guasto: si osservava ogni volume montato. Il Finder pero' mette nella barra
# laterale l'icona dell'applicazione a cui l'estensione appartiene **al posto**
# dell'icona del disco -- e' scritto nella guida di Apple («the sidebar icons
# you provide will replace the default folder icons ... for any of the root
# folders that your extension is monitoring») -- e cosi' ogni disco esterno si
# ritrovava la nostra icona, anche quando sul desktop la sua compariva giusta.
#
# Due volumi veri, perche' la prova sta nei file che ci stanno sopra.
# ---------------------------------------------------------------------------
if command -v swiftc >/dev/null 2>&1 && command -v hdiutil >/dev/null 2>&1; then
    d=$(mktemp -d -t volumi)
    b=$(mktemp -t volumi)
    hdiutil create -size 20m -fs HFS+ -volname ProvaClassico -ov "$d/classico.dmg" >/dev/null 2>&1
    hdiutil create -size 20m -fs HFS+ -volname ProvaModerno  -ov "$d/moderno.dmg"  >/dev/null 2>&1
    monta() { hdiutil attach "$1" -nobrowse 2>/dev/null | awk '/\/Volumes\//{ $1=""; $2=""; sub(/^  */,""); print }'; }
    vc=$(monta "$d/classico.dmg")
    vm=$(monta "$d/moderno.dmg")

    if [ -n "$vc" ] && [ -n "$vm" ]; then
        # Un file con type e creator classici, come quelli dei vecchi dischi.
        printf 'documento' > "$vc/Lettera"
        xattr -w -x com.apple.FinderInfo \
            "54 45 58 54 4D 53 57 44 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" \
            "$vc/Lettera" 2>/dev/null
        # E sull'altro, roba di oggi e basta.
        printf 'niente di classico' > "$vm/appunti.txt"
        mkdir -p "$vm/una cartella"

        if swiftc -O -o "$b" tests/volumi/main.swift tests/support/Testi.swift \
                "Modules/Apps/Sources/Data - Classic Mac/VolumeClassico.swift" \
                "Modules/Apps/Sources/Data - Classic Mac/ClassicIcon.swift" 2>/dev/null; then
            uscita=$("$b" "$vc" "$vm" 2>&1)
            if [ $? -eq 0 ]; then
                ok "si osservano solo i volumi con roba classica: gli altri tengono la loro icona"
            else
                fail "la scelta dei volumi da osservare non torna" "$uscita"
            fi
        else
            fail "il test dei volumi non si compila"
        fi
    else
        printf '  \033[33m·\033[0m test dei volumi saltato (immagini non montate)\n'
    fi

    [ -n "$vc" ] && hdiutil detach "$vc" >/dev/null 2>&1
    [ -n "$vm" ] && hdiutil detach "$vm" >/dev/null 2>&1
    rm -rf "$d" "$b"
else
    printf '  \033[33m·\033[0m test dei volumi saltato (manca swiftc o hdiutil)\n'
fi

# 25. Il pannello: colonne allineate, pallini di stato, entitlement richiudibili,
#     sfondo trasparente.
#
# Quattro difetti che si vedono solo aprendo il pannello: due tabelle con la
# colonna delle etichette di larghezza diversa (con `max-content` ognuna si
# misura per conto suo), nessun segno che dica a colpo d'occhio se la firma e'
# a posto, gli entitlement di certe applicazioni lunghi una pagina e sempre
# aperti, e un rettangolo bianco dipinto sopra lo sfondo del pannello.
# ---------------------------------------------------------------------------
guasti=""
for tema in "" "-apparency"; do
    css="Modules/Apps/AppsResources/style$tema.css"
    cerca "grid-template-columns: var(--etichetta)" "$css" || guasti="$guasti $css: colonna non condivisa;"
    cerca "background: transparent" "$css" || guasti="$guasti $css: sfondo non trasparente;"
    cerca "segno.buono" "$css" || guasti="$guasti $css: manca il pallino verde;"
done
for modello in Modules/Apps/AppsResources/template.html Modules/Apps/AppsResources/template-apparency.html Modules/Apps/AppsResources/template-originale.html; do
    cerca "<details" "$modello" || guasti="$guasti $modello: entitlement non richiudibili;"
done
sed 's://.*::' "Modules/Apps/Sources/Data - macOS/MacApp.swift" | cerca "enum Segno" || guasti="$guasti manca la classificazione dei segni;"
if [ -z "$guasti" ]; then
    ok "il pannello: colonne condivise, pallini, entitlement richiudibili, sfondo trasparente"
else
    fail "il pannello ha perso una delle correzioni" "$guasti"
fi

# 26. L'agente lavora per cartella, non per disco.
#
# La richiesta era precisa: l'agente deve occuparsi **della cartella che viene
# aperta**, non percorrere il volume -- se no e' lavoro che nessuno ha chiesto e
# si sente. Senza l'estensione del Finder la cartella aperta si riconosce dal
# filesystem: aprendo una cartella il Finder ci scrive dentro il `.DS_Store`, e
# quell'evento e' il segnale.
#
# Il test lo prova per davvero: due finti programmi classici, uno nella radice e
# uno in una sottocartella. All'avvio l'agente deve dare l'icona **solo** a
# quello della radice; l'altro deve restare intatto finche' nella sua cartella
# non succede qualcosa.
# ---------------------------------------------------------------------------
if command -v swiftc >/dev/null 2>&1 && command -v hdiutil >/dev/null 2>&1; then
    d=$(mktemp -d -t agente)
    b=$(mktemp -t agente)
    hdiutil create -size 20m -fs HFS+ -volname ProvaAgente -ov "$d/disco.dmg" >/dev/null 2>&1
    # Montato **visibile**: l'agente salta i volumi nascosti, che nel Finder non
    # si aprono e quindi non hanno cartelle da guardare.
    punto=$(hdiutil attach "$d/disco.dmg" 2>/dev/null | awk '/\/Volumes\//{ $1=""; $2=""; sub(/^  */,""); print }')

    if [ -n "$punto" ] && swiftc -O -o "$b" Agent/main.swift tests/support/Testi.swift \
            "Modules/Apps/Sources/Data - Classic Mac/IconeAutomatiche.swift" \
            "Modules/Apps/Sources/Data - Classic Mac/VolumeClassico.swift" \
            "Modules/Apps/Sources/Data - Classic Mac/ClassicIcon.swift" \
            "Modules/Apps/Sources/Data - Classic Mac/ClassicIconWriter.swift" \
            "Modules/Apps/Sources/Data - Classic Mac/ConsensiDischi.swift" \
            "Modules/Apps/Sources/Data - Classic Mac/ForkBackup.swift" 2>/dev/null; then

        # I permessi di questa prova stanno in una cartella a parte: la prova non
        # deve toccare quelli dell'utente.
        export QLAPPBUNDLE_CONSENSI_PROVA="$d/consensi"
        mkdir -p "$d/consensi" "$punto/Cartella"
        python3 tests/agente/finta-app.py "$punto/AllaRadice" >/dev/null 2>&1
        python3 tests/agente/finta-app.py "$punto/Cartella/Programma" >/dev/null 2>&1

        # Il bit dell'icona personalizzata: byte 8 del FinderInfo, cioe' i
        # caratteri 17-18 della forma esadecimale senza spazi.
        segno() { xattr -p -x com.apple.FinderInfo "$1" 2>/dev/null | tr -d ' \n' | cut -c17-18; }

        # Prima senza permesso: l'agente deve chiedere, non scrivere.
        "$b" >/dev/null 2>&1 &
        agente=$!
        sleep 5
        senza_permesso=$(segno "$punto/AllaRadice")
        kill $agente 2>/dev/null
        wait $agente 2>/dev/null

        # Poi col permesso dato a questo disco, riconosciuto dal suo UUID.
        uuid=$(diskutil info "$punto" 2>/dev/null | awk -F': *' '/Volume UUID/{print $2}')
        printf '{"%s":{"nome":"ProvaAgente","stato":"consentito","data":0}}' "$uuid" > "$d/consensi/dischi.json"

        "$b" >/dev/null 2>&1 &
        agente=$!
        sleep 5
        radice=$(segno "$punto/AllaRadice")
        dentro_prima=$(segno "$punto/Cartella/Programma")

        # Quello che fa il Finder quando si apre una cartella.
        printf 'x' > "$punto/Cartella/.DS_Store"
        sleep 6
        dentro_dopo=$(segno "$punto/Cartella/Programma")
        kill $agente 2>/dev/null
        wait $agente 2>/dev/null   # se no la shell stampa «Terminated» in mezzo ai test

        if [ "$senza_permesso" = "00" ] && [ "$radice" = "04" ] && [ "$dentro_prima" = "00" ] && [ "$dentro_dopo" = "04" ]; then
            ok "l'agente non scrive senza permesso; col permesso da' l'icona alla cartella aperta, e solo a quella"
        else
            fail "l'agente non si comporta come deve" \
                 "senza permesso: $senza_permesso (atteso 00), radice: $radice (atteso 04), dentro prima: $dentro_prima (atteso 00), dentro dopo: $dentro_dopo (atteso 04), uuid: $uuid"
        fi
        unset QLAPPBUNDLE_CONSENSI_PROVA
    else
        printf '  \033[33m·\033[0m test dell'"'"'agente saltato (immagine non montata o agente non compilato)\n'
    fi

    [ -n "$punto" ] && hdiutil detach "$punto" >/dev/null 2>&1
    rm -rf "$d" "$b"
else
    printf '  \033[33m·\033[0m test dell'"'"'agente saltato (manca swiftc o hdiutil)\n'
fi

# 27. L'applicazione rimette le proprie estensioni, e non chiede prima.
#
# Un'estensione di QuickLook la registra macOS quando scopre l'app, non a ogni avvio: se quella registrazione salta,
# riaprire l'app non basta. Quindi a ogni avvio (da Applicazioni) l'app ripassa al sistema le sue estensioni.
# Il controllo del contrario non si può fare dentro la sandbox, quindi niente «prima controlla se manca».
# ---------------------------------------------------------------------------
guasti=""
senza_commenti=$(sed 's://.*::' App/ActivationView.swift)
echo "$senza_commenti" | cerca '"-a", url.path' \
    || guasti="$guasti non registra piu' con pluginkit -a;"
sed 's://.*::' App/QuickLookManagerApp.swift | cerca "ExtensionRegistrar.registerIfInstalled()" \
    || guasti="$guasti l'apertura dell'app non le ripassa piu' al sistema;"
if [ -z "$guasti" ]; then
    ok "l'app ripassa le proprie estensioni al sistema a ogni apertura"
else
    fail "il ripasso delle estensioni si e' rotto" "$guasti"
fi


echo "──────────────────────────────────────────────────────"
if [ "$FAILED" -gt 0 ]; then
    printf '\033[31m%d falliti\033[0m, %d passati\n' "$FAILED" "$PASSED"; exit 1
fi
printf '\033[32m%d passati\033[0m\n' "$PASSED"
