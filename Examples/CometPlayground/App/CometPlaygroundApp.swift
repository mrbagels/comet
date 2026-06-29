import Dependencies
import SwiftUI

@main
struct CometPlaygroundApp: App {
  init() {
    prepareDependencies {
      $0.bootstrapDatabase()
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
    }
  }
}
