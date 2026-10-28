"""Un finto programma Macintosh classico, con l'icona nel fork di risorse.

Serve ai test dell'agente: un file con type APPL, creator PNnu e un fork che
contiene BNDL, FREF, ICN# e icl8 -- cioe' la catena che il Finder del 1984
seguiva per trovare l'icona di un'applicazione, e che il nostro lettore segue
ancora. Senza la variante a colori (icl8) l'icns non si costruisce: l'ICN# da
sola e' in bianco e nero.

    python3 finta-app.py /percorso/del/file
"""
import struct, subprocess, sys

def risorsa(tipo, ident, dati):
    return (tipo, ident, dati)

def fork(risorse):
    dati = b""
    posizioni = {}
    for tipo, ident, contenuto in risorse:
        posizioni[(tipo, ident)] = len(dati)
        dati += struct.pack(">I", len(contenuto)) + contenuto

    tipi = {}
    for tipo, ident, _ in risorse:
        tipi.setdefault(tipo, []).append(ident)

    areaTipi = 2 + 8 * len(tipi)
    # L'intestazione della mappa: 16 byte di copia dell'intestazione del fork,
    # 4 per il prossimo handle, 2 per il riferimento al file, 2 di attributi.
    # I due scostamenti (lista dei tipi, lista dei nomi) stanno **dentro** i 28
    # byte, ai byte 24 e 26: scriverli dopo un bytearray(28) li mette quattro
    # byte piu' in la' e i tipi escono vuoti.
    mappa = bytearray(24)
    riferimenti = b""
    voci = b""
    scost = areaTipi
    for tipo, identificativi in tipi.items():
        voci += tipo.encode("mac-roman") + struct.pack(">HH", len(identificativi) - 1, scost)
        for ident in identificativi:
            off = posizioni[(tipo, ident)]
            riferimenti += struct.pack(">hH", ident, 0xFFFF) + bytes([0]) + off.to_bytes(3, "big") + b"\x00\x00\x00\x00"
        scost += 12 * len(identificativi)

    listaTipi = struct.pack(">H", len(tipi) - 1) + voci + riferimenti
    mappa += struct.pack(">HH", 28, 28 + len(listaTipi))
    mappa += listaTipi

    testa = struct.pack(">IIII", 256, 256 + len(dati), len(dati), len(mappa))
    intero = bytearray(testa + b"\x00" * (256 - len(testa)) + dati + bytes(mappa))
    intero[256 + len(dati):256 + len(dati) + 16] = testa   # la copia dell'intestazione
    return bytes(intero)

# ICN#: 128 byte di icona + 128 di maschera. Un quadrato pieno, che si vede.
icona = b"\xff\xff\xff\xff" * 32
maschera = b"\xff\xff\xff\xff" * 32
icn = icona + maschera

# icl8: la stessa icona a colori, 32x32 byte di indici nella tavolozza. Senza
# una variante a colori l'icns non si costruisce -- l'`ICN#` da sola e' in
# bianco e nero, e il pannello vuole il colore.
icl8 = bytes([0x1d]) * (32 * 32)

# BNDL: creator, versione, due tipi (FREF e ICN#), ognuno con una coppia
# «identificativo locale → identificativo della risorsa».
bndl = b"PNnu" + struct.pack(">HH", 0, 1)
bndl += b"FREF" + struct.pack(">H", 0) + struct.pack(">HH", 0, 128)
bndl += b"ICN#" + struct.pack(">H", 0) + struct.pack(">HH", 0, 128)

# FREF: il tipo di file che descrive (APPL) e l'icona locale.
fref = b"APPL" + struct.pack(">H", 0) + bytes([0])

f = fork([("BNDL", 128, bndl), ("FREF", 128, fref), ("ICN#", 128, icn), ("icl8", 128, icl8)])
percorso = sys.argv[1]
open(percorso, "wb").write(b"M" * 2048)
subprocess.run(["xattr", "-w", "-x", "com.apple.ResourceFork", f.hex(), percorso], check=True)
subprocess.run(["xattr", "-w", "-x", "com.apple.FinderInfo",
                "41 50 50 4C 50 4E 6E 75" + " 00" * 24, percorso], check=True)
print(f"scritto {percorso}: fork di {len(f)} byte")
