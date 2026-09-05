import AppKit

@MainActor
final class FinderServiceProvider: NSObject {
    private let handler: ([URL]) -> Void

    init(handler: @escaping ([URL]) -> Void) {
        self.handler = handler
    }

    @objc func inspect(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        guard !urls.isEmpty else {
            error.pointee = "Finder did not provide a file or folder to inspect."
            return
        }
        handler(urls)
    }
}
