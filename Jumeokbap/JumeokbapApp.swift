//
//  JumeokbapApp.swift
//  Jumeokbap
//
//  Created by logan on 10/7/25.
//

import SwiftUI

@main
struct JumeokbapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView(timerManager: appDelegate.timerManager)
                .frame(width: 300, height: 350)
        }
    }
}
