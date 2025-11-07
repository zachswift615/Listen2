//
//  LibraryView.swift
//  Listen2
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: LibraryViewModel
    @State private var showingFilePicker = false
    @State private var showingReader = false
    @State private var selectedDocument: Document?
    @State private var showingSettings = false

    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(modelContext: modelContext))
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
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    if let url = try? result.get().first {
                        await viewModel.importDocument(from: url, sourceType: .pdf)
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
            .sheet(item: $selectedDocument) { document in
                ReaderView(document: document, modelContext: modelContext)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var documentList: some View {
        List {
            ForEach(viewModel.filteredDocuments) { document in
                Button {
                    selectedDocument = document
                } label: {
                    DocumentRowView(document: document)
                }
                .buttonStyle(.plain)
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
        EmptyStateView(
            icon: "books.vertical",
            title: "No Documents",
            message: "Import a PDF or paste text to get started"
        )
    }

    private var processingOverlay: some View {
        Color.clear
            .loadingOverlay(isLoading: true, message: "Processing...")
    }
}
