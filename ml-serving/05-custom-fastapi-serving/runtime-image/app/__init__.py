# This file makes ml-serving/05-custom-fastapi-serving/runtime-image/app/ a Python package.
# Required for relative imports (from .model_loader import ModelLoader).
# When FastAPI runs: uvicorn app.main:app
# Python resolves "app" as this package, then "main" as app/main.py.
