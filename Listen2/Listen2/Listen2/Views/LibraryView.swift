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
        }
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
}
