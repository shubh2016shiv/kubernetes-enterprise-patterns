#!/usr/bin/env bash
# =============================================================================
# FILE:    step-by-step-install.sh
# PURPOSE: One-shot installer for all Kubernetes developer tools on WSL2.
#          Installs: kind, kubectl, helm, kubectx+kubens, k9s.
#          Each tool is installed, verified, and explained before moving on.
#          Run this once. After this, your WSL2 environment is ready to create
#          and operate Kubernetes clusters.
#
# USAGE:   Run from inside WSL2 Ubuntu terminal:
#            bash setup/00-prerequisites/platform-guides/windows-wsl2/step-by-step-install.sh
#
# PREREQS: Docker Desktop running on Windows with WSL2 integration enabled.
#          Internet access to download binaries from official sources.
#          sudo privileges in WSL2 (default for Ubuntu in WSL2).
#
# MACHINE: Tested on Windows 11 / WSL2 Ubuntu 22.04 / 16 GB RAM / RTX 2060.
#
# ENTERPRISE NOTE: In enterprise environments, tool installation is done via:
#   - Nix package manager (hermetic, reproducible per-project environments)
#   - Custom internal package repositories (Artifactory, Nexus)
#   - Dev containers (VS Code devcontainer.json pre-installs everything)
#   - Golden AMIs / VM images with tools pre-baked
#   This script is the learner-friendly equivalent: install once, learn forever.
# =============================================================================

set -euo pipefail
# Why set -euo pipefail?
#   -e: exit immediately if any command returns a non-zero exit code.
#   -u: treat unset variables as errors (catches typos in variable names).
#   -o pipefail: if any command in a pipeline fails, the whole pipeline fails.
#   Together, these make scripts predictable and safe — they fail loudly instead
#   of silently continuing into a broken state. This is standard in enterprise scripts.

# ┌─────────────────────────────────────────────────────────────────────┐
# │                    INSTALLER FLOW                                    │
# │                                                                      │
# │  Stage 1: Detect architecture (amd64 vs arm64)                      │
# │      └── Needed because binary download URLs differ by CPU arch      │
# │                                                                      │
# │  Stage 2: Install kind                                               │
# │      └── The cluster engine — without this nothing else matters      │
# │                                                                      │
# │  Stage 3: Install kubectl                                            │
# │      └── The universal Kubernetes CLI                                │
# │                                                                      │
# │  Stage 4: Install helm                                               │
# │      └── The Kubernetes package manager                              │
# │                                                                      │
# │  Stage 5: Install kubectx + kubens                                   │
# │      └── Context and namespace switching tools                       │
# │                                                                      │
# │  Stage 6: Install k9s                                                │
# │      └── Terminal Kubernetes dashboard                               │
# │                                                                      │
# │  Stage 7: Configure kubectl aliases and shell completion             │
# │      └── Saves hundreds of keystrokes per day                        │
# │                                                                      │
# │  Stage 8: Final verification                                         │
# │      └── Print version table — all tools installed and on PATH       │
# └─────────────────────────────────────────────────────────────────────┘

# ─────────────────────────────────────────────────────────────────────
# Shared helpers
# ─────────────────────────────────────────────────────────────────────

# Print a formatted section banner so the learner knows which stage they're in.
print_stage() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_ok()   { echo "  ✓ $1"; }
print_info() { echo "  → $1"; }
print_warn() { echo "  ⚠ $1"; }

# ─────────────────────────────────────────────────────────────────────
# Stage 1.0: Architecture Detection
# Purpose:   Binary downloads differ by CPU architecture.
#            Most Windows laptops are amd64 (Intel/AMD x86-64).
#            Surface Pro X and ARM-based machines would be arm64.
# Expected output: ARCH=amd64 (most common) or ARCH=arm64.
# ─────────────────────────────────────────────────────────────────────
print_stage "Stage 1: Detecting System Architecture"

ARCH="amd64"
if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
  ARCH="arm64"
fi

print_ok "Architecture detected: ${ARCH}"
print_info "This affects which binary URLs are used in the next stages."

# Also detect the OS for tools that need it (Linux vs macOS in WSL2 is always Linux)
OS="linux"
print_ok "Operating system: ${OS}"

