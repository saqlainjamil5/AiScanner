import SwiftUI
import PhotosUI

// MARK: - Enhanced Content View with Tabs
struct ContentView: View {
    @StateObject private var viewModel = DocumentScannerViewModel()
    @State private var selectedTab = 0
    @State private var showPhotoPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var showExportSheet = false
    @State private var showSettings = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Scanner Tab
            ScannerTabView(
                viewModel: viewModel,
                pickedItem: $pickedItem
            )
            .tabItem {
                Label("Scanner", systemImage: "doc.viewfinder")
            }
            .tag(0)
            
            // Documents Tab
            DocumentsTabView(viewModel: viewModel)
                .tabItem {
                    Label("Documents", systemImage: "folder")
                }
                .tag(1)
            
            // Smart Folders Tab
            SmartFoldersView(viewModel: viewModel)
                .tabItem {
                    Label("Folders", systemImage: "folder.badge.gearshape")
                }
                .tag(2)
            
            // Settings Tab
            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
        }
        .onChange(of: pickedItem) { newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await viewModel.processCapturedImage(uiImage)
                }
            }
        }
        .task {
            await viewModel.configureCamera()
        }
    }
}

// MARK: - Scanner Tab
struct ScannerTabView: View {
    @ObservedObject var viewModel: DocumentScannerViewModel
    @Binding var pickedItem: PhotosPickerItem?
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemGray6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Camera Preview with Edge Detection
                    ZStack {
                        CameraView(
                            imageHandler: { image in
                                Task {
                                    await viewModel.processCapturedImage(image)
                                }
                            },
                            isRunning: $viewModel.isCameraRunning,
                            viewModel: viewModel
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                        
                        // Processing Overlay
                        if viewModel.isProcessing {
                            ZStack {
                                Color.black.opacity(0.7)
                                    .clipShape(RoundedRectangle(cornerRadius: 24))
                                
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(1.5)
                                    
                                    Text(viewModel.processingStatus)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        
                        // Camera Controls Overlay
                        VStack {
                            HStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    // Edge Detection Toggle
                                    ControlButton(
                                        icon: viewModel.showingEdgeDetection ? "crop" : "crop.fill",
                                        isActive: viewModel.showingEdgeDetection
                                    ) {
                                        viewModel.toggleEdgeDetection()
                                    }
                                    
                                    // Flashlight
                                    ControlButton(
                                        icon: viewModel.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                                        isActive: viewModel.isTorchOn
                                    ) {
                                        viewModel.toggleTorch()
                                    }
                                }
                                .padding(20)
                            }
                            Spacer()
                        }
                        
                        // Bottom Controls
                        VStack {
                            Spacer()
                            CameraControlsBar(
                                pickedItem: $pickedItem,
                                onCapture: { viewModel.capturePhoto() },
                                onFlip: { viewModel.flipCamera() }
                            )
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)
                        }
                    }
                    .frame(height: 420)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Recent Scans Quick View
                    if !viewModel.scans.isEmpty {
                        RecentScansCarousel(
                            scans: Array(viewModel.scans.prefix(5)),
                            onSelect: { scan in
                                viewModel.selectedScan = scan
                            }
                        )
                        .frame(height: 140)
                    }
                }
            }
            .navigationTitle("AI Scanner")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $viewModel.selectedScan) { scan in
                EnhancedScanDetailView(scan: scan, viewModel: viewModel)
            }
        }
    }
}

