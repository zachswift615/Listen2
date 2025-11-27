//
//  LibraryView.swift
//  Listen2
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var ttsService: TTSService
    @StateObject private var viewModel: LibraryViewModel
    @State private var showingFilePicker = false
    @State private var showingSettings = false
    @State private var showingDriveLinkSheet = false
    @State private var driveLinkText = ""
    @Binding var urlToImport: URL?

    init(modelContext: ModelContext, urlToImport: Binding<URL?> = .constant(nil)) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(modelContext: modelContext))
        _urlToImport = urlToImport
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Main content
                if viewModel.filteredDocuments.isEmpty {
                    emptyStateView
                } else {
                    documentList
                }

                // Processing overlay
                if viewModel.isProcessing {
                    processingOverlay
                }
            }
            .navigationTitle("Library")
            .searchable(text: $viewModel.searchText, prompt: "Search documents")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task {
                                if let clipboardText = UIPasteboard.general.string {
                                    await viewModel.importFromClipboard(clipboardText)
                                }
                            }
                        } label: {
                            Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                        }

                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("Import File", systemImage: "plus")
                        }

                        Button {
                            driveLinkText = ""
                            showingDriveLinkSheet = true
                        } label: {
                            Label("Import from Link", systemImage: "link")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.pdf, .epub, .plainText, UTType(filenameExtension: "md") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    if let url = try? result.get().first {
                        await importFile(from: url)
                    }
                }
            }
            .onChange(of: urlToImport) { _, newURL in
                if let url = newURL {
                    Task {
                        await importFile(from: url)
                        urlToImport = nil
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .navigationDestination(for: Document.self) { document in
                ReaderView(document: document, modelContext: modelContext)
                    .environmentObject(ttsService)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingDriveLinkSheet) {
                importFromLinkSheet
            }
        }
    }

    private var importFromLinkSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste link here", text: $driveLinkText)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Google Drive or Direct Link")
                } footer: {
                    Text("Paste a Google Drive share link or a direct download URL to an EPUB, PDF, or text file.")
                }
            }
            .navigationTitle("Import from Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingDriveLinkSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        showingDriveLinkSheet = false
                        Task {
                            await importFromLink(driveLinkText)
                        }
                    }
                    .disabled(driveLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var documentList: some View {
        List {
            ForEach(viewModel.filteredDocuments) { document in
                NavigationLink(value: document) {
                    DocumentRowView(document: document)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteDocument(document)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            EmptyStateView(
                icon: "books.vertical",
                title: "No Documents",
                message: "Import a PDF, EPUB, or paste text to get started"
            )

            Button {
                Task {
                    await viewModel.importSampleDocuments()
                }
            } label: {
                Label("Try Sample Content", systemImage: "star.fill")
            }
            .buttonStyle(.primary)
        }
    }

    private var processingOverlay: some View {
        Color.clear
            .loadingOverlay(isLoading: true, message: "Importing document...")
    }

    private func importFile(from url: URL) async {
        // Determine source type from file extension
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "epub":
            await viewModel.importDocument(from: url, sourceType: .epub)
        case "pdf":
            await viewModel.importDocument(from: url, sourceType: .pdf)
        case "txt", "md", "markdown":
            // Import text files with proper filename handling
            await viewModel.importTextFile(from: url)
        default:
            // Default to PDF for unknown extensions
            await viewModel.importDocument(from: url, sourceType: .pdf)
        }
    }

    private func importFromLink(_ linkText: String) async {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await MainActor.run {
            viewModel.isProcessing = true
            viewModel.errorMessage = nil
        }

        do {
            // Convert Google Drive share link to direct download URL if needed
            let downloadURL = try convertToDownloadURL(trimmed)

            print("[Import] Downloading from: \(downloadURL)")

            // Download the file
            let (tempURL, response) = try await URLSession.shared.download(from: downloadURL)

            // Log response info for debugging
            if let httpResponse = response as? HTTPURLResponse {
                print("[Import] Status: \(httpResponse.statusCode)")
                print("[Import] Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "none")")
                print("[Import] Content-Disposition: \(httpResponse.value(forHTTPHeaderField: "Content-Disposition") ?? "none")")
            }
            print("[Import] Suggested filename: \(response.suggestedFilename ?? "none")")

            // Try to determine filename from Content-Disposition header or URL
            guard let filename = extractFilename(from: response, url: downloadURL) else {
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)

                await MainActor.run {
                    viewModel.errorMessage = "Could not determine file type. Make sure the link points to an EPUB, PDF, or text file."
                    viewModel.isProcessing = false
                }
                return
            }

            print("[Import] Using filename: \(filename)")

            // Move to a proper location with the correct extension
            let documentsDir = FileManager.default.temporaryDirectory
            let destinationURL = documentsDir.appendingPathComponent(filename)

            // Remove existing file if present
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            // Import based on file type
            await importFile(from: destinationURL)

            // Clean up temp file after import
            try? FileManager.default.removeItem(at: destinationURL)

        } catch {
            await MainActor.run {
                viewModel.errorMessage = "Failed to import from link: \(error.localizedDescription)"
                viewModel.isProcessing = false
            }
        }
    }

    private func convertToDownloadURL(_ urlString: String) throws -> URL {
        // Handle Google Drive share links
        // Format: https://drive.google.com/file/d/FILE_ID/view?usp=sharing
        // Convert to: https://drive.google.com/uc?export=download&confirm=t&id=FILE_ID
        // The confirm=t parameter bypasses the virus scan warning for large files

        if urlString.contains("drive.google.com/file/d/") {
            // Extract file ID using regex
            let pattern = "drive\\.google\\.com/file/d/([a-zA-Z0-9_-]+)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
                  let idRange = Range(match.range(at: 1), in: urlString) else {
                throw URLError(.badURL)
            }

            let fileID = String(urlString[idRange])
            let downloadURLString = "https://drive.google.com/uc?export=download&confirm=t&id=\(fileID)"

            guard let url = URL(string: downloadURLString) else {
                throw URLError(.badURL)
            }
            return url
        }

        // For other URLs, use as-is
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        return url
    }

    private func extractFilename(from response: URLResponse, url: URL) -> String? {
        // Try Content-Disposition header first
        if let httpResponse = response as? HTTPURLResponse,
           let contentDisposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition") {
            // Parse filename from Content-Disposition: attachment; filename="book.epub"
            // Also handle filename*=UTF-8''encoded%20name.epub format
            let patterns = [
                "filename\\*=(?:UTF-8'')?([^;\\s]+)",  // filename*=UTF-8''name.epub
                "filename=[\"']([^\"']+)[\"']",        // filename="name.epub"
                "filename=([^;\\s]+)"                   // filename=name.epub
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: contentDisposition, range: NSRange(contentDisposition.startIndex..., in: contentDisposition)),
                   let range = Range(match.range(at: 1), in: contentDisposition) {
                    var filename = String(contentDisposition[range])
                    // URL decode if needed
                    if let decoded = filename.removingPercentEncoding {
                        filename = decoded
                    }
                    if filename.contains(".") {
                        return filename
                    }
                }
            }
        }

        // Try suggested filename from response (often works well for Google Drive)
        if let suggested = response.suggestedFilename, suggested.contains(".") {
            return suggested
        }

        // Fall back to URL path component
        let lastComponent = url.lastPathComponent
        if !lastComponent.isEmpty && lastComponent != "/" && lastComponent.contains(".") {
            return lastComponent
        }

        // Last resort: infer extension from Content-Type
        if let httpResponse = response as? HTTPURLResponse,
           let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            let ext: String?
            if contentType.contains("epub") {
                ext = "epub"
            } else if contentType.contains("pdf") {
                ext = "pdf"
            } else if contentType.contains("text/plain") {
                ext = "txt"
            } else {
                ext = nil
            }

            if let ext = ext {
                return "downloaded_file.\(ext)"
            }
        }

        return nil
    }
}
