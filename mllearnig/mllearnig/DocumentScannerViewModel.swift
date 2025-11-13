import Foundation
import SwiftUI
import AVFoundation
import Vision
import UniformTypeIdentifiers
import Combine

@MainActor
final class DocumentScannerViewModel: ObservableObject {
    // MARK: - Camera
    @Published var isCameraRunning = false
    @Published var isTorchOn = false
    
    // MARK: - Processing state
    @Published var isProcessing = false
    @Published var processingStatus = ""
    
    // MARK: - Results
    @Published private(set) var scans: [ScannedDocument] = []
    @Published var selectedScan: ScannedDocument?
    @Published var selectedScans: Set<UUID> = []
    
    // MARK: - Advanced Features
    @Published var searchQuery = ""
    @Published var currentFilter: ScanFilter = .all
    @Published var smartFolders: [SmartFolder] = []
    @Published var detectedLanguage: String = "en"
    @Published var showingEdgeDetection = true
    
    // MARK: - Cloud Sync
    @Published var isCloudSyncEnabled = false
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    
    // MARK: - Internal services
    private let ocr = OCRService()
    private let extractor = ExtractionUtils()
    private let edgeDetector = DocumentEdgeDetector()
    private let searchEngine = SmartSearchEngine()
    private let languageProcessor = LanguageProcessor()
    // Make cloud sync optional; only create when enabled
    private var cloudSync: CloudSyncManager?
    private let exportManager = ExportManager()
    
    // Shared camera provided by CameraView/CameraPreviewController
    fileprivate weak var camera: CameraController?
    
