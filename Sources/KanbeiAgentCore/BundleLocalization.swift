//
//  BundleLocalization.swift
//  KanbeiAgentCore
//

import Foundation

extension Bundle {
  /// SPM resource bundles don't include CFBundleLocalizations in Info.plist, so
  /// this helper avoids the issue where Bundle.localizations doesn't work properly.
  /// It uses Locale.preferredLanguages to directly get the system's preferred language,
  /// and returns the corresponding .lproj bundle.
  static var localizedModule: Bundle {
    for lang in Locale.preferredLanguages {
      let code = lang.components(separatedBy: "-").first ?? lang
      if let url = module.url(forResource: code, withExtension: "lproj"),
         let b = Bundle(url: url) {
        return b
      }
    }
    return .module
  }
}
