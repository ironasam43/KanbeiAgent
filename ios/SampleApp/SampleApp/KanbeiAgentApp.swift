//
//  KanbeiAgentApp.swift
//  KanbeiAgent
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
    .defaultSize(width: 800, height: 600)
    .windowResizability(.contentMinSize)
  }
}
