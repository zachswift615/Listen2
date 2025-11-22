//
//  OnnxInference.h
//  Listen2
//
//  C wrapper for ONNX Runtime inference operations.
//  Provides a simple API for running ONNX models from Swift.
//

#ifndef OnnxInference_h
#define OnnxInference_h

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle for an ONNX inference session
typedef struct OnnxSession OnnxSession;

/// Create a new ONNX inference session
/// @param model_path Path to the .onnx model file
/// @param num_threads Number of threads for inference (0 = default)
/// @param use_coreml Whether to use CoreML execution provider (1 = yes, 0 = no)
/// @return Session handle, or NULL on failure
OnnxSession* OnnxSessionCreate(const char* model_path, int num_threads, int use_coreml);

/// Destroy an ONNX inference session
/// @param session Session to destroy
void OnnxSessionDestroy(OnnxSession* session);

/// Get the last error message (if any)
/// @return Error message string, or NULL if no error
const char* OnnxSessionGetLastError(void);

/// Run inference with float input and get float output
/// @param session The session to use
/// @param input_name Name of the input tensor (e.g., "input")
/// @param input_data Pointer to input float data
/// @param input_shape Array of input dimensions
/// @param input_shape_len Number of input dimensions
/// @param output_name Name of the output tensor (e.g., "logits")
/// @param output_data Pointer to output float buffer (must be pre-allocated)
/// @param output_shape Output dimensions (filled by this function)
/// @param output_shape_len Number of output dimensions (in/out parameter)
/// @return 0 on success, non-zero on failure
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
);

/// Get expected output size for a given input shape (for pre-allocating buffers)
/// @param session The session to use
/// @param input_shape Array of input dimensions
/// @param input_shape_len Number of input dimensions
/// @param output_name Name of the output tensor
/// @return Expected number of output elements, or 0 on failure
size_t OnnxSessionGetOutputSize(
    OnnxSession* session,
    const int64_t* input_shape,
    size_t input_shape_len,
    const char* output_name
);

#ifdef __cplusplus
}
#endif

#endif /* OnnxInference_h */
