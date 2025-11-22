//
//  OnnxInference.mm
//  Listen2
//
//  Objective-C++ implementation of ONNX Runtime wrapper.
//

#import "OnnxInference.h"
#import "onnxruntime_c_api.h"
#import <Foundation/Foundation.h>
#import <string>
#import <vector>

// Thread-local error message
static thread_local std::string g_lastError;

// ONNX Runtime API (global, retrieved once)
static const OrtApi* g_ortApi = nullptr;

// Get the ORT API, initializing if needed
static const OrtApi* GetOrtApi() {
    if (g_ortApi == nullptr) {
        g_ortApi = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    }
    return g_ortApi;
}

// Helper to set error message
static void SetError(const char* msg) {
    if (msg) {
        g_lastError = msg;
    } else {
        g_lastError.clear();
    }
}

// Helper to set error from OrtStatus
static void SetErrorFromStatus(const OrtApi* api, OrtStatus* status) {
    if (status != nullptr) {
        const char* msg = api->GetErrorMessage(status);
        SetError(msg);
        api->ReleaseStatus(status);
    } else {
        g_lastError.clear();
    }
}

// Session structure
struct OnnxSession {
    OrtEnv* env;
    OrtSession* session;
    OrtSessionOptions* sessionOptions;
    OrtMemoryInfo* memoryInfo;

    OnnxSession() : env(nullptr), session(nullptr), sessionOptions(nullptr), memoryInfo(nullptr) {}

    ~OnnxSession() {
        const OrtApi* api = GetOrtApi();
        if (api) {
            if (memoryInfo) api->ReleaseMemoryInfo(memoryInfo);
            if (session) api->ReleaseSession(session);
            if (sessionOptions) api->ReleaseSessionOptions(sessionOptions);
            if (env) api->ReleaseEnv(env);
        }
    }
};

extern "C" {

OnnxSession* OnnxSessionCreate(const char* model_path, int num_threads, int use_coreml) {
    const OrtApi* api = GetOrtApi();
    if (!api) {
        SetError("Failed to get ONNX Runtime API");
        return nullptr;
    }

    OnnxSession* sess = new OnnxSession();
    OrtStatus* status = nullptr;

    // Create environment
    status = api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "Listen2", &sess->env);
    if (status != nullptr) {
        SetErrorFromStatus(api, status);
        delete sess;
        return nullptr;
    }

    // Create session options
    status = api->CreateSessionOptions(&sess->sessionOptions);
    if (status != nullptr) {
        SetErrorFromStatus(api, status);
        delete sess;
        return nullptr;
    }

    // Set number of threads
    if (num_threads > 0) {
        status = api->SetIntraOpNumThreads(sess->sessionOptions, num_threads);
        if (status != nullptr) {
            SetErrorFromStatus(api, status);
            delete sess;
            return nullptr;
        }
    }

    // Set graph optimization level
    status = api->SetSessionGraphOptimizationLevel(sess->sessionOptions, ORT_ENABLE_ALL);
    if (status != nullptr) {
        SetErrorFromStatus(api, status);
        delete sess;
        return nullptr;
    }

    // CoreML execution provider not available in this build
    (void)use_coreml;

    // Create session from model file
    status = api->CreateSession(sess->env, model_path, sess->sessionOptions, &sess->session);
    if (status != nullptr) {
        SetErrorFromStatus(api, status);
        delete sess;
        return nullptr;
    }

    // Create CPU memory info for tensor creation
    status = api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &sess->memoryInfo);
    if (status != nullptr) {
        SetErrorFromStatus(api, status);
        delete sess;
        return nullptr;
    }

    g_lastError.clear();
    NSLog(@"[OnnxInference] Session created successfully: %s", model_path);
    return sess;
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
    if (!session || !input_data || !output_data) {
        SetError("Invalid parameters");
        return -1;
    }

    const OrtApi* api = GetOrtApi();
    if (!api) {
        SetError("Failed to get ONNX Runtime API");
        return -1;
    }

    OrtStatus* status = nullptr;
    OrtValue* input_tensor = nullptr;
    OrtValue* output_tensor = nullptr;

    // Calculate input size
    size_t input_size = 1;
    for (size_t i = 0; i < input_shape_len; i++) {
        input_size *= (size_t)input_shape[i];
    }

    // Create input tensor
    status = api->CreateTensorWithDataAsOrtValue(
        session->memoryInfo,
        (void*)input_data,
        input_size * sizeof(float),
        input_shape,
        input_shape_len,
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
        &input_tensor
    );
    if (status != nullptr) {
        SetErrorFromStatus(api, status);
        return -1;
    }

    // Prepare input/output names
    const char* input_names[] = { input_name };
    const char* output_names[] = { output_name };

    // Run inference
    status = api->Run(
        session->session,
        nullptr,  // run options
        input_names,
        (const OrtValue* const*)&input_tensor,
        1,  // num inputs
        output_names,
        1,  // num outputs
        &output_tensor
    );

    api->ReleaseValue(input_tensor);

    if (status != nullptr) {
        SetErrorFromStatus(api, status);
        return -1;
    }

    // Get output tensor info
    OrtTensorTypeAndShapeInfo* output_info = nullptr;
    status = api->GetTensorTypeAndShape(output_tensor, &output_info);
    if (status != nullptr) {
        SetErrorFromStatus(api, status);
        api->ReleaseValue(output_tensor);
        return -1;
    }

    // Get output dimensions
    size_t num_dims = 0;
    status = api->GetDimensionsCount(output_info, &num_dims);
    if (status != nullptr || num_dims > *output_shape_len) {
        if (status) SetErrorFromStatus(api, status);
        else SetError("Output shape buffer too small");
        api->ReleaseTensorTypeAndShapeInfo(output_info);
        api->ReleaseValue(output_tensor);
        return -1;
    }

    status = api->GetDimensions(output_info, output_shape, num_dims);
    if (status != nullptr) {
        SetErrorFromStatus(api, status);
        api->ReleaseTensorTypeAndShapeInfo(output_info);
        api->ReleaseValue(output_tensor);
        return -1;
    }
    *output_shape_len = num_dims;

    // Calculate output size
    size_t output_size = 1;
    for (size_t i = 0; i < num_dims; i++) {
        output_size *= (size_t)output_shape[i];
    }

    api->ReleaseTensorTypeAndShapeInfo(output_info);

    // Copy output data
    float* output_ptr = nullptr;
    status = api->GetTensorMutableData(output_tensor, (void**)&output_ptr);
    if (status != nullptr) {
        SetErrorFromStatus(api, status);
        api->ReleaseValue(output_tensor);
        return -1;
    }

    memcpy(output_data, output_ptr, output_size * sizeof(float));

    api->ReleaseValue(output_tensor);
    g_lastError.clear();

    return 0;
}

size_t OnnxSessionGetOutputSize(
    OnnxSession* session,
    const int64_t* input_shape,
    size_t input_shape_len,
    const char* output_name
) {
    // For MMS_FA model:
    // Input: [batch, samples] at 16kHz
    // Output: [batch, frames, vocab_size] where frames = samples / 320 (hop_size)
    // vocab_size = 29 for MMS_FA

    if (!session || input_shape_len < 2) {
        return 0;
    }

    int64_t batch = input_shape[0];
    int64_t samples = input_shape[1];

    // MMS_FA uses hop_size of 320 samples per frame
    int64_t frames = samples / 320;
    int64_t vocab_size = 29;  // MMS_FA vocabulary size

    (void)output_name;
    return (size_t)(batch * frames * vocab_size);
}

} // extern "C"
