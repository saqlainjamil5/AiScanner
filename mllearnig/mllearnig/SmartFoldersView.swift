import SwiftUI

// MARK: - Smart Folders View
struct SmartFoldersView: View {
    @ObservedObject var viewModel: DocumentScannerViewModel
    @State private var showCreateFolder = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.smartFolders) { folder in
                    NavigationLink {
                        FolderDetailView(folder: folder, viewModel: viewModel)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: folder.icon)
                                .font(.title2)
                                .foregroundStyle(Color(folder.color))
                                .frame(width: 40, height: 40)
                                .background(Color(folder.color).opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(folder.name)
                                    .font(.headline)
                                
                                Text("\(documentsCount(for: folder)) documents")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        viewModel.deleteSmartFolder(viewModel.smartFolders[index])
                    }
                }
            }
            .navigationTitle("Smart Folders")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateFolder = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .sheet(isPresented: $showCreateFolder) {
                CreateFolderSheet(viewModel: viewModel)
            }
        }
    }
    
    func documentsCount(for folder: SmartFolder) -> Int {
        viewModel.scans.filter { folder.matches($0) }.count
    }
}

// MARK: - Folder Detail View
struct FolderDetailView: View {
    let folder: SmartFolder
    @ObservedObject var viewModel: DocumentScannerViewModel
    
    var matchingScans: [ScannedDocument] {
        viewModel.scans.filter { folder.matches($0) }
    }
    
    var body: some View {
        Group {
            if matchingScans.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: folder.icon)
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary.opacity(0.5))
                    
                    Text("No Documents")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Documents matching this folder's rules will appear here")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(matchingScans) { scan in
                            ModernScanCard(scan: scan, isLatest: false)
                                .onTapGesture {
                                    viewModel.selectedScan = scan
                                }
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Create Folder Sheet
struct CreateFolderSheet: View {
    @ObservedObject var viewModel: DocumentScannerViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var folderName = ""
    @State private var selectedIcon = "folder.fill"
    @State private var selectedColor = "blue"
    @State private var filterText = ""
    @State private var ruleType: SmartFolder.FilterRule.RuleType = .contains
    
