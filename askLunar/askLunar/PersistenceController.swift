//
//  PersistenceController.swift
//  askLunar
//
//  Created on 4/30/24
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "TarotDataModel")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
    }
    
    // MARK: - Core Data Helper Methods
    
    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    // Helper methods for TarotSession
    func createTarotSession(timestamp: Date, cardName: String, cardImage: String, interpretation: String) -> TarotSession {
        let context = container.viewContext
        let session = TarotSession(context: context)
        session.timestamp = timestamp
        session.cardName = cardName
        session.cardImage = cardImage
        session.interpretation = interpretation
        save()
        return session
    }
    
    func fetchTarotSessions() -> [TarotSession] {
        let context = container.viewContext
        let fetchRequest = NSFetchRequest<TarotSession>(entityName: "TarotSession")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            return try context.fetch(fetchRequest)
        } catch {
            print("Error fetching tarot sessions: \(error)")
            return []
        }
    }
    
    func deleteTarotSession(_ session: TarotSession) {
        let context = container.viewContext
        context.delete(session)
        save()
    }
} 