//
//  ContentView.swift
//  askLunar
//
//  Created by PeterReturn on 17/1/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var drawnCard: TarotSession?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            if let card = drawnCard {
                VStack {
                    Image(card.cardName)  // Remove TarotCard/ prefix since folder is not namespaced
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 300)
                        .onAppear {
                            #if DEBUG
                            print("Debug: Loading card image: \(card.cardName)")
                            if let _ = UIImage(named: card.cardName) {
                                errorMessage = nil
                            } else {
                                errorMessage = "Image not found: \(card.cardName)"
                            }
                            #endif
                        }
                    Text(card.cardName)
                        .font(.title)
                    Text(card.interpretation)
                        .padding()
                    Button(action: drawCard) {
                        Text("Draw Another Card")
                            .padding()
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                }
            } else {
                VStack {
                    Image("TarotDeck")  // Changed to use TarotDeck image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 300)
                        .onAppear {
                            print("Debug: Loading default TarotDeck image")
                        }
                    Button(action: drawCard) {
                        Text("Draw Card")
                            .padding()
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                }
            }
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .padding()
    }

    private func drawCard() {
        isLoading = true
        fetchTarotCard { cardName, interpretation in
            let newCard = TarotSession(timestamp: Date(), cardName: cardName, cardImage: cardName, interpretation: interpretation)
            // Remove TarotCard/ prefix since folder is not namespaced
            modelContext.insert(newCard)
            drawnCard = newCard
            isLoading = false
        }
    }

    private func fetchTarotCard(completion: @escaping (String, String) -> Void) {
        guard let url: URL = URL(string: "https://dev.xiangci.net/api/tarot/one-card") else { 
            errorMessage = "Invalid URL"
            isLoading = false
            return 
        }
        
        let task: URLSessionDataTask = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data: Data = data, error == nil else { 
                DispatchQueue.main.async {
                    errorMessage = "Failed to fetch card"
                    isLoading = false
                }
                return 
            }
            
            if let json: [String : Any] = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let cardName: String = json["cardName"] as? String,
               let interpretation: String = json["interpretation"] as? String {
                DispatchQueue.main.async {
                    completion(cardName, interpretation)
                }
            } else {
                DispatchQueue.main.async {
                    errorMessage = "Invalid response from server"
                    isLoading = false
                }
            }
        }
        
        task.resume()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TarotSession.self, inMemory: true)
}
