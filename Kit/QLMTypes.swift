// Generato da scripts/gen-types.py: non modificare a mano.
enum QLMTypes {
    static let apps: Set<String> = [
        "com.apple.application-and-system-extension",
        "com.apple.application-bundle",
        "com.apple.application-file",
        "com.apple.driver-extension",
        "com.apple.framework",
        "com.apple.itunes.ipa",
        "com.apple.kernel-extension",
        "com.apple.mach-o-dylib",
        "com.apple.plugin",
        "com.apple.system-extension",
        "com.apple.systempreference.prefpane",
        "com.apple.xcode.archive",
        "com.apple.xpc-service",
        "com.giovariot.quicklookmanager.classic-application",
        "com.giovariot.quicklookmanager.flatpak-bundle",
        "com.google.android.apk",
        "com.microsoft.windows-dynamic-link-library",
        "com.microsoft.windows-executable",
        "com.opa334.trollstore.tipa",
        "dyn.ah62d4rv4ge80c6dp",
        "dyn.ah62d4rv4ge80c6dpry",
        "dyn.ah62d4rv4ge80q5dbsv2gc42",
        "dyn.ah62d4rv4ge81k4puqe",
        "public.archive.apk",
    ]
    static let raw: Set<String> = [
        "com.adobe.raw-image",
        "com.anogeissus.arq",
        "com.anogeissus.x3f",
        "com.canon.cr2-raw-image",
        "com.canon.cr3-raw-image",
        "com.canon.crw-raw-image",
        "com.epson.raw-image",
        "com.fuji.raw-image",
        "com.gopro.gpr",
        "com.hasselblad.3fr-raw-image",
        "com.hasselblad.fff-raw-image",
        "com.kodak.raw-image",
        "com.konicaminolta.raw-image",
        "com.leafamerica.raw-image",
        "com.leica.rwl-raw-image",
        "com.nikon.nrw-raw-image",
        "com.nikon.raw-image",
        "com.olympus.raw-image",
        "com.panasonic.raw-image",
        "com.panasonic.rw2-raw-image",
        "com.pentax.raw-image",
        "com.phaseone.raw-image",
        "com.samsung.raw-image",
        "com.sigmaphoto.photopro-x3f",
        "com.sony.arw-raw-image",
        "com.sony.raw-image",
        "com.sony.sr2-raw-image",
        "public.camera-raw-image",
    ]
    static let models: Set<String> = [
        "com.bambulab.3mf",
        "com.preview3mf.3mf-file",
        "com.shapr3d.3d-manufacturing.3mf",
    ]
    static let eps: Set<String> = [
        "com.adobe.encapsulated-postscript",
    ]
    static let archives: Set<String> = [
        "com.apple.xar-archive",
        "com.facebook.zstd-archive",
        "com.microsoft.cab",
        "com.rarlab.rar-archive",
        "com.redhat.rpm-archive",
        "org.7-zip.7-zip-archive",
        "org.debian.deb-archive",
        "org.gnu.gnu-zip-archive",
        "org.gnu.gnu-zip-tar-archive",
        "org.tukaani.lzma-archive",
        "org.tukaani.tar-xz-archive",
        "org.tukaani.xz-archive",
        "public.bzip2-archive",
        "public.cpio-archive",
        "public.iso-image",
        "public.lha-archive",
        "public.tar-archive",
        "public.tar-bzip2-archive",
        "public.zip-archive",
    ]
    static let video: Set<String> = [
        "com.adobe.flash.video",
        "com.giovariot.quicklookmanager.divx",
        "com.giovariot.quicklookmanager.m2ts",
        "com.giovariot.quicklookmanager.mxf",
        "com.giovariot.quicklookmanager.realmedia",
        "com.giovariot.quicklookmanager.vob",
        "com.microsoft.advanced-systems-format",
        "com.microsoft.windows-media-wmv",
        "org.matroska.mka",
        "org.matroska.mkv",
        "org.webmproject.webm",
        "org.xiph.ogv",
        "public.avi",
    ]
    static let pkg: Set<String> = [
        "com.apple.installer-meta-package",
        "com.apple.installer-package-archive",
    ]

    /// Il modulo che dichiara questo tipo (UTI in minuscolo), se ce n'è uno; il testo non ha un elenco proprio.
    static func module(forType uti: String) -> QLMModule? {
        if apps.contains(uti) { return .apps }
        if raw.contains(uti) { return .raw }
        if models.contains(uti) { return .models }
        if eps.contains(uti) { return .eps }
        if archives.contains(uti) { return .archives }
        if video.contains(uti) { return .video }
        if pkg.contains(uti) { return .pkg }
        return nil
    }
}
