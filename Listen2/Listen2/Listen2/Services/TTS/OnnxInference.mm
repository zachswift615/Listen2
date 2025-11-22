//
//  OnnxInference.mm
//  Listen2
//
//  Objective-C++ implementation of ONNX Runtime wrapper.
//  Provides stub implementation if ONNX Runtime headers are not available.
//

#import "OnnxInference.h"
#import <Foundation/Foundation.h>
#import <string>

// Thread-local error message
static thread_local std::string g_lastError;

// Helper to set error message
static void SetError(const char* msg) {
    if (msg) {
        g_lastError = msg;
    } else {
        g_lastError.clear();
    }
}

// Stub session structure
struct OnnxSession {
    // Empty - real implementation would hold ORT objects
};

extern "C" {

OnnxSession* OnnxSessionCreate(const char* model_path, int num_threads, int use_coreml) {
    // Stub implementation - ONNX Runtime not configured
    // To enable: add onnxruntime.xcframework/Headers to Header Search Paths
    SetError("ONNX Runtime not available - stub implementation");
    NSLog(@"[OnnxInference] STUB: Would create session for: %s", model_path);
    (void)num_threads;
    (void)use_coreml;
    return nullptr;
}

void OnnxSessionDestroy(OnnxSession* session) {
    if (session) {
        delete session;
    }
}

const char* OnnxSessionGetLastError(void) {
    if (g_lastError.empty()) {
        return nullptr;
    }
    return g_lastError.c_str();
}

int OnnxSessionRun(
    OnnxSession* session,
    const char* input_name,
    const float* input_data,
    const int64_t* input_shape,
    size_t input_shape_len,
    const char* output_name,
    float* output_data,
    int64_t* output_shape,
    size_t* output_shape_len
) {
    SetError("ONNX Runtime not available - stub implementation");
    (void)session;
    (void)input_name;
    (void)input_data;
    (void)input_shape;
    (void)input_shape_len;
    (void)output_name;
    (void)output_data;
    (void)output_shape;
    (void)output_shape_len;
    return -1;
}

size_t OnnxSessionGetOutputSize(
    OnnxSession* session,
    const int64_t* input_shape,
    size_t input_shape_len,
    const char* output_name
) {
    // For MMS_FA model estimation
    if (!session || input_shape_len < 2) {
        return 0;
    }

    int64_t samples = input_shape[1];
    int64_t frames = samples / 320;  // hop_size
    int64_t vocab_size = 29;

    (void)output_name;
    return (size_t)(frames * vocab_size);
}

} // extern "C"
