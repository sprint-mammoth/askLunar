//
//  TarotSession.swift
//  askLunar
//
//  Created by PeterReturn on 17/1/25.
//

import Foundation
import SwiftData

@Model
final class TarotSession {
    var timestamp: Date
    var cardName: String
    var cardImage: String
    var interpretation: String
    
    init(timestamp: Date, cardName: String, cardImage: String, interpretation: String) {
        self.timestamp = timestamp
        self.cardName = cardName
        self.cardImage = cardImage
        self.interpretation = interpretation
    }
}
