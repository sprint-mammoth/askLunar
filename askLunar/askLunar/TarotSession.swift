//
//  TarotSession.swift
//  askLunar
//
//  Created by PeterReturn on 17/1/25.
//

import Foundation
import CoreData

// This class is marked as public to be accessible across the app
@objc(TarotSession)
public class TarotSession: NSManagedObject, Identifiable {
    @NSManaged public var timestamp: Date?
    @NSManaged public var cardName: String?
    @NSManaged public var cardImage: String?
    @NSManaged public var interpretation: String?
    
    // Computed properties for ensuring non-nil values
    public var wrappedTimestamp: Date {
        timestamp ?? Date()
    }
    
    public var wrappedCardName: String {
        cardName ?? "Unknown Card"
    }
    
    public var wrappedCardImage: String {
        cardImage ?? "default_card"
    }
    
    public var wrappedInterpretation: String {
        interpretation ?? "No interpretation available"
    }
}

// MARK: - Core Data Support
extension TarotSession {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TarotSession> {
        return NSFetchRequest<TarotSession>(entityName: "TarotSession")
    }
    
    convenience init(context: NSManagedObjectContext, timestamp: Date, cardName: String, cardImage: String, interpretation: String) {
        self.init(context: context)
        self.timestamp = timestamp
        self.cardName = cardName
        self.cardImage = cardImage
        self.interpretation = interpretation
    }
}
