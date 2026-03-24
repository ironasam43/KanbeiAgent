//
//  KanbeiAgentApp.swift
//  KanbeiAgentIOS
//

import SwiftUI
import KanbeiAgentCore

@main
struct KanbeiAgentApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(TokenUsageStore.shared)
    }
  }
}