# ─────────────────────────────────────────────────────────────────────
# Stage 2.0: Install kind
# Purpose:   kind (Kubernetes IN Docker) is the local cluster engine.
#            It creates real Kubernetes nodes as Docker containers.
#            Without kind, we cannot create a multi-node cluster locally.
#
# Why kind over Minikube or Docker Desktop Kubernetes?
#   - kind supports multi-node clusters (control-plane + workers) locally.
#   - kind is how Kubernetes CI pipelines validate code (GitHub Actions).
#   - kind clusters match real cluster topology better than single-node alternatives.
#   - Docker Desktop Kubernetes is single-node and adds kubeconfig confusion.
#
# Enterprise equivalent: EKS node groups, GKE node pools, AKS node pools.
# ─────────────────────────────────────────────────────────────────────
print_stage "Stage 2: Installing kind (Kubernetes Cluster Engine)"

# Check if kind is already installed — idempotent install
if command -v kind &>/dev/null; then
  print_ok "kind already installed: $(kind version)"
  print_info "Skipping re-installation."
else
  # Stage 2.1: Download kind binary to a safe temporary location.
  # Why /tmp? We do not have write access to /usr/local/bin directly.
  # We download to /tmp first, set permissions, then move with sudo.
  print_info "Downloading kind to /tmp/kind ..."

  KIND_VERSION="v0.23.0"
  # Why pin a version? In enterprise, you always pin tool versions.
  # "Latest" is non-deterministic and can break CI pipelines silently.

  curl -Lo /tmp/kind \
    "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${OS}-${ARCH}"

  # Stage 2.2: Make the binary executable.
  # Linux requires explicit executable permission — files are not auto-executable.
  chmod +x /tmp/kind

  # Stage 2.3: Move to system PATH with sudo.
  # /usr/local/bin is the standard location for user-installed system tools.
  # Files here are available to all users without modifying PATH.
  sudo mv /tmp/kind /usr/local/bin/kind

  print_ok "kind ${KIND_VERSION} installed to /usr/local/bin/kind"
fi

# Verify kind is callable and on PATH
kind version &>/dev/null && print_ok "kind is operational." \
  || { echo "✗ kind installation failed. Check internet connection and retry."; exit 1; }

# ─────────────────────────────────────────────────────────────────────
# Stage 3.0: Install kubectl
# Purpose:   kubectl is THE Kubernetes CLI. Every Kubernetes engineer uses
#            the same binary regardless of whether the cluster is local (kind),
#            AWS EKS, Google GKE, Azure AKS, or on-premises.
#            kubectl talks to the kube-apiserver and is the primary interface
#            for all cluster operations.
#
# Enterprise note: kubectl version is versioned alongside the cluster.
#   The client should be within 1 minor version of the cluster server.
#   Enterprise teams pin kubectl versions and distribute them via:
#   - Internal package repos (Artifactory)
#   - Dev containers
#   - Nix shells
# ─────────────────────────────────────────────────────────────────────
print_stage "Stage 3: Installing kubectl (The Universal Kubernetes CLI)"

if command -v kubectl &>/dev/null; then
  print_ok "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
  print_info "Skipping re-installation."
else
  print_info "Fetching latest stable kubectl version string ..."
  # The stable.txt file is maintained by the Kubernetes project and always
  # points to the latest stable release. This is the recommended approach.
  K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  print_info "Installing kubectl ${K8S_VERSION} ..."

  # Stage 3.1: Download the binary
  curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/${ARCH}/kubectl"

  # Stage 3.2: Verify the download using the official SHA-256 checksum.
  # Why verify? This is supply chain security — you confirm you downloaded
  # exactly what the Kubernetes project published, not a tampered binary.
  # Enterprise teams require this for all tool installations.
  curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/${ARCH}/kubectl.sha256"

  if echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check --quiet; then
    print_ok "SHA-256 checksum verified — binary is authentic."
  else
    echo "✗ Checksum mismatch! The downloaded kubectl binary may be corrupted."
    echo "  Delete /tmp/kubectl and retry. If this persists, check dl.k8s.io status."
    rm -f kubectl kubectl.sha256
    exit 1
  fi

  # Stage 3.3: Install using the `install` command (sets owner, group, permissions in one step)
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

  # Clean up download artifacts
  rm -f kubectl kubectl.sha256

  print_ok "kubectl ${K8S_VERSION} installed to /usr/local/bin/kubectl"
