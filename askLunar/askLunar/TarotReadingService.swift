import Foundation

// 统一错误类型
enum TarotError: Error {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(message: String)
    case networkError(Error)
    case maxRetriesExceeded
}

// SSE事件模型
struct SSEEvent {
    let type: String
    let data: String
    let id: String?
    let retry: TimeInterval?
}

// 状态管理actor
actor TarotStateManager {
    private(set) var openingText = ""
    private(set) var interpretationText = ""
    private(set) var oneLinerText = ""
    
    func resetAll() {
        openingText = ""
        interpretationText = ""
        oneLinerText = ""
    }
    
    // 合并读写操作减少Actor同步开销
    func updateAndGetOpeningText(_ text: String, append: Bool = true) -> String {
        if append {
            openingText += text
        } else {
            openingText = text
        }
        return openingText
    }
    
    // 合并读写操作减少Actor同步开销
    func updateAndGetInterpretationText(_ text: String, append: Bool = true) -> String {
        if append {
            interpretationText += text
        } else {
            interpretationText = text
        }
        return interpretationText
    }
    
    // 合并读写操作减少Actor同步开销
    func updateAndGetOneLinerText(_ text: String) -> String {
        oneLinerText = text
        return oneLinerText
    }
}

class TarotReadingService: NSObject {
    // AsyncStream continuations
    private var openingContinuation: AsyncStream<String>.Continuation?
    private var interpretationContinuation: AsyncStream<String>.Continuation?
    private var oneLinerContinuation: AsyncStream<String>.Continuation?
    
