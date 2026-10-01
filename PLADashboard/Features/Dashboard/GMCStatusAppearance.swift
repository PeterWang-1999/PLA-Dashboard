import SwiftUI
import AppKit

/// 列表与详情共用目录完整性提示颜色，随当前视图的系统外观解析。
enum GMCStatusAppearance {
    static let listIcon = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 0.65, blue: 0.22, alpha: 1)
            : NSColor(srgbRed: 0.80, green: 0.36, blue: 0.02, alpha: 1)
    })

    static let foreground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 0.78, blue: 0.35, alpha: 1)
            : NSColor(srgbRed: 0.45, green: 0.28, blue: 0.02, alpha: 1)
    })

    static let background = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.20, green: 0.17, blue: 0.10, alpha: 1)
            : NSColor(srgbRed: 1, green: 0.96, blue: 0.86, alpha: 1)
    })
}
