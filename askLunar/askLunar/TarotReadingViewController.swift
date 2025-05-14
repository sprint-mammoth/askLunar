import UIKit
import SwiftUI
import Combine

// MARK: - Main Tarot Reading View Controller
final class TarotReadingViewController: UIViewController {
    // MARK: UI Components
    lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    lazy var cardImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 10
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    
    lazy var cardNameLabel: UILabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 24)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    lazy var openingTextView: UITextView = {
        return createSectionTextView()
    }()
    
    lazy var interpretationTextView: UITextView = {
        return createSectionTextView()
    }()
    
    lazy var oneLinerTextView: UITextView = {
        return createSectionTextView()
    }()
    
    lazy var openingHeaderLabel: UILabel = {
        return createSectionHeaderLabel("Opening")
    }()
    
    lazy var interpretationHeaderLabel: UILabel = {
        return createSectionHeaderLabel("Interpretation")
    }()
    
    lazy var oneLinerHeaderLabel: UILabel = {
        return createSectionHeaderLabel("Summary")
    }()
    
    lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    lazy var errorView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemRed.withAlphaComponent(0.1)
        view.layer.cornerRadius = 10
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .systemRed
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    lazy var retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Retry", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = 8
        button.addAction(UIAction { [weak self] _ in
            self?.retryCount += 1
            print("Retrying reading (attempt \(self?.retryCount ?? 0))")
            self?.startReading()
        }, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    lazy var startReadingButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Get Tarot Reading", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemPurple
        button.layer.cornerRadius = 10
        button.addAction(UIAction { [weak self] _ in
            self?.startReading()
        }, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    lazy var speedSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 1
        slider.maximumValue = 10
        slider.value = 3
        slider.addAction(UIAction { [weak self] _ in
            // Speed slider is now for display only
            // TarotReadingService doesn't support chunk size adjustment
        }, for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()
    
    lazy var speedLabel: UILabel = {
        let label = UILabel()
        label.text = "Output Speed:"
        label.font = .preferredFont(forTextStyle: .caption1)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: Properties
    private let cardName = "The Fool"
    private let cardImageName = "0.THE FOOL"
    
    private var retryCount = 0
    
    // Content properties
    private var opening = ""
    private var interpretation = ""
    private var oneLiner = ""
    
    // TarotReadingService for SSE streaming
    private var tarotService: TarotReadingService?
    
    // Tasks for AsyncStream consumption
    private var openingTask: Task<Void, Never>?
    private var interpretationTask: Task<Void, Never>?
    private var oneLinerTask: Task<Void, Never>?
    
    // Access to Core Data
    private let persistenceController = PersistenceController.shared
    
    // MARK: View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        title = "Tarot Reading"
        
        // Set initial card data
        cardNameLabel.text = cardName
        if let image = UIImage(named: cardImageName) {
            cardImageView.image = image
            print("Successfully loaded image: \(cardImageName)")
        } else {
            print("Failed to load image: \(cardImageName)")
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cleanup()
    }
    
    deinit {
        cleanup()
        print("TarotReadingViewController deinitialized")
    }
    
    private func cleanup() {
        // Cancel all tasks
        openingTask?.cancel()
        interpretationTask?.cancel()
        oneLinerTask?.cancel()
        
        // Cancel service
        tarotService?.cancelReading()
        
        // Reset variables
        openingTask = nil
        interpretationTask = nil
        oneLinerTask = nil
        tarotService = nil
    }
}

// MARK: - UI Setup
private extension TarotReadingViewController {
    func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Add scroll view and content view
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        // Add components to content view
        contentView.addSubview(cardImageView)
        contentView.addSubview(cardNameLabel)
        
        // Speed control section
        let speedControlContainer = createContainerView(backgroundColor: UIColor.systemGray6.withAlphaComponent(0.3))
        contentView.addSubview(speedControlContainer)
        speedControlContainer.addSubview(speedLabel)
        speedControlContainer.addSubview(speedSlider)
        
        // Loading indicator
        contentView.addSubview(loadingIndicator)
        
        // Section containers
        let openingContainer = createContainerView(backgroundColor: UIColor.systemGray.withAlphaComponent(0.2))
        contentView.addSubview(openingContainer)
        openingContainer.addSubview(openingHeaderLabel)
        openingContainer.addSubview(openingTextView)
        
        let interpretationContainer = createContainerView(backgroundColor: UIColor.systemGray.withAlphaComponent(0.2))
        contentView.addSubview(interpretationContainer)
        interpretationContainer.addSubview(interpretationHeaderLabel)
        interpretationContainer.addSubview(interpretationTextView)
        
        let oneLinerContainer = createContainerView(backgroundColor: UIColor.systemGray.withAlphaComponent(0.2))
        contentView.addSubview(oneLinerContainer)
        oneLinerContainer.addSubview(oneLinerHeaderLabel)
        oneLinerContainer.addSubview(oneLinerTextView)
        
        // Error view
        contentView.addSubview(errorView)
        errorView.addSubview(errorLabel)
        errorView.addSubview(retryButton)
        
        // Start reading button
        contentView.addSubview(startReadingButton)
        
        // Setup constraints
        setupConstraints(
            speedControlContainer: speedControlContainer,
            openingContainer: openingContainer,
            interpretationContainer: interpretationContainer,
            oneLinerContainer: oneLinerContainer
        )
    }
    
    func setupConstraints(
        speedControlContainer: UIView,
        openingContainer: UIView,
        interpretationContainer: UIView,
        oneLinerContainer: UIView
    ) {
        let margins = view.layoutMarginsGuide
        
        // ScrollView constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // ContentView constraints
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
        
        // Card image and name
        NSLayoutConstraint.activate([
            cardImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            cardImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cardImageView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.7),
            cardImageView.heightAnchor.constraint(equalToConstant: 200),
            
            cardNameLabel.topAnchor.constraint(equalTo: cardImageView.bottomAnchor, constant: 10),
            cardNameLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cardNameLabel.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            cardNameLabel.trailingAnchor.constraint(equalTo: margins.trailingAnchor)
        ])
        
        // Speed control container
        NSLayoutConstraint.activate([
            speedControlContainer.topAnchor.constraint(equalTo: cardNameLabel.bottomAnchor, constant: 20),
            speedControlContainer.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            speedControlContainer.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            
            speedLabel.leadingAnchor.constraint(equalTo: speedControlContainer.leadingAnchor, constant: 15),
            speedLabel.centerYAnchor.constraint(equalTo: speedControlContainer.centerYAnchor),
            
            speedSlider.leadingAnchor.constraint(equalTo: speedLabel.trailingAnchor, constant: 10),
            speedSlider.trailingAnchor.constraint(equalTo: speedControlContainer.trailingAnchor, constant: -15),
            speedSlider.centerYAnchor.constraint(equalTo: speedControlContainer.centerYAnchor),
            
            speedControlContainer.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Loading indicator
        NSLayoutConstraint.activate([
            loadingIndicator.topAnchor.constraint(equalTo: speedControlContainer.bottomAnchor, constant: 15),
            loadingIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
        ])
        
        // Section containers
        setupSectionContainerConstraints(
            container: openingContainer,
            headerLabel: openingHeaderLabel,
            textView: openingTextView,
            topAnchor: loadingIndicator.bottomAnchor
        )
        
        setupSectionContainerConstraints(
            container: interpretationContainer,
            headerLabel: interpretationHeaderLabel,
            textView: interpretationTextView,
            topAnchor: openingContainer.bottomAnchor
        )
        
        setupSectionContainerConstraints(
            container: oneLinerContainer,
            headerLabel: oneLinerHeaderLabel,
            textView: oneLinerTextView,
            topAnchor: interpretationContainer.bottomAnchor
        )
        
        // Error view
        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: oneLinerContainer.bottomAnchor, constant: 20),
            errorView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            
            errorLabel.topAnchor.constraint(equalTo: errorView.topAnchor, constant: 15),
            errorLabel.leadingAnchor.constraint(equalTo: errorView.leadingAnchor, constant: 15),
            errorLabel.trailingAnchor.constraint(equalTo: errorView.trailingAnchor, constant: -15),
            
            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 10),
            retryButton.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            retryButton.widthAnchor.constraint(equalToConstant: 100),
            retryButton.heightAnchor.constraint(equalToConstant: 40),
            retryButton.bottomAnchor.constraint(equalTo: errorView.bottomAnchor, constant: -15)
        ])
        
        // Start reading button
        NSLayoutConstraint.activate([
            startReadingButton.topAnchor.constraint(equalTo: errorView.bottomAnchor, constant: 20),
            startReadingButton.leadingAnchor.constraint(equalTo: margins.leadingAnchor, constant: 20),
            startReadingButton.trailingAnchor.constraint(equalTo: margins.trailingAnchor, constant: -20),
            startReadingButton.heightAnchor.constraint(equalToConstant: 50),
            startReadingButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    func setupSectionContainerConstraints(
        container: UIView,
        headerLabel: UILabel,
        textView: UITextView,
        topAnchor: NSLayoutYAxisAnchor
    ) {
        let margins = view.layoutMarginsGuide
        
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            container.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            
            headerLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 15),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),
            headerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -15),
            
            textView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 5),
            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -15),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
    }
    
    func createSectionTextView() -> UITextView {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }
    
    func createSectionHeaderLabel(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .boldSystemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    func createContainerView(backgroundColor: UIColor) -> UIView {
        let view = UIView()
        view.backgroundColor = backgroundColor
        view.layer.cornerRadius = 10
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}

// MARK: - Actions & Control Flow
extension TarotReadingViewController {
    private func startReading() {
        // Reset UI state
        opening = ""
        interpretation = ""
        oneLiner = ""
        
        openingTextView.text = "Waiting for content..."
        interpretationTextView.text = "Waiting for content..."
        oneLinerTextView.text = "Waiting for content..."
        
        errorView.isHidden = true
        startReadingButton.isEnabled = false
        loadingIndicator.startAnimating()
        
        // Setup TarotReadingService and streams
        setupStreamConsumers()
    }
    
    private func setupStreamConsumers() {
        // Create TarotReadingService and set completion handlers
        tarotService = TarotReadingService(
            onCompleted: { [weak self] in
                Task { @MainActor in
                    self?.completeReading()
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.handleError(error)
                }
            }
        )
        
        // Setup tasks to consume the streams
        setupOpeningStream()
        setupInterpretationStream()
        setupOneLinerStream()
        
        // Start the tarot reading using the service
        tarotService?.getReading(
            for: cardName,
            cardId: 0, // The Fool is 0
            orientation: "upright",
            spreadId: "spread_01"
        )
    }
    
    private func setupOpeningStream() {
        guard let service = tarotService else { return }
        
        openingTask = Task {
            do {
                for await chunk in service.openingStream {
                    try Task.checkCancellation()
                    
                    // Update UI on main thread
                    await MainActor.run {
                        appendOpening(chunk)
                    }
                }
                
                // Stream completed normally
                debugPrint("Opening stream completed successfully")
            } catch {
                debugPrint("Opening stream task cancelled: \(error)")
            }
        }
    }
    
    private func setupInterpretationStream() {
        guard let service = tarotService else { return }
        
        interpretationTask = Task {
            do {
                for await chunk in service.interpretationStream {
                    try Task.checkCancellation()
                    
                    // Update UI on main thread
                    await MainActor.run {
                        appendInterpretation(chunk)
                    }
                }
                
                // Stream completed normally
                debugPrint("Interpretation stream completed successfully")
            } catch {
                debugPrint("Interpretation stream task cancelled: \(error)")
            }
        }
    }
    
    private func setupOneLinerStream() {
        guard let service = tarotService else { return }
        
        oneLinerTask = Task {
            do {
                for await chunk in service.oneLinerStream {
                    try Task.checkCancellation()
                    
                    // Update UI on main thread
                    await MainActor.run {
                        appendOneLiner(chunk)
                    }
                }
                                
                // Stream completed normally
                debugPrint("OneLiner stream completed successfully")
            } catch {
                debugPrint("OneLiner stream task cancelled: \(error)")
            }
        }
    }
    
    @MainActor
    private func appendOpening(_ chunk: String) {
        if opening.isEmpty {
            openingTextView.text = chunk
        } else {
            openingTextView.text.append(chunk)
        }
        opening.append(chunk)
        scrollToBottom(textView: openingTextView)
    }
    
    @MainActor
    private func appendInterpretation(_ chunk: String) {
        if interpretation.isEmpty {
            interpretationTextView.text = chunk
        } else {
            interpretationTextView.text.append(chunk)
        }
        interpretation.append(chunk)
        scrollToBottom(textView: interpretationTextView)
    }
    
    @MainActor
    private func appendOneLiner(_ chunk: String) {
        if oneLiner.isEmpty {
            oneLinerTextView.text = chunk
        } else {
            oneLinerTextView.text.append(chunk)
        }
        oneLiner.append(chunk)
        scrollToBottom(textView: oneLinerTextView)
    }
    
    @MainActor
    private func handleError(_ error: Error) {
        loadingIndicator.stopAnimating()
        startReadingButton.isEnabled = true
        
        errorView.isHidden = false
        
        // Improve error messages for specific cases
        if let tarotError = error as? TarotError {
            switch tarotError {
            case .invalidResponse:
                errorLabel.text = "Invalid response received from server"
            case .httpError(let statusCode, let message):
                errorLabel.text = "HTTP Error \(statusCode): \(message)"
            case .decodingError(let message):
                errorLabel.text = "Failed to decode response: \(message)"
            case .networkError(let underlyingError):
                errorLabel.text = "Network error: \(underlyingError.localizedDescription)"
            case .maxRetriesExceeded:
                errorLabel.text = "Maximum retry attempts exceeded. Please try again later."
            }
        } else if error.localizedDescription.contains("EventSourceError error 0") {
            errorLabel.text = "Connection error: Unable to establish SSE connection. Please check your internet connection and try again."
        } else {
            errorLabel.text = error.localizedDescription
        }
    }
    
    @MainActor
    private func completeReading() {
        loadingIndicator.stopAnimating()
        startReadingButton.isEnabled = true
        
        // Save the reading to CoreData if we have complete content
        if !interpretation.isEmpty {
            saveReadingToCoreData()
        }
    }
    
    private func scrollToBottom(textView: UITextView) {
        guard !textView.text.isEmpty else { return }
        let offset = CGPoint(
            x: 0,
            y: max(0, textView.contentSize.height - textView.bounds.height)
        )
        textView.setContentOffset(offset, animated: false)
    }
    
    private func saveReadingToCoreData() {
        // Create a new TarotSession and save it to Core Data
        _ = persistenceController.createTarotSession(
            timestamp: Date(),
            cardName: cardName,
            cardImage: cardImageName,
            interpretation: interpretation
        )
        
        print("Saved reading to Core Data")
    }
}

// MARK: - SwiftUI Wrapper for Preview
struct TarotReadingViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TarotReadingViewController {
        return TarotReadingViewController()
    }
    
    func updateUIViewController(_ uiViewController: TarotReadingViewController, context: Context) {
        // Update if needed
    }
}

struct TarotReadingViewControllerRepresentable_Previews: PreviewProvider {
    static var previews: some View {
        TarotReadingViewControllerRepresentable()
            .edgesIgnoringSafeArea(.all)
    }
} 