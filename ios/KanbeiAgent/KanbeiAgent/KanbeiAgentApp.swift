//
//  KanbeiAgentApp.swift
//  KanbeiAgent
//
//  Created by 小林 正徳 on 2026/03/22.
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
