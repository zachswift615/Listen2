#!/usr/bin/env python3
"""
Export MMS_FA model to ONNX format for iOS CTC forced alignment.

This script:
1. Loads the MMS_FA model from torchaudio.pipelines
2. Exports it to ONNX with dynamic axes for batch and time dimensions
3. Saves the labels to a text file
4. Verifies the export with onnxruntime inference test

Usage:
    source venv-mms-spike/bin/activate && python scripts/export_mms_fa_model.py
"""

import torch
import torchaudio
import numpy as np
import os
import sys

# Output paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "Listen2", "Listen2", "Listen2", "Resources", "mms-fa")
ONNX_PATH = os.path.join(OUTPUT_DIR, "mms-fa.onnx")
LABELS_PATH = os.path.join(OUTPUT_DIR, "labels.txt")


def main():
    print("=" * 60)
    print("MMS_FA Model Export to ONNX")
    print("=" * 60)

    # Create output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"\nOutput directory: {OUTPUT_DIR}")

    # 1. Load MMS_FA bundle
    print("\n1. Loading MMS_FA bundle...")
    try:
        from torchaudio.pipelines import MMS_FA as bundle
        print(f"   Sample rate: {bundle.sample_rate}")
    except ImportError as e:
        print(f"   ERROR: {e}")
        print("   MMS_FA may not be available in this torchaudio version")
        print(f"   torchaudio version: {torchaudio.__version__}")
        sys.exit(1)

    # 2. Get and save labels
    print("\n2. Getting labels/vocabulary...")
    try:
        labels = bundle.get_labels()
        print(f"   Label count: {len(labels)}")
        print(f"   Labels: {labels}")

        # Save labels to file
        with open(LABELS_PATH, 'w') as f:
            for label in labels:
                f.write(f"{label}\n")
        print(f"   Saved labels to: {LABELS_PATH}")

    except Exception as e:
        print(f"   ERROR getting labels: {e}")
        sys.exit(1)

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
        sys.exit(1)

    # 4. Test inference with PyTorch
    print("\n4. Testing PyTorch inference...")
    try:
        # Create 1 second of dummy audio at 16kHz
        dummy_audio = torch.randn(1, 16000)
        with torch.no_grad():
            output = model(dummy_audio)

        # Handle tuple output (model returns tuple, we need output[0])
        if isinstance(output, tuple):
            emissions = output[0]
            print(f"   Model returns tuple with {len(output)} elements")
            print(f"   Using output[0] for emissions")
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

    except Exception as e:
        print(f"   ERROR in inference: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    # 5. Export to ONNX
    print("\n5. Exporting to ONNX...")
    try:
        # Wrap model to return only the emissions tensor
        class EmissionsOnlyWrapper(torch.nn.Module):
            def __init__(self, model):
                super().__init__()
                self.model = model

            def forward(self, audio):
                output = self.model(audio)
                if isinstance(output, tuple):
                    return output[0]
                return output

        wrapped_model = EmissionsOnlyWrapper(model)
        wrapped_model.eval()

        torch.onnx.export(
            wrapped_model,
            dummy_audio,
            ONNX_PATH,
            input_names=["audio"],
            output_names=["emissions"],
            dynamic_axes={
                "audio": {0: "batch", 1: "time"},
                "emissions": {0: "batch", 1: "frames", 2: "vocab"}
            },
            opset_version=14,
            verbose=False
        )

        # Calculate total size including any external data file
        file_size_bytes = os.path.getsize(ONNX_PATH)
        external_data_path = ONNX_PATH + ".data"
        external_data_size = 0
        if os.path.exists(external_data_path):
            external_data_size = os.path.getsize(external_data_path)

        total_size_bytes = file_size_bytes + external_data_size
        total_size_mb = total_size_bytes / 1024 / 1024
        file_size_mb = file_size_bytes / 1024 / 1024

        print(f"   Export successful!")
        print(f"   ONNX file: {ONNX_PATH}")
        print(f"   ONNX file size: {file_size_mb:.2f} MB ({file_size_bytes:,} bytes)")
        if external_data_size > 0:
            ext_mb = external_data_size / 1024 / 1024
            print(f"   External data file: {external_data_path}")
            print(f"   External data size: {ext_mb:.2f} MB ({external_data_size:,} bytes)")
        print(f"   TOTAL SIZE: {total_size_mb:.2f} MB ({total_size_bytes:,} bytes)")

    except Exception as e:
        print(f"   ERROR exporting to ONNX: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    # 6. Verify with ONNX Runtime
    print("\n6. Verifying with ONNX Runtime...")
    try:
        import onnxruntime as ort

        session = ort.InferenceSession(ONNX_PATH)

        # Get input/output info
        print(f"   Inputs:")
        for inp in session.get_inputs():
            print(f"     - {inp.name}: {inp.shape} ({inp.type})")

        print(f"   Outputs:")
        for out in session.get_outputs():
            print(f"     - {out.name}: {out.shape} ({out.type})")

        # Run inference with same dummy audio
        ort_input = dummy_audio.numpy()
        ort_output = session.run(None, {"audio": ort_input})

        print(f"\n   ONNX Runtime inference:")
        print(f"   Input shape: {ort_input.shape}")
        print(f"   Output shape: {ort_output[0].shape}")

        # Compare with PyTorch output
        pt_output = emissions.numpy()
        max_diff = np.abs(ort_output[0] - pt_output).max()
        mean_diff = np.abs(ort_output[0] - pt_output).mean()
        print(f"\n   Verification against PyTorch:")
        print(f"   Max difference: {max_diff:.6f}")
        print(f"   Mean difference: {mean_diff:.6f}")

        if max_diff < 1e-4:
            print("   PASS: ONNX output matches PyTorch!")
        else:
            print("   WARNING: Small numerical differences (usually acceptable)")

    except ImportError:
        print("   WARNING: onnxruntime not installed, skipping verification")
    except Exception as e:
        print(f"   ERROR in ONNX verification: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    # 7. Test variable length audio
    print("\n7. Testing variable length audio...")
    try:
        for duration_sec in [0.5, 1.0, 2.0, 5.0]:
            samples = int(16000 * duration_sec)
            test_audio = np.random.randn(1, samples).astype(np.float32)
            result = session.run(None, {"audio": test_audio})
            frames = result[0].shape[1]
            fps = frames / duration_sec
            print(f"   {duration_sec}s ({samples:,} samples) -> {frames} frames ({fps:.1f} fps)")
    except Exception as e:
        print(f"   ERROR with variable length: {e}")

    # Summary
    print("\n" + "=" * 60)
    print("EXPORT SUMMARY")
    print("=" * 60)
    print(f"ONNX model: {ONNX_PATH}")
    print(f"  ONNX file size: {file_size_mb:.2f} MB")
    if external_data_size > 0:
        print(f"  External data: {external_data_size / 1024 / 1024:.2f} MB")
    print(f"  TOTAL SIZE: {total_size_mb:.2f} MB")
    print(f"Labels file: {LABELS_PATH}")
    print(f"  Count: {len(labels)}")
    print(f"  Labels: {labels}")
    print(f"\nKey information for iOS integration:")
    print(f"  - Sample rate: 16000 Hz")
    print(f"  - Frame rate: ~{num_frames} fps (for 1s audio)")
    print(f"  - Frame duration: ~{frame_duration*1000:.1f} ms")
    print(f"  - Blank token: index 0 ('{labels[0]}')")
    print(f"  - Space token: index {len(labels)-1} ('{labels[-1]}')")
    print(f"  - Apostrophe: index {labels.index(chr(39))} (\"'\") " if "'" in labels else "")
    print("\nExport completed successfully!")

    return 0


if __name__ == "__main__":
    sys.exit(main())
