//
//  SUStreamTextView.swift
//  askLunar
//
//  Created by AI Assistant
//

import SwiftUI
import Combine

// MARK: - Text Stream Generator
final class SUTextStreamGenerator: ObservableObject {
    enum State: String {
        case idle
        case streaming
        case paused
        case finished
    }
    
    let text: String
    var currentIndex: String.Index
    var chunkSize: Int
    var state: State = .idle
    var continuation: AsyncStream<String>.Continuation?
    
    private var generatorTask: Task<Void, Error>?
    
    lazy var stream: AsyncStream<String> = {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.state = .idle
                self?.continuation = nil
                self?.generatorTask?.cancel()
                self?.generatorTask = nil
            }
        }
    }()
    
    init(text: String, chunkSize: Int = 3) {
        self.text = text
        self.currentIndex = text.startIndex
        self.chunkSize = max(1, chunkSize)
    }
    
    func start() {
        guard state != .streaming else { return }
        
        if generatorTask != nil && state == .paused {
            state = .streaming
            return
        }
        
        if continuation == nil {
            _ = stream
            guard continuation != nil else { return }
        }
        
        state = .streaming
        generatorTask = Task {
            while currentIndex < text.endIndex {
                if Task.isCancelled {
                    throw CancellationError()
                }
                
                if state == .paused {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    continue
                }
                
                if state != .streaming {
                    break
                }
                
                let endIndex = text.index(
                    currentIndex,
                    offsetBy: chunkSize,
                    limitedBy: text.endIndex
                ) ?? text.endIndex
                
                let chunk = String(text[currentIndex..<endIndex])
                continuation?.yield(chunk)
                currentIndex = endIndex
                
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            
            if currentIndex >= text.endIndex {
                state = .finished
                continuation?.finish()
            }
        }
    }
    
    func pause() {
        if state == .streaming {
            state = .paused
        }
    }
    
    func resume() {
        guard state == .paused else { return }
        state = .streaming
    }
    
    func reset() {
        generatorTask?.cancel()
        generatorTask = nil
        currentIndex = text.startIndex
        state = .idle
    }
    
    var progress: Int {
        text.distance(from: text.startIndex, to: currentIndex)
    }
    
    var total: Int {
        text.count
    }
}

// MARK: - Main View
struct SUStreamTextView: View {
    @StateObject private var viewModel = SUStreamTextViewModel()
    
    var body: some View {
        VStack(spacing: 16) {
            // Speed Control
            HStack {
                Text("输出速度:")
                    .font(.caption)
                Slider(value: $viewModel.speed, in: 1...10, step: 1)
                
                Spacer()
                
                // State Display
                Text("State: \(viewModel.stateText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(stateColor(viewModel.stateText))
                            .opacity(0.2)
                    )
                
                Text("\(viewModel.progress)/\(viewModel.total)")
                    .font(.system(.caption, design: .monospaced))
            }
            
            // Text Display
            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.displayText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(UIColor.systemGray5), lineWidth: 1)
                        )
                        .id("textContent")
                }
                .onChange(of: viewModel.displayText) { _ in
                    withAnimation {
                        proxy.scrollTo("textContent", anchor: .bottom)
                    }
                }
            }
            
            // Control Button
            Button(action: viewModel.toggleStreaming) {
                Text(viewModel.buttonTitle)
                    .font(.system(size: 18, weight: .bold))
            }
        }
        .padding(20)
    }
    
    // 状态颜色映射函数
    private func stateColor(_ state: String) -> Color {
        switch state {
        case "streaming":
            return .green
        case "paused":
            return .orange
        case "finished":
            return .blue
        default:
            return .gray
        }
    }
}

// MARK: - ViewModel
@MainActor
final class SUStreamTextViewModel: ObservableObject {
    @Published var speed: Double = 3
    @Published var displayText: String = ""
    @Published var buttonTitle: String = "开始流式输出"
    @Published var progress: Int = 0
    @Published var total: Int = 0
    @Published var stateText: String = "idle"
    
    private let sampleTexts = [
        "这是一个流式文本输出的演示实现。通过生成器模式，我们可以将长文本分块处理，实现流畅的逐段显示效果。适用于聊天消息、日志输出等场景。",
        "Swift的Async/Await机制为异步编程带来了革命性改变。结合AsyncStream，我们可以轻松实现数据流处理，而无需复杂的回调嵌套。",
        "在这个实现中：\n1. TextStreamGenerator负责文本分块\n2. 主线程只处理UI更新\n3. 通过Task实现安全线程切换\n4. 通过状态管理实现暂停和继续\n5. 使用AsyncStream处理异步数据流\n6. 保证UI更新在主线程执行"
    ]
    
    private var currentText: String?
    private var generator: SUTextStreamGenerator?
    private var streamTask: Task<Void, Never>?
    
    func toggleStreaming() {
        if generator == nil {
            startStreaming()
        } else {
            switch generator?.state {
            case .streaming:
                generator?.pause()
                buttonTitle = "继续输出"
                stateText = "paused"
            case .paused:
                generator?.resume()
                generator?.start()
                buttonTitle = "暂停输出"
                stateText = "streaming"
            case .finished:
                resetStreaming()
                startStreaming()
            case .idle:
                resetStreaming()
                startStreaming()
            default:
                resetStreaming()
            }
        }
    }
    
    private func startStreaming() {
        displayText = ""
        
        if currentText == nil {
            currentText = sampleTexts.randomElement()
        }
        
        guard let textToUse = currentText else { return }
        
        generator = SUTextStreamGenerator(text: textToUse, chunkSize: Int(speed))
        buttonTitle = "暂停输出"
        // Get the state of the generator and update the stateText
        let generatorState = generator?.state
        stateText = generatorState?.rawValue ?? "idle"
        
        // Cancel any existing task before starting a new one
        streamTask?.cancel()
        
        // Create a new task with explicit actor isolation handling
        streamTask = Task { [weak self] in
            guard let generator = self?.generator else { return }
            
            // Stream is not optional, so we don't need to use guard let
            let stream = generator.stream
            
            do {
                for await chunk in stream {
                    try Task.checkCancellation()
                    
                    // Explicitly jump back to the main actor to update UI state
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        self.displayText += chunk
                        self.updateProgress()
                    }
                }

                // get the state of the generator and update the stateText
                let generatorState = generator.state                
                // Handle completion on the main actor
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.stateText = generatorState.rawValue
                    if generatorState == .finished {
                        self.buttonTitle = "重置开始"
                    } else if generatorState == .idle {
                        self.buttonTitle = "开始流式输出"
                    }
                }
            } catch {
                print("Stream cancelled: \(error)")
            }
        }
        
        // Start the generator after setting up the task to ensure the stream is being monitored
        generator?.start()
    }
    
    private func resetStreaming() {
        streamTask?.cancel()
        streamTask = nil
        generator?.reset()
        generator = nil
        currentText = nil
        buttonTitle = "开始流式输出"
        progress = 0
        total = 0
        stateText = "idle"
    }
    
    private func updateProgress() {
        guard let generator = generator else { return }
        progress = generator.progress
        total = generator.total
    }
    
    deinit {
        streamTask?.cancel()
        generator?.reset()
    }
}

// MARK: - Preview
struct SUStreamTextView_Previews: PreviewProvider {
    static var previews: some View {
        SUStreamTextView()
    }
} 
