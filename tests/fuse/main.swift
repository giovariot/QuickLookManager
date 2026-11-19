import Foundation

// Su un volume montato da un driver FUSE non si scrive: l'icona la fa già il
// driver, e la copia del fork originale non verrebbe conservata.
//
// Con macFUSE il volume si riconosce dal tipo ("macfuse_hfs"). Con FUSE-T no:
// passa da un server NFS locale e il kernel lo chiama "nfs". Lo si riconosce
// dall'origine del mount, "fuse-t:/Nome". Prima il controllo guardava solo il
// tipo, e un volume di FuseMac montato con FUSE-T passava per scrivibile.

var errori: [String] = []
func pretendi(_ condizione: Bool, _ cosa: String) {
    if !condizione { errori.append(cosa) }
}

pretendi(VolumeClassico.eFuse(tipo: "macfuse_hfs", origine: "/dev/disk4"),
         "un volume HFS di FuseMac con macFUSE non è riconosciuto")
pretendi(VolumeClassico.eFuse(tipo: "macfuse_mfs", origine: "/dev/disk5"),
         "un volume MFS di FuseMac con macFUSE non è riconosciuto")
pretendi(VolumeClassico.eFuse(tipo: "fusefs", origine: "qualcosa"),
         "un filesystem FUSE generico non è riconosciuto")
pretendi(VolumeClassico.eFuse(tipo: "nfs", origine: "fuse-t:/System 7"),
         "un volume montato con FUSE-T (nfs) passa per scrivibile")
pretendi(VolumeClassico.eFuse(tipo: "smbfs", origine: "//Guest:@fuse-t/System 7"),
         "un volume montato con FUSE-T (smb) passa per scrivibile")

// E i volumi veri non devono essere scambiati per FUSE.
pretendi(!VolumeClassico.eFuse(tipo: "apfs", origine: "/dev/disk3s1"), "APFS scambiato per FUSE")
pretendi(!VolumeClassico.eFuse(tipo: "hfs", origine: "/dev/disk6s2"), "HFS+ scambiato per FUSE")
pretendi(!VolumeClassico.eFuse(tipo: "nfs", origine: "server:/export/home"), "un NFS vero scambiato per FUSE")
pretendi(!VolumeClassico.eFuse(tipo: "smbfs", origine: "//utente@nas/Dati"), "un SMB vero scambiato per FUSE")

if errori.isEmpty { exit(0) }
for e in errori { print(e) }
exit(1)
