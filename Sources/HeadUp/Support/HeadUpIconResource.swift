import AppKit
import Foundation

enum HeadUpIconResource {
    static func image(named name: String, pointHeight: CGFloat) -> NSImage {
        let mainBundleURL = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "MenuBarIcons"
        )
        let packageURL = Bundle.module.url(forResource: name, withExtension: "png")

        guard let url = mainBundleURL ?? packageURL,
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil) ?? NSImage()
        }

        image.isTemplate = true
        let aspectRatio = image.size.width / image.size.height
        image.size = NSSize(width: pointHeight * aspectRatio, height: pointHeight)
        return image
    }
}
