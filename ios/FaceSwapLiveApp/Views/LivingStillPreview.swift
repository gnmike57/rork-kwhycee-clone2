import SwiftUI
import UIKit

/// Frame Check's view of the same renderer the page receives.
struct LivingStillPreview: View {
    let image: UIImage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Living still")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("The same picture the page is drawing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Color.clear
                .aspectRatio(max(image.size.width, 1) / max(image.size.height, 1), contentMode: .fit)
                .frame(maxHeight: 240)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 16))
                .accessibilityLabel("Living still preview")
        }
    }
}