    // MARK: - Computed Properties
    var filteredScans: [ScannedDocument] {
        var result = currentFilter.filter(scans)
        
        if !searchQuery.isEmpty {
            result = result.filter { scan in
                scan.recognizedText.localizedCaseInsensitiveContains(searchQuery) ||
                scan.summary.localizedCaseInsensitiveContains(searchQuery) ||
                (scan.extracted.dateString?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            }
        }
        
        return result
    }
    
    var isSelectionMode: Bool {
        !selectedScans.isEmpty
    }
    
    // MARK: - Initialization
    init() {
        loadSmartFolders()
        // Restore persisted cloud setting if you persisted it
        if UserDefaults.standard.object(forKey: "cloudSyncEnabled") != nil {
            isCloudSyncEnabled = UserDefaults.standard.bool(forKey: "cloudSyncEnabled")
        }
        if isCloudSyncEnabled {
            cloudSync = CloudSyncManager()
            Task { await syncWithCloud() }
        }
    }
    
    // MARK: - Camera Management
    func attachCamera(_ controller: CameraController) {
        self.camera = controller
        Task {
            do {
                try await controller.start()
                self.isCameraRunning = true
            } catch {
                print("Camera start error: \(error)")
            }
        }
    }
    
    func configureCamera() async {
        if camera != nil {
            isCameraRunning = true
        }
    }
    
    func stopCamera() {
        Task { [weak self] in
            do {
                try await self?.camera?.stop()
            } catch {
                print("Camera stop error: \(error)")
            }
            self?.isCameraRunning = false
        }
    }
    
    func capturePhoto() {
        Task {
            guard let camera else { return }
            do {
                let image = try await camera.capturePhoto()
                await processCapturedImage(image)
            } catch {
                print("Capture error: \(error)")
            }
        }
    }
    
    // MARK: - Image Processing (Enhanced)
    func processCapturedImage(_ image: UIImage) async {
        isProcessing = true
        processingStatus = "Detecting edges..."
        
        var processedImage = image
        
        // Step 1: Edge detection and crop
        if showingEdgeDetection {
            if let cropped = await edgeDetector.detectAndCrop(image: image) {
                processedImage = cropped
            }
            processingStatus = "Enhancing document..."
            processedImage = await edgeDetector.enhanceDocument(image: processedImage)
        }
        
        // Step 2: OCR
        processingStatus = "Recognizing text..."
        let recognized = await ocr.recognizeText(in: processedImage)
        
        // Step 3: Language detection
        processingStatus = "Detecting language..."
        let language = await languageProcessor.detectLanguage(in: recognized)
        detectedLanguage = language
        
        // Step 4: Extract fields
        processingStatus = "Extracting data..."
        let fields = extractor.extract(from: recognized)
        
        // Step 5: Generate tags
        processingStatus = "Generating tags..."
        let tags = await searchEngine.generateTags(for: recognized)
        
        // Step 6: Create summary
        let summary = extractor.summarize(text: recognized, fields: fields)
        
        // Build document
        let doc = ScannedDocument(
            id: UUID(),
            timestamp: Date(),
            image: processedImage,
            recognizedText: recognized,
            extracted: fields,
            summary: summary,
            tags: tags,
            language: language
        )
        
        doc.generateThumbnailIfNeeded(maxSide: 256)
        scans.insert(doc, at: 0)
        
        // Upload to cloud if enabled
        if isCloudSyncEnabled {
            await uploadToCloud(doc)
        }
        
        // Auto-categorize into smart folders
        categorizeIntoFolders(doc)
        
        isProcessing = false
        processingStatus = ""
    }
    
    // MARK: - Camera Controls
    func toggleTorch() {
        Task {
            do {
                try await camera?.setTorch(on: !isTorchOn)
                isTorchOn.toggle()
            } catch {
                print("Torch error: \(error)")
            }
        }
    }
    
    func flipCamera() {
        Task {
            do {
                try await camera?.flipCamera()
            } catch {
                print("Flip camera error: \(error)")
            }
        }
    }
    
    // MARK: - Selection Management
    func toggleSelection(for scan: ScannedDocument) {
        if selectedScans.contains(scan.id) {
            selectedScans.remove(scan.id)
        } else {
            selectedScans.insert(scan.id)
        }
    }
    
    func selectAll() {
        selectedScans = Set(filteredScans.map { $0.id })
    }
    
    func deselectAll() {
        selectedScans.removeAll()
    }
    
    var selectedScanObjects: [ScannedDocument] {
        scans.filter { selectedScans.contains($0.id) }
    }
    
    // MARK: - Export Functions
    func exportToPDF() async -> Data? {
        let scansToExport = isSelectionMode ? selectedScanObjects : scans
        return await exportManager.export(scans: scansToExport, format: .pdf)
    }
    
    func exportToFormat(_ format: ExportFormat) async -> Data? {
        let scansToExport = isSelectionMode ? selectedScanObjects : scans
        return await exportManager.export(scans: scansToExport, format: format)
    }
    
    func shareScans() -> [Any] {
        var items: [Any] = []
        let scansToShare = isSelectionMode ? selectedScanObjects : [scans.first].compactMap { $0 }
        
        for scan in scansToShare {
            if let image = scan.image {
                items.append(image)
            }
            items.append(scan.recognizedText)
        }
        
        return items
    }
    
    // MARK: - Cloud Sync
    func syncWithCloud() async {
        guard isCloudSyncEnabled else { return }
        // Create CloudSyncManager lazily
        if cloudSync == nil { cloudSync = CloudSyncManager() }
        guard let cloudSync else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let cloudScans = try await cloudSync.fetchScans()
            for cloudScan in cloudScans {
                if !scans.contains(where: { $0.id == cloudScan.id }) {
                    scans.append(cloudScan)
                }
            }
            lastSyncDate = Date()
        } catch {
            print("Cloud sync error: \(error)")
        }
    }
    
    private func uploadToCloud(_ scan: ScannedDocument) async {
        guard isCloudSyncEnabled else { return }
        if cloudSync == nil { cloudSync = CloudSyncManager() }
        guard let cloudSync else { return }
        
        do {
            try await cloudSync.uploadScan(scan)
        } catch {
            print("Cloud upload error: \(error)")
        }
    }
    
    // MARK: - Smart Folders
    func createSmartFolder(name: String, rules: [SmartFolder.FilterRule]) {
        let folder = SmartFolder(
            id: UUID(),
            name: name,
            icon: "folder.fill",
            color: "blue",
            rules: rules
        )
        smartFolders.append(folder)
        saveSmartFolders()
    }
    
