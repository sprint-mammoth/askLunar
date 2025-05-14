//
//  ContentView.swift
//  askLunar
//
//  Created by PeterReturn on 17/1/25.
//

import SwiftUI
import CoreData
import AuthenticationServices

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var authService = AuthenticationService()
    @State private var drawnCard: TarotSession?
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack {
                if authService.isAuthenticated {
                    // User info section
                    VStack {
                        if let userInfo = authService.userInfo {
                            Text("Welcome!")
                                .font(.title)
                            if let email = userInfo.email {
                                Text("Email: \(email)")
                            }
                            if let fullName = userInfo.fullName {
                                Text("Name: \(fullName)")
                            }
                            Text("User ID: \(userInfo.id)")
                        }
                        
                        Button("Sign Out") {
                            authService.signOut()
                        }
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.red)
                        .cornerRadius(8)
                    }
                    .padding()
                    
                    Divider()
                    
                    // Tarot card section
                    if let card = drawnCard {
                        VStack {
                            Image(card.wrappedCardName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 300)
                            Text(card.wrappedCardName)
                                .font(.title)
                            Text(card.wrappedInterpretation)
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
                            Image("TarotDeck")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 300)
                            Button(action: drawCard) {
                                Text("Draw Card")
                                    .padding()
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoading)
                        }
                    }
                } else {
                    VStack {
                        Text("Welcome to askLunar")
                            .font(.title)
                            .padding()
                        
                        SignInWithAppleButton(
                            .signIn,
                            onRequest: { request in
                                request.requestedScopes = [.fullName, .email]
                            },
                            onCompletion: { _ in
                                // We don't need to handle the result here as it's handled by the AuthenticationService delegate
                                print("Debug: Apple Sign In button tapped")
                            }
                        )
                        .frame(width: 280, height: 45)
                        .padding()
                        
                        NavigationLink {
                            TarotReadingViewControllerRepresentable()
                                .ignoresSafeArea()
                        } label: {
                            Text("Try Tarot Stream Test")
                                .padding()
                                .foregroundColor(.white)
                                .frame(width: 280)
                                .background(Color.purple)
                                .cornerRadius(8)
                        }
                        .padding(.top, 8)
                        
                        NavigationLink {
                            StreamTextViewControllerRepresentable()
                                .ignoresSafeArea()
                        } label: {
                            Text("Try Stream Text Demo")
                                .padding()
                                .foregroundColor(.white)
                                .frame(width: 280)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                        .padding(.top, 8)
                        
                        NavigationLink {
                            SUStreamTextView()
                        } label: {
                            Text("Try SwiftUI Stream Text")
                                .padding()
                                .foregroundColor(.white)
                                .frame(width: 280)
                                .background(Color.green)
                                .cornerRadius(8)
                        }
                        .padding(.top, 8)
                        
                        if let error = authService.errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .padding()
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Ask Lunar")
            .toolbar {
                // Removing the toolbar item since we've moved it to the main view
            }
        }
    }
    
    private func drawCard() {
        isLoading = true
        fetchTarotCard { cardName, interpretation in
            let newCard = PersistenceController.shared.createTarotSession(
                timestamp: Date(),
                cardName: cardName,
                cardImage: cardName,
                interpretation: interpretation
            )
            drawnCard = newCard
            isLoading = false
        }
    }
    
    private func fetchTarotCard(completion: @escaping (String, String) -> Void) {
        guard let url = URL(string: "https://dev.xiangci.net/api/tarot/one-card") else { 
            authService.errorMessage = "Invalid URL"
            isLoading = false
            return 
        }
        
        var request = URLRequest(url: url)
        authService.addAuthorizationHeader(to: &request)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { 
                DispatchQueue.main.async {
                    authService.errorMessage = "Failed to fetch card"
                    isLoading = false
                }
                return 
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let cardName = json["cardName"] as? String,
               let interpretation = json["interpretation"] as? String {
                DispatchQueue.main.async {
                    completion(cardName, interpretation)
                }
            } else {
                DispatchQueue.main.async {
                    authService.errorMessage = "Invalid response from server"
                    isLoading = false
                }
            }
        }
        
        task.resume()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
