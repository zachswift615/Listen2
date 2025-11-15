#!/bin/bash
#
# Export a Piper model with w_ceil and copy to Listen2 Resources
#
# Usage:
#   ./scripts/export-and-update-model.sh <checkpoint-path> <model-name>
#
# Example:
#   ./scripts/export-and-update-model.sh \
#     ~/projects/piper/checkpoints/lessac-high/en/en_US/lessac/high/epoch=2218-step=838782.ckpt \
#     en_US-lessac-high

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PIPER_DIR="$HOME/projects/piper"
MODELS_DIR="$PIPER_DIR/models"
RESOURCES_DIR="$PROJECT_ROOT/Listen2/Listen2/Listen2/Resources/PiperModels"

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <checkpoint-path> <model-name>"
    echo ""
    echo "Example:"
    echo "  $0 ~/projects/piper/checkpoints/lessac-high/en/en_US/lessac/high/epoch=2218-step=838782.ckpt en_US-lessac-high"
    exit 1
fi

CHECKPOINT="$1"
MODEL_NAME="$2"

# Validate inputs
if [ ! -f "$CHECKPOINT" ]; then
    echo "❌ Error: Checkpoint not found: $CHECKPOINT"
    exit 1
fi

if [ ! -d "$PIPER_DIR" ]; then
    echo "❌ Error: Piper directory not found: $PIPER_DIR"
    exit 1
fi

if [ ! -d "$RESOURCES_DIR" ]; then
    echo "❌ Error: Resources directory not found: $RESOURCES_DIR"
    exit 1
fi

# Output paths
OUTPUT_MODEL="$MODELS_DIR/${MODEL_NAME}.onnx"
DEST_MODEL="$RESOURCES_DIR/${MODEL_NAME}.onnx"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Exporting Piper Model with w_ceil"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Checkpoint:  $CHECKPOINT"
echo "Model name:  $MODEL_NAME"
echo "Output:      $OUTPUT_MODEL"
echo "Destination: $DEST_MODEL"
echo ""

# Step 1: Export the model
echo "📦 Step 1: Exporting model..."
cd "$PIPER_DIR"
source venv/bin/activate
python3 -m piper_train.export_onnx "$CHECKPOINT" "$OUTPUT_MODEL"

if [ ! -f "$OUTPUT_MODEL" ]; then
    echo "❌ Export failed - model not created"
    exit 1
fi

# Step 2: Verify model has w_ceil and metadata
echo ""
echo "✅ Step 2: Verifying model..."
python3 << EOF
import onnx

model = onnx.load("$OUTPUT_MODEL")

# Check outputs
outputs = [o.name for o in model.graph.output]
if "w_ceil" not in outputs:
    print("❌ ERROR: w_ceil output not found!")
    exit(1)

# Check w_ceil shape
for output in model.graph.output:
    if output.name == "w_ceil":
        shape = output.type.tensor_type.shape
        dims = len(shape.dim)
        if dims != 1:
            print(f"❌ ERROR: w_ceil is {dims}D, expected 1D!")
            exit(1)

# Check metadata
metadata = {prop.key: prop.value for prop in model.metadata_props}
required_keys = ["sample_rate", "n_speakers", "model_type"]
for key in required_keys:
    if key not in metadata:
        print(f"❌ ERROR: Missing required metadata: {key}")
        exit(1)

print("✅ Model verification passed!")
print(f"   - w_ceil: 1D tensor")
print(f"   - sample_rate: {metadata.get('sample_rate')}")
print(f"   - n_speakers: {metadata.get('n_speakers')}")
EOF

if [ $? -ne 0 ]; then
    echo "❌ Verification failed"
    exit 1
fi

# Step 3: Copy to Listen2
echo ""
echo "📁 Step 3: Copying to Listen2 Resources..."
cp "$OUTPUT_MODEL" "$DEST_MODEL"

if [ ! -f "$DEST_MODEL" ]; then
    echo "❌ Copy failed"
    exit 1
fi

# Step 4: Show result
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SUCCESS!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ls -lh "$DEST_MODEL"
echo ""
echo "Next steps:"
echo "  1. Clean build in Xcode (⇧⌘K)"
echo "  2. Build and run (⌘R)"
echo "  3. Check logs for:"
echo "     ✅ 'First phoneme duration: 3 samples = 0.0001s'"
echo "     ❌ NOT 'First phoneme duration: -2147483648'"
echo ""