    // Public AsyncStreams
    lazy var openingStream: AsyncStream<String> = {
        AsyncStream { [weak self] continuation in
            self?.openingContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.openingContinuation = nil
            }
        }
    }()
    
    lazy var interpretationStream: AsyncStream<String> = {
        AsyncStream { [weak self] continuation in
            self?.interpretationContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.interpretationContinuation = nil
            }
        }
    }()
    
    lazy var oneLinerStream: AsyncStream<String> = {
        AsyncStream { [weak self] continuation in
            self?.oneLinerContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.oneLinerContinuation = nil
            }
        }
    }()
    
    // State manager using actor for thread safety
    private let stateManager = TarotStateManager()
    
    // JWT Token for authentication
    private var authToken: String?
    
    // URLSession for streaming
    private var urlSession: URLSession!
    private var urlSessionTask: URLSessionTask?
    
    // Task to manage event stream
    private var streamTask: Task<Void, Never>?
    
    // Buffer for partial data
    private var eventBuffer = ""
    
    // Retry configuration
    private var retryCount = 0
    private let maxRetries = 3
    private var baseRetryDelay: TimeInterval = 2.0
    private var lastEventId: String?
    private var currentRetryDelay: TimeInterval = 3.0
    
    // Reading parameters for retries
    private var lastReadingParameters: (card: String, cardId: Int, orientation: String, spreadId: String)?
    
    // Completion handler for notifying status
    private var onCompleted: (() -> Void)?
    private var onError: ((Error) -> Void)?
    
    override convenience init() {
        self.init(authToken: nil, onCompleted: nil, onError: nil)
    }
    
    init(authToken: String? = nil, onCompleted: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        super.init()
        self.authToken = authToken
        self.onCompleted = onCompleted
        self.onError = onError
        setupURLSession()
    }
    
    deinit {
        print("TarotReadingService deinitializing...") // 调试生命周期
        cancelReading()
        urlSession.invalidateAndCancel() // 确保session释放
        print("TarotReadingService deinitialized") // 确认清理完成
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes for long connections
        config.timeoutIntervalForResource = 300
        
        // Disable HTTP pipelining to ensure immediate delivery of SSE chunks
        config.httpShouldUsePipelining = false
        
        // Prevent caching of streaming data
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        urlSession = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil
        )
    }
    
    /// Set the authentication token
    func setAuthToken(_ token: String?) {
        self.authToken = token
    }
    
    /// Set completion handlers
    func setCompletionHandlers(onCompleted: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        self.onCompleted = onCompleted
        self.onError = onError
    }
    
    func getReading(for card: String, cardId: Int = 1, orientation: String = "upright", spreadId: String = "spread_01") {
        // Store parameters for potential retries
        lastReadingParameters = (card: card, cardId: cardId, orientation: orientation, spreadId: spreadId)
        
        // Reset retry count for new readings
        if retryCount > 0 {
            print("Attempting retry #\(retryCount)")
        } else {
            retryCount = 0
        }
        
        cancelReading()
        
        // Initialize streams if needed
        _ = openingStream
        _ = interpretationStream
        _ = oneLinerStream
        
        // Start a task to handle the SSE stream
        streamTask = Task {
            do {
                // Reset state
                await stateManager.resetAll()
                
                // Create and configure request
                let request = try self.createRequest(
                    for: card,
                    cardId: cardId,
                    orientation: orientation,
                    spreadId: spreadId
                )
                
                print("Starting SSE stream request to: \(request.url?.absoluteString ?? "unknown URL")")
                
                // Start the URLSession task
                let task = urlSession.dataTask(with: request)
                
                // Store task reference on main thread
                await MainActor.run {
                    self.urlSessionTask = task
                    self.eventBuffer = ""
                }
                
                task.resume()
                print("SSE data task started")
                
                // Keep task alive until cancelled (iOS 15 compatible)
                try await Task.sleep(nanoseconds: 300_000_000_000) // 300 seconds = 5 minutes
            } catch {
                if error is CancellationError {
                    print("SSE stream task cancelled normally")
                } else {
                    print("Error in SSE stream task: \(error.localizedDescription)")
                    // Notify error handler if available
                    await MainActor.run {
                        self.onError?(TarotError.networkError(error))
                    }
                    
                    // Consider retry for network errors
                    self.scheduleRetryIfNeeded()
                }
            }
        }
    }
    
    private func createRequest(for card: String, cardId: Int, orientation: String, spreadId: String) throws -> URLRequest {
        // Create request
        let url = URL(string: "https://dev.xiangci.top/api/tarot/free-reading-sse")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add explicit Accept header for SSE
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        // Add additional headers for better SSE handling
        request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")
        // request.addValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        
        // Add Last-Event-ID if available for reconnection
        if let eventId = lastEventId {
            request.addValue(eventId, forHTTPHeaderField: "Last-Event-ID")
        }
        
        // Authentication header handling
        if let token = authToken, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.addValue("Bearer fake-token", forHTTPHeaderField: "Authorization")
        }
        
        // Build request body
        let cardObject: [String: Any] = [
            "card_id": cardId,
            "card_name": card,
            "card_cname": card,
            "card_type": "major",
            "orientation": orientation
        ]
        
        let cardPosition: [String: Any] = [
            "card": cardObject,
            "position": 1,
            "position_name": "Current Situation"
        ]
        
        let requestBody: [String: Any] = [
            "cards": [cardPosition],
            "spread_id": spreadId
        ]
        
        // Serialize to JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            return request
        } catch {
            print("Error serializing request body: \(error.localizedDescription)")
            throw TarotError.decodingError(message: "Failed to serialize request: \(error.localizedDescription)")
        }
    }
    
    // Process SSE events from incoming data chunks
    private func processEventData(_ data: Data) {
        let receiveTime = Date()
        guard let text = String(data: data, encoding: .utf8) else {
            print("Unable to decode data as UTF-8 text. Received \(data.count) bytes")
            return
        }
        
        print("⏱️ [\(formatTimeInterval())] Received \(data.count) bytes: \(text.prefix(50))...")
        
        // Append to buffer with explicit synchronization
        eventBuffer += text
        
        // 缓冲区溢出保护
        if eventBuffer.count > 1_000_000 { // 1MB上限
            print("SSE buffer overflow detected! Buffer size: \(eventBuffer.count) bytes")
            eventBuffer.removeAll(keepingCapacity: false)
            onError?(TarotError.decodingError(message: "Buffer overflow - event stream data exceeded 1MB limit"))
            return
        }
        
        // Process complete events in the buffer
        var eventsProcessed = 0
        let processingStartTime = Date()
        
        while let endOfLineIndex = eventBuffer.range(of: "\n\n") {
            let rawEvent = String(eventBuffer[..<endOfLineIndex.lowerBound])
            eventBuffer = String(eventBuffer[endOfLineIndex.upperBound...])
            
            eventsProcessed += 1
            let eventParseStartTime = Date()
            
            // Parse the event
            var eventType = ""
            var eventData = ""
            var eventId: String?
            var retryInterval: TimeInterval?
            
            // Process each line in the event
            rawEvent.components(separatedBy: .newlines).forEach { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("event:") {
                    eventType = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("data:") {
                    // Append data lines with a newline to maintain multi-line data
                    let dataPart = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if !eventData.isEmpty {
                        eventData.append("\n")
                    }
                    eventData.append(dataPart)
                } else if trimmed.hasPrefix("id:") {
                    eventId = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    // Store last event ID for potential reconnection
                    lastEventId = eventId
                } else if trimmed.hasPrefix("retry:") {
                    if let retryMs = TimeInterval(String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)) {
                        retryInterval = retryMs / 1000.0 // Convert from ms to seconds
                        // Update our retry delay for future reconnections
                        currentRetryDelay = retryInterval ?? baseRetryDelay
                    }
                }
            }
            
            let parseTime = Date().timeIntervalSince(eventParseStartTime)
            
            // Process the event if we have valid data
            if !eventType.isEmpty || !eventData.isEmpty {
                print("⏱️ [\(formatTimeInterval())] Parsed event: \(eventType) in \(parseTime * 1000)ms")
                
                // Create SSE event
                let sseEvent = SSEEvent(
                    type: eventType,
                    data: eventData,
                    id: eventId,
                    retry: retryInterval
                )
                
                // Process event with minimal delay - NOT on MainActor
                Task {
                    let eventHandleStartTime = Date()
                    await handleEvent(sseEvent)
                    let handleTime = Date().timeIntervalSince(eventHandleStartTime)
                    print("⏱️ [\(formatTimeInterval())] Handled event: \(eventType) in \(handleTime * 1000)ms")
                }
            }
        }
        
        let totalProcessingTime = Date().timeIntervalSince(processingStartTime)
        print("⏱️ [\(formatTimeInterval())] Processed \(eventsProcessed) events in \(totalProcessingTime * 1000)ms")
        
        // Event complete notification for monitoring the data flow
        let totalTime = Date().timeIntervalSince(receiveTime)
        print("⏱️ [\(formatTimeInterval())] Data chunk processing completed in \(totalTime * 1000)ms")
    }
    
    // 提供格式化的时间戳
    private func formatTimeInterval() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
    
    // Handle parsed SSE events
    private func handleEvent(_ event: SSEEvent) async {
        let startTime = Date()
        // 记录事件处理开始
        print("⏱️ [\(formatTimeInterval())] Start processing event: \(event.type)")
        
        // Reset retry count on successful events
        if !event.type.isEmpty && event.type != "error" {
            retryCount = 0
        }
        
        // Parse event data
        let parseStartTime = Date()
        let content = parseEventData(event.data)
        let parseTime = Date().timeIntervalSince(parseStartTime)
        print("⏱️ [\(formatTimeInterval())] Parsed event data in \(parseTime * 1000)ms")
        
        // Process different event types
        switch event.type {
        case "connected":
            print("Connected to SSE")
            
        case "opening_start":
            print("Opening statement started")
            let stateUpdateStartTime = Date()
            _ = await stateManager.updateAndGetOpeningText("", append: false)
            let stateUpdateTime = Date().timeIntervalSince(stateUpdateStartTime)
            
            print("⏱️ [\(formatTimeInterval())] State updated in \(stateUpdateTime * 1000)ms")
            //openingContinuation?.yield(updatedText)
            print("🔴 [\(formatTimeInterval())] SENT opening update to stream: '' (empty reset)")
            
        case "opening_chunk":
            // 合并状态更新和获取，减少Actor调用
            let stateUpdateStartTime = Date()
            let updatedText = await stateManager.updateAndGetOpeningText(content)
            let stateUpdateTime = Date().timeIntervalSince(stateUpdateStartTime)
            
            print("⏱️ [\(formatTimeInterval())] State updated in \(stateUpdateTime * 1000)ms, text length: \(updatedText.count)")
            openingContinuation?.yield(content)
            print("🔴 [\(formatTimeInterval())] SENT opening chunk to stream: \(content) (chunk length: \(content.count) chars)")
            
        case "opening":
            let stateUpdateStartTime = Date()
            let updatedText = await stateManager.updateAndGetOpeningText(content, append: false)
            let stateUpdateTime = Date().timeIntervalSince(stateUpdateStartTime)
            
            print("⏱️ [\(formatTimeInterval())] State replaced in \(stateUpdateTime * 1000)ms")
            //openingContinuation?.yield(updatedText)
            print("🔴 [\(formatTimeInterval())] SENT complete opening to stream: \(updatedText.prefix(30))... (\(updatedText.count) chars)")
            
        case "interpretation_start":
            print("Interpretation started")
            let stateUpdateStartTime = Date()
            _ = await stateManager.updateAndGetInterpretationText("", append: false)
            let stateUpdateTime = Date().timeIntervalSince(stateUpdateStartTime)
            
            print("⏱️ [\(formatTimeInterval())] State updated in \(stateUpdateTime * 1000)ms")
            //interpretationContinuation?.yield(updatedText)
            print("🔴 [\(formatTimeInterval())] SENT interpretation update to stream: '' (empty reset)")
            
        case "interpretation_chunk":
            let stateUpdateStartTime = Date()
            let updatedText = await stateManager.updateAndGetInterpretationText(content)
            let stateUpdateTime = Date().timeIntervalSince(stateUpdateStartTime)
            
            print("⏱️ [\(formatTimeInterval())] State updated in \(stateUpdateTime * 1000)ms, text length: \(updatedText.count)")
            interpretationContinuation?.yield(content)
            print("🔴 [\(formatTimeInterval())] SENT interpretation chunk to stream: \(content) (chunk length: \(content.count) chars)")
            
        case "interpretation":
            let stateUpdateStartTime = Date()
            let updatedText = await stateManager.updateAndGetInterpretationText(content, append: false)
            let stateUpdateTime = Date().timeIntervalSince(stateUpdateStartTime)
            
            print("⏱️ [\(formatTimeInterval())] State replaced in \(stateUpdateTime * 1000)ms")
            //interpretationContinuation?.yield(updatedText)
            print("🔴 [\(formatTimeInterval())] SENT complete interpretation to stream: \(updatedText.prefix(30))... (\(updatedText.count) chars)")
            
        case "one_liner":
            let stateUpdateStartTime = Date()
            let updatedText = await stateManager.updateAndGetOneLinerText(content)
            let stateUpdateTime = Date().timeIntervalSince(stateUpdateStartTime)
            
            print("⏱️ [\(formatTimeInterval())] State updated in \(stateUpdateTime * 1000)ms")
            oneLinerContinuation?.yield(updatedText)
            print("🔴 [\(formatTimeInterval())] SENT complete one-liner to stream: \(updatedText.prefix(30))... (\(updatedText.count) chars)")
            
        case "complete":
            print("SSE stream completed")
            await MainActor.run {
                onCompleted?()
            }
            
        case "error":
            let error = NSError(domain: "TarotReadingService", code: 1, userInfo: [NSLocalizedDescriptionKey: content])
            await MainActor.run {
                onError?(error)
            }
            
            // Consider retry on server error
            scheduleRetryIfNeeded()
            
        default:
            print("Unknown event: \(event.type), data: \(content)")
        }
        
        // 记录整个事件处理的耗时
        let totalTime = Date().timeIntervalSince(startTime)
        print("⏱️ [\(formatTimeInterval())] Event \(event.type) processed in \(totalTime * 1000)ms")
    }
    
    // Parse event data with better error handling
    /// SSE 事件处理优先级：
    /// 1. 显式 event 类型
    /// 2. data 字段 JSON 解析
    /// 3. 原始 data 回退
    private func parseEventData(_ data: String) -> String {
        // Try to parse as JSON first
        if let jsonData = data.data(using: .utf8) {
            do {
                // Try as dictionary with string values
                if let decoded = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let content = decoded["content"] as? String {
                    return content
                }
                
                // Try with JSONDecoder
                let decoder = JSONDecoder()
                struct EventContent: Decodable {
                    let content: String
                }
                
                let eventContent = try decoder.decode(EventContent.self, from: jsonData)
                return eventContent.content
            } catch {
                print("JSON parsing error: \(error.localizedDescription)")
                // Fall back to raw data
            }
        }
        
        // Return the original data if JSON parsing fails
        return data
    }
    
    // Schedule retry with exponential backoff
    private func scheduleRetryIfNeeded() {
        guard let params = lastReadingParameters else { return }
        
        if retryCount < maxRetries {
            // Calculate backoff with jitter
            let jitter = Double.random(in: 0...0.3) // Add 0-30% jitter
            let delay = currentRetryDelay * pow(1.5, Double(retryCount)) * (1.0 + jitter)
            
            print("Scheduling retry #\(retryCount + 1) in \(delay) seconds")
            
            // Schedule retry (iOS 15 compatible)
            Task {
                // Convert seconds to nanoseconds (UInt64)
                let delayNanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                
                if !Task.isCancelled {
                    retryCount += 1
                    getReading(
                        for: params.card,
                        cardId: params.cardId,
                        orientation: params.orientation,
                        spreadId: params.spreadId
                    )
                }
            }
        } else {
            print("Max retries exceeded")
            Task { @MainActor in 
                onError?(TarotError.maxRetriesExceeded)
            }
        }
    }
    
    func cancelReading() {
        streamTask?.cancel()
        streamTask = nil
        
        urlSessionTask?.cancel()
        urlSessionTask = nil
        
        // Clean up more thoroughly
        urlSession.invalidateAndCancel()
        setupURLSession() // Create fresh session
        
        // Clear buffer
        eventBuffer.removeAll()
        
        // Close streams
        openingContinuation?.finish()
        interpretationContinuation?.finish()
        oneLinerContinuation?.finish()
    }
}

