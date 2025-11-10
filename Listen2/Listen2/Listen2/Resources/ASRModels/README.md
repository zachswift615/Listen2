# ASR Models

This directory contains Automatic Speech Recognition (ASR) models for Listen2.

## Whisper Tiny (INT8 Quantized)

### Source
- **Official Release**: https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2
- **Project**: [k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
- **Documentation**: https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/tiny.en.html

### Version
- Downloaded: July 13, 2024
- Model: Whisper Tiny (English, INT8 quantized)
- Runtime: sherpa-onnx with ONNX Runtime

### Files and Sizes
```
whisper-tiny/
├── tiny-encoder.int8.onnx  (12 MB)  - Quantized encoder model
├── tiny-decoder.int8.onnx  (86 MB)  - Quantized decoder model
└── tiny-tokens.txt         (798 KB) - Token vocabulary
```

**Total Size**: ~99 MB

### Comparison with Non-Quantized Models
The INT8 quantized models provide significant size reduction while maintaining good accuracy:

| Model Type | Encoder | Decoder | Total |
|------------|---------|---------|-------|
| INT8 (quantized) | 12 MB | 86 MB | ~99 MB |
| FP32 (original) | 36 MB | 109 MB | ~145 MB |

**Size Reduction**: ~32% smaller than FP32 models

### License
These models are derived from OpenAI's Whisper models and follow the same MIT License.

### Usage
These models are used by sherpa-onnx for offline speech recognition. They are automatically loaded by the ASRService in Listen2.

### Model Selection Rationale
- **Whisper Tiny**: Smallest Whisper variant, suitable for real-time processing
- **INT8 Quantization**: Reduced memory footprint and faster inference
- **English-only**: Optimized for English speech recognition
- **Offline**: No internet connection required

### Technical Details
- **Format**: ONNX (Open Neural Network Exchange)
- **Quantization**: INT8 post-training quantization
- **Input**: 16kHz mono audio
- **Output**: English text transcription

### References
- [Whisper Paper](https://arxiv.org/abs/2212.04356)
- [ONNX Runtime](https://onnxruntime.ai/)
- [sherpa-onnx Documentation](https://k2-fsa.github.io/sherpa/)
