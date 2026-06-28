import Dependencies
import SwiftUI

@main
struct CometPlaygroundApp: App {
  init() {
    prepareDependencies {
      try! $0.bootstrapDatabase()
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
    }
  }
}
