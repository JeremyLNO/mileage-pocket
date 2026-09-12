import SwiftUI

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "car.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.tint)
            Text(verbatim: "Mileage Pocket")
                .font(.largeTitle.bold())
        }
    }
}

#Preview {
    RootView()
}
