import SwiftUI

enum AppTab: Hashable {
  case home
  case proofs
  case activity
}

struct RootView: View {
  @State private var model = DemoCatalog()
  @State private var selectedTab: AppTab = .home

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Home", systemImage: "sparkles", value: .home) {
        HomeTab(model: model, selectedTab: $selectedTab)
      }

      Tab("Proofs", systemImage: "checklist", value: .proofs) {
        ProofsTab(model: model)
      }

      Tab("Activity", systemImage: "waveform.path.ecg", value: .activity) {
        ActivityTab(model: model)
      }
    }
    .tint(ThemeColor.ocean)
    .background(PlaygroundBackdrop())
  }
}
