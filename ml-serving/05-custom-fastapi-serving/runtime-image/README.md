# runtime-image

This folder contains the custom FastAPI inference container image.

## File Order

1. `model/train_and_save.py`: creates the model artifact used by the runtime.
2. `requirements.txt`: Python dependency contract for the image build.
3. `Dockerfile`: container build recipe.
4. `build-and-load.sh`: local build and `kind` image load workflow.
5. `app/`: the inference server code itself.

## Enterprise Translation

In production, image build, vulnerability scanning, artifact signing, and registry publishing would run in CI/CD rather than on a developer laptop.