// MARK: - Recent Scans Carousel
struct RecentScansCarousel: View {
    let scans: [ScannedDocument]
    let onSelect: (ScannedDocument) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Scans")
                .font(.headline)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(scans) { scan in
                        RecentScanCard(scan: scan)
                            .onTapGesture {
                                onSelect(scan)
                            }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

struct RecentScanCard: View {
    let scan: ScannedDocument
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let thumb = scan.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: 100, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Text(scan.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: 100)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Documents Tab with Advanced Features
struct DocumentsTabView: View {
    @ObservedObject var viewModel: DocumentScannerViewModel
    @State private var showFilterMenu = false
    @State private var showExportOptions = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.filteredScans.isEmpty {
                    EmptyStateView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Search Bar
                            SearchBar(text: $viewModel.searchQuery)
                                .padding(.horizontal)
                            
                            // Filter Pills
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(ScanFilter.allCases, id: \.self) { filter in
                                        FilterPill(
                                            title: filter.rawValue,
                                            isSelected: viewModel.currentFilter == filter
                                        ) {
                                            withAnimation {
                                                viewModel.currentFilter = filter
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            // Selection Mode Banner
                            if viewModel.isSelectionMode {
                                SelectionBanner(viewModel: viewModel)
                            }
                            
                            // Document List
                            ForEach(viewModel.filteredScans) { scan in
                                SelectableDocumentCard(
                                    scan: scan,
                                    isSelected: viewModel.selectedScans.contains(scan.id),
                                    isSelectionMode: viewModel.isSelectionMode
                                ) {
                                    if viewModel.isSelectionMode {
                                        viewModel.toggleSelection(for: scan)
                                    } else {
                                        viewModel.selectedScan = scan
                                    }
                                } onLongPress: {
                                    viewModel.toggleSelection(for: scan)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Documents")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if viewModel.isSelectionMode {
                            Button {
                                viewModel.selectAll()
                            } label: {
                                Label("Select All", systemImage: "checkmark.circle")
                            }
                            
                            Button {
                                viewModel.deselectAll()
                            } label: {
                                Label("Deselect All", systemImage: "circle")
                            }
                            
                            Divider()
                            
                            Button {
                                showExportOptions = true
                            } label: {
                                Label("Export Selected", systemImage: "square.and.arrow.up")
                            }
                            
                            Button(role: .destructive) {
                                viewModel.deleteSelected()
                            } label: {
                                Label("Delete Selected", systemImage: "trash")
                            }
                        } else {
                            Button {
                                showExportOptions = true
                            } label: {
                                Label("Export All", systemImage: "square.and.arrow.up")
                            }
                            
                            Button {
                                Task {
                                    await viewModel.syncWithCloud()
                                }
                            } label: {
                                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                viewModel.clearAll()
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .sheet(item: $viewModel.selectedScan) { scan in
                EnhancedScanDetailView(scan: scan, viewModel: viewModel)
            }
            .sheet(isPresented: $showExportOptions) {
                ExportOptionsSheet(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search documents...", text: $text)
                .textFieldStyle(.plain)
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Filter Pill
struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.blue : Color(.systemGray5),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}

// MARK: - Selection Banner
struct SelectionBanner: View {
    @ObservedObject var viewModel: DocumentScannerViewModel
    
    var body: some View {
        HStack {
            Text("\(viewModel.selectedScans.count) selected")
                .font(.headline)
            
            Spacer()
            
            Button("Cancel") {
                viewModel.deselectAll()
            }
            .foregroundStyle(.blue)
        }
        .padding()
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - Selectable Document Card
struct SelectableDocumentCard: View {
    let scan: ScannedDocument
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Selection Circle
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            
            // Thumbnail
            Group {
                if let thumb = scan.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(scan.title)
                    .font(.headline)
                    .lineLimit(2)
                
                // Tags
                if !scan.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(scan.tags.prefix(3), id: \.self) { tag in
                                TagView(text: tag)
                            }
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    if let date = scan.extracted.dateString {
                        Label(date, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let amount = scan.extracted.totalAmount {
                        Label(amount, systemImage: "dollarsign.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onTapGesture(perform: onTap)
        .onLongPressGesture(perform: onLongPress)
    }
}

// MARK: - Tag View
struct TagView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
    }
}

// MARK: - Export Options Sheet
struct ExportOptionsSheet: View {
    @ObservedObject var viewModel: DocumentScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Export Format") {
                    ExportButton(icon: "doc.fill", title: "PDF Document", subtitle: "Multi-page PDF") {
                        await exportAs(.pdf)
                    }
                    
                    ExportButton(icon: "doc.text", title: "Text File", subtitle: "Plain text format") {
                        await exportAs(.text)
                    }
                    
                    ExportButton(icon: "curlybraces", title: "JSON", subtitle: "Structured data") {
                        await exportAs(.json)
                    }
                    
                    ExportButton(icon: "number", title: "Markdown", subtitle: "Markdown format") {
                        await exportAs(.markdown)
                    }
                    
                    ExportButton(icon: "table", title: "CSV", subtitle: "Spreadsheet compatible") {
                        await exportAs(.csv)
                    }
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isExporting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Exporting...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    func exportAs(_ format: ExportFormat) async {
        isExporting = true
        
        if let data = await viewModel.exportToFormat(format) {
            // Save or share the data
            let filename = "export.\(fileExtension(for: format))"
            if let url = saveToFiles(data: data, filename: filename) {
                shareFile(url: url)
            }
        }
        
        isExporting = false
        dismiss()
    }
    
    func fileExtension(for format: ExportFormat) -> String {
        switch format {
        case .pdf: return "pdf"
        case .text: return "txt"
        case .json: return "json"
        case .markdown: return "md"
        case .csv: return "csv"
        }
    }
    
    func saveToFiles(data: Data, filename: String) -> URL? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)
        return tempURL
    }
    
    func shareFile(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

struct ExportButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () async -> Void
    
    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
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
}

// MARK: - Camera Controls Bar (assumed existing)
struct CameraControlsBar: View {
    @Binding var pickedItem: PhotosPickerItem?
    let onCapture: () -> Void
    let onFlip: () -> Void
    
    var body: some View {
        HStack(spacing: 24) {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .padding()
                    .background(.ultraThinMaterial, in: Circle())
            }
            
            Button(action: onCapture) {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 68, height: 68)
                    .overlay(Circle().fill(.white).frame(width: 58, height: 58))
            }
            
            Button(action: onFlip) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title2)
                    .padding()
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Empty State View (assumed existing)
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No Documents Yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Scan documents to see them here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

// MARK: - Control Button (new)
struct ControlButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? .white : .primary)
                .frame(width: 44, height: 44)
                .background(
                    (isActive
                        ? AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color(.systemBackground).opacity(0.6))),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .stroke(isActive ? Color.white.opacity(0.8) : Color.primary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}
