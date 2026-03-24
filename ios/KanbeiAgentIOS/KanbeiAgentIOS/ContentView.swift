//
//  ContentView.swift
//  KanbeiAgentIOS
//

import SwiftUI
import KanbeiAgentCore

struct ContentView: View {
  var body: some View {
    ChatView(context: SimpleAgentContext(
      workingDirectoryURL: FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask
      ).first!
    ))
  }
}
