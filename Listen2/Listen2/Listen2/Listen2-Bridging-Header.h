//
//  Listen2-Bridging-Header.h
//  Listen2
//
//  Bridging header for C APIs
//

#ifndef Listen2_Bridging_Header_h
#define Listen2_Bridging_Header_h

// Import sherpa-onnx C API
#import <sherpa-onnx/c-api/c-api.h>

// Import VoxPDF C API
#import "voxpdf.h"

// Import ONNX Runtime wrapper for CTCForcedAligner
#import "OnnxInference.h"

#endif /* Listen2_Bridging_Header_h */