// MARK: - URLSessionDataDelegate
extension TarotReadingService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Check for HTTP status code
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            onError?(TarotError.invalidResponse)
            return
        }
        
        // Log response details
        print("HTTP Response: \(httpResponse.statusCode) - \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))")
        print("Response headers: \(httpResponse.allHeaderFields)")
        
        // Verify status code
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = "HTTP Error: \(httpResponse.statusCode) - \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
            print("SSE Error: \(errorMessage)")
            onError?(TarotError.httpError(statusCode: httpResponse.statusCode, message: errorMessage))
            completionHandler(.cancel)
            
            // Consider retry for certain status codes
            if [500, 502, 503, 504].contains(httpResponse.statusCode) {
                scheduleRetryIfNeeded()
            }
            return
        }
        
        // Accept the response
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Process data as it arrives
        print("Received data chunk: \(data.count) bytes")
        processEventData(data)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("URLSession task completed with error: \(error.localizedDescription)")
            onError?(TarotError.networkError(error))
            
            // Check if we should retry network errors
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                // Retry for transient network errors
                if [
                    NSURLErrorNetworkConnectionLost,
                    NSURLErrorTimedOut,
                    NSURLErrorCannotConnectToHost,
                    NSURLErrorCannotFindHost,
                    NSURLErrorDNSLookupFailed
                ].contains(nsError.code) {
                    scheduleRetryIfNeeded()
                }
            }
        } else {
            print("URLSession task completed successfully")
            onCompleted?()
        }
    }
} 
