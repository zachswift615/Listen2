#!/usr/bin/env python3
"""Test INT8 quantization accuracy for MMS_FA forced alignment."""

import numpy as np
import os
import onnxruntime as ort
from onnxruntime.quantization import quantize_dynamic, QuantType

# Paths
script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(script_dir)
model_dir = os.path.join(project_root, "Listen2/Listen2/Listen2/Resources/mms-fa")
fp32_model = os.path.join(model_dir, "mms-fa.onnx")
int8_model = os.path.join(model_dir, "mms-fa-int8.onnx")

print("=" * 60)
print("MMS_FA INT8 Quantization Test")
print("=" * 60)

# 1. Quantize with dynamic INT8
print("\n1. Quantizing to INT8...")
try:
    # Skip Conv operations which have dynamic weights in this model
    # Focus on MatMul/Gemm which are the bulk of the model
    quantize_dynamic(
        model_input=fp32_model,
        model_output=int8_model,
        weight_type=QuantType.QInt8,
        extra_options={"MatMulConstBOnly": True},
        op_types_to_quantize=['MatMul', 'Gemm']  # Skip Conv
    )

    # Check sizes
    fp32_size = os.path.getsize(fp32_model) / 1024 / 1024
    fp32_data_size = os.path.getsize(fp32_model + ".data") / 1024 / 1024
    int8_size = os.path.getsize(int8_model) / 1024 / 1024
    int8_data_path = int8_model + ".data"
    int8_data_size = os.path.getsize(int8_data_path) / 1024 / 1024 if os.path.exists(int8_data_path) else 0

    print(f"   FP32 model: {fp32_size:.1f} MB + {fp32_data_size:.1f} MB data = {fp32_size + fp32_data_size:.1f} MB total")
    print(f"   INT8 model: {int8_size:.1f} MB + {int8_data_size:.1f} MB data = {int8_size + int8_data_size:.1f} MB total")
    print(f"   Compression ratio: {(fp32_size + fp32_data_size) / (int8_size + int8_data_size):.1f}x")
except Exception as e:
    print(f"   ERROR: {e}")
    import traceback
    traceback.print_exc()
    exit(1)

# 2. Load both models
print("\n2. Loading models for comparison...")
try:
    sess_fp32 = ort.InferenceSession(fp32_model)
    sess_int8 = ort.InferenceSession(int8_model)
    print("   Both models loaded successfully")
except Exception as e:
    print(f"   ERROR: {e}")
    exit(1)

# 3. Test with multiple audio samples
print("\n3. Comparing frame-level emissions...")

test_cases = [
    ("1 second silence", np.zeros((1, 16000), dtype=np.float32)),
    ("1 second noise", np.random.randn(1, 16000).astype(np.float32) * 0.1),
    ("2 seconds noise", np.random.randn(1, 32000).astype(np.float32) * 0.1),
    ("5 seconds noise", np.random.randn(1, 80000).astype(np.float32) * 0.1),
]

all_diffs = []
for name, audio in test_cases:
    fp32_out = sess_fp32.run(None, {"audio": audio})[0]
    int8_out = sess_int8.run(None, {"audio": audio})[0]

    # Compute differences
    abs_diff = np.abs(fp32_out - int8_out)
    max_diff = abs_diff.max()
    mean_diff = abs_diff.mean()

    # Check if argmax (predicted token) matches at each frame
    fp32_argmax = np.argmax(fp32_out, axis=-1)
    int8_argmax = np.argmax(int8_out, axis=-1)
    matching_frames = np.sum(fp32_argmax == int8_argmax)
    total_frames = fp32_argmax.size
    match_rate = matching_frames / total_frames * 100

    all_diffs.append({
        "name": name,
        "max_diff": max_diff,
        "mean_diff": mean_diff,
        "match_rate": match_rate,
        "frames": total_frames
    })

    print(f"\n   {name}:")
    print(f"     Frames: {total_frames}")
    print(f"     Max logit diff: {max_diff:.4f}")
    print(f"     Mean logit diff: {mean_diff:.6f}")
    print(f"     Argmax match rate: {match_rate:.1f}% ({matching_frames}/{total_frames})")

