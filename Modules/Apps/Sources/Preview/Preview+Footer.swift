import Foundation

extension PreviewGenerator {
	/// Process meta information about the plugin. Like version and debug flag.
	mutating func procFooterInfo() {
		self.apply([
			"SrcAppName": "QuickLook Manager",
			"SrcLinkUrl": "https://github.com/giovariot/QuickLookManager",
			"SrcLinkName": "giovariot/QuickLookManager",
			"SrcVersion": QLMBundle.hostInfo?["CFBundleShortVersionString"] as? String ?? "",
			"SrcBuildVer": QLMBundle.hostInfo?["CFBundleVersion"] as? String ?? "",
		])
#if DEBUG
		self.data["SrcAppName"]! += " (debug)"
#endif
	}
}
