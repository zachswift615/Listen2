# Performance Baseline

## VoxPDF Performance Tests

This document tracks performance benchmarks for VoxPDF text and TOC extraction operations.

### Test Environment

- **Device**: iPhone 16 Simulator
- **OS Version**: iOS 18.3.1
- **Date**: 2025-11-09
- **VoxPDF Version**: voxpdf-core (via VoxPDFCore.xcframework)
- **Xcode**: 16C5032a

### Performance Tests

#### 1. PDF Text Extraction (Paragraphs)
**Test**: `testPDFExtractionPerformance()`
- **Method**: `VoxPDFService.extractParagraphs(from:)`
- **Baseline**: *Not yet measured - requires test PDF*
- **Status**: Test infrastructure complete

#### 2. PDF Text Extraction (Raw Text)
**Test**: `testTextExtractionPerformance()`
- **Method**: `VoxPDFService.extractText(from:)`
- **Baseline**: *Not yet measured - requires test PDF*
- **Status**: Test infrastructure complete

#### 3. TOC Extraction
**Test**: `testTOCExtractionPerformance()`
- **Method**: `VoxPDFService.extractTOC(from:paragraphs:)`
- **Baseline**: *Not yet measured - requires test PDF*
- **Status**: Test infrastructure complete

#### 4. Word Position Extraction
**Test**: `testWordPositionExtractionPerformance()`
- **Method**: `VoxPDFService.extractWordPositions(from:)`
- **Baseline**: *Not yet measured - requires test PDF*
- **Status**: Test infrastructure complete

### Running Performance Tests

```bash
cd Listen2/Listen2/Listen2
xcodebuild test -scheme Listen2 \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:Listen2Tests/VoxPDFPerformanceTests
```

### Adding Test PDFs

To enable performance measurement, add a test PDF to the test bundle:

1. Add `large-document.pdf` to `Listen2Tests` target in Xcode
2. Ensure it's included in the test bundle resources
3. Run the performance tests to establish baseline metrics

Recommended test PDF characteristics:
- 100+ pages for meaningful performance measurement
- Contains both text and table of contents
- Represents typical user documents

### VoxPDF vs PDFKit Comparison

**Planned**: Add comparative performance tests between VoxPDF and PDFKit once test PDFs are available.

Expected metrics to compare:
- Text extraction speed (pages/second)
- Memory usage during extraction
- TOC extraction accuracy and speed
- Word-level position extraction performance

### Notes

- All tests use `XCTest.measure {}` block for performance measurement
- Tests gracefully skip via `XCTSkip` if test PDF not available
- Performance tests run with `.userInitiated` priority
- Async operations use XCTestExpectation with 10-second timeout

### Future Work

1. Add real-world test PDFs of varying sizes (10, 50, 100+ pages)
2. Establish baseline metrics for each test
3. Add PDFKit comparison tests
4. Set up performance regression monitoring
5. Document memory usage patterns
6. Add performance budgets for each operation
