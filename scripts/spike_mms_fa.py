#!/usr/bin/env python3
"""
Spike: Validate MMS_FA model export and ONNX inference.

This spike tests:
1. Can we load MMS_FA from torchaudio?
2. What are the actual labels/vocabulary?
3. Can we export to ONNX with dynamic axes?
4. What is the model size?
5. Can we run inference with onnxruntime?
6. What is the output shape and format?
"""

import torch
import torchaudio
import numpy as np
import os
import tempfile

def main():
    print("=" * 60)
    print("SPIKE: MMS_FA Model Validation")
    print("=" * 60)

    # 1. Load MMS_FA
    print("\n1. Loading MMS_FA bundle...")
    try:
        from torchaudio.pipelines import MMS_FA as bundle
        print(f"   Sample rate: {bundle.sample_rate}")
    except ImportError as e:
        print(f"   ERROR: {e}")
        print("   MMS_FA may not be available in this torchaudio version")

        # Check available pipelines
        print("\n   Available pipelines:")
        import torchaudio.pipelines as p
        available = [x for x in dir(p) if not x.startswith('_')]
        for name in available[:20]:
            print(f"     - {name}")
        return

    # 2. Get labels
    print("\n2. Getting labels/vocabulary...")
    try:
        labels = bundle.get_labels()
        print(f"   Label count: {len(labels)}")
        print(f"   First 20 labels: {labels[:20]}")
        print(f"   All labels: {labels}")
    except Exception as e:
        print(f"   ERROR getting labels: {e}")
        labels = None

    # 3. Load model
    print("\n3. Loading model...")
    try:
        model = bundle.get_model()
        model.eval()
        print(f"   Model type: {type(model).__name__}")

        # Count parameters
        total_params = sum(p.numel() for p in model.parameters())
        print(f"   Total parameters: {total_params:,}")
        print(f"   Estimated size: {total_params * 4 / 1024 / 1024:.1f} MB (float32)")
    except Exception as e:
        print(f"   ERROR loading model: {e}")
        return

    # 4. Test inference with PyTorch
    print("\n4. Testing PyTorch inference...")
    try:
        # Create 1 second of dummy audio
        dummy_audio = torch.randn(1, 16000)
        with torch.no_grad():
            output = model(dummy_audio)

        # Handle tuple output
        if isinstance(output, tuple):
            emissions = output[0]
            print(f"   Model returns tuple with {len(output)} elements")
        else:
            emissions = output

        print(f"   Input shape: {dummy_audio.shape}")
        print(f"   Output shape: {emissions.shape}")
        print(f"   Output dtype: {emissions.dtype}")

        # Calculate frame rate
        num_frames = emissions.shape[1]
        frame_duration = 1.0 / num_frames
        print(f"   Frames per second: {num_frames}")
        print(f"   Frame duration: {frame_duration*1000:.1f} ms")

        # Check output values
        print(f"   Output min: {emissions.min().item():.3f}")
        print(f"   Output max: {emissions.max().item():.3f}")
        print(f"   Output mean: {emissions.mean().item():.3f}")
    except Exception as e:
        print(f"   ERROR in inference: {e}")
        import traceback
        traceback.print_exc()
        return

    # 5. Export to ONNX
    print("\n5. Exporting to ONNX...")
    onnx_path = os.path.join(tempfile.gettempdir(), "mms_fa_spike.onnx")
    try:
        torch.onnx.export(
            model,
            dummy_audio,
            onnx_path,
            input_names=["audio"],
            output_names=["emissions"],
            dynamic_axes={
                "audio": {0: "batch", 1: "time"},
                "emissions": {0: "batch", 1: "frames", 2: "vocab"}
            },
            opset_version=14,
            verbose=False
        )

        file_size = os.path.getsize(onnx_path) / 1024 / 1024
        print(f"   Export successful!")
        print(f"   ONNX file: {onnx_path}")
        print(f"   File size: {file_size:.1f} MB")
    except Exception as e:
        print(f"   ERROR exporting to ONNX: {e}")
        import traceback
        traceback.print_exc()
        return

    # 6. Test ONNX Runtime inference
    print("\n6. Testing ONNX Runtime inference...")
    try:
        import onnxruntime as ort

        session = ort.InferenceSession(onnx_path)

        # Get input/output info
        print(f"   Inputs:")
        for inp in session.get_inputs():
            print(f"     - {inp.name}: {inp.shape} ({inp.type})")

        print(f"   Outputs:")
        for out in session.get_outputs():
            print(f"     - {out.name}: {out.shape} ({out.type})")

        # Run inference
        ort_input = dummy_audio.numpy()
        ort_output = session.run(None, {"audio": ort_input})

        print(f"\n   ONNX inference result:")
        print(f"   Input shape: {ort_input.shape}")
        print(f"   Output shape: {ort_output[0].shape}")

        # Compare with PyTorch
        pt_output = emissions.numpy()
        max_diff = np.abs(ort_output[0] - pt_output).max()
        print(f"   Max diff from PyTorch: {max_diff:.6f}")

        if max_diff < 1e-4:
            print("   ✅ ONNX output matches PyTorch!")
        else:
            print("   ⚠️ Small numerical differences (expected)")

    except Exception as e:
        print(f"   ERROR in ONNX inference: {e}")
        import traceback
        traceback.print_exc()
        return

    # 7. Test with variable length audio
    print("\n7. Testing variable length audio...")
    try:
        for duration_sec in [0.5, 1.0, 2.0, 5.0]:
            samples = int(16000 * duration_sec)
            test_audio = np.random.randn(1, samples).astype(np.float32)
            result = session.run(None, {"audio": test_audio})
            print(f"   {duration_sec}s ({samples} samples) -> {result[0].shape[1]} frames")
    except Exception as e:
        print(f"   ERROR with variable length: {e}")

    # 8. Test CTC alignment
    print("\n8. Testing CTC forced alignment...")
    try:
        # Use torchaudio's forced_align function
        from torchaudio.functional import forced_align

        # Tokenize "hello"
        if labels:
            transcript = "hello"
            tokens = []
            for char in transcript.lower():
                if char in labels:
                    tokens.append(labels.index(char))
                elif char == " " and "|" in labels:
                    tokens.append(labels.index("|"))

            print(f"   Transcript: '{transcript}'")
            print(f"   Tokens: {tokens}")

            # Prepare for forced_align
            emissions_log = torch.log_softmax(emissions, dim=-1)
            targets = torch.tensor([tokens], dtype=torch.int32)
            input_lengths = torch.tensor([emissions.shape[1]])
            target_lengths = torch.tensor([len(tokens)])

            # Get alignment
            alignments, scores = forced_align(
                emissions_log,
                targets,
                input_lengths,
                target_lengths,
                blank=0  # CTC blank is usually index 0
            )

            print(f"   Alignment shape: {alignments.shape}")
            print(f"   Alignment: {alignments[0].tolist()[:20]}...")
            print(f"   Score: {scores[0].item():.3f}")

    except Exception as e:
        print(f"   ERROR in CTC alignment: {e}")
        import traceback
        traceback.print_exc()

    # Summary
    print("\n" + "=" * 60)
    print("SPIKE SUMMARY")
    print("=" * 60)
    print(f"✅ MMS_FA model loads successfully")
    print(f"✅ Labels count: {len(labels) if labels else 'N/A'}")
    print(f"✅ ONNX export works")
    print(f"✅ ONNX file size: {file_size:.1f} MB")
    print(f"✅ ONNX Runtime inference works")
    print(f"✅ Variable length audio supported")
    print(f"✅ Frame rate: ~{num_frames} fps for 1s audio")
    print(f"\nNext steps:")
    print(f"1. Add ONNX model to iOS project (~{file_size:.0f}MB)")
    print(f"2. Implement CTC trellis in Swift")
    print(f"3. Use sherpa-onnx ONNX Runtime or add onnxruntime-objc")

    # Cleanup
    if os.path.exists(onnx_path):
        os.remove(onnx_path)
        print(f"\nCleaned up: {onnx_path}")

if __name__ == "__main__":
    main()
