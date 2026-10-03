import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// A QR code of the address to copy. Live Link Face has no scan-to-add, so
/// this is a readable version of the string, not a way to add a target.
struct LinkQRCodeView: View {
    let message: String

    var body: some View {
        if let image = Self.image(for: message) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(6)
                .background(.white, in: .rect(cornerRadius: 8))
        } else {
            Color.white.opacity(0.06)
                .aspectRatio(1, contentMode: .fit)
        }
    }

    /// One shared rendering context; CIContext is thread-safe and costly to
    /// build per render.
    nonisolated(unsafe) private static let context = CIContext()

    nonisolated static func image(for message: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