fi

kubectl version --client &>/dev/null && print_ok "kubectl is operational." \
  || { echo "✗ kubectl installation failed."; exit 1; }

# ─────────────────────────────────────────────────────────────────────
# Stage 4.0: Install helm
# Purpose:   Helm is the Kubernetes package manager. Enterprise platforms
#            are deployed via Helm charts (KServe, Istio, Prometheus,
#            cert-manager, ExternalDNS, Argo CD, etc.).
#            Without Helm, the ml-serving/ track is blocked.
#
# Enterprise equivalent: helm is universal across all Kubernetes platforms.
#   Enterprises version-lock chart dependencies in Chart.lock and use
#   private chart repositories (Chartmuseum, Artifactory).
# ─────────────────────────────────────────────────────────────────────
print_stage "Stage 4: Installing helm (Kubernetes Package Manager)"

if command -v helm &>/dev/null; then
  print_ok "helm already installed: $(helm version --short)"
  print_info "Skipping re-installation."
else
  print_info "Installing helm via official installer script ..."
  # The official Helm installer script detects your OS and arch automatically.
  # It downloads the correct binary and installs it to /usr/local/bin/helm.
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  print_ok "helm installed."
fi

helm version --short &>/dev/null && print_ok "helm is operational." \
  || { echo "✗ helm installation failed."; exit 1; }

# ─────────────────────────────────────────────────────────────────────
# Stage 5.0: Install kubectx and kubens
# Purpose:   These two tools solve the most common mistake in Kubernetes:
#            running commands against the wrong cluster or namespace.
#
#   kubectx: switches between kubeconfig contexts (= clusters).
#            Without it: kubectl config use-context <long-name>
#            With it:    kubectx learning-cluster
#
#   kubens:  switches the default namespace for kubectl commands.
#            Without it: kubectl -n staging get pods
#            With it:    kubens staging && kubectl get pods
#
#   Enterprise: These are standard in every platform team's toolbox.
#               Accidents from wrong-context commands have caused production
#               outages. These tools make context always visible.
# ─────────────────────────────────────────────────────────────────────
print_stage "Stage 5: Installing kubectx + kubens (Context and Namespace Switching)"

if command -v kubectx &>/dev/null; then
  print_ok "kubectx already installed."
  print_info "Skipping re-installation."
else
  print_info "Cloning kubectx from GitHub to /usr/local/kubectx ..."
  # We clone the repo (not just a binary) because it contains both tools.
  sudo git clone https://github.com/ahmetb/kubectx /usr/local/kubectx --quiet

  # Create symbolic links in /usr/local/bin so both tools are on PATH
  sudo ln -sf /usr/local/kubectx/kubectx /usr/local/bin/kubectx
  sudo ln -sf /usr/local/kubectx/kubens  /usr/local/bin/kubens

  print_ok "kubectx and kubens installed."
fi

kubectx --version &>/dev/null && print_ok "kubectx is operational." \
  || print_warn "kubectx installed but version check failed — check PATH."

# ─────────────────────────────────────────────────────────────────────
# Stage 6.0: Install k9s
# Purpose:   k9s is a terminal-based Kubernetes cluster dashboard.
#            It provides a live, interactive view of all cluster resources:
#            nodes, pods, deployments, services, logs, events.
#
#            Without k9s: you run kubectl get pods -A -w repeatedly.
#            With k9s:    you see everything live in a structured TUI.
#
#   Enterprise: k9s is used by platform engineers for day-to-day debugging.
#               Alternatives include Lens (GUI), Rancher, OpenLens.
#               Many teams run k9s in a shared tmux session during incidents.
# ─────────────────────────────────────────────────────────────────────
print_stage "Stage 6: Installing k9s (Terminal Kubernetes Dashboard)"

if command -v k9s &>/dev/null; then
  print_ok "k9s already installed: $(k9s version --short 2>/dev/null | head -1)"
  print_info "Skipping re-installation."
