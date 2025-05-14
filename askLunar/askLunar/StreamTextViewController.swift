//
//  StreamTextViewController.swift
//  TextStreamDemo
//
//  Created by AI Assistant
//

import UIKit
import Combine
import SwiftUI

// MARK: - 文本流生成器
final class TextStreamGenerator: CustomDebugStringConvertible {
    enum State {
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
    
    // 添加任务保存
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
        
        // 检查文本是否为空
        if text.isEmpty {
            debugPrint("警告: 初始化生成器的文本为空!")
        } else {
            debugPrint("生成器初始化，文本长度: \(text.count), 开头: \"\(text.prefix(10))...\"")
        }
    }
    
    func start() {
        guard state != .streaming else { return }
        
        // 已经有任务在运行，只需更改状态
        if generatorTask != nil && state == .paused {
            debugPrint("只需从暂停状态恢复")
            state = .streaming
            return
        }
        
        // 确保 continuation 已经初始化
        if continuation == nil {
            debugPrint("等待 continuation 初始化...")
            _ = stream  // 触发 lazy var 初始化
            guard continuation != nil else {
                debugPrint("无法初始化 continuation")
                return
            }
        }
        
        // 创建新的生成任务
        state = .streaming
        generatorTask = Task {
            debugPrint("开始新的生成任务")
            
            while currentIndex < text.endIndex {
                // 检查状态变化
                if Task.isCancelled {
                    throw CancellationError()
                }
                
                if state == .paused {
                    // 暂停状态：等待一段时间再检查状态
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    continue
                }
                
                if state != .streaming {
                    break
                }
                
                // 正常生成文本块
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
            
            // 检查是否已经到达文本末尾
            if currentIndex >= text.endIndex {
                debugPrint("到达文本末尾，设置 finished 状态")
                state = .finished
                continuation?.finish()
                debugPrint("stream 已结束")
            }
        }
    }
    
    func pause() {
        if state == .streaming {
            debugPrint("暂停生成器，当前进度: \(currentIndex)")
            state = .paused
        }
    }
    
    func resume() {
        guard state == .paused else {
            debugPrint("不能恢复：当前状态不是暂停, 而是: \(state)")
            return
        }
        
        debugPrint("从暂停状态恢复，当前进度: \(currentIndex)")
        state = .streaming
    }
    
    func reset() {
        generatorTask?.cancel()
        generatorTask = nil
        currentIndex = text.startIndex
        state = .idle
    }
    
    var debugDescription: String {
        "TextStreamGenerator(state: \(state), progress: \(text.distance(from: text.startIndex, to: currentIndex))/\(text.count))"
    }
}

// MARK: - 主视图控制器
final class StreamTextViewController: UIViewController {
    // MARK: UI组件
    lazy var textView: UITextView = {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.isEditable = false
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        tv.layer.borderColor = UIColor.systemGray5.cgColor
        tv.layer.borderWidth = 1
        tv.layer.cornerRadius = 8
        tv.layoutManager.allowsNonContiguousLayout = false
        return tv
    }()
    
    lazy var controlButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("开始流式输出", for: .normal)
        btn.titleLabel?.font = .boldSystemFont(ofSize: 18)
        btn.addAction(UIAction { [weak self] _ in
            self?.didTapControlButton()
        }, for: .touchUpInside)
        return btn
    }()
    
    lazy var speedSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 1
        slider.maximumValue = 10
        slider.value = 3
        slider.addAction(UIAction { [weak self] _ in
            self?.generator?.chunkSize = Int(slider.value)
        }, for: .valueChanged)
        return slider
    }()
    
    lazy var progressLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .right
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        return label
    }()
    
    // MARK: 属性
    var generator: TextStreamGenerator?
    var sampleTexts = [
        "这是一个流式文本输出的演示实现。通过生成器模式，我们可以将长文本分块处理，实现流畅的逐段显示效果。适用于聊天消息、日志输出等场景。",
        "Swift的Async/Await机制为异步编程带来了革命性改变。结合AsyncStream，我们可以轻松实现数据流处理，而无需复杂的回调嵌套。",
        "在这个实现中：\n1. TextStreamGenerator负责文本分块\n2. 主线程只处理UI更新\n3. 通过Task实现安全线程切换\n4. 通过状态管理实现暂停和继续\n5. 使用AsyncStream处理异步数据流\n6. 保证UI更新在主线程执行"
    ]
    var currentText: String?
    var currentTask: Task<Void, Never>?
    
    // MARK: 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        title = "流式文本演示"
        
        // 预选一个文本
        currentText = sampleTexts.randomElement()
        
        // 预设文本到 TextView（可选）
        if let preselectedText = currentText {
            textView.text = "准备开始流式显示以下内容：\n\n\(preselectedText)"
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cleanup()
    }
    
    deinit {
        cleanup()
        print("Controller deinitialized")
    }
    
    private func cleanup() {
        currentTask?.cancel()
        generator?.reset()
        generator = nil
    }
}

