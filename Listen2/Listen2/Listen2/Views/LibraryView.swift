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
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @StateObject private var viewModel: LibraryViewModel
    @State private var showingFilePicker = false
    @State private var showingSettings = false
    @State private var showingDriveLinkSheet = false
    @State private var driveLinkText = ""
    @State private var navigationPath = NavigationPath()
    @State private var autoPlayDocument: Document?
    @Binding var urlToImport: URL?
    @Binding var siriReadClipboard: Bool

    init(modelContext: ModelContext, urlToImport: Binding<URL?> = .constant(nil), siriReadClipboard: Binding<Bool> = .constant(false)) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(modelContext: modelContext))
        _urlToImport = urlToImport
        _siriReadClipboard = siriReadClipboard
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                    .accessibilityLabel("Settings")
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
                    .accessibilityLabel("Add document")
                    .accessibilityHint("Import from file, clipboard, or link")
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
                ReaderView(
                    document: document,
                    modelContext: modelContext,
                    autoPlay: autoPlayDocument?.id == document.id
                )
                .environmentObject(ttsService)
                .environmentObject(purchaseManager)
                .onAppear {
                    // Clear autoPlay after navigation
                    if autoPlayDocument?.id == document.id {
                        autoPlayDocument = nil
                    }
                }
            }
            .onChange(of: siriReadClipboard) { _, shouldRead in
                guard shouldRead else { return }
                siriReadClipboard = false

                Task {
                    // Import clipboard content
                    guard let clipboardText = UIPasteboard.general.string else { return }
                    let document = await viewModel.importFromClipboardAndReturn(clipboardText)

                    // Navigate to the new document and auto-play
                    if let document = document {
                        autoPlayDocument = document
                        navigationPath.append(document)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(purchaseManager)
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
            .accessibilityHint("Load example documents to try the app")
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

        // Extract URL from text - handles case where user pastes text containing a URL
        guard let extractedURL = extractURLFromText(trimmed) else {
            await MainActor.run {
                viewModel.errorMessage = "Could not find a valid URL in the pasted text. Please paste a Google Drive or direct download link."
                viewModel.isProcessing = false
            }
            return
        }

        await MainActor.run {
            viewModel.isProcessing = true
            viewModel.errorMessage = nil
        }

        do {
            // Convert Google Drive share link to direct download URL if needed
            var downloadURL = try convertToDownloadURL(extractedURL)
            let isGoogleDrive = extractedURL.contains("drive.google.com") || extractedURL.contains("drive.usercontent.google.com")

            print("[Import] Downloading from: \(downloadURL)")

            // Download the file
            var (tempURL, response) = try await URLSession.shared.download(from: downloadURL)

            // Log response info for debugging
            if let httpResponse = response as? HTTPURLResponse {
                print("[Import] Status: \(httpResponse.statusCode)")
                print("[Import] Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "none")")
                print("[Import] Content-Disposition: \(httpResponse.value(forHTTPHeaderField: "Content-Disposition") ?? "none")")
            }
            print("[Import] Suggested filename: \(response.suggestedFilename ?? "none")")

            // Check if Google Drive returned HTML (virus scan warning page) instead of the file
            if isGoogleDrive,
               let httpResponse = response as? HTTPURLResponse,
               let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               contentType.contains("text/html") {
                print("[Import] Got HTML response from Google Drive, attempting to extract confirmation URL")

                // Read the HTML content to find the confirmation URL
                let htmlContent = try String(contentsOf: tempURL, encoding: .utf8)
                try? FileManager.default.removeItem(at: tempURL)

                if let confirmURL = extractGoogleDriveConfirmURL(from: htmlContent, originalURL: downloadURL) {
                    print("[Import] Found confirmation URL, retrying download")
                    downloadURL = confirmURL
                    (tempURL, response) = try await URLSession.shared.download(from: downloadURL)

                    // Log retry response
                    if let httpResponse = response as? HTTPURLResponse {
                        print("[Import] Retry Status: \(httpResponse.statusCode)")
                        print("[Import] Retry Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "none")")
                    }
                } else {
                    print("[Import] Could not extract confirmation URL from HTML")
                    await MainActor.run {
                        viewModel.errorMessage = "Could not download from Google Drive. Make sure the file's sharing is set to 'Anyone with the link' (not 'Restricted')."
                        viewModel.isProcessing = false
                    }
                    return
                }
            }

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

    /// Extracts the actual download URL from Google Drive's virus scan confirmation page
    private func extractGoogleDriveConfirmURL(from html: String, originalURL: URL) -> URL? {
        // Google Drive confirmation pages contain forms or links with the actual download URL
        // Look for patterns like:
        // - /uc?export=download&confirm=XXXX&id=FILE_ID
        // - action="...confirm=XXXX..."
        // - href="...confirm=XXXX..."
        // - uuid=XXXX (newer format)

        print("[Import] HTML length: \(html.count) characters")

        // Try to find the confirm token
        let patterns = [
            "confirm=([a-zA-Z0-9_-]+)&",  // confirm=TOKEN&
            "confirm=([a-zA-Z0-9_-]+)\"",  // confirm=TOKEN"
            "confirm=([a-zA-Z0-9_-]+)'",   // confirm=TOKEN'
            "/uc\\?export=download&amp;confirm=([a-zA-Z0-9_-]+)",  // URL-encoded in HTML
            "download_warning_[^\"']*=([a-zA-Z0-9_-]+)",  // Cookie-based token
            "uuid=([a-zA-Z0-9_-]+)",  // UUID format used in newer pages
            "at=([a-zA-Z0-9_-]+)"  // Auth token format
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let tokenRange = Range(match.range(at: 1), in: html) {
                let token = String(html[tokenRange])

                // Skip if token is just "t" (the generic one we already tried)
                if token == "t" { continue }

                // Build the new URL with the actual confirmation token
                if let fileID = extractFileID(from: originalURL) {
                    // Try the newer usercontent domain first
                    let confirmURLString = "https://drive.usercontent.google.com/download?id=\(fileID)&export=download&confirm=\(token)"
                    print("[Import] Extracted confirm token: \(token)")
                    return URL(string: confirmURLString)
                }
            }
        }

        // Also try to find a direct download link in the page
        let downloadLinkPatterns = [
            "href=\"(/uc\\?export=download[^\"]+)\"",
            "action=\"(/uc\\?export=download[^\"]+)\"",
            "href=\"(https://drive\\.usercontent\\.google\\.com/download[^\"]+)\"",
            "action=\"(https://drive\\.usercontent\\.google\\.com/download[^\"]+)\"",
            "form-action[^>]+action=\"([^\"]+)\""
        ]

        for pattern in downloadLinkPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let urlRange = Range(match.range(at: 1), in: html) {
                var urlPath = String(html[urlRange])
                // Decode HTML entities
                urlPath = urlPath.replacingOccurrences(of: "&amp;", with: "&")

                print("[Import] Found download link pattern: \(urlPath)")

                // Handle relative URLs
                if urlPath.hasPrefix("/") {
                    if let fullURL = URL(string: "https://drive.google.com\(urlPath)") {
                        print("[Import] Found direct download link: \(fullURL)")
                        return fullURL
                    }
                } else if urlPath.hasPrefix("http") {
                    if let fullURL = URL(string: urlPath) {
                        print("[Import] Found direct download link: \(fullURL)")
                        return fullURL
                    }
                }
            }
        }

        // Log a snippet of the HTML for debugging
        let previewLength = min(500, html.count)
        let preview = String(html.prefix(previewLength))
        print("[Import] HTML preview: \(preview)")

        return nil
    }

    /// Extracts a URL from text that may contain other content
    /// Handles cases where users paste logs or text that happens to contain a URL
    private func extractURLFromText(_ text: String) -> String? {
        // If it looks like a clean URL already, use it
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            // Check if it's JUST a URL (no spaces/newlines except at ends)
            let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanText.contains(" ") && !cleanText.contains("\n") {
                return cleanText
            }
        }

        // Try to find a URL in the text using data detector
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)

        if let match = detector?.firstMatch(in: text, options: [], range: range),
           let urlRange = Range(match.range, in: text) {
            let urlString = String(text[urlRange])
            // Prioritize Google Drive and common file hosting URLs
            if urlString.contains("drive.google.com") ||
               urlString.contains("dropbox.com") ||
               urlString.hasSuffix(".epub") ||
               urlString.hasSuffix(".pdf") ||
               urlString.hasSuffix(".txt") {
                return urlString
            }
        }

        // Search for all URLs and prioritize relevant ones
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        for match in matches {
            if let urlRange = Range(match.range, in: text) {
                let urlString = String(text[urlRange])
                if urlString.contains("drive.google.com") {
                    return urlString
                }
            }
        }

        // Fall back to first URL found
        if let match = matches.first,
           let urlRange = Range(match.range, in: text) {
            return String(text[urlRange])
        }

        return nil
    }

    /// Extracts the file ID from a Google Drive URL
    private func extractFileID(from url: URL) -> String? {
        // Try to get from URL query parameter
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let idItem = queryItems.first(where: { $0.name == "id" }),
           let id = idItem.value {
            return id
        }

        // Try to extract from path
        let urlString = url.absoluteString
        let pattern = "drive\\.google\\.com/file/d/([a-zA-Z0-9_-]+)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
           let idRange = Range(match.range(at: 1), in: urlString) {
            return String(urlString[idRange])
        }

        return nil
    }

    private func convertToDownloadURL(_ urlString: String) throws -> URL {
        // Handle Google Drive share links
        // Format: https://drive.google.com/file/d/FILE_ID/view?usp=sharing
        // Try multiple download URL formats as Google keeps changing their API

        if urlString.contains("drive.google.com/file/d/") {
            // Extract file ID using regex
            let pattern = "drive\\.google\\.com/file/d/([a-zA-Z0-9_-]+)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
                  let idRange = Range(match.range(at: 1), in: urlString) else {
                throw URLError(.badURL)
            }

            let fileID = String(urlString[idRange])

            // Use the newer drive.usercontent.google.com endpoint
            // This often works better for public files
            let downloadURLString = "https://drive.usercontent.google.com/download?id=\(fileID)&export=download&confirm=t"

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