else
  print_info "Installing k9s via webinstall.dev ..."
  # webinstall.dev is a vendor-neutral installer that detects your OS/arch
  # and installs the correct binary. It is used by many Kubernetes projects.
  curl -sS https://webinstall.dev/k9s | bash

  # webinstall.dev installs to ~/.local/bin — ensure it is on PATH
  export PATH="$HOME/.local/bin:$PATH"

  print_ok "k9s installed."
fi

# k9s may be in ~/.local/bin — add to PATH if needed
export PATH="$HOME/.local/bin:$PATH"
k9s version &>/dev/null && print_ok "k9s is operational." \
  || print_warn "k9s installed but not on PATH yet — will be available after PATH update."

# ─────────────────────────────────────────────────────────────────────
# Stage 7.0: Configure Shell Aliases and kubectl Completion
# Purpose:   Add kubectl auto-completion and the 'k' alias to ~/.bashrc.
#            This persists across terminal sessions.
#
#            Why 'k' for kubectl?
#            Industry standard alias. Every Kubernetes engineer uses it.
#            You will type `k get pods` hundreds of times per day.
#
#   Enterprise: Teams share a standard .bashrc / .zshrc snippet in their
#               onboarding docs so everyone's shell has the same aliases.
# ─────────────────────────────────────────────────────────────────────
print_stage "Stage 7: Configuring Shell Aliases and Kubectl Completion"

BASHRC="$HOME/.bashrc"

# Only add if not already present — idempotent
if ! grep -q "kubectl completion bash" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" << 'EOF'

# ─── Kubernetes Tools ──────────────────────────────────────────────────
# kubectl shell completion — enables Tab to auto-complete commands, flags, names
source <(kubectl completion bash)

# 'k' is the industry standard alias for kubectl.
# Usage: k get pods  instead of  kubectl get pods
alias k=kubectl

# Make Tab completion work with the 'k' alias too
complete -o default -F __start_kubectl k

# kubens completion
[ -f /usr/local/kubectx/completion/kubens.bash ] && \
  source /usr/local/kubectx/completion/kubens.bash

# kubectx completion
[ -f /usr/local/kubectx/completion/kubectx.bash ] && \
  source /usr/local/kubectx/completion/kubectx.bash

# Ensure k9s (installed by webinstall.dev) is on PATH
export PATH="$HOME/.local/bin:$PATH"
# ───────────────────────────────────────────────────────────────────────
EOF
  print_ok "kubectl aliases and completion added to ~/.bashrc."
else
  print_ok "kubectl aliases already in ~/.bashrc. No changes made."
fi

# Apply changes to the current session
# shellcheck source=/dev/null
source "$BASHRC" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────
# Stage 8.0: Final Verification
# Purpose:   Print a summary table of all installed tools and their versions.
#            If any tool is missing, the learner knows what to fix.
# ─────────────────────────────────────────────────────────────────────
print_stage "Stage 8: Final Verification — Tool Version Summary"

echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║            Kubernetes Developer Tools — Installed            ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check each tool and print its version or a failure marker
check_tool() {
  local name="$1"
  local cmd="$2"
  if output=$(eval "$cmd" 2>/dev/null | head -1); then
    printf "  %-12s ✓  %s\n" "${name}" "${output}"
  else
    printf "  %-12s ✗  NOT FOUND — rerun this script or install manually\n" "${name}"
  fi
}

check_tool "docker"   "docker version --format '{{.Client.Version}}' | head -1"
check_tool "kind"     "kind version"
check_tool "kubectl"  "kubectl version --client --short 2>/dev/null || kubectl version --client -o yaml | grep gitVersion | head -1"
check_tool "helm"     "helm version --short"
check_tool "kubectx"  "kubectx --version 2>/dev/null || echo 'installed (version flag not supported)'"
check_tool "kubens"   "kubens --version 2>/dev/null || echo 'installed (version flag not supported)'"
check_tool "k9s"      "k9s version --short 2>/dev/null | head -1"

echo ""
echo "  ─────────────────────────────────────────────────────────────"
echo "  Shell completion and 'k' alias have been added to ~/.bashrc."
echo "  Run: source ~/.bashrc  — to activate them in this session."
echo ""
echo "  ─────────────────────────────────────────────────────────────"
echo "  ✓ Installation complete."
echo "  → Next step: bash setup/00-prerequisites/check-prerequisites.sh"
echo "  → Then:      bash setup/01-cluster-setup/create-cluster.sh"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