// MARK: - UI设置
private extension StreamTextViewController {
    func setupUI() {
        view.backgroundColor = .systemBackground
        
        let headerStack = UIStackView(arrangedSubviews: [
            createLabel("输出速度:"),
            speedSlider,
            progressLabel
        ])
        headerStack.spacing = 8
        
        let stackView = UIStackView(arrangedSubviews: [
            headerStack,
            textView,
            controlButton
        ])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            textView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.6)
        ])
    }
    
    func createLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .caption1)
        return label
    }
}

// MARK: - 控制逻辑
private extension StreamTextViewController {
    func didTapControlButton() {
        debugPrint("按钮点击，当前状态:", generator?.state ?? "nil (无生成器)")
        
        if generator == nil {
            startStreaming()
        } else {
            switch generator?.state {
            case .streaming:
                debugPrint("暂停流式输出")
                generator?.pause()
                controlButton.setTitle("继续输出", for: .normal)
            case .paused:
                debugPrint("继续流式输出") 
                generator?.resume()
                generator?.start()  // 重要：恢复后需要调用start来检测状态变化
                controlButton.setTitle("暂停输出", for: .normal)
            case .finished:
                debugPrint("重新开始流式输出(已完成)")
                resetStreaming()
                startStreaming()
            default:
                debugPrint("重置流式输出(其他状态)")
                resetStreaming()
            }
        }
    }
    
    func startStreaming() {
        debugPrint("Starting streaming")
        textView.text = ""
        
        // 使用当前文本或重新随机选择
        if currentText == nil {
            let selectedText = sampleTexts.randomElement() ?? ""
            currentText = selectedText
            debugPrint("Selected new random text: \"\(selectedText.prefix(20))...\"")
        } else {
            debugPrint("Using existing text")
        }
        
        guard let textToUse = currentText else { return }
        debugPrint("Text length:", textToUse.count)
        debugPrint("Text starts with: \"\(textToUse.prefix(20))...\"")
        
        // 确保文本完整性
        generator = TextStreamGenerator(text: textToUse, chunkSize: Int(speedSlider.value))
        debugPrint("Generator created with chunkSize:", Int(speedSlider.value))
        
        controlButton.setTitle("暂停输出", for: .normal)
        
        currentTask = Task { [weak self, generator] in
            guard let stream = generator?.stream else { return }
            debugPrint("Stream task started")
            
            do {
                for await chunk in stream {
                    try Task.checkCancellation()
                    self?.appendText(chunk)
                }
            } catch {
                print("Stream cancelled: \(error)")
            }
            
            // 检查最终状态
            debugPrint("Stream 循环结束，检查状态：", generator?.state ?? "nil")
            if generator?.state == .finished || generator?.state == .idle {
                debugPrint("检测到生成器已结束，准备更新按钮")
                await MainActor.run {
                    debugPrint("在主线程更新按钮")
                    self?.controlButton.setTitle("重新开始", for: .normal)
                }
            }
        }
        
        generator?.start()
        debugPrint("Generator started")
    }
    
    func resetStreaming() {
        debugPrint("Resetting streaming")
        cleanup()
        currentText = nil
        controlButton.setTitle("开始流式输出", for: .normal)
    }
    
    @MainActor
    func appendText(_ chunk: String) {
        if !chunk.isEmpty {
            debugPrint("Appending chunk:", chunk)
        }
        UIView.performWithoutAnimation {
            textView.text.append(chunk)
            updateProgress()
            scrollToBottom()
        }
    }
    
    private func updateProgress() {
        guard let generator = generator else { return }
        
        progressLabel.text = String(
            format: "%d/%d",
            generator.text.distance(from: generator.text.startIndex, to: generator.currentIndex),
            generator.text.count
        )
    }
    
    private func scrollToBottom() {
        guard !textView.text.isEmpty else { return }
        let offset = CGPoint(
            x: 0,
            y: max(0, textView.contentSize.height - textView.bounds.height)
        )
        textView.setContentOffset(offset, animated: false)
    }
}

// MARK: - SwiftUI Wrapper
struct StreamTextViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> StreamTextViewController {
        return StreamTextViewController()
    }
    
    func updateUIViewController(_ uiViewController: StreamTextViewController, context: Context) {
        // Update the view controller if needed
    }
}

// Preview Provider
struct StreamTextViewControllerRepresentable_Previews: PreviewProvider {
    static var previews: some View {
        StreamTextViewControllerRepresentable()
    }
}