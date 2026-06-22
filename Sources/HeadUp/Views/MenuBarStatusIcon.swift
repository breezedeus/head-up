import AppKit
import SwiftUI

struct MenuBarStatusIcon: View {
    let status: PostureStatus

    var body: some View {
        Image(nsImage: HeadUpIconResource.image(named: status.menuBarIconName, pointHeight: 16))
            .renderingMode(.template)
    }
}
