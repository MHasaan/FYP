import torch
import onnxruntime as ort
import sys

print(f"Python version: {sys.version}")
print(f"Torch version: {torch.__version__}")
print(f"Torch CUDA available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"Torch CUDA device count: {torch.cuda.device_count()}")
    print(f"Torch CUDA device name: {torch.cuda.get_device_name(0)}")

print(f"ONNX Runtime version: {ort.__version__}")
print(f"ONNX Runtime available providers: {ort.get_available_providers()}")

try:
    from rtmlib import Body
    print("rtmlib is installed")
except ImportError:
    print("rtmlib is NOT installed")