    let icons = ["folder.fill", "doc.fill", "receipt", "dollarsign.circle", "calendar", "tag.fill"]
    let colors = ["blue", "green", "red", "orange", "purple", "pink"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Folder Details") {
                    TextField("Folder Name", text: $folderName)
                    
                    Picker("Icon", selection: $selectedIcon) {
                        ForEach(icons, id: \.self) { icon in
                            Image(systemName: icon).tag(icon)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Color", selection: $selectedColor) {
                        ForEach(colors, id: \.self) { color in
                            Text(color.capitalized).tag(color)
                        }
                    }
                }
                
                Section("Filter Rules") {
                    Picker("Rule Type", selection: $ruleType) {
                        Text("Contains").tag(SmartFolder.FilterRule.RuleType.contains)
                        Text("Starts With").tag(SmartFolder.FilterRule.RuleType.startsWith)
                        Text("Ends With").tag(SmartFolder.FilterRule.RuleType.endsWith)
                        Text("Has Amount").tag(SmartFolder.FilterRule.RuleType.hasAmount)
                        Text("Has Date").tag(SmartFolder.FilterRule.RuleType.hasDate)
                    }
                    
                    if ruleType != .hasAmount && ruleType != .hasDate {
                        TextField("Filter Text", text: $filterText)
                    }
                }
                
                Section {
                    Text("Documents that match all rules will appear in this folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Smart Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createFolder()
                    }
                    .disabled(folderName.isEmpty)
                }
            }
        }
    }
    
    func createFolder() {
        let rule = SmartFolder.FilterRule(type: ruleType, value: filterText)
        viewModel.createSmartFolder(name: folderName, rules: [rule])
        dismiss()
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var viewModel: DocumentScannerViewModel
    @State private var showClearAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Scanning") {
                    Toggle(isOn: $viewModel.showingEdgeDetection) {
                        Label("Auto Edge Detection", systemImage: "crop")
                    }
                    
                    Toggle(isOn: .constant(true)) {
                        Label("Auto Enhance", systemImage: "wand.and.stars")
                    }
                    
                    Picker("OCR Language", selection: $viewModel.detectedLanguage) {
                        Text("Auto Detect").tag("auto")
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                    }
                }
                
                Section("Cloud Sync") {
                    Toggle(isOn: $viewModel.isCloudSyncEnabled) {
                        Label("iCloud Sync", systemImage: "icloud")
                    }
                    .onChange(of: viewModel.isCloudSyncEnabled) { _ in
                        viewModel.toggleCloudSync()
                    }
                    
                    if viewModel.isCloudSyncEnabled {
                        HStack {
                            Text("Last Synced")
                            Spacer()
                            if let lastSync = viewModel.lastSyncDate {
                                Text(lastSync, style: .relative)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Never")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Button {
                            Task {
                                await viewModel.syncWithCloud()
                            }
                        } label: {
                            HStack {
                                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                if viewModel.isSyncing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(viewModel.isSyncing)
                    }
                }
                
                Section("Storage") {
                    HStack {
                        Text("Documents")
                        Spacer()
                        Text("\(viewModel.scans.count)")
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        showClearAlert = true
                    } label: {
                        Label("Clear All Documents", systemImage: "trash")
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    
                    Link(destination: URL(string: "https://example.com/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Clear All Documents?", isPresented: $showClearAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    viewModel.clearAll()
                }
            } message: {
                Text("This will permanently delete all scanned documents. This action cannot be undone.")
            }
        }
    }
}

// MARK: - Enhanced Scan Detail View
struct EnhancedScanDetailView: View {
    let scan: ScannedDocument
    @ObservedObject var viewModel: DocumentScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var showingTranslation = false
    @State private var translatedText = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Image
                    if let image = scan.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    }
                    
                    // Language & Tags Section
                    HStack {
                        // Language Badge
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.caption)
                            Text(languageName(for: scan.language))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                        
                        // Tags
                        ForEach(scan.tags.prefix(3), id: \.self) { tag in
                            TagView(text: tag)
                        }
                        
                        Spacer()
                    }
                    
                    // Extracted Fields Card
                    if scan.extracted.dateString != nil || scan.extracted.totalAmount != nil {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Extracted Data", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            
                            VStack(spacing: 12) {
                                if let date = scan.extracted.dateString {
                                    InfoRow(icon: "calendar", label: "Date", value: date, color: .blue)
                                }
                                if let total = scan.extracted.totalAmount {
                                    InfoRow(icon: "dollarsign.circle", label: "Total", value: total, color: .green)
                                }
                            }
                        }
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    
                    // Recognized Text with Translation
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Recognized Text", systemImage: "doc.text")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button {
                                showingTranslation.toggle()
                            } label: {
                                Label("Translate", systemImage: "character.bubble")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                        
                        Text(showingTranslation && !translatedText.isEmpty ? translatedText : scan.recognizedText)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                    }
                    
                    // Summary
                    if !scan.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("AI Summary", systemImage: "text.alignleft")
                                .font(.headline)
                            
                            Text(scan.summary)
                                .font(.body)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        ActionButton(
                            title: "Copy Text",
                            icon: "doc.on.doc",
                            color: .blue
                        ) {
                            UIPasteboard.general.string = scan.recognizedText
                        }
                        
                        ActionButton(
                            title: "Share",
                            icon: "square.and.arrow.up",
                            color: .green
                        ) {
                            showShareSheet = true
                        }
                        
                        ActionButton(
                            title: "Export as PDF",
                            icon: "doc.fill",
                            color: .orange
                        ) {
                            Task {
                                if let pdfData = await PDFGenerator().createPDF(from: [scan]) {
                                    savePDF(data: pdfData)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Scan Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = scan.image {
                    ShareSheet(items: [image, scan.recognizedText])
                }
            }
        }
    }
    
    func languageName(for code: String) -> String {
        let locale = Locale(identifier: "en")
        return locale.localizedString(forLanguageCode: code)?.capitalized ?? "Unknown"
    }
    
    func savePDF(data: Data) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("scan.pdf")
        try? data.write(to: tempURL)
        
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.headline)
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .padding()
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Info Row
struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
