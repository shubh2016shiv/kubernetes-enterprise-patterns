The ML serving curriculum has been moved out of `setup/`.

Why:
`setup/` is for Kubernetes primitives: Pods, Deployments, Services, RBAC,
resource management, probes, and enterprise cluster habits.

Real MLOps serving deserves its own folder because enterprise model deployment
is not just "create a Deployment". It involves model artifact storage,
serving runtimes, KServe `InferenceService` resources, autoscaling, rollout,
rollback, and operational debugging.

Go here instead:

  ../ml-serving/

Start with:

  ../ml-serving/README.md

The old custom FastAPI deployment pattern is useful as a contrast study, but the
main enterprise path is now KServe Standard mode.
