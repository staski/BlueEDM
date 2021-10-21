//
//  BlueEDMApp.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 27.09.21.
//

import SwiftUI

@main
struct BlueEDMApp: App {
    @StateObject var edm = EDMBluetoothManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(edm)
        }.onChange(of: scenePhase) { phase in
            if phase == .active {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            if phase == .background {
                
            }
        }
    }
}
