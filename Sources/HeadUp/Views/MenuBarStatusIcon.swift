import AppKit
import SwiftUI

struct MenuBarStatusIcon: View {
    let status: PostureStatus

    var body: some View {
        Image(nsImage: MenuBarIconLoader.image(named: status.menuBarIconName))
            .renderingMode(.template)
    }
}

private enum MenuBarIconLoader {
    static func image(named name: String) -> NSImage {
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
        let targetHeight = 16.0
        let aspectRatio = image.size.width / image.size.height
        image.size = NSSize(width: targetHeight * aspectRatio, height: targetHeight)
        return image
    }
}
