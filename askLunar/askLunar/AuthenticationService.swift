import Foundation
import AuthenticationServices
import UIKit

class AuthenticationService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var userInfo: UserInfo?
    @Published var errorMessage: String?
    
    private var accessToken: String?
    private let baseURL = "https://dev.xiangci.top/api"
    
    struct UserInfo: Codable {
        let id: String
        let email: String?
        let fullName: String?
    }
    
    struct LoginResponse: Codable {
        let access_token: String
        let token_type: String
        let expires_in: Int
    }
    
    func signInWithApple() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        
        // Get the window scene and its first window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            authorizationController.presentationContextProvider = window.rootViewController as? ASAuthorizationControllerPresentationContextProviding
        }
        
        authorizationController.performRequests()
    }
    
    // Public method to add authorization header to requests
    func addAuthorizationHeader(to request: inout URLRequest) {
        if let accessToken = accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
    }
    
    private func authenticateWithBackend(idToken: String) {
        guard let url = URL(string: "\(baseURL)/auth/login") else {
            self.errorMessage = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["id_token": idToken]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }
                
                do {
                    let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
                    self?.accessToken = loginResponse.access_token
                    self?.isAuthenticated = true
                    self?.fetchUserInfo()
                } catch {
                    self?.errorMessage = "Failed to parse login response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func fetchUserInfo() {
        guard let url = URL(string: "\(baseURL)/user/me") else {
            self.errorMessage = "Invalid URL or missing access token"
            return
        }
        
        var request = URLRequest(url: url)
        addAuthorizationHeader(to: &request)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Failed to fetch user info: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No user data received"
                    return
                }
                
                do {
                    let userInfo = try JSONDecoder().decode(UserInfo.self, from: data)
                    self?.userInfo = userInfo
                } catch {
                    self?.errorMessage = "Failed to parse user info: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func signOut() {
        accessToken = nil
        userInfo = nil
        isAuthenticated = false
    }
}

extension AuthenticationService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
           let identityToken = appleIDCredential.identityToken,
           let idToken = String(data: identityToken, encoding: .utf8) {
            print("Debug: Successfully got Apple ID token")
            authenticateWithBackend(idToken: idToken)
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("Debug: Apple Sign In failed with error: \(error.localizedDescription)")
        self.errorMessage = "Sign in failed: \(error.localizedDescription)"
    }
} 