//
//  askLunarApp.swift
//  askLunar
//
//  Created by PeterReturn on 17/1/25.
//

import SwiftUI

@main
struct askLunarApp: App {
    // This singleton manages the Core Data stack
    let persistenceController = PersistenceController.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
