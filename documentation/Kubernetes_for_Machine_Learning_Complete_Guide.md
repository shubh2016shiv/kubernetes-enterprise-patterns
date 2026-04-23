# Kubernetes for Machine Learning: From Containers to Production ML Systems

## Executive Summary

This document provides a comprehensive guide to using Kubernetes specifically for machine learning workloads. Starting from foundational Kubernetes concepts, we build toward enterprise-grade ML deployment patterns. You will understand how Kubernetes serves as the infrastructure backbone for modern MLOps, enabling scalable training, reliable deployment, and efficient resource management for machine learning systems.

The target audience is data scientists and ML engineers who understand basic machine learning concepts but need to understand how Kubernetes enables production ML deployments. By the end of this document, you will be able to design, deploy, and manage ML workloads on Kubernetes with confidence.

---

## Table of Contents

1. [Kubernetes Fundamentals for ML](#1-kubernetes-fundamentals-for-ml)
2. [ML Workload Architecture on Kubernetes](#2-ml-workload-architecture-on-kubernetes)
3. [Resource Management: CPU, Memory, and GPU](#3-resource-management-cpu-memory-and-gpu)
4. [Storage for ML: Persistent Volumes and Data Access](#4-storage-for-ml-persistent-volumes-and-data-access)
5. [Training Orchestration with Kubeflow and Argo Workflows](#5-training-orchestration-with-kubeflow-and-argo-workflows)
6. [Model Serving on Kubernetes: KServe and Seldon Core](#6-model-serving-on-kubernetes-kserve-and-seldon-core)
7. [MLflow on Kubernetes](#7-mlflow-on-kubernetes)
8. [GitOps Deployment with ArgoCD](#8-gitops-deployment-with-argocd)
9. [Multi-Tenant ML Environments](#9-multi-tenant-ml-environments)
10. [Monitoring and Observability](#10-monitoring-and-observability)
11. [Troubleshooting and Best Practices](#11-troubleshooting-and-best-practices)

---

## 1. Kubernetes Fundamentals for ML

### 1.1 Why Kubernetes for Machine Learning?

Before diving into specific ML use cases, it is essential to understand why Kubernetes has become the de facto standard for ML infrastructure. The answer lies in the unique challenges that ML workloads present: highly variable resource requirements, GPU acceleration needs, large dataset handling, experiment reproducibility, and the need for both batch processing and real-time inference.

Traditional infrastructure approaches struggle with these challenges. Allocating servers for occasional ML training jobs leads to resource waste. Managing GPU access manually is error-prone. Deploying model serving endpoints with the right scaling characteristics requires specialized knowledge. Kubernetes addresses all these challenges through its core abstractions.

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                    WHY KUBERNETES FOR MACHINE LEARNING?                      ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║    TRADITIONAL INFRASTRUCTURE                  KUBERNETES APPROACH           ║
║   ═══════════════════════════               ═════════════════════════        ║
║                                                                              ║
║   ┌─────────────────────────┐               ┌─────────────────────────┐      ║
║   │  Dedicated GPU Servers  │               │      GPU Node Pool      │      ║
║   │                         │               │  ┌────┬────┬────┐       │      ║
║   │  • Wasted capacity      │               │  │GPU │GPU │GPU │       │      ║
║   │  • Manual management    │               │  └────┴────┴────┘       │      ║
║   │  • No auto-scaling      │               │  Shared by all pods     │      ║
║   │                         │               │  Auto-scaling           │      ║
║   └─────────────────────────┘               └─────────────────────────┘      ║
║                                                                              ║
║   ┌─────────────────────────┐               ┌─────────────────────────┐      ║
║   │    Manual Deployment    │               │   Declarative Deploy    │      ║
║   │                         │               │  ┌───────────────────┐  │      ║
║   │  • Copy files           │               │  │ apiVersion: v1    │  │      ║
║   │  • Configure server     │               │  │ kind: Deployment  │  │      ║
║   │  • Restart manually     │               │  └───────────────────┘  │      ║
║   │                         │               │  kubectl apply          │      ║
║   └─────────────────────────┘               └─────────────────────────┘      ║
║                                                                              ║
║   ┌─────────────────────────┐               ┌─────────────────────────┐      ║
║   │    Ad-hoc Monitoring    │               │   Built-in Monitoring   │      ║
║   │                         │               │  ┌───────────────────┐  │      ║
║   │  • Custom scripts       │               │  │ Prometheus        │  │      ║
║   │  • No standardization   │               │  │ Grafana           │  │      ║
║   │  • Fragmented           │               │  │ Auto-alerting     │  │      ║
║   │                         │               │  └───────────────────┘  │      ║
║   └─────────────────────────┘               └─────────────────────────┘      ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### 1.2 Core Kubernetes Concepts

Understanding Kubernetes for ML requires familiarity with its core abstractions. This section explains the key concepts that underpin ML workloads.

**Pods** are the fundamental unit of deployment in Kubernetes. A pod represents a single instance of a running process and can contain one or more containers. For ML workloads, a pod typically contains the training script container, possibly a data loading sidecar, and sometimes inference server containers. Pods are ephemeral by default, meaning that any data written to the container filesystem is lost when the pod terminates. This characteristic has significant implications for ML training, which we will address through persistent volumes.

```yaml
# ============================================================
# Example Pod Definition for ML Training
# ============================================================
apiVersion: v1
kind: Pod
metadata:
  name: ml-training-pod
  namespace: ml-workloads
  labels:
    app: training
    model: fraud-detection
spec:
  # Restart policy for batch jobs
  restartPolicy: OnFailure

  # Container configuration
  containers:
  - name: training
    image: ml-training:v2.1
    command: ["python", "/app/train.py"]

    # Resource requests - guaranteed allocation
    resources:
      requests:
        memory: "4Gi"
        cpu: "2"
        nvidia.com/gpu: "1"  # Request 1 GPU
      limits:
        memory: "8Gi"
        cpu: "4"
        nvidia.com/gpu: "1"

    # Environment variables
    env:
    - name: MLFLOW_TRACKING_URI
      value: "http://mlflow-server:5000"
    - name: TRAINING_DATA_PATH
      value: "/data/training.csv"

    # Volume mounts for data and model artifacts
    volumeMounts:
    - name: training-data
      mountPath: /data
    - name: model-output
      mountPath: /outputs

  # Volumes for persistent storage
  volumes:
  - name: training-data
    persistentVolumeClaim:
      claimName: training-data-pvc
  - name: model-output
    persistentVolumeClaim:
      claimName: model-output-pvc

  # Node selection for GPU nodes
  nodeSelector:
    node-type: gpu

  # Tolerations for GPU nodes (if nodes have taints)
  tolerations:
  - key: "nvidia.com/gpu"
    operator: "Exists"
    effect: "NoSchedule"
```

**Deployments** manage the lifecycle of pods, providing declarative updates, rolling restarts, and scaling capabilities. For ML training, deployments are typically used for long-running training jobs where checkpoint recovery is important. For model serving, deployments provide the foundation for canary deployments and blue-green strategies discussed in the previous document.

```yaml
# ============================================================
# Deployment for Model Training Job
# ============================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fraud-detection-training
  namespace: ml-workloads
spec:
  # Number of desired pod instances
  replicas: 1

  # Selector to identify managed pods
  selector:
    matchLabels:
      app: training
      model: fraud-detection

  # Strategy for updates
  strategy:
    type: Recreate  # Delete and recreate for training jobs

  template:
    metadata:
      labels:
        app: training
        model: fraud-detection
    spec:
      restartPolicy: OnFailure
      containers:
      - name: trainer
        image: ml-training:v2.1
        command: ["python", "/app/train.py"]
        resources:
          requests:
            memory: "8Gi"
            cpu: "4"
            nvidia.com/gpu: "1"
          limits:
            memory: "16Gi"
            cpu: "8"
            nvidia.com/gpu: "1"
        volumeMounts:
        - name: data
          mountPath: /data
        - name: output
          mountPath: /outputs
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: training-data
      - name: output
        persistentVolumeClaim:
          claimName: model-artifacts
```

**Services** provide stable network endpoints for pods. For model serving, services expose the inference endpoint to users or other services. Kubernetes services provide load balancing across pod replicas, automatic service discovery, and integration with external load balancers.

```yaml
# ============================================================
# Service for Model Inference Endpoint
# ============================================================
apiVersion: v1
kind: Service
metadata:
  name: fraud-detection-inference
  namespace: ml-production
spec:
  # Service type determines network access
  type: ClusterIP  # Internal only

  selector:
    app: inference
    model: fraud-detection

  ports:
  - name: http
    port: 80        # Service port
    targetPort: 8000  # Container port
    protocol: TCP

  # Session affinity for stateful inference
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800  # 3 hours
```

**Namespaces** provide scope for Kubernetes resources, enabling multi-tenancy, resource isolation, and organizational management. A well-designed namespace strategy is crucial for enterprise ML environments.

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                        KUBERNETES NAMESPACE STRATEGY                         ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │                               CLUSTER                                │   ║
║   │                                                                      │   ║
║   │  ┌────────────────┐    ┌────────────────┐    ┌────────────────┐      │   ║
║   │  │  ml-platform   │    │ ml-production  │    │   ml-team-a    │      │   ║
║   │  │                │    │                │    │                │      │   ║
║   │  │ • MLflow       │    │ • Inference    │    │ • Dev work     │      │   ║
║   │  │ • Kubeflow     │    │ • Services     │    │ • Testing      │      │   ║
║   │  │ • Monitoring   │    │ • Ingress      │    │ • Training     │      │   ║
║   │  └────────────────┘    └────────────────┘    └────────────────┘      │   ║
║   │                                                                      │   ║
║   │  ┌────────────────┐    ┌────────────────┐    ┌────────────────┐      │   ║
║   │  │   ml-team-b    │    │   ml-team-c    │    │    ml-batch    │      │   ║
║   │  │                │    │                │    │                │      │   ║
║   │  │ • Dev work     │    │ • Research     │    │ • ETL jobs     │      │   ║
║   │  │ • Training     │    │ • Experiments  │    │ • Nightly      │      │   ║
║   │  │ • Testing      │    │ • Prototypes   │    │ • Scheduled    │      │   ║
║   │  └────────────────┘    └────────────────┘    └────────────────┘      │   ║
║   │                                                                      │   ║
║   └──────────────────────────────────────────────────────────────────────┘   ║
║                                                                              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   NAMESPACE PURPOSE:                                                         ║
║   ══════════════════════════════════════════════════════════════════════     ║
║   • Resource isolation between teams and environments                        ║
║   • Resource quotas to prevent resource exhaustion                           ║
║   • Network policies for traffic control                                     ║
║   • RBAC for access control                                                  ║
║   • Logical grouping for organization                                        ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### 1.3 The Kubernetes Control Plane and Worker Nodes

Understanding how Kubernetes works under the hood helps when debugging ML workloads. The Kubernetes cluster consists of a control plane and worker nodes.

The **control plane** manages the cluster state, including which pods should run where, how services should route traffic, and how persistent volumes should be attached. For production ML workloads, the control plane handles scheduling decisions that consider GPU availability, memory requirements, and affinity rules.

The **worker nodes** run the actual workloads. For ML workloads, some nodes are equipped with GPUs, and the kubelet process on these nodes communicates with the NVIDIA device plugin to advertise GPU resources to the scheduler.

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                        KUBERNETES CLUSTER ARCHITECTURE                       ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │                            CONTROL PLANE                             │   ║
║   │                                                                      │   ║
║   │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐          │   ║
║   │  │   API Server   │  │   Scheduler    │  │   Controller   │          │   ║
║   │  │(kube-apiserver)│  │                │  │    Manager     │          │   ║
║   │  │                │  │• Pod placement │  │                │          │   ║
║   │  │• REST API      │  │• GPU scheduling│  │• ReplicaSets   │          │   ║
║   │  │• Auth          │  │• Node scoring  │  │• Endpoints     │          │   ║
║   │  │• Validation    │  │• Affinity      │  │• Namespaces    │          │   ║
║   │  └────────────────┘  └────────────────┘  └────────────────┘          │   ║
║   │                                                                      │   ║
║   │  ┌────────────────┐  ┌────────────────┐                              │   ║
║   │  │      etcd      │  │Cloud Controller│                              │   ║
║   │  │                │  │    Manager     │                              │   ║
║   │  │• Cluster state │  │                │                              │   ║
║   │  │• Persistence   │  │• AWS/GCP/Azure │                              │   ║
║   │  └────────────────┘  └────────────────┘                              │   ║
║   │                                                                      │   ║
║   └──────────────────────────────────┬───────────────────────────────────┘   ║
║                                      │                                       ║
║                                      │                                       ║
║                    ┌─────────────────┴─────────────────┐                     ║
║                    │                                   │                     ║
║                    ▼                                   ▼                     ║
║  ┌─────────────────────────────────┐   ┌─────────────────────────────────┐   ║
║  │        WORKER NODE (CPU)        │   │        WORKER NODE (GPU)        │   ║
║  │ ┌─────────────────────────────┐ │   │ ┌─────────────────────────────┐ │   ║
║  │ │ kubelet                     │ │   │ │ kubelet                     │ │   ║
║  │ │ • Pod lifecycle             │ │   │ │ • Pod lifecycle             │ │   ║
║  │ │ • Volume management         │ │   │ │ • Volume management         │ │   ║
║  │ └─────────────────────────────┘ │   │ │ • GPU management            │ │   ║
║  │                                 │   │ └─────────────────────────────┘ │   ║
║  │ ┌─────────────────────────────┐ │   │                                 │   ║
║  │ │ kube-proxy                  │ │   │ ┌─────────────────────────────┐ │   ║
║  │ │ • Network routing           │ │   │ │ NVIDIA Device Plugin        │ │   ║
║  │ └─────────────────────────────┘ │   │ │ • GPU discovery             │ │   ║
║  │                                 │   │ │ • Resource advertisement    │ │   ║
║  │ ┌─────────────────────────────┐ │   │ │ • Health monitoring         │ │   ║
║  │ │ Container Runtime           │ │   │ └─────────────────────────────┘ │   ║
║  │ │ (containerd)                │ │   │                                 │   ║
║  │ │ • Pull images               │ │   │ ┌─────────────────────────────┐ │   ║
║  │ │ • Start containers          │ │   │ │ Container Runtime           │ │   ║
║  │ └─────────────────────────────┘ │   │ │ (containerd)                │ │   ║
║  │                                 │   │ └─────────────────────────────┘ │   ║
║  │  ┌─────┐   ┌─────┐   ┌─────┐    │   │                                 │   ║
║  │  │ Pod │   │ Pod │   │ Pod │    │   │  ┌─────┐   ┌─────┐              │   ║
║  │  │ CPU │   │ CPU │   │ CPU │    │   │  │ Pod │   │ Pod │              │   ║
║  │  │     │   │     │   │     │    │   │  │ GPU │   │ GPU │              │   ║
║  │  └─────┘   └─────┘   └─────┘    │   │  └─────┘   └─────┘              │   ║
║  └─────────────────────────────────┘   └─────────────────────────────────┘   ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

---

## 2. ML Workload Architecture on Kubernetes

### 2.1 Anatomy of an ML Workload

ML workloads on Kubernetes can be categorized into three types: training workloads, batch inference workloads, and real-time inference workloads. Each type has distinct characteristics and Kubernetes patterns.

**Training Workloads** are typically long-running jobs that consume significant computational resources. They execute a training script that loads data, trains a model, and saves artifacts. Training workloads benefit from GPU acceleration, checkpointing for fault tolerance, and persistent storage for datasets and model outputs.

**Batch Inference Workloads** process large volumes of data in a single job. They are scheduled periodically (e.g., nightly predictions) or triggered by data availability. Batch inference jobs are embarrassingly parallel and can be scaled across many pods for faster processing.

**Real-time Inference Workloads** serve predictions through an API. They require low latency, high availability, and automatic scaling based on request volume. Real-time inference is typically deployed as a Deployment with a Service, managed by autoscalers.

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                       ML WORKLOAD TYPES ON KUBERNETES                        ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  ┌────────────────────────────────────────────────────────────────────────┐  ║
║  │                           TRAINING WORKLOADS                           │  ║
║  │                                                                        │  ║
║  │  Use Cases:                                                            │  ║
║  │  • Model training from scratch                                         │  ║
║  │  • Fine-tuning pretrained models                                       │  ║
║  │  • Hyperparameter tuning                                               │  ║
║  │                                                                        │  ║
║  │  Kubernetes Patterns:                                                  │  ║
║  │  • Job or single-pod Deployment                                        │  ║
║  │  • GPU node selectors                                                  │  ║
║  │  • Persistent volumes for data and checkpoints                         │  ║
║  │  • Kubeflow Pipelines or Argo Workflows for orchestration              │  ║
║  │                                                                        │  ║
║  │  Example Resource Profile:                                             │  ║
║  │  ┌──────────────────────────────────────────────────────────────────┐  │  ║
║  │  │ CPU: 8 cores | Memory: 64 GB | GPU: 1x A100                      │  │  ║
║  │  │ Duration: 2-24 hours                                             │  │  ║
║  │  │ Storage: 100 GB for data, 10 GB for checkpoints                  │  │  ║
║  │  └──────────────────────────────────────────────────────────────────┘  │  ║
║  │                                                                        │  ║
║  └────────────────────────────────────────────────────────────────────────┘  ║
║                                                                              ║
║  ┌────────────────────────────────────────────────────────────────────────┐  ║
║  │                        BATCH INFERENCE WORKLOADS                       │  ║
║  │                                                                        │  ║
║  │  Use Cases:                                                            │  ║
║  │  • Processing historical data for predictions                          │  ║
║  │  • Generating reports with model outputs                               │  ║
║  │  • Large-scale feature computation                                     │  ║
║  │                                                                        │  ║
║  │  Kubernetes Patterns:                                                  │  ║
║  │  • Kubernetes Jobs (single or batch)                                   │  ║
║  │  • Parallelism with work queue or index-based splitting                │  ║
║  │  • CronJobs for scheduled execution                                    │  ║
║  │                                                                        │  ║
║  │  Example Resource Profile:                                             │  ║
║  │  ┌──────────────────────────────────────────────────────────────────┐  │  ║
║  │  │ CPU: 4 cores | Memory: 16 GB | GPU: optional                     │  │  ║
║  │  │ Duration: 10 min - 2 hours                                       │  │  ║
║  │  │ Parallelism: 10-100 pods for large datasets                      │  │  ║
║  │  └──────────────────────────────────────────────────────────────────┘  │  ║
║  │                                                                        │  ║
║  └────────────────────────────────────────────────────────────────────────┘  ║
║                                                                              ║
║  ┌────────────────────────────────────────────────────────────────────────┐  ║
║  │                      REAL-TIME INFERENCE WORKLOADS                     │  ║
║  │                                                                        │  ║
║  │  Use Cases:                                                            │  ║
║  │  • API-based prediction serving                                        │  ║
║  │  • Streaming prediction with low latency                               │  ║
║  │  • Synchronous response patterns                                       │  ║
║  │                                                                        │  ║
║  │  Kubernetes Patterns:                                                  │  ║
║  │  • Deployment with replicas for high availability                      │  ║
║  │  • Horizontal Pod Autoscaler for scaling                               │  ║
║  │  • Service with load balancing                                         │  ║
║  │  • Ingress for external access                                         │  ║
║  │                                                                        │  ║
║  │  Example Resource Profile:                                             │  ║
║  │  ┌──────────────────────────────────────────────────────────────────┐  │  ║
║  │  │ CPU: 2 cores | Memory: 4 GB | Replicas: 3-10                     │  │  ║
║  │  │ Latency: < 100ms per prediction                                  │  │  ║
║  │  │ Throughput: 100-10,000 requests/second                           │  │  ║
║  │  └──────────────────────────────────────────────────────────────────┘  │  ║
║  │                                                                        │  ║
║  └────────────────────────────────────────────────────────────────────────┘  ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### 2.2 End-to-End ML Architecture on Kubernetes

A complete ML system on Kubernetes integrates multiple components: data storage, feature engineering, model training, model registry, model serving, and monitoring. Understanding how these components interact is crucial for designing production ML systems.

```
╔═════════════════════════════════════════════════════════════════════════════════╗
║                   END-TO-END ML ARCHITECTURE ON KUBERNETES                      ║
╠═════════════════════════════════════════════════════════════════════════════════╣
║                                                                                 ║
║  ┌────────────────────────────────────────────────────────────────────────┐     ║
║  │                           EXTERNAL SERVICES                            │     ║
║  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │     ║
║  │  │  Data Lake  │  │   Feature   │  │    Model    │  │ Monitoring  │    │     ║
║  │  │  (S3/GCS)   │  │    Store    │  │  Registry   │  │(Prometheus) │    │     ║
║  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │     ║
║  └───────────────────────────────────┬────────────────────────────────────┘     ║
║                                      │                                          ║
║                                      ▼                                          ║
║  ┌────────────────────────────────────────────────────────────────────────┐     ║
║  │                         ML PLATFORM NAMESPACE                          │     ║
║  │                                                                        │     ║
║  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │     ║
║  │  │  Kubeflow   │  │    Argo     │  │   MLflow    │  │   KServe/   │    │     ║
║  │  │  Pipelines  │  │  Workflows  │  │   Server    │  │   Seldon    │    │     ║
║  │  │             │  │             │  │             │  │    Core     │    │     ║
║  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │     ║
║  │         │                │                │                │           │     ║
║  │         └────────────────┴───────┬────────┴────────────────┘           │     ║
║  └───────────────────────────────────┼────────────────────────────────────┘     ║
║                                      │                                          ║
║       ┌──────────────────────────────┼──────────────────────────────┐           ║
║       │                              │                              │           ║
║       ▼                              ▼                              ▼           ║
║  ┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐  ║
║  │    TRAINING JOBS    │    │ FEATURE ENGINEERING │    │    MODEL SERVING    │  ║
║  │      NAMESPACE      │    │      NAMESPACE      │    │      NAMESPACE      │  ║
║  │                     │    │                     │    │                     │  ║
║  │ ┌────────────────┐  │    │ ┌────────────────┐  │    │ ┌────────────────┐  │  ║
║  │ │  Training Pod  │  │    │ │  Feature Job   │  │    │ │ Inference Pod  │  │  ║
║  │ │     (GPU)      │  │    │ │    (Batch)     │  │    │ │  (Replicas)    │  │  ║
║  │ └────────────────┘  │    │ └────────────────┘  │    │ └────────────────┘  │  ║
║  │         │           │    │         │           │    │         │           │  ║
║  │         ▼           │    │         ▼           │    │         ▼           │  ║
║  │ ┌────────────────┐  │    │ ┌────────────────┐  │    │ ┌────────────────┐  │  ║
║  │ │   PVC: Data    │  │    │ │ PVC: Features  │  │    │ │    Service     │  │  ║
║  │ │  PVC: Output   │  │    │ │                │  │    │ │                │  │  ║
║  │ └────────────────┘  │    │ └────────────────┘  │    │ └────────────────┘  │  ║
║  └─────────────────────┘    └─────────────────────┘    └─────────────────────┘  ║
║                                                                                 ║
║  ┌────────────────────────────────────────────────────────────────────────┐     ║
║  │                          SHARED INFRASTRUCTURE                         │     ║
║  │                                                                        │     ║
║  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │     ║
║  │  │  GPU Nodes  │  │  CPU Nodes  │  │   Ingress   │  │  PVC/SaaS   │    │     ║
║  │  │ (A100/V100) │  │  (General)  │  │ Controller  │  │  (Storage)  │    │     ║
║  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │     ║
║  └────────────────────────────────────────────────────────────────────────┘     ║
║                                                                                 ║
╚═════════════════════════════════════════════════════════════════════════════════╝
```

### 2.3 Kubernetes Jobs for ML Batch Processing

For batch inference and one-time training tasks, Kubernetes Jobs provide a simple yet powerful abstraction. A Job creates one or more pods and ensures that a specified number of them complete successfully.

```yaml
# ============================================================
# Kubernetes Job for Batch Inference
# ============================================================
apiVersion: batch/v1
kind: Job
metadata:
  name: fraud-detection-batch-inference
  namespace: ml-batch
spec:
  # Maximum number of pods to run in parallel
  parallelism: 10

  # Desired number of successfully completed pods
  completions: 100

  # Seconds to wait before marking job as failed
  activeDeadlineSeconds: 7200

  # Seconds to keep job after completion
  ttlSecondsAfterFinished: 3600

  # Retry policy
  backoffLimit: 3

  template:
    metadata:
      labels:
        app: batch-inference
        model: fraud-detection
        batch-id: "2024-01-15"
    spec:
      restartPolicy: OnFailure

      containers:
      - name: inference
        image: ml-inference:v1.5
        command:
          - python
          - /app/batch_inference.py
          - --batch-start=$(BATCH_START)
          - --batch-end=$(BATCH_END)
          - --model-version=$(MODEL_VERSION)

        env:
        - name: MLFLOW_TRACKING_URI
          value: "http://mlflow-server:5000"
        - name: MODEL_VERSION
          value: "10"  # Version to use for inference
        - name: BATCH_START
          value: "0"
        - name: BATCH_END
          value: "1000"

        resources:
          requests:
            memory: "2Gi"
            cpu: "2"
          limits:
            memory: "4Gi"
            cpu: "4"

        volumeMounts:
        - name: data
          mountPath: /data
        - name: output
          mountPath: /outputs

      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: inference-input-data
      - name: output
        persistentVolumeClaim:
          claimName: inference-output-data

      # Schedule on CPU nodes for batch processing
      nodeSelector:
        workload-type: batch

      tolerations:
      - key: "workload-type"
        operator: "Equal"
        value: "batch"
        effect: "NoSchedule"
```

```yaml
# ============================================================
# CronJob for Scheduled Batch Inference
# ============================================================
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-fraud-predictions
  namespace: ml-batch
spec:
  # Run at 2 AM daily
  schedule: "0 2 * * *"

  # Timezone for the schedule
  timeZone: "America/New_York"

  # Concurrency policy
  concurrencyPolicy: Forbid  # Don't run if previous still running

  # Successful jobs to keep
  successfulJobsHistoryLimit: 3

  # Failed jobs to keep
  failedJobsHistoryLimit: 3

  # Starting deadline for missed jobs
  startingDeadlineSeconds: 3600

  jobTemplate:
    spec:
      parallelism: 20
      completions: 200
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: inference
            image: ml-inference:v1.5
            command: ["python", "/app/daily_predictions.py"]
            env:
            - name: DATE
              value: "{{ .Date }}"  # Templated at job creation
            resources:
              requests:
                memory: "2Gi"
                cpu: "2"
              limits:
                memory: "4Gi"
                cpu: "4"
```

---

## 3. Resource Management: CPU, Memory, and GPU

### 3.1 Understanding Kubernetes Resource Model

Kubernetes provides two mechanisms for specifying container resource requirements: requests and limits. Understanding the distinction is crucial for efficient ML workload management.

**Requests** specify the minimum resources that Kubernetes guarantees for a container. The scheduler uses requests to find a node with sufficient capacity. If a container requests 2 CPUs and 8GB of memory, Kubernetes ensures that these resources are available before scheduling the pod.

**Limits** specify the maximum resources that a container can use. If a container attempts to exceed its memory limit, it is terminated (OOMKilled). If it exceeds its CPU limit, it is throttled.

```yaml
# ============================================================
# Resource Requests and Limits Explained
# ============================================================
spec:
  containers:
  - name: ml-training
    resources:
      requests:
        # Guaranteed allocation - scheduler uses this
        memory: "8Gi"
        cpu: "2"
        nvidia.com/gpu: "1"

      limits:
        # Maximum usage - container cannot exceed
        memory: "16Gi"
        cpu: "4"
        nvidia.com/gpu: "1"
```

```
╔══════════════════════════════════════════════════════════════════════════════╗
║               REQUESTS VS LIMITS: A VISUAL EXPLANATION                       ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   NODE CAPACITY: 32 CPU cores, 128 GB RAM                                    ║
║                                                                              ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │                                                                      │   ║
║   │  ┌─────────────────────┐    ┌─────────────────────┐                  │   ║
║   │  │ Pod A               │    │ Pod B               │                  │   ║
║   │  │                     │    │                     │                  │   ║
║   │  │ requests:           │    │ requests:           │                  │   ║
║   │  │   cpu: 4            │    │   cpu: 2            │                  │   ║
║   │  │   memory: 16Gi      │    │   memory: 8Gi       │                  │   ║
║   │  │                     │    │                     │                  │   ║
║   │  │ limits:             │    │ limits:             │                  │   ║
║   │  │   cpu: 8            │    │   cpu: 4            │                  │   ║
║   │  │   memory: 32Gi      │    │   memory: 16Gi      │                  │   ║
║   │  └─────────────────────┘    └─────────────────────┘                  │   ║
║   │                                                                      │   ║
║   │  ┌─────────────────────┐                                             │   ║
║   │  │ Pod C               │                                             │   ║
║   │  │                     │                                             │   ║
║   │  │ requests:           │                                             │   ║
║   │  │   cpu: 2            │                                             │   ║
║   │  │   memory: 8Gi       │                                             │   ║
║   │  │                     │                                             │   ║
║   │  │ limits:             │                                             │   ║
║   │  │   cpu: 4            │                                             │   ║
║   │  │   memory: 16Gi      │                                             │   ║
║   │  └─────────────────────┘                                             │   ║
║   │                                                                      │   ║
║   └──────────────────────────────────────────────────────────────────────┘   ║
║                                                                              ║
║   TOTAL ALLOCATED:                                                           ║
║   ══════════════════════════════════════════════════════════════════════     ║
║   Requests: 8 CPU (25% of node), 32 GB RAM (25% of node)                     ║
║   Limits:   16 CPU (50% of node), 64 GB RAM (50% of node)                    ║
║                                                                              ║
║   WHAT THIS MEANS:                                                           ║
║   ══════════════════════════════════════════════════════════════════════     ║
║   • Scheduler guarantees 8 CPU for Pod A                                     ║
║   • Pod A can burst to 8 CPU but may be throttled                            ║
║   • Pod B and C can use their requests + unused capacity                     ║
║   • Node is fully allocated by requests (8+2+2 = 12 cores requested)         ║
║   • 4 CPU cores remain available for burst or new pods                       ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### 3.2 GPU Scheduling and Management

GPU resources require special handling in Kubernetes. The NVIDIA device plugin must be installed on GPU nodes, and pods must request GPU resources explicitly.

**GPU Node Setup**: GPU nodes require the NVIDIA driver, container runtime with GPU support, and the Kubernetes device plugin. On nodes with NVIDIA GPUs, the device plugin advertises GPU resources as `nvidia.com/gpu`.

```yaml
# ============================================================
# Pod with GPU Request
# ============================================================
apiVersion: v1
kind: Pod
metadata:
  name: gpu-training-pod
spec:
  containers:
  - name: trainer
    image: pytorch/pytorch:2.0.1-cuda11.7-cudnn8-runtime
    command: ["python", "train.py"]

    resources:
      requests:
        # Request 1 GPU - Kubernetes will find a node with available GPU
        nvidia.com/gpu: "1"
      limits:
        nvidia.com/gpu: "1"  # Usually same as request for GPUs

    env:
    - name: CUDA_VISIBLE_DEVICES
      value: "0"  # Use first GPU in the container

    volumeMounts:
    - name: nvidia-container-runtime
      mountPath: /usr/local/nvidia

  volumes:
  - name: nvidia-container-runtime
    hostPath:
      path: /usr/local/nvidia

  # Node must have GPU capacity
  nodeSelector:
    gpu-type: nvidia-tesla-v100

  # Tolerate any taints on GPU nodes
  tolerations:
  - key: "nvidia.com/gpu"
    operator: "Exists"
    effect: "NoSchedule"
```

**GPU Oversubscription**: For inference workloads that do not fully utilize GPUs, you can schedule multiple pods per GPU using time-slicing or GPU partitioning. This approach increases throughput but may introduce latency variability.

```yaml
# ============================================================
# Time-Sliced GPU Configuration
# ============================================================
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin-config
  namespace: kube-system
data:
  config.yaml: |
    version: v1
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: 4  # 4 containers share 1 physical GPU
```

### 3.3 Resource Quotas and LimitRanges

Namespaces provide isolation, but without quotas and limits, a single namespace can exhaust cluster resources. ResourceQuota and LimitRange objects prevent this.

```yaml
# ============================================================
# ResourceQuota for ML Namespace
# ============================================================
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ml-workloads-quota
  namespace: ml-training
spec:
  # Total resource limits for the namespace
  hard:
    # Compute resources
    requests.cpu: "64"
    requests.memory: "256Gi"
    limits.cpu: "128"
    limits.memory: "512Gi"

    # GPU quota - prevents GPU exhaustion
    requests.nvidia.com/gpu: "8"

    # Object counts
    pods: "50"
    persistentvolumeclaims: "20"
    services: "10"

    # Storage
    requests.storage: "500Gi"

  # Scope-specific quotas
  scopes:
  - BestEffort  # Pods with QOS BestEffort
  - NotBestEffort  # Pods with Guaranteed or Burstable QOS

# NOTE: ResourceQuota applies to the entire namespace totals.
# For per-pod limits, use LimitRange.
```

```yaml
# ============================================================
# LimitRange for Default Resource Constraints
# ============================================================
apiVersion: v1
kind: LimitRange
metadata:
  name: ml-default-limits
  namespace: ml-training
spec:
  limits:
  - type: Container
    # Default requests if not specified
    defaultRequest:
      cpu: "500m"
      memory: "512Mi"
      nvidia.com/gpu: "0"

    # Default limits if not specified
    default:
      cpu: "1"
      memory: "1Gi"

    # Maximum limits a container can set
    max:
      cpu: "32"
      memory: "128Gi"
      nvidia.com/gpu: "4"

    # Minimum limits a container must request
    min:
      cpu: "100m"
      memory: "128Mi"

    # Limit/Request ratio for CPU (containers can use up to 4x request)
    maxLimitRequestRatio:
      cpu: "4"
      memory: "4"
      nvidia.com/gpu: "1"
```

### 3.4 Quality of Service Classes

Kubernetes assigns Quality of Service (QoS) classes based on resource requests and limits. Understanding QoS helps predict pod scheduling and eviction behavior.

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                            KUBERNETES QOS CLASSES                            ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  GUARANTEED (Highest Priority)                                               ║
║  ══════════════════════════════════════════════════════════════════════      ║
║  Requirements:                                                               ║
║  • Every container must have memory and CPU limits                           ║
║  • Every container must have memory and CPU requests                         ║
║  • Requests must equal limits for all resources                              ║
║                                                                              ║
║  Use Case: Production inference pods, critical training jobs                 ║
║  Behavior: Last to be evicted, scheduled on nodes with exact capacity        ║
║                                                                              ║
║  ┌──────────────────────────────────────────────────────────────────────┐    ║
║  │ containers:                                                          │    ║
║  │ - resources:                                                         │    ║
║  │     requests:                                                        │    ║
║  │       memory: "4Gi"                                                  │    ║
║  │       cpu: "2"                                                       │    ║
║  │     limits:                                                          │    ║
║  │       memory: "4Gi"  # Equal to requests!                            │    ║
║  │       cpu: "2"       # Equal to requests!                            │    ║
║  └──────────────────────────────────────────────────────────────────────┘    ║
║                                                                              ║
║  BURSTABLE                                                                   ║
║  ══════════════════════════════════════════════════════════════════════      ║
║  Requirements:                                                               ║
║  • At least one container has memory or CPU request                          ║
║  • Does not meet Guaranteed criteria                                         ║
║                                                                              ║
║  Use Case: Development workloads, batch jobs with variable resource needs    ║
║  Behavior: Can burst beyond requests up to limits, moderate eviction risk    ║
║                                                                              ║
║  ┌──────────────────────────────────────────────────────────────────────┐    ║
║  │ containers:                                                          │    ║
║  │ - resources:                                                         │    ║
║  │     requests:                                                        │    ║
║  │       memory: "2Gi"                                                  │    ║
║  │       cpu: "1"                                                       │    ║
║  │     limits:                                                          │    ║
║  │       memory: "8Gi"  # Higher than requests                          │    ║
║  │       cpu: "4"       # Higher than requests                          │    ║
║  └──────────────────────────────────────────────────────────────────────┘    ║
║                                                                              ║
║  BESTEFFORT (Lowest Priority)                                                ║
║  ══════════════════════════════════════════════════════════════════════      ║
║  Requirements:                                                               ║
║  • No container has memory or CPU requests or limits                         ║
║                                                                              ║
║  Use Case: Optional workloads, monitoring agents                             ║
║  Behavior: Evicted first when node is under pressure                         ║
║                                                                              ║
║  ┌──────────────────────────────────────────────────────────────────────┐    ║
║  │ containers:                                                          │    ║
║  │ - resources: {}  # No requests or limits specified                   │    ║
║  │                                                                      │    ║
║  └──────────────────────────────────────────────────────────────────────┘    ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

---

## 4. Storage for ML: Persistent Volumes and Data Access

### 4.1 ML Storage Patterns

Machine learning workloads have distinct storage patterns. Training jobs need access to large datasets, model artifacts need persistent storage for later serving, and inference jobs need fast access to model files. Kubernetes Persistent Volumes address these patterns through various storage backends and access modes.

**ReadWriteOnce (RWO)**: The volume is mounted as read-write by a single node. This is the most common mode for ML workloads where the training job runs on a single pod.

**ReadOnlyMany (ROX)**: The volume is mounted as read-only by multiple nodes. This is useful for shared datasets accessed by multiple training pods.

**ReadWriteMany (RWX)**: The volume is mounted as read-write by multiple nodes. This is less common and requires network file systems like NFS or cloud-specific solutions.

```yaml
# ============================================================
# PersistentVolumeClaim for Training Data
# ============================================================
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: training-data-pvc
  namespace: ml-training
spec:
  # Storage class determines the backend provisioner
  storageClassName: standard-rwo

  # Access mode - single node read-write
  accessModes:
    - ReadWriteOnce

  # Requested storage size
  resources:
    requests:
      storage: 100Gi

  # Optional: use specific volume
  volumeName: training-data-pv

# ============================================================
# PersistentVolumeClaim for Model Artifacts (with retention)
# ============================================================
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-artifacts-pvc
  namespace: ml-training
spec:
  storageClassName: standard-rwo
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi

  # Retention policy
  persistentVolumeReclaimPolicy: Retain  # Keep data after PVC deletion
```

### 4.2 Storage Classes and Provisioners

StorageClass objects define the provisioner and parameters for dynamic volume provisioning. Different cloud providers and storage solutions expose different storage classes.

```yaml
# ============================================================
# StorageClass Examples for Cloud Providers
# ============================================================

# AWS EBS - Standard block storage
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-standard
provisioner: ebs.csi.aws.com
parameters:
  type: gp3  # General Purpose SSD
  iops: "3000"
  throughput: "125Mi"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer  # Wait for pod to be scheduled

# AWS EFS - Network file system (ReadWriteMany)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-standard
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-12345678
  directoryPerms: "755"
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
  basePath: "/ml-artifacts"

# GCP Persistent Disk
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gcp-standard
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-standard
  replication-type: regional-pd
volumeBindingMode: WaitForFirstConsumer

# Azure Files (ReadWriteMany)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-files
provisioner: file.csi.azure.com
parameters:
  skuName: Standard_LRS
  protocol: nfs
```

### 4.3 Data Access Patterns for ML Training

Efficient data access is critical for ML training performance. Kubernetes provides several patterns for accessing training data, each with trade-offs.

```yaml
# ============================================================
# Pattern 1: PVC Mount (Simple, Good Performance)
# ============================================================
# Best for: Single-node training, moderate dataset sizes (< 100GB)
# Trade-offs: Data tied to pod lifecycle, limited portability

spec:
  containers:
  - name: trainer
    volumeMounts:
    - name: training-data
      mountPath: /data
  volumes:
  - name: training-data
    persistentVolumeClaim:
      claimName: training-data-pvc

# ============================================================
# Pattern 2: Init Container for Data Download
# ============================================================
# Best for: Large datasets that should be cached, multi-pod training
# Trade-offs: Additional startup time, storage duplication

spec:
  initContainers:
  - name: download-data
    image: data-downloader:v1
    command:
      - python
      - /scripts/download_data.py
      - --source=s3://ml-data/training
      - --dest=/data
    volumeMounts:
    - name: training-data
      mountPath: /data

  containers:
  - name: trainer
    volumeMounts:
    - name: training-data
      mountPath: /data

  volumes:
  - name: training-data
    emptyDir: {}  # Temporary storage for init container

# ============================================================
# Pattern 3: Sidecar for Data Access
# ============================================================
# Best for: Streaming data, data that changes frequently
# Trade-offs: Network dependency, complexity

spec:
  containers:
  - name: trainer
    volumeMounts:
    - name: shared-data
      mountPath: /data

  - name: data-loader  # Sidecar
    image: data-loader:v1
    command:
      - python
      - /scripts/stream_data.py
      - --source=s3://ml-data/training
      - --dest=/data
    volumeMounts:
    - name: shared-data
      mountPath: /data

  volumes:
  - name: shared-data
    emptyDir: {}
```

### 4.4 Model Artifact Storage

Model artifacts require persistent storage that survives training jobs and is accessible to serving infrastructure. MLflow's model registry typically stores artifacts in object storage (S3, GCS, Azure Blob) or a shared filesystem.

```yaml
# ============================================================
# Model Artifact Storage with S3 Backend
# ============================================================
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mlflow-artifacts-pvc
  namespace: ml-platform
spec:
  storageClassName: ebs-standard
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Gi

---
# Kubernetes Secret for S3 Access
apiVersion: v1
kind: Secret
metadata:
  name: mlflow-s3-secret
  namespace: ml-platform
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "YOUR_ACCESS_KEY"
  AWS_SECRET_ACCESS_KEY: "YOUR_SECRET_KEY"
  AWS_DEFAULT_REGION: "us-east-1"

---
# MLflow deployment with S3 artifact storage
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow-server
  namespace: ml-platform
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mlflow
  template:
    spec:
      containers:
      - name: mlflow
        image: ghcr.io/mlflow/mlflow:latest
        ports:
        - containerPort: 5000

        args:
          - mlflow server
          - --host=0.0.0.0
          - --port=5000
          - --backend-store-uri=postgresql://mlflow:password@mlflow-db:5432/mlflow
          - --default-artifact-root=s3://ml-artifacts/mlflow/
          - --workers=4

        env:
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: mlflow-s3-secret
              key: AWS_ACCESS_KEY_ID
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: mlflow-s3-secret
              key: AWS_SECRET_ACCESS_KEY

        resources:
          requests:
            memory: "2Gi"
            cpu: "1"
          limits:
            memory: "4Gi"
            cpu: "2"
```

---

## 5. Training Orchestration with Kubeflow and Argo Workflows

### 5.1 Why Use Workflow Orchestration?

While Kubernetes Jobs and CronJobs handle simple batch workloads, complex ML training pipelines require orchestration tools that can manage multi-step workflows with dependencies, conditional execution, and failure handling. Two dominant tools for this purpose are Kubeflow Pipelines and Argo Workflows.

**Kubeflow Pipelines** provides a graphical UI, experiment tracking, and a high-level DSL for defining ML workflows. It is ideal for organizations that want a managed ML platform experience.

**Argo Workflows** is a Kubernetes-native workflow engine that provides YAML-based workflow definitions, comprehensive error handling, and tight Kubernetes integration. It is preferred for organizations that want lightweight, infrastructure-focused orchestration.

```
╔══════════════════════════════════════════════════════════════════════════════╗
║               KUBEFLOW PIPELINES VS ARGO WORKFLOWS COMPARISON                ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  ┌────────────────────────────┐      ┌────────────────────────────┐          ║
║  │     KUBEFLOW PIPELINES     │      │       ARGO WORKFLOWS       │          ║
║  ├────────────────────────────┤      ├────────────────────────────┤          ║
║  │                            │      │                            │          ║
║  │ Strengths:                 │      │ Strengths:                 │          ║
║  │ • Rich UI with run history │      │ • Kubernetes-native YAML   │          ║
║  │ • Experiment tracking      │      │ • Full control over specs  │          ║
║  │ • Visual pipeline builder  │      │ • Lightweight install      │          ║
║  │ • Built-in hyperparameter  │      │ • Excellent error handling │          ║
║  │   tuning (Katib)           │      │ • DAG and step-based       │          ║
║  │ • Metadata store           │      │ • Template-based           │          ║
║  │                            │      │                            │          ║
║  │ Trade-offs:                │      │ Trade-offs:                │          ║
║  │ • Heavy installation       │      │ • No built-in UI           │          ║
║  │ • Steeper learning curve   │      │ • Manual experiment setup  │          ║
║  │ • More moving parts        │      │ • No native HP tuning      │          ║
║  │                            │      │                            │          ║
║  └────────────────────────────┘      └────────────────────────────┘          ║
║                                                                              ║
║   DECISION GUIDE:                                                            ║
║   ══════════════════════════════════════════════════════════════════════     ║
║   Choose Kubeflow if:                                                        ║
║   • You want a full ML platform with UI                                      ║
║   • Data scientists need self-service pipeline creation                      ║
║   • Built-in hyperparameter tuning is important                              ║
║                                                                              ║
║   Choose Argo Workflows if:                                                  ║
║   • You want lightweight, Kubernetes-focused orchestration                   ║
║   • Teams are comfortable with YAML configuration                            ║
║   • You need tight integration with existing Kubernetes tools                ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### 5.2 Argo Workflows for ML Training

Argo Workflows defines workflows as Directed Acyclic Graphs (DAGs) or sequential steps. Each step is a container, enabling full programmatic control while leveraging Kubernetes scheduling.

```yaml
# ============================================================
# Argo Workflow: End-to-End ML Training Pipeline
# ============================================================
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: ml-training-pipeline-
  namespace: ml-workloads
  labels:
    workflows.argoproj.io/workflow-template: fraud-detection-training
spec:
  # Entry point
  entrypoint: ml-pipeline

  # Service account for pod execution
  serviceAccountName: ml-workflow

  # Default parameters
  arguments:
    parameters:
    - name: model-name
      value: fraud-detection
    - name: training-data-path
      value: s3://ml-data/training/fraud_data.csv
    - name: hyperparameters
      value: '{"n_estimators": 500, "max_depth": 8}'
    - name: mlflow-run-id
      value: ""

  # DAG workflow definition
  templates:

  # ─────────────────────────────────────────────────────────
  # Main Pipeline Template
  # ─────────────────────────────────────────────────────────
  - name: ml-pipeline
    dag:
      tasks:
      - name: data-validation
        template: validate-data
        arguments:
          parameters:
          - name: data-path
            value: "{{ Workflow.parameters.training-data-path }}"

      - name: train-model
        template: train-model
        arguments:
          parameters:
          - name: data-path
            value: "{{ Workflow.parameters.training-data-path }}"
          - name: hyperparameters
            value: "{{ Workflow.parameters.hyperparameters }}"
          - name: mlflow-run-id
            value: "{{ Workflow.parameters.mlflow-run-id }}"
        # Wait for data validation
        depends: "data-validation"

      - name: evaluate-model
        template: evaluate-model
        arguments:
          parameters:
          - name: model-version
            value: "{{ tasks.train-model.outputs.parameters.model-version }}"
        # Wait for training
        depends: "train-model"

      - name: register-model
        template: register-model
        arguments:
          parameters:
          - name: model-version
            value: "{{ tasks.train-model.outputs.parameters.model-version }}"
          - name: evaluation-passed
            value: "{{ tasks.evaluate-model.outputs.parameters.evaluation-passed }}"
        # Wait for evaluation
        depends: "evaluate-model"

  # ─────────────────────────────────────────────────────────
  # Data Validation Task
  # ─────────────────────────────────────────────────────────
  - name: validate-data
    inputs:
      parameters:
      - name: data-path

    container:
      image: python:3.11-slim
      command: [python, /scripts/validate_data.py]
      args:
        - --data-path={{ inputs.parameters.data-path }}

      env:
      - name: MLFLOW_TRACKING_URI
        value: "http://mlflow-server:5000"

      resources:
        requests:
          memory: "1Gi"
          cpu: "500m"
        limits:
          memory: "2Gi"
          cpu: "1"

      volumeMounts:
      - name: workdir
        mountPath: /workdir
      - name: scripts
        mountPath: /scripts

    volumes:
    - name: workdir
      emptyDir: {}
    - name: scripts
      configmap:
        name: ml-scripts
        defaultMode: 0777

    outputs:
      parameters:
      - name: validation-status
        valueFrom:
          path: /workdir/validation_status.txt

  # ─────────────────────────────────────────────────────────
  # Model Training Task
  # ─────────────────────────────────────────────────────────
  - name: train-model
    inputs:
      parameters:
      - name: data-path
      - name: hyperparameters
      - name: mlflow-run-id

    container:
      image: ml-training:latest
      command: [python, /scripts/train.py]
      args:
        - --data-path={{ inputs.parameters.data-path }}
        - --hyperparameters={{ inputs.parameters.hyperparameters }}
        - --model-name={{ Workflow.parameters.model-name }}
        - --mlflow-run-id={{ inputs.parameters.mlflow-run-id }}
        - --output-path=/outputs/model

      env:
      - name: MLFLOW_TRACKING_URI
        value: "http://mlflow-server:5000"
      - name: AWS_ACCESS_KEY_ID
        valueFrom:
          secretKeyRef:
            name: ml-s3-secret
            key: AWS_ACCESS_KEY_ID
      - name: AWS_SECRET_ACCESS_KEY
        valueFrom:
          secretKeyRef:
            name: ml-s3-secret
            key: AWS_SECRET_ACCESS_KEY

      resources:
        requests:
          memory: "8Gi"
          cpu: "4"
          nvidia.com/gpu: "1"
        limits:
          memory: "16Gi"
          cpu: "8"
          nvidia.com/gpu: "1"

      volumeMounts:
      - name: outputs
        mountPath: /outputs
      - name: scripts
        mountPath: /scripts

    volumes:
    - name: outputs
      persistentVolumeClaim:
        claimName: model-output-pvc
    - name: scripts
      configmap:
        name: ml-scripts
        defaultMode: 0777

    outputs:
      parameters:
      - name: model-version
        valueFrom:
          path: /outputs/model_version.txt
      - name: metrics
        valueFrom:
          path: /outputs/metrics.json

  # ─────────────────────────────────────────────────────────
  # Model Evaluation Task
  # ─────────────────────────────────────────────────────────
  - name: evaluate-model
    inputs:
      parameters:
      - name: model-version

    container:
      image: ml-evaluation:latest
      command: [python, /scripts/evaluate.py]
      args:
        - --model-version={{ inputs.parameters.model-version }}
        - --threshold=0.85  # Minimum AUC to pass

      env:
      - name: MLFLOW_TRACKING_URI
        value: "http://mlflow-server:5000"

      resources:
        requests:
          memory: "4Gi"
          cpu: "2"
        limits:
          memory: "8Gi"
          cpu: "4"

      volumeMounts:
      - name: workdir
        mountPath: /workdir
      - name: scripts
        mountPath: /scripts

    volumes:
    - name: workdir
      emptyDir: {}
    - name: scripts
      configmap:
        name: ml-scripts
        defaultMode: 0777

    outputs:
      parameters:
      - name: evaluation-passed
        valueFrom:
          path: /workdir/evaluation_passed.txt

  # ─────────────────────────────────────────────────────────
  # Model Registration Task
  # ─────────────────────────────────────────────────────────
  - name: register-model
    inputs:
      parameters:
      - name: model-version
      - name: evaluation-passed

    container:
      image: ml-registry:latest
      command: [python, /scripts/register.py]
      args:
        - --model-name={{ Workflow.parameters.model-name }}
        - --model-version={{ inputs.parameters.model-version }}
        - --evaluation-passed={{ inputs.parameters.evaluation-passed }}
        - --promote-to-production=true

      env:
      - name: MLFLOW_TRACKING_URI
        value: "http://mlflow-server:5000"

      resources:
        requests:
          memory: "512Mi"
          cpu: "250m"
        limits:
          memory: "1Gi"
          cpu: "1"

      volumeMounts:
      - name: workdir
        mountPath: /workdir
      - name: scripts
        mountPath: /scripts

    volumes:
    - name: workdir
      emptyDir: {}
    - name: scripts
      configmap:
        name: ml-scripts
        defaultMode: 0777

    # Fail workflow if evaluation did not pass
    when: "{{ inputs.parameters.evaluation-passed }} == true"
```

### 5.3 Kubeflow Pipelines for ML

Kubeflow Pipelines provides a higher-level abstraction with a visual UI, experiment tracking, and component registry. The SDK allows defining pipelines in Python, which compiles to Argo Workflows under the hood.

```python
# ============================================================
# Kubeflow Pipeline Definition (Python SDK)
# ============================================================
from kfp import components, dsl, Pipeline
from kfp.components import InputPath, OutputPath

# Load components from container images
download_data_op = components.load_component_from_url(
    "https://raw.githubusercontent.com/kubeflow/pipeline-components/master/components/DataGCP/BigQuery/ExecuteQuery/component.yaml"
)

train_model_op = components.load_component_from_url(
    "https://raw.githubusercontent.com/kubeflow/pipeline-components/master/components/ML/Train/CatBoost/Train/component.yaml"
)

evaluate_model_op = components.load_component_from_url(
    "https://raw.githubusercontent.com/kubeflow/pipeline-components/master/components/Metrics/ClassificationMetrics/component.yaml"
)

deploy_model_op = components.load_component_from_url(
    "https://raw.githubusercontent.com/kubeflow/pipeline-components/master/components/KServe/Deploy/component.yaml"
)


@dsl.pipeline(
    name="Fraud Detection Training Pipeline",
    description="End-to-end pipeline for training and deploying fraud detection model"
)
def fraud_detection_pipeline(
    project_id: str,
    dataset_query: str,
    model_name: str = "fraud-detection",
    min_accuracy: float = 0.85,
    training_rounds: int = 500
):
    """
    Pipeline parameters:
    - project_id: GCP project for BigQuery
    - dataset_query: SQL query to retrieve training data
    - model_name: Name for the MLflow model registration
    - min_accuracy: Minimum accuracy threshold for deployment
    - training_rounds: Number of training iterations
    """

    # Download and prepare data
    data_prep = download_data_op(
        query=dataset_query,
        project_id=project_id,
        output_path="/data/train_data.csv"
    )

    # Train model with GPU
    train = train_model_op(
        train_data=data_prep.outputs["output_path"],
        num_iterations=training_rounds,
        learning_rate=0.05,
        max_depth=8,
        model_name=model_name
    )
    train.add_node_selector_constraint(
        label_name="cloud.google.com/gke-accelerator",
        value="NVIDIA_TESLA_T100"
    )
    train.set_gpu_limit("1")
    train.set_memory_request("8Gi")
    train.set_memory_limit("16Gi")

    # Evaluate model
    evaluate = evaluate_model_op(
        predictions=train.outputs["model_path"],
        actual=data_prep.outputs["output_path"],
        metric_threshold=min_accuracy
    )

    # Conditional deployment based on evaluation
    with dsl.Condition(evaluate.outputs["passed"] == "true"):
        deploy = deploy_model_op(
            model_name=model_name,
            model_version=train.outputs["model_version"],
            namespace="ml-production"
        )


# Compile pipeline
if __name__ == "__main__":
    from kfp.compiler import Compiler
    Compiler().compile(
        fraud_detection_pipeline,
        "/pipelines/fraud_detection_pipeline.yaml"
    )
```

### 5.4 Hyperparameter Tuning with Katib

Katib is Kubeflow's hyperparameter tuning component, implementing Bayesian optimization, grid search, random search, and other tuning strategies.

```yaml
# ============================================================
# Katib Experiment for Hyperparameter Tuning
# ============================================================
apiVersion: kubeflow.org/v1beta1
kind: Experiment
metadata:
  name: fraud-detection-hp-tuning
  namespace: ml-workloads
spec:
  # Objective to optimize
  objective:
    type: maximize
    goal: 0.95
    objectiveMetricName: auc

  # Algorithm to use
  algorithm:
    algorithmName: bayesianoptimization
    warm_stopping: "3"

  # Number of trials to run
  parallelTrialCount: 3
  maxTrialCount: 30
  maxFailedTrialCount: 5

  # Trial template
  trialTemplate:
    primaryContainerName: training
    apiVersion: argoproj.io/v1alpha1
    kind: Workflow
    spec:
      entrypoint: training-task
      arguments:
      - - --n_estimators={{.HyperParameter.n_estimators}}
      - - --max_depth={{.HyperParameter.max_depth}}
      - - --learning_rate={{.HyperParameter.learning_rate}}
      - - --mlflow_run_name={{.Trial.name}}

      container:
        image: ml-training:v1.5
        command:
        - python
        - /scripts/train.py
        resources:
          requests:
            memory: "4Gi"
            cpu: "2"
            nvidia.com/gpu: "1"
          limits:
            memory: "8Gi"
            cpu: "4"
            nvidia.com/gpu: "1"

      volumes:
      - name: workdir
        persistentVolumeClaim:
          claimName: ml-workdir-pvc
      volumeMounts:
      - name: workdir
        mountPath: /workdir

  # Hyperparameter search space
  parameters:
  - name: n_estimators
    parameterType: int
    feasibleSpace:
      min: "100"
      max: "1000"
      step: "100"

  - name: max_depth
    parameterType: int
    feasibleSpace:
      min: "3"
      max: "15"

  - name: learning_rate
    parameterType: float
    feasibleSpace:
      min: "0.01"
      max: "0.3"
      log_base: true  # Logarithmic scale

  - name: num_leaves
    parameterType: categorical
    feasibleSpace:
      list:
      - "31"
      - "50"
      - "100"
      - "200"
```

---

## 6. Model Serving on Kubernetes: KServe and Seldon Core

### 6.1 Model Serving Architecture

Model serving on Kubernetes requires addressing several challenges: loading models, handling prediction requests, managing model versions, and scaling based on load. Two dominant tools for this purpose are KServe and Seldon Core.

**KServe** (formerly KFServing) provides a standardized API for model serving with support for multiple frameworks. It handles model lifecycle management, auto-scaling, and provides features like explainability and out-of-the-box support for inference on GPUs.

**Seldon Core** provides a more flexible framework with extensive deployment strategies including canary releases, A/B testing, and multi-armed bandits. It integrates well with MLflow and supports custom inference servers.

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                  MODEL SERVING ON KUBERNETES: ARCHITECTURE                   ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   EXTERNAL TRAFFIC                                                           ║
║   ══════════════════════════════════════════════════════════════════════     ║
║   ┌─────────────┐                                                            ║
║   │   Clients   │                                                            ║
║   │ Applications│                                                            ║
║   └──────┬──────┘                                                            ║
║          │                                                                   ║
║          ▼                                                                   ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │                            INGRESS LAYER                             │   ║
║   │  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐           │   ║
║   │  │   Ingress   │      │   Gateway   │      │   Router    │           │   ║
║   │  │ Controller  │      │   (Istio)   │      │             │           │   ║
║   │  └─────────────┘      └─────────────┘      └─────────────┘           │   ║
║   └──────────────────────────────────┬───────────────────────────────────┘   ║
║                                      │                                       ║
║                                      ▼                                       ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │                         MODEL SERVING LAYER                          │   ║
║   │                                                                      │   ║
║   │  ┌────────────────────────────────────────────────────────────────┐  │   ║
║   │  │                     KServe / Seldon Core                       │  │   ║
║   │  │  ┌───────────────────┐          ┌───────────────────┐          │  │   ║
║   │  │  │ InferenceService  │          │ SeldonDeployment  │          │  │   ║
║   │  │  │        or         │          │        or         │          │  │   ║
║   │  │  │ SeldonDeployment  │          │ InferenceService  │          │  │   ║
║   │  │  └───────────────────┘          └───────────────────┘          │  │   ║
║   │  │                                                                │  │   ║
║   │  │  ┌───────────────────┐          ┌───────────────────┐          │  │   ║
║   │  │  │    Transformer    │          │     Predictor     │          │  │   ║
║   │  │  │  (Preprocessing)  │          │      (Model)      │          │  │   ║
║   │  │  └───────────────────┘          └───────────────────┘          │  │   ║
║   │  └────────────────────────────────────────────────────────────────┘  │   ║
║   │                                                                      │   ║
║   │  ┌────────────────────────────────────────────────────────────────┐  │   ║
║   │  │                         MODEL REGISTRY                         │  │   ║
║   │  │  MLflow Model Registry  <───  Model Registry API               │  │   ║
║   │  │           │                          │                         │  │   ║
║   │  │           ▼                          ▼                         │  │   ║
║   │  │  ┌───────────────────┐          ┌───────────────────┐          │  │   ║
║   │  │  │    Model Cache    │          │ Artifact Storage  │          │  │   ║
║   │  │  │   (PVC/Memory)    │          │ (S3/GCS/Azure)    │          │  │   ║
║   │  │  └───────────────────┘          └───────────────────┘          │  │   ║
║   │  └────────────────────────────────────────────────────────────────┘  │   ║
║   │                                                                      │   ║
║   └──────────────────────────────────────────────────────────────────────┘   ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### 6.2 KServe Deployment

KServe provides a simplified deployment experience with built-in support for common ML frameworks. The InferenceService CRD abstracts away infrastructure details.

```yaml
# ============================================================
# KServe InferenceService Definition
# ============================================================
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: fraud-detection
  namespace: ml-production
  annotations:
    # Enable autoscaling
    autoscaling.knative.dev/classType: hpa
    autoscaling.knative.dev/target: "80"
spec:
  predictor:
    # Model framework and storage
    sklearn:
      protocolVersion: v2  # KServe v2 protocol
      storageUri: s3://ml-artifacts/models/fraud-detection

      # Resource configuration
      resources:
        requests:
          cpu: "1"
          memory: "2Gi"
        limits:
          cpu: "2"
          memory: "4Gi"

      # Storage secret for S3 access
      storageUri: s3://ml-artifacts/models/fraud-detection

    # Alternatively, for ONNX models:
    # onnx:
    #   protocolVersion: v2
    #   storageUri: s3://ml-artifacts/models/fraud-detection.onnx

    # Alternatively, for custom serving:
    # container:
    #   image: ml-server:v1.5
    #   command: ["python", "/server/model_server.py"]
    #   resources:
    #     requests:
    #       cpu: "1"
    #       memory: "4Gi"
    #       nvidia.com/gpu: "1"
    #     limits:
    #       cpu: "2"
    #       memory: "8Gi"
    #       nvidia.com/gpu: "1"

  # Optional: Transformer for preprocessing
  transformer:
    name: fraud-transformer
    container:
      image: fraud-transformer:v1.0
      env:
      - name: FEATURE_CONFIG
        valueFrom:
          configMapKeyRef:
            name: feature-config
            key: fraud_features.json
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "1"
          memory: "2Gi"

---
# Auto-scaling configuration
apiVersion: v1
kind: HorizontalPodAutoscaler
metadata:
  name: fraud-detection-hpa
  namespace: ml-production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fraud-detection-predictor  # KServe creates this deployment
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
  - type: Pods
    pods:
      metric:
        name: request_latency_p99
      target:
        type: AverageValue
        averageValue: "100m"
```

### 6.3 Seldon Core Deployment

Seldon Core provides more granular control over deployment strategies. Its multi-armed bandit support enables automated model selection based on performance metrics.

```yaml
# ============================================================
# Seldon Core Deployment with Canary Strategy
# ============================================================
apiVersion: machinelearning.seldon.io/v1alpha2
kind: SeldonDeployment
metadata:
  name: fraud-detection
  namespace: ml-production
spec:
  name: fraud-detection
  predictors:

  # Primary (champion) model - 90% of traffic
  - name: primary
    replicas: 9
    weight: 90
    componentSpecs:
    - spec:
        containers:
        - name: fraud-model
          image: ml-server:v2.1
          env:
          - name: MODEL_NAME
            value: fraud-detection
          - name: MODEL_VERSION
            value: "10"  # Current production version
          - name: MLFLOW_TRACKING_URI
            value: http://mlflow-server:5000
          resources:
            requests:
              cpu: "1"
              memory: "2Gi"
            limits:
              cpu: "2"
              memory: "4Gi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 60
            periodSeconds: 10

        # PoddisruptionBudget for availability
        podDisruptionBudget:
          minAvailable: 8

    # Traffic allocation
    traffic: 90

  # Canary (challenger) model - 10% of traffic
  - name: candidate
    replicas: 1
    weight: 10
    componentSpecs:
    - spec:
        containers:
        - name: fraud-model
          image: ml-server:v2.2  # New version being tested
          env:
          - name: MODEL_NAME
            value: fraud-detection
          - name: MODEL_VERSION
            value: "11"  # Candidate version
          - name: MLFLOW_TRACKING_URI
            value: http://mlflow-server:5000
          resources:
            requests:
              cpu: "1"
              memory: "2Gi"
            limits:
              cpu: "2"
              memory: "4Gi"

    traffic: 10

---
# Seldon Core with A/B Testing and Metric-based Routing
apiVersion: machinelearning.seldon.io/v1alpha2
kind: SeldonDeployment
metadata:
  name: recommendation-engine
  namespace: ml-production
spec:
  name: recommendation-engine
  predictors:
  - name: default
    replicas: 10

    # AB Tester configuration
    aBTesting:
      # Traffic split based on user cookie
      traffic:
        candidate: 20  # 20% to candidate
        default: 80    # 80% to primary

    # Success criteria for automatic promotion
    explainers:
      anchor: true

    componentSpecs:
    - spec:
        containers:
        - name: model
          image: recommendation-model:v3.1

        # Service level settings
        annotations:
          prometheus.io/scrape: "true"
          prometheus.io/port: "8000"
          prometheus.io/path: "/metrics"

    # SeldonCore Graph definition
    graph:
      name: model
      type: MODEL
      modelUri: s3://ml-artifacts/models/recommendation
      serverType: mlflow  # Integration with MLflow
```

### 6.4 Custom Model Server

When built-in frameworks do not meet your requirements, you can deploy a custom model server. This provides full control over model loading, inference logic, and lifecycle management.

```python
# ============================================================
# Custom Model Server for KServe
# ============================================================
"""
Custom inference server compatible with KServe v2 protocol.
"""

from typing import Dict, List, Optional
import numpy as np
import mlflow
from mlserver import MLModel, types
from mlserver.codecs import decode_args


class FraudDetectionModel(MLModel):
    """
    Custom fraud detection model server using MLflow.
    Implements KServe v2 inference protocol.
    """

    async def load(self) -> None:
        """Load model from MLflow registry on startup."""
        model_uri = self.settings.parameters.uri
        self.model = mlflow.lightgbm.load_model(model_uri)

        # Load feature configuration
        self.feature_names = [
            "transaction_amount",
            "transaction_frequency",
            "account_age_days",
            # ... additional features
        ]

        print(f"Model loaded from {model_uri}")

    async def predict(self, payload: types.InferenceRequest) -> types.InferenceResponse:
        """
        Process inference request following KServe v2 protocol.
        """
        inputs = self._extract_inputs(payload)
        predictions = self.model.predict(inputs)

        return types.InferenceResponse(
            model_name=self.settings.model_name,
            model_version=self.settings.model_version,
            outputs=[
                types.ResponseOutput(
                    name="predictions",
                    shape=predictions.shape,
                    datatype="FP32",
                    data=predictions.tolist(),
                )
            ],
        )

    def _extract_inputs(self, payload: types.InferenceRequest) -> np.ndarray:
        """Extract and validate input data."""
        inputs = payload.inputs

        # Find input by name
        input_data = next(
            (inp for inp in inputs if inp.name in ["inputs", "features"]),
            inputs[0]
        )

        # Decode input data
        data = decode_args(input_data)

        # Convert to numpy array
        X = np.array(data)

        # Validate shape
        if X.ndim == 1:
            X = X.reshape(1, -1)

        return X


# Entry point for container
if __name__ == "__main__":
    from mlserver import Settings
    from mlserver import MLModelSettings

    settings = Settings(
        model_name="fraud-detection",
        model_version="1.0.0",
    )

    model_settings = MLModelSettings(
        uri="models:/fraud-detection@champion",
    )

    server = MLModel(
        settings=settings,
        model_settings=model_settings,
    )

    server.start()
```

```yaml
# ============================================================
# Deployment of Custom Model Server
# ============================================================
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: fraud-detection-custom
  namespace: ml-production
spec:
  predictor:
    # Custom container specification
    container:
      image: fraud-detection-server:v1.0

      # Command and args for loading specific model version
      command:
        - python
        - /server/model_server.py
      args:
        - --model_name=fraud-detection
        - --model_alias=champion
        - --mlflow_uri=http://mlflow-server:5000

      env:
      - name: MLFLOW_TRACKING_URI
        value: http://mlflow-server:5000

      ports:
      - containerPort: 8080
        name: http

      resources:
        requests:
          cpu: "1"
          memory: "4Gi"
          nvidia.com/gpu: "1"
        limits:
          cpu: "2"
          memory: "8Gi"
          nvidia.com/gpu: "1"

      readinessProbe:
        httpGet:
          path: /health
          port: 8080
        initialDelaySeconds: 20
        periodSeconds: 5
        timeoutSeconds: 3
        failureThreshold: 3

      livenessProbe:
        httpGet:
          path: /health
          port: 8080
        initialDelaySeconds: 60
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 3
```

---

## 7. MLflow on Kubernetes

### 7.1 MLflow Deployment Architecture

MLflow consists of multiple components that can be deployed on Kubernetes: the tracking server, the model registry, the artifact store, and the metadata store. Understanding how these components interact helps in designing production deployments.

```yaml
# ============================================================
# MLflow Complete Deployment on Kubernetes
# ============================================================
---
# MLflow Tracking Server Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow-server
  namespace: ml-platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app: mlflow
  strategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: mlflow
    spec:
      containers:
      - name: mlflow
        image: ghcr.io/mlflow/mlflow:v2.12.1
        ports:
        - containerPort: 5000
          name: http

        args:
        - mlflow server
        - --host=0.0.0.0
        - --port=5000
        - --backend-store-uri=postgresql://{{.Values.mlflow.dbUser}}:{{.Values.mlflow.dbPassword}}@mlflow-db:5432/mlflow
        - --default-artifact-root=s3://ml-artifacts/mlflow/
        - --workers=4
        - --workers-timeout=3600

        env:
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: ml-s3-secret
              key: AWS_ACCESS_KEY_ID
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: ml-s3-secret
              key: AWS_SECRET_ACCESS_KEY

        resources:
          requests:
            memory: "2Gi"
            cpu: "1"
          limits:
            memory: "4Gi"
            cpu: "2"

        livenessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 30
          periodSeconds: 10

        readinessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 10
          periodSeconds: 5

      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: mlflow
              topologyKey: kubernetes.io/hostname

---
# MLflow Service
apiVersion: v1
kind: Service
metadata:
  name: mlflow-server
  namespace: ml-platform
spec:
  selector:
    app: mlflow
  ports:
  - port: 80
    targetPort: 5000
  type: ClusterIP

---
# MLflow Database (PostgreSQL)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mlflow-db
  namespace: ml-platform
spec:
  serviceName: mlflow-db
  replicas: 1
  selector:
    matchLabels:
      app: mlflow-db
  template:
    metadata:
      labels:
        app: mlflow-db
    spec:
      containers:
      - name: postgresql
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: mlflow
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: mlflow-db-secret
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mlflow-db-secret
              key: password
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1"
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: mlflow-db-pvc

---
# MLflow PVC for database
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mlflow-db-pvc
  namespace: ml-platform
spec:
  storageClassName: standard-rwo
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
```

### 7.2 MLflow Integration with Training Pipelines

Training jobs interact with MLflow through the tracking API. On Kubernetes, this requires configuring the tracking URI and authentication.

```python
# ============================================================
# Training Script with MLflow Integration
# ============================================================
"""
Training script designed for Kubernetes execution.
Logs metrics, parameters, and artifacts to MLflow.
"""

import mlflow
from mlflow.tracking import MlflowClient
import mlflow.lightgbm
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score
import lightgbm as lgb
import os
import json

def setup_mlflow():
    """Configure MLflow connection for Kubernetes deployment."""
    # Get MLflow server URL from environment
    mlflow_uri = os.environ.get("MLFLOW_TRACKING_URI", "http://mlflow-server:5000")
    mlflow.set_tracking_uri(mlflow_uri)

    # Set experiment
    experiment_name = os.environ.get("MLFLOW_EXPERIMENT_NAME", "default")
    mlflow.set_experiment(experiment_name)

    # Enable automatic logging
    mlflow.lightgbm.autolog()

    return mlflow.get_tracking_uri()

def train_model(
    train_data_path: str,
    hyperparameters: dict,
    model_name: str
) -> dict:
    """Train a LightGBM model and log to MLflow."""

    # Setup MLflow
    tracking_uri = setup_mlflow()
    print(f"MLflow tracking: {tracking_uri}")

    # Start run
    run_name = f"training-{model_name}-{os.environ.get('HOSTNAME', 'local')}"
    with mlflow.start_run(run_name=run_name) as run:
        run_id = run.info.run_id
        print(f"MLflow run ID: {run_id}")

        # Log pipeline metadata
        mlflow.set_tag("pipeline", "kubernetes-training")
        mlflow.set_tag("node", os.environ.get("HOSTNAME", "unknown"))
        mlflow.set_tag("model_name", model_name)

        # Log hyperparameters
        mlflow.log_params({
            f"hyperparam.{k}": v for k, v in hyperparameters.items()
        })

        # Load data
        df = pd.read_csv(train_data_path)
        X = df.drop(columns=["target"])
        y = df["target"]

        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42, stratify=y
        )

        # Log data statistics
        mlflow.log_params({
            "data.train_size": len(X_train),
            "data.test_size": len(X_test),
            "data.num_features": X.shape[1],
            "data.positive_rate": y.mean()
        })

        # Train model
        model = lgb.LGBMClassifier(**hyperparameters)
        model.fit(
            X_train, y_train,
            eval_set=[(X_test, y_test)],
            callbacks=[lgb.early_stopping(50, verbose=False)]
        )

        # Evaluate
        y_pred_proba = model.predict_proba(X_test)[:, 1]
        auc = roc_auc_score(y_test, y_pred_proba)

        mlflow.log_metrics({
            "auc": auc,
            "train_samples": len(X_train),
            "test_samples": len(X_test)
        })

        # Create signature for model validation
        signature = mlflow.models.infer_signature(
            X_test, model.predict(X_test)
        )

        # Register model
        mlflow.lightgbm.log_model(
            model,
            artifact_path="model",
            signature=signature,
            registered_model_name=model_name
        )

        # Return metrics for further processing
        return {
            "run_id": run_id,
            "auc": auc,
            "model_name": model_name
        }

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--train-data", required=True)
    parser.add_argument("--model-name", required=True)
    parser.add_argument("--hyperparameters", default="{}")
    args = parser.parse_args()

    hyperparameters = json.loads(args.hyperparameters)
    result = train_model(args.train_data, hyperparameters, args.model_name)

    print(f"Training complete: {result}")
```

---

## 8. GitOps Deployment with ArgoCD

### 8.1 GitOps Fundamentals

GitOps extends Git's version control capabilities to infrastructure management. In a GitOps workflow, the desired state of Kubernetes resources is stored in Git, and automated tools (typically ArgoCD or Flux) ensure the actual cluster state matches the desired state.

For ML workloads, GitOps provides several benefits:

- **Audit Trail**: Every deployment change is a Git commit, providing complete history
- **Rollback Capability**: Reverting a deployment is as simple as reverting a commit
- **Collaboration**: Pull requests enable peer review of deployment changes
- **Consistency**: The same manifests are deployed across environments

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                               GITOPS WORKFLOW                                ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │                            GIT REPOSITORY                            │   ║
║   │                                                                      │   ║
║   │  ┌────────────────────────────────────────────────────────────────┐  │   ║
║   │  │ Directory Structure:                                           │  │   ║
║   │  │                                                                │  │   ║
║   │  │ ├── ml-models/                                                 │  │   ║
║   │  │ │   ├── fraud-detection/                                       │  │   ║
║   │  │ │   │   ├── production/                                        │  │   ║
║   │  │ │   │   │   ├── deployment.yaml                                │  │   ║
║   │  │ │   │   │   ├── service.yaml                                   │  │   ║
║   │  │ │   │   │   └── kustomization.yaml                             │  │   ║
║   │  │ │   │   └── staging/                                           │  │   ║
║   │  │ │   │       ├── deployment.yaml                                │  │   ║
║   │  │ │   │       └── service.yaml                                   │  │   ║
║   │  │ │   └── recommendation-engine/                                 │  │   ║
║   │  │ ├── ml-pipelines/                                              │  │   ║
║   │  │ │   ├── training-pipeline.yaml                                 │  │   ║
║   │  │ │   └── batch-inference.yaml                                   │  │   ║
║   │  │ └── mlflow/                                                    │  │   ║
║   │  │     ├── mlflow-server.yaml                                     │  │   ║
║   │  │     └── mlflow-db.yaml                                         │  │   ║
║   │  └────────────────────────────────────────────────────────────────┘  │   ║
║   │                                                                      │   ║
║   └──────────────────────────────────┬───────────────────────────────────┘   ║
║                                      │                                       ║
║                             Push (merge to main)                             ║
║                                      ▼                                       ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │                                ARGOCD                                │   ║
║   │                                                                      │   ║
║   │  ┌────────────────────────────────────────────────────────────────┐  │   ║
║   │  │ ArgoCD continuously monitors Git repository                    │  │   ║
║   │  │ Detects changes and syncs to Kubernetes cluster                │  │   ║
║   │  │                                                                │  │   ║
║   │  │  Git Repo ───────────────────────────────► K8s Cluster         │  │   ║
║   │  │      │          (manifest changes)            (sync)           │  │   ║
║   │  │      ◄─────────────────────────────────────────────────        │  │   ║
║   │  │               (health status feedback)                         │  │   ║
║   │  └────────────────────────────────────────────────────────────────┘  │   ║
║   │                                                                      │   ║
║   └──────────────────────────────────┬───────────────────────────────────┘   ║
║                                      │                                       ║
║                                    Sync                                      ║
║                                      ▼                                       ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │                          KUBERNETES CLUSTER                          │   ║
║   │                                                                      │   ║
║   │    ┌──────────────────────┐          ┌──────────────────────┐        │   ║
║   │    │    ml-production     │          │      ml-staging      │        │   ║
║   │    │      namespace       │          │      namespace       │        │   ║
║   │    │                      │          │                      │        │   ║
║   │    │   Fraud Detection    │          │   Fraud Detection    │        │   ║
║   │    │   v2.1 (champion)    │          │   v2.2 (candidate)   │        │   ║
║   │    └──────────────────────┘          └──────────────────────┘        │   ║
║   │                                                                      │   ║
║   └──────────────────────────────────────────────────────────────────────┘   ║
║                                                                              ║
║   CI/CD TRIGGER (Optional):                                                  ║
║   ══════════════════════════════════════════════════════════════════════     ║
║   Git Push → CI Pipeline → Train Model → Register to MLflow →                ║
║   Update Manifest in Git → ArgoCD Syncs to Production                        ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### 8.2 ArgoCD Application for ML Deployments

ArgoCD uses Application resources to define which Git repository paths should be synchronized to which Kubernetes clusters and namespaces.

```yaml
# ============================================================
# ArgoCD Application: Production ML Service
# ============================================================
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fraud-detection-prod
  namespace: argocd
  labels:
    app: ml-inference
    environment: production
spec:
  # Project scope
  project: ml-platform

  # Source: Git repository
  source:
    repoURL: https://github.com/company/ml-deployments
    targetRevision: main
    path: ml-models/fraud-detection/production

    # Kustomize for environment-specific overlays
    kustomize:
      commonLabels:
        app: fraud-detection
        team: ml-platform
        environment: production

  # Destination: Kubernetes cluster
  destination:
    server: https://kubernetes.default.svc
    namespace: ml-production

  # Sync policy
  syncPolicy:
    automated:
      # Automatically sync when Git changes
      prune: true        # Remove resources deleted from Git
      selfHeal: true     # Restore resources to Git state
      allowEmpty: false  # Don't allow empty diffs

    # Sync options
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - ServerSideApply=true  # Use server-side apply for better conflict handling

  # Retry configuration
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m

  # Ignore differences (field-level sync control)
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas  # Don't sync replica count (managed by HPA)
    - /status

  # Manual sync required for production
  requiresManualSync: true

---
# ArgoCD Application: ML Pipeline
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ml-training-pipeline
  namespace: argocd
  labels:
    app: ml-pipeline
spec:
  project: ml-platform

  source:
    repoURL: https://github.com/company/ml-deployments
    targetRevision: main
    path: ml-pipelines/training

  destination:
    server: https://kubernetes.default.svc
    namespace: ml-workloads

  syncPolicy:
    automated:
      prune: true
      selfHeal: true

---
# ArgoCD Project for ML Platform
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: ml-platform
  namespace: argocd
spec:
  # Allowed source repositories
  sourceRepos:
  - https://github.com/company/ml-deployments
  - https://github.com/company/ml-pipelines

  # Allowed destination clusters and namespaces
  destinations:
  - server: https://kubernetes.default.svc
    namespace: ml-platform
  - server: https://kubernetes.default.svc
    namespace: ml-production
  - server: https://kubernetes.default.svc
    namespace: ml-staging
  - server: https://kubernetes.default.svc
    namespace: ml-workloads

  # Allowed resource types
  resourceWhitelist:
  - group: apps
    kinds:
    - Deployment
    - StatefulSet
    - DaemonSet
  - group: batch
    kinds:
    - Job
    - CronJob
  - group: ""
    kinds:
    - Service
    - PersistentVolumeClaim
    - ConfigMap
    - Secret
  - group: machinelearning.seldon.io
    kinds:
    - SeldonDeployment
  - group: serving.kserve.io
    kinds:
    - InferenceService

  # Namespace resource quotas
  namespaceResourceBlacklist:
  - group: ""
    kinds:
    - ResourceQuota
    - LimitRange
```

### 8.3 Automated Model Deployment Pipeline

Combining CI/CD with GitOps enables fully automated model deployment: code changes trigger training, successful training updates model manifests, and ArgoCD deploys the new model.

```yaml
# ============================================================
# GitHub Actions: CI/CD with GitOps
# ============================================================
name: ML Model Deployment Pipeline

on:
  push:
    branches: [main]
    paths:
      - 'training/**'
      - 'features/**'

  workflow_dispatch:

env:
  MLFLOW_TRACKING_URI: http://mlflow-server.ml-platform:5000
  REGISTRY: ghcr.io/company

jobs:
  # ─────────────────────────────────────────────────────────────
  # JOB 1: Build and Test
  # ─────────────────────────────────────────────────────────────
  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Lint and test
        run: |
          pip install flake8 pytest
          flake8 training/ --max-line-length=100
          pytest training/ -v --cov=.

      - name: Build training image
        run: |
          docker build -t ${{ env.REGISTRY }}/ml-training:${{ github.sha }} training/
          docker push ${{ env.REGISTRY }}/ml-training:${{ github.sha }}

  # ─────────────────────────────────────────────────────────────
  # JOB 2: Train Model
  # ─────────────────────────────────────────────────────────────
  train:
    needs: build-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run training
        run: |
          kubectl apply -f - <<EOF
          apiVersion: batch/v1
          kind: Job
          metadata:
            name: ml-training-${{ github.run_id }}
            namespace: ml-workloads
          spec:
            ttlSecondsAfterFinished: 3600
            template:
              spec:
                restartPolicy: OnFailure
                containers:
                - name: trainer
                  image: ${{ env.REGISTRY }}/ml-training:${{ github.sha }}
                  env:
                  - name: MLFLOW_TRACKING_URI
                    value: ${{ env.MLFLOW_TRACKING_URI }}
                  - name: MODEL_NAME
                    value: fraud-detection
                  resources:
                    requests:
                      memory: "8Gi"
                      cpu: "4"
                      nvidia.com/gpu: "1"
                    limits:
                      memory: "16Gi"
                      cpu: "8"
                      nvidia.com/gpu: "1"
          EOF

      - name: Wait for training completion
        run: |
          kubectl wait --for=condition=complete \
            job/ml-training-${{ github.run_id }} \
            -n ml-workloads \
            --timeout=7200s

      - name: Get training result
        run: |
          kubectl logs job/ml-training-${{ github.run_id }} -n ml-workloads

  # ─────────────────────────────────────────────────────────────
  # JOB 3: Update GitOps Manifests
  # ─────────────────────────────────────────────────────────────
  update-manifests:
    needs: train
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Get latest model version from MLflow
        run: |
          MODEL_VERSION=$(python -c "
          import mlflow
          client = mlflow.MlflowClient()
          latest = client.get_latest_version('fraud-detection')
          print(latest.version)
          ")
          echo "MODEL_VERSION=$MODEL_VERSION" >> $GITHUB_ENV

      - name: Update deployment manifests
        run: |
          # Update image in deployment
          sed -i 's|image: .*|image: ${{ env.REGISTRY }}/ml-training:${{ github.sha }}|' \
            ml-models/fraud-detection/production/deployment.yaml

          # Update model version annotation
          sed -i 's|model-version: .*|model-version: "$MODEL_VERSION"|' \
            ml-models/fraud-detection/production/deployment.yaml

          # Update model URI in annotation
          sed -i 's|models:/fraud-detection@.*|models:/fraud-detection@v$MODEL_VERSION|' \
            ml-models/fraud-detection/production/deployment.yaml

      - name: Create commit
        run: |
          git config user.name "ML Pipeline"
          git config user.email "ml-pipeline@company.com"

          git add ml-models/fraud-detection/
          git diff --staged || true

          git commit -m "Update fraud-detection model to version ${{ env.MODEL_VERSION }}

          Triggered by: ${{ github.event_name }}
          Run ID: ${{ github.run_id }}
          Commit: ${{ github.sha }}"

          git push origin main

  # ArgoCD will automatically detect the Git change and sync to cluster
```

---

## 9. Multi-Tenant ML Environments

### 9.1 Namespace-Based Multi-Tenancy

Enterprise ML environments often need to serve multiple teams or customers on shared infrastructure. Kubernetes namespaces provide logical isolation, and with proper configuration, they can support secure multi-tenancy.

```yaml
# ============================================================
# Multi-Tenant Namespace Setup
# ============================================================
---
# Namespace for Team A
apiVersion: v1
kind: Namespace
metadata:
  name: ml-team-a
  labels:
    team: team-a
    cost-center: ml-engineering

---
# ResourceQuota for Team A
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-quota
  namespace: ml-team-a
spec:
  hard:
    requests.cpu: "32"
    requests.memory: "128Gi"
    requests.nvidia.com/gpu: "4"
    limits.cpu: "64"
    limits.memory: "256Gi"
    pods: "20"
    persistentvolumeclaims: "10"

---
# LimitRange for Team A
apiVersion: v1
kind: LimitRange
metadata:
  name: team-a-limits
  namespace: ml-team-a
spec:
  limits:
  - type: Container
    default:
      cpu: "1"
      memory: "2Gi"
    defaultRequest:
      cpu: "250m"
      memory: "512Mi"
    max:
      cpu: "16"
      memory: "64Gi"
      nvidia.com/gpu: "2"

---
# Network Policy for Team A
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: team-a-network-policy
  namespace: ml-team-a
spec:
  # Ingress from same namespace and ingress controller
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ml-team-a
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    - podSelector: {}

  # Allow egress to MLflow and external storage
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: ml-platform
    - namespaceSelector:
        matchLabels:
          name: ml-data
  - to:
    - namespaceSelector: {}  # External access
    ports:
    - port: 443

---
# RBAC for Team A
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: team-a-developer
  namespace: ml-team-a
rules:
- apiGroups: [""]
  resources: ["pods", "services", "persistentvolumeclaims", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-developer-binding
  namespace: ml-team-a
subjects:
- kind: Group
  name: team-a-developers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: team-a-developer
  apiGroup: rbac.authorization.k8s.io
```

### 9.2 Node Pools for ML Workloads

Different ML workloads have different hardware requirements. Node pools allow you to provision different node types for different workload categories.

```yaml
# ============================================================
# Node Pool Configuration (GKE Example)
# ============================================================
# GKE Node Pool for GPU workloads
apiVersion: v1
kind: NodePool  # Provider-specific resource
metadata:
  name: gpu-nodepool
  namespace: ml-platform
spec:
  nodeCount: 3
  nodeConfig:
    machineType: a2-highgpu-1g  # NVIDIA A100
    diskType: pd-ssd
    diskSizeGb: 100

    # GPU configuration
    guestAccelerators:
    - acceleratorType: nvidia-tesla-a100
      acceleratorCount: 1

    # Labels for node selection
    labels:
      workload-type: ml-gpu
      gpu-type: nvidia-a100

    # Taints to prevent non-GPU workloads from scheduling
    taints:
    - key: nvidia.com/gpu
      value: gpu
      effect: NoSchedule

    # Labels for scheduling
    labels:
      cloud.google.com/gke-accelerator: nvidia-tesla-a100

---
# Node Pool for CPU batch workloads
apiVersion: v1
kind: NodePool
metadata:
  name: cpu-batch-nodepool
  namespace: ml-platform
spec:
  nodeCount: 10
  nodeConfig:
    machineType: n2-standard-8
    diskType: pd-standard
    diskSizeGb: 50

    labels:
      workload-type: ml-batch

    taints:
    - key: workload-type
      value: batch
      effect: NoSchedule

---
# Pod using specific node pool
apiVersion: v1
kind: Pod
metadata:
  name: gpu-training
spec:
  containers:
  - name: trainer
    image: ml-training:latest
    resources:
      requests:
        memory: "8Gi"
        cpu: "2"
        nvidia.com/gpu: "1"
      limits:
        memory: "16Gi"
        cpu: "4"
        nvidia.com/gpu: "1"

  # Select GPU nodes
  nodeSelector:
    workload-type: ml-gpu

  # Tolerate GPU taint
  tolerations:
  - key: "nvidia.com/gpu"
    operator: "Exists"
    effect: "NoSchedule"
```

---

## 10. Monitoring and Observability

### 10.1 ML-Specific Metrics

Monitoring ML workloads requires tracking not just infrastructure metrics but also ML-specific metrics: prediction latency, model accuracy, data drift, and business outcomes.

```yaml
# ============================================================
# Prometheus Metrics for ML Inference
# ============================================================
apiVersion: v1
kind: ConfigMap
metadata:
  name: ml-inference-metrics
  namespace: ml-platform
data:
  metrics.yaml: |
    # ML Inference Metrics

    # Request metrics
    inference_requests_total:
      type: Counter
      description: Total number of inference requests
      labels: [model_name, model_version, status]

    inference_request_duration_seconds:
      type: Histogram
      description: Inference request latency
      buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5]
      labels: [model_name, model_version]

    # Model metrics
    model_predictions_total:
      type: Counter
      description: Total predictions made by each model
      labels: [model_name, model_version, class]

    model_confidence_histogram:
      type: Histogram
      description: Distribution of prediction confidence scores
      buckets: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
      labels: [model_name, model_version]

    # Data metrics
    input_feature_drift_score:
      type: Gauge
      description: Population Stability Index (PSI) for input features
      labels: [model_name, feature_name]

    # Training metrics
    training_duration_seconds:
      type: Gauge
      description: Time taken for model training
      labels: [model_name, run_id]

    training_auc:
      type: Gauge
      description: AUC score from training
      labels: [model_name, run_id]
```

```python
# ============================================================
# Metrics instrumentation in inference server
# ============================================================
from prometheus_client import Counter, Histogram, Gauge
import time

# Define metrics
inference_requests = Counter(
    'inference_requests_total',
    'Total inference requests',
    ['model_name', 'model_version', 'status']
)

inference_latency = Histogram(
    'inference_request_duration_seconds',
    'Inference request latency',
    ['model_name', 'model_version'],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0]
)

prediction_distribution = Histogram(
    'model_prediction_distribution',
    'Distribution of model predictions',
    ['model_name', 'model_version'],
    buckets=[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
)

def predict_with_metrics(model, features, model_name, model_version):
    """Execute prediction with metrics collection."""
    start_time = time.time()

    try:
        # Make prediction
        prediction = model.predict(features)
        status = "success"
    except Exception as e:
        status = "error"
        raise
    finally:
        # Record metrics
        duration = time.time() - start_time

        inference_requests.labels(
            model_name=model_name,
            model_version=model_version,
            status=status
        ).inc()

        inference_latency.labels(
            model_name=model_name,
            model_version=model_version
        ).observe(duration)

        # Record prediction distribution for binary models
        if hasattr(prediction, 'tolist'):
            for prob in prediction:
                prediction_distribution.labels(
                    model_name=model_name,
                    model_version=model_version
                ).observe(prob)

    return prediction
```

### 10.2 Grafana Dashboard for ML Operations

```yaml
# ============================================================
# Grafana Dashboard for ML Inference
# ============================================================
apiVersion: v1
kind: ConfigMap
metadata:
  name: ml-inference-grafana-dashboard
  namespace: monitoring
data:
  ml-inference-dashboard.json: |
    {
      "dashboard": {
        "title": "ML Inference Dashboard",
        "uid": "ml-inference",
        "panels": [
          {
            "title": "Request Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "sum(rate(inference_requests_total[5m])) by (model_name)",
                "legendFormat": "{{model_name}}"
              }
            ]
          },
          {
            "title": "Latency P99",
            "type": "graph",
            "targets": [
              {
                "expr": "histogram_quantile(0.99, rate(inference_request_duration_seconds_bucket[5m])) by (model_name)",
                "legendFormat": "{{model_name}} P99"
              }
            ]
          },
          {
            "title": "Error Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "sum(rate(inference_requests_total{status='error'}[5m])) by (model_name) / sum(rate(inference_requests_total[5m])) by (model_name)",
                "legendFormat": "{{model_name}} error rate"
              }
            ]
          },
          {
            "title": "Prediction Distribution",
            "type": "heatmap",
            "targets": [
              {
                "expr": "rate(model_prediction_distribution_bucket[5m])",
                "legendFormat": "{{le}}"
              }
            ]
          }
        ]
      }
    }
```

---

## 11. Troubleshooting and Best Practices

### 11.1 Common Issues and Solutions

**Pod Pending with GPU Request**: If a pod requesting GPUs remains in Pending state, verify GPU node availability, device plugin status, and node selectors.

```bash
# Check GPU node capacity
kubectl describe nodes | grep -A 5 "Capacity"
# Expected: nvidia.com/gpu: 2

# Check device plugin
kubectl get pods -n kube-system | grep nvidia
# Expected: nvidia-device-plugin-daemonset running

# Check pod events for scheduling issues
kubectl describe pod <pod-name>
# Look for "didn't match node selector" or "insufficient nvidia.com/gpu"
```

**OutOfMemory Errors**: ML training often requires more memory than initially allocated. Monitor actual usage and adjust limits.

```bash
# Check actual memory usage
kubectl top pods -n ml-workloads
# Compare with requested limits
```

**Model Loading Failures**: Model artifacts may be too large or use incompatible formats. Check artifact size and model framework compatibility.

```yaml
# Increase timeout for large model loading
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
spec:
  predictor:
    timeout: 120  # seconds
    container:
      image: ml-server:latest
```

### 11.2 Best Practices Summary

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                KUBERNETES ML BEST PRACTICES: QUICK REFERENCE                 ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  RESOURCE MANAGEMENT                                                         ║
║  ══════════════════════════════════════════════════════════════════════      ║
║  ✓ Set resource requests for scheduling                                      ║
║  ✓ Set resource limits to prevent runaway containers                         ║
║  ✓ Use QoS classes: Guaranteed for production inference                      ║
║  ✓ Use LimitRange to enforce defaults                                        ║
║  ✓ Monitor actual vs requested resources                                     ║
║                                                                              ║
║  GPU UTILIZATION                                                             ║
║  ══════════════════════════════════════════════════════════════════════      ║
║  ✓ Request GPUs explicitly with nvidia.com/gpu                               ║
║  ✓ Use node selectors for GPU nodes                                          ║
║  ✓ Tolerate GPU node taints                                                  ║
║  ✓ Consider GPU time-slicing for inference workloads                         ║
║  ✓ Enable CUDA monitoring                                                    ║
║                                                                              ║
║  STORAGE                                                                     ║
║  ══════════════════════════════════════════════════════════════════════      ║
║  ✓ Use PVCs for model artifacts and datasets                                 ║
║  ✓ Use ReadWriteOnce for single-pod access                                   ║
║  ✓ Use ReadOnlyMany for shared datasets                                      ║
║  ✓ Consider init containers for data preparation                             ║
║  ✓ Configure appropriate storage classes for performance                     ║
║                                                                              ║
║  MODEL SERVING                                                               ║
║  ══════════════════════════════════════════════════════════════════════      ║
║  ✓ Use readiness probes for model loading                                    ║
║  ✓ Configure appropriate timeouts                                            ║
║  ✓ Enable autoscaling based on request metrics                               ║
║  ✓ Use canary deployments for gradual rollouts                               ║
║  ✓ Configure resource limits for inference pods                              ║
║                                                                              ║
║  MONITORING                                                                  ║
║  ══════════════════════════════════════════════════════════════════════      ║
║  ✓ Expose Prometheus metrics from inference servers                          ║
║  ✓ Track prediction latency, error rates, and throughput                     ║
║  ✓ Monitor data drift metrics                                                ║
║  ✓ Set up alerts for anomaly detection                                       ║
║  ✓ Log model version and run metadata for debugging                          ║
║                                                                              ║
║  CI/CD AND DEPLOYMENT                                                        ║
║  ══════════════════════════════════════════════════════════════════════      ║
║  ✓ Use GitOps for declarative deployments                                    ║
║  ✓ Integrate MLflow for model tracking                                       ║
║  ✓ Automate validation gates before deployment                               ║
║  ✓ Use Kubernetes Jobs for batch workloads                                   ║
║  ✓ Configure PodDisruptionBudget for availability                            ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### 11.3 Architecture Decision Checklist

When designing ML workloads on Kubernetes, use this checklist to ensure completeness:

**Compute Resources**:

- Are GPU requirements specified correctly?
- Are CPU and memory requests and limits set appropriately?
- Is the workload QoS class correct?
- Are node selectors and tolerations configured?

**Storage**:

- Are PVCs used for persistent data?
- Is the storage class appropriate for performance needs?
- Are access modes correct (RWO, ROX, RWX)?
- Is data access pattern efficient?

**Networking**:

- Are services configured correctly?
- Are ingress resources set up for external access?
- Are network policies protecting sensitive services?
- Is DNS resolution working?

**Monitoring**:

- Are Prometheus metrics exposed?
- Are Grafana dashboards configured?
- Are alerts set up for critical metrics?
- Is logging configured?

**Deployment**:

- Are readiness and liveness probes configured?
- Is autoscaling set up?
- Are resource limits preventing resource exhaustion?
- Is rollback capability verified?

---

## Conclusion

Kubernetes has become the standard platform for production ML workloads, providing the container orchestration, resource management, and scaling capabilities that ML systems require. This document has covered the essential concepts for deploying ML workloads on Kubernetes, from understanding core abstractions to implementing enterprise-grade patterns.

The key takeaways are:

**Fundamentals Matter**: Understanding pods, deployments, services, and namespaces provides the foundation for all Kubernetes ML work.

**Resource Management is Critical**: Proper CPU, memory, and GPU allocation ensures efficient utilization and prevents resource exhaustion.

**Specialized Tools Enhance Productivity**: Kubeflow, Argo Workflows, KServe, and Seldon Core provide higher-level abstractions for ML-specific tasks.

**GitOps Enables Reliability**: Declarative deployments through ArgoCD provide auditability, rollback capability, and collaboration workflows.

**Monitoring Enables Observability**: ML-specific metrics and dashboards help detect issues before they impact users.

By applying these principles, you can build production ML systems on Kubernetes that are reliable, scalable, and maintainable.

---

**Document Version**: 1.0
**Last Updated**: April 2026
**Author**: MiniMax Agent