    func deleteSmartFolder(_ folder: SmartFolder) {
        smartFolders.removeAll { $0.id == folder.id }
        saveSmartFolders()
    }
    
    private func categorizeIntoFolders(_ scan: ScannedDocument) {
        // Auto-categorize scan into matching smart folders
        for folder in smartFolders {
            if folder.matches(scan) {
                // You could add a folderIds property to ScannedDocument
                print("Scan matches folder: \(folder.name)")
            }
        }
    }
    
    private func saveSmartFolders() {
        if let encoded = try? JSONEncoder().encode(smartFolders) {
            UserDefaults.standard.set(encoded, forKey: "smartFolders")
        }
    }
    
    private func loadSmartFolders() {
        if let data = UserDefaults.standard.data(forKey: "smartFolders"),
           let decoded = try? JSONDecoder().decode([SmartFolder].self, from: data) {
            smartFolders = decoded
        } else {
            // Create default folders
            smartFolders = [
                SmartFolder(id: UUID(), name: "Receipts", icon: "receipt", color: "green",
                          rules: [.init(type: .contains, value: "receipt")]),
                SmartFolder(id: UUID(), name: "Invoices", icon: "doc.text", color: "blue",
                          rules: [.init(type: .contains, value: "invoice")]),
                SmartFolder(id: UUID(), name: "With Amounts", icon: "dollarsign.circle", color: "orange",
                          rules: [.init(type: .hasAmount, value: "")])
            ]
        }
    }
    
    // MARK: - Search
    func performSearch() async {
        guard !searchQuery.isEmpty else { return }
        let results = await searchEngine.search(query: searchQuery, in: scans)
        // Update UI with search results
        print("Found \(results.count) results")
    }
    
    // MARK: - Batch Operations
    func deleteSelected() {
        scans.removeAll { selectedScans.contains($0.id) }
        selectedScans.removeAll()
    }
    
    func exportSelected(format: ExportFormat) async -> Data? {
        return await exportManager.export(scans: selectedScanObjects, format: format)
    }
    
    // MARK: - Original Functions
    func deleteScans(at offsets: IndexSet) {
        scans.remove(atOffsets: offsets)
    }
    
    func clearAll() {
        scans.removeAll()
        selectedScans.removeAll()
    }
    
    func copyLatestTextToPasteboard() {
        guard let first = scans.first else { return }
        UIPasteboard.general.string = first.recognizedText
    }
    
    // MARK: - Settings
    func toggleCloudSync() {
        isCloudSyncEnabled.toggle()
        UserDefaults.standard.set(isCloudSyncEnabled, forKey: "cloudSyncEnabled")
        
        if isCloudSyncEnabled {
            cloudSync = CloudSyncManager()
            Task { await syncWithCloud() }
        } else {
            cloudSync = nil
        }
    }
    
    func toggleEdgeDetection() {
        showingEdgeDetection.toggle()
        UserDefaults.standard.set(showingEdgeDetection, forKey: "edgeDetectionEnabled")
    }
}

// MARK: - Updated ScannedDocument Model
extension ScannedDocument {
    convenience init(id: UUID, timestamp: Date, image: UIImage?, recognizedText: String,
                    extracted: ExtractedFields, summary: String, tags: [String], language: String) {
        self.init(id: id, timestamp: timestamp, image: image, recognizedText: recognizedText,
                 extracted: extracted, summary: summary)
        self.tags = tags
        self.language = language
    }
    
    var tags: [String] {
        get { (objc_getAssociatedObject(self, &AssociatedKeys.tags) as? [String]) ?? [] }
        set { objc_setAssociatedObject(self, &AssociatedKeys.tags, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    
    var language: String {
        get { (objc_getAssociatedObject(self, &AssociatedKeys.language) as? String) ?? "en" }
        set { objc_setAssociatedObject(self, &AssociatedKeys.language, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    
    private struct AssociatedKeys {
        static var tags = "tags"
        static var language = "language"
    }
}
