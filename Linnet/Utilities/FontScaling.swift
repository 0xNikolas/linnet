import SwiftUI

extension Font {
    /// Scaled system font. Reads the user's font size offset from UserDefaults.
    /// Default offset is +2pt from the base size.
    static func app(
        size: CGFloat,
        weight: Weight = .regular,
        design: Design = .default
    ) -> Font {
        let offset = CGFloat(UserDefaults.standard.double(forKey: "fontSizeOffset"))
        return .system(size: size + offset, weight: weight, design: design)
    }
}
