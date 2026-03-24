//
//  ContentView.swift
//  KanbeiAgent
//

import SwiftUI
import KanbeiAgentCore

struct ContentView: View {
  var body: some View {
    ChatView(context: SimpleAgentContext(
      workingDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
    ))
    .frame(minWidth: 600, minHeight: 500)
  }
}
