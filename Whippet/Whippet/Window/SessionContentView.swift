import SwiftUI

/// Placeholder SwiftUI view displayed inside the floating session panel.
///
/// This view will be replaced with the full session list UI in Step 6.
/// For now it shows a minimal placeholder to verify NSHostingController integration.
struct SessionContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dog.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("Whippet Sessions")
                .font(.headline)

            Text("No sessions yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