# 4. Test forced alignment accuracy
print("\n4. Testing forced alignment consistency...")
try:
    import torch
    from torchaudio.functional import forced_align

    # Get emissions for alignment test
    test_audio = np.random.randn(1, 32000).astype(np.float32) * 0.1
    fp32_emissions = sess_fp32.run(None, {"audio": test_audio})[0]
    int8_emissions = sess_int8.run(None, {"audio": test_audio})[0]

    # Convert to log softmax for CTC
    fp32_log = torch.log_softmax(torch.from_numpy(fp32_emissions), dim=-1)
    int8_log = torch.log_softmax(torch.from_numpy(int8_emissions), dim=-1)

    # Test transcript: "hello world"
    # Labels: ['-', 'a', 'i', 'e', 'n', 'o', 'u', 't', 's', 'r', 'm', 'k', 'l', 'd', 'g', 'h', 'y', 'b', 'p', 'w', 'c', 'v', 'j', 'z', 'f', "'", 'q', 'x', '*']
    # h=15, e=3, l=12, o=5, *=28, w=19, r=9, d=13
    tokens = torch.tensor([[15, 3, 12, 12, 5, 28, 19, 5, 9, 12, 13]], dtype=torch.int32)
    input_lengths = torch.tensor([fp32_emissions.shape[1]])
    target_lengths = torch.tensor([11])

    fp32_align, fp32_scores = forced_align(fp32_log, tokens, input_lengths, target_lengths, blank=0)
    int8_align, int8_scores = forced_align(int8_log, tokens, input_lengths, target_lengths, blank=0)

    # Compare alignments
    fp32_path = fp32_align[0].numpy()
    int8_path = int8_align[0].numpy()

    # Find word boundaries (token transitions)
    def get_word_boundaries(path, tokens_flat):
        boundaries = []
        current_token = -1
        for frame, token_idx in enumerate(path):
            if token_idx != 0 and token_idx != current_token:  # Not blank and new token
                if token_idx == 28:  # Space token - word boundary
                    boundaries.append(frame)
                current_token = token_idx
        return boundaries

    tokens_flat = tokens[0].numpy()
    fp32_boundaries = get_word_boundaries(fp32_path, tokens_flat)
    int8_boundaries = get_word_boundaries(int8_path, tokens_flat)

    print(f"   FP32 word boundaries: {fp32_boundaries}")
    print(f"   INT8 word boundaries: {int8_boundaries}")

    if len(fp32_boundaries) == len(int8_boundaries):
        diffs_frames = [abs(a - b) for a, b in zip(fp32_boundaries, int8_boundaries)]
        diffs_ms = [d * 20 for d in diffs_frames]  # 20ms per frame
        print(f"   Boundary differences: {diffs_frames} frames = {diffs_ms} ms")
        max_boundary_diff_ms = max(diffs_ms) if diffs_ms else 0
        print(f"   Max boundary difference: {max_boundary_diff_ms} ms")
    else:
        print(f"   WARNING: Different number of boundaries detected")

except Exception as e:
    print(f"   Forced alignment test skipped: {e}")

# 5. Summary
print("\n" + "=" * 60)
print("SUMMARY")
print("=" * 60)
avg_match = sum(d["match_rate"] for d in all_diffs) / len(all_diffs)
max_logit_diff = max(d["max_diff"] for d in all_diffs)
print(f"Average argmax match rate: {avg_match:.1f}%")
print(f"Maximum logit difference: {max_logit_diff:.4f}")
print(f"INT8 model size: {int8_size + int8_data_size:.1f} MB")

if avg_match >= 95:
    print("\n[PASS] INT8 quantization looks SAFE for forced alignment")
    print("   Frame-level predictions are highly consistent with FP32")
elif avg_match >= 90:
    print("\n[WARN] INT8 quantization is ACCEPTABLE but may have minor drift")
    print("   Consider testing with real audio samples")
else:
    print("\n[FAIL] INT8 quantization may cause SIGNIFICANT accuracy loss")
    print("   Consider FP16 or quantization-aware training")

print(f"\nINT8 model saved to: {int8_model}")
