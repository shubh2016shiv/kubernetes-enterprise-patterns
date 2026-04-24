#!/usr/bin/env bash
# =============================================================================
# FILE: 00-prerequisites/check-prerequisites.sh
# PURPOSE: Validate that every tool required to run an enterprise Kubernetes
#          workflow is installed and at an acceptable version.
#
# ENTERPRISE CONTEXT:
#   In a real company, this script (or a CI job equivalent) would be run by
#   every new engineer on day-1 onboarding. It ensures everyone on the team
#   is using compatible tooling, preventing "works on my machine" issues.
#
# HOW TO RUN:
#   bash 00-prerequisites/check-prerequisites.sh
#
# SHELL: bash (WSL2 / Git Bash / macOS Terminal / Linux)
# =============================================================================

# ─── SHELL SAFETY FLAGS ───────────────────────────────────────────────────────
# These three options are standard in all professional shell scripts.
# Skipping them causes scripts to silently succeed even when they fail.
set -e   # Exit immediately if any command returns a non-zero (failure) status
set -u   # Treat unset variables as an error — no accidental empty strings
set -o pipefail  # If any command in a pipeline fails, the whole pipeline fails
#                # Without this: `false | true` would succeed (misleading!)

# ─── COLOR CODES ──────────────────────────────────────────────────────────────
# ANSI escape codes for colored terminal output.
# These are universally supported in Linux, macOS, and WSL2 terminals.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'   # Resets all formatting back to default

# ─── HELPER FUNCTIONS ─────────────────────────────────────────────────────────

# print_header: Visual separator to make script output easy to scan
print_header() {
  echo ""
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${RESET}"
  echo -e "${CYAN}${BOLD}  $1${RESET}"
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${RESET}"
}

# check_tool: The core validation function.
#   $1 = tool name (e.g., "kubectl")
#   $2 = command to get version string (e.g., "kubectl version --client --short")
#   $3 = minimum acceptable version substring (e.g., "1.28" or "0.21")
#   $4 = requirement level: "required" or "optional"
#
# How it works:
#   1. Checks if the tool binary exists in PATH using `command -v`
#   2. Runs the version command and captures output
#   3. Checks if the minimum version string appears in the output
#   4. Prints PASS / WARN / FAIL accordingly and increments the correct counter
check_tool() {
  local tool_name="$1"         # Human-readable name
  local version_command="$2"   # Shell command to get version
  local min_version="$3"       # Version substring we require to exist
  local requirement_level="${4:-required}"  # Default to required for safety

  printf "  Checking %-20s " "${tool_name}..."

  # `command -v` returns the path to the binary, or fails if not found.
  # It's POSIX-compliant and more reliable than `which` across all shells.
  if ! command -v "$(echo "$version_command" | awk '{print $1}')" &>/dev/null; then
    if [[ "${requirement_level}" == "optional" ]]; then
      echo -e "${YELLOW}⚠ NOT FOUND (OPTIONAL)${RESET}"
      echo -e "    ${YELLOW}→ Nice to have for daily workflow, but not required to start${RESET}"
      WARN_COUNT=$((WARN_COUNT + 1))
    else
      echo -e "${RED}✗ NOT FOUND${RESET}"
      echo -e "    ${YELLOW}→ See install-guide.md for installation steps${RESET}"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    return
  fi

  # Run the version command, capturing both stdout and stderr.
  # Some tools (e.g., kubectl) print to stderr, some to stdout.
  local version_output
  version_output=$(eval "$version_command" 2>&1)

  # Check if the minimum version string exists anywhere in the output.
  # Using grep with -q for quiet mode (no output, just exit code).
  if echo "$version_output" | grep -q "${min_version}"; then
    echo -e "${GREEN}✓ OK${RESET}  ($version_output)"
  else
    echo -e "${YELLOW}⚠ VERSION MISMATCH${RESET}"
    echo -e "    Found:    ${version_output}"
    echo -e "    Required: ${min_version}+"
    echo -e "    ${YELLOW}→ Upgrade recommended but not blocking${RESET}"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
}

# check_docker_running: Specifically validates that Docker daemon is accessible.
# This is separate from checking if Docker is installed, because Docker
# Desktop on Windows requires the app to be OPEN before the daemon accepts
# connections. In enterprise, this would be the Docker daemon on a Linux host.
check_docker_running() {
  printf "  Checking %-20s " "Docker daemon..."
  if docker info &>/dev/null; then
    local docker_version
    docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    echo -e "${GREEN}✓ RUNNING${RESET}  (Docker Engine ${docker_version})"
  else
    echo -e "${RED}✗ NOT RUNNING${RESET}"
    echo -e "    ${YELLOW}→ Open Docker Desktop application first${RESET}"
    echo -e "    ${YELLOW}→ On WSL2: Docker Desktop must be started on Windows side${RESET}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# check_wsl2: On Windows, WSL2 is the recommended environment for enterprise-
# grade K8s work. This check detects if we're inside WSL2 vs Git Bash.
check_wsl2() {
  print_header "Environment Detection"
  if grep -q "microsoft" /proc/version 2>/dev/null; then
    echo -e "  ${GREEN}✓ Running inside WSL2 (recommended)${RESET}"
    # WSL2 version is visible in the kernel string
    local kernel
    kernel=$(uname -r)
    echo -e "    Kernel: ${kernel}"
    echo -e "    ${CYAN}→ Docker Desktop + WSL2 integration = enterprise-grade setup${RESET}"
  elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    echo -e "  ${YELLOW}⚠ Running in Git Bash (functional but not preferred)${RESET}"
    echo -e "    ${YELLOW}→ For full enterprise parity, switch to WSL2${RESET}"
    echo -e "    ${YELLOW}→ Scripts will still work, but path handling differs${RESET}"
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo -e "  ${GREEN}✓ Running on native Linux${RESET}"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "  ${GREEN}✓ Running on macOS${RESET}"
  fi
}

# ─── MAIN SCRIPT ──────────────────────────────────────────────────────────────

# Initialize counters for summary at the end
FAIL_COUNT=0
WARN_COUNT=0

echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║     Kubernetes Enterprise Environment Pre-Check       ║${RESET}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════╝${RESET}"

# ─── STEP 1: Detect Environment ───────────────────────────────────────────────
check_wsl2

# ─── STEP 2: Docker ───────────────────────────────────────────────────────────
# Docker must be installed AND running before anything else can work.
# kind runs Kubernetes nodes as Docker containers, so Docker is foundational.
print_header "Core: Docker"
check_tool "Docker CLI" "docker --version" "20." "required"
check_docker_running

# ─── STEP 3: kind ─────────────────────────────────────────────────────────────
# kind = Kubernetes IN Docker. This is how we create local clusters.
# Each cluster "node" is actually a Docker container running a full K8s node.
#
# ENTERPRISE NOTE: kind is used in:
#   - GitHub Actions CI/CD for K8s integration tests
#   - Local development environments at Google, Stripe, and others
#   - CKA/CKAD exam simulators
print_header "Cluster Tool: kind"
check_tool "kind" "kind version" "0.23" "required"

# ─── STEP 4: kubectl ──────────────────────────────────────────────────────────
# kubectl (Kubernetes Control) is THE command-line interface for EVERY
# Kubernetes cluster in existence — local, AWS EKS, GKE, AKS, bare-metal.
# You will type kubectl hundreds of times per day as a K8s engineer.
#
# VERSION SKEW RULE (important for interviews!):
#   kubectl can be at most 1 minor version away from the cluster API server.
#   If cluster runs 1.30, your kubectl must be 1.29, 1.30, or 1.31.
#   Going beyond ±1 minor version = unsupported and may cause subtle bugs.
print_header "Primary CLI: kubectl"
check_tool "kubectl" "kubectl version --client --short 2>/dev/null || kubectl version --client" "1.30" "required"

# ─── STEP 5: Optional but Highly Recommended Tools ────────────────────────────
# These tools are standard in enterprise Kubernetes workflows.
# They are not required for this curriculum but mentioned for awareness.
print_header "Enterprise Productivity Tools (Optional)"

# kubectx / kubens: Switch between clusters and namespaces instantly
# ENTERPRISE USE: When you manage prod, staging, and dev clusters
check_tool "kubectx" "kubectx --version 2>/dev/null || echo 'not installed'" "." "optional"

# k9s: A terminal UI for Kubernetes. Think "top" but for your entire cluster.
# ENTERPRISE USE: Real-time monitoring, log streaming, exec into pods
check_tool "k9s" "k9s version --short 2>/dev/null || echo 'not installed'" "." "optional"

# helm: The Kubernetes package manager.
# ENTERPRISE USE: Deploying databases, monitoring stacks, ingress controllers
check_tool "helm" "helm version --short 2>/dev/null || echo 'not installed'" "." "optional"

# ─── STEP 6: System Resources ─────────────────────────────────────────────────
# kind nodes (Docker containers) need RAM. A 3-node cluster needs ~2-3 GB.
# Your machine has 16 GB, which is plenty for a realistic enterprise simulation.
print_header "System Resources"

# Get total RAM
if [[ -f /proc/meminfo ]]; then
  # Linux/WSL2 path — /proc/meminfo gives us exact numbers
  TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  TOTAL_GB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_KB / 1048576}")
  AVAIL_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
  AVAIL_GB=$(awk "BEGIN {printf \"%.1f\", $AVAIL_KB / 1048576}")
  echo -e "  Total RAM: ${TOTAL_GB} GB"
  echo -e "  Available: ${AVAIL_GB} GB"

  # We need at least 4 GB free for a 3-node kind cluster
  if (( AVAIL_KB > 4194304 )); then
    echo -e "  ${GREEN}✓ Sufficient memory for 3-node cluster${RESET}"
  else
    echo -e "  ${YELLOW}⚠ Low available memory. Consider closing other applications.${RESET}"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
elif command -v sysctl &>/dev/null; then
  # macOS path
  TOTAL_BYTES=$(sysctl -n hw.memsize)
  TOTAL_GB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_BYTES / 1073741824}")
  echo -e "  Total RAM: ${TOTAL_GB} GB"
fi

# ─── STEP 7: kubeconfig directory ─────────────────────────────────────────────
# ~/.kube/config is where kubectl stores credentials for all clusters.
# In enterprise, this is managed by your cloud provider CLI (aws, gcloud, az)
# or by your identity platform (Vault, Teleport, etc.)
print_header "kubeconfig Location"
KUBECONFIG_PATH="${HOME}/.kube/config"
if [[ -f "$KUBECONFIG_PATH" ]]; then
  echo -e "  ${GREEN}✓ Found: ${KUBECONFIG_PATH}${RESET}"
  # List available contexts (each context = cluster + user + namespace)
  CONTEXT_COUNT=$(kubectl config get-contexts --no-headers 2>/dev/null | wc -l)
  echo -e "  Configured contexts: ${CONTEXT_COUNT}"
else
  echo -e "  ${YELLOW}⚠ No kubeconfig found yet (expected if no cluster created)${RESET}"
  echo -e "    → kind will create it automatically when you create a cluster"
fi

# ─── SUMMARY ──────────────────────────────────────────────────────────────────
print_header "Summary"
if [[ $FAIL_COUNT -eq 0 ]] && [[ $WARN_COUNT -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✓ ALL CHECKS PASSED — Environment is ready!${RESET}"
  echo -e "  ${CYAN}→ Next step: bash 01-cluster-setup/create-cluster.sh${RESET}"
elif [[ $FAIL_COUNT -eq 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}⚠ WARNINGS: ${WARN_COUNT} (non-blocking)${RESET}"
  echo -e "  ${CYAN}→ You can proceed, but review warnings above${RESET}"
else
  echo -e "  ${RED}${BOLD}✗ FAILURES: ${FAIL_COUNT} — Fix these before proceeding${RESET}"
  echo -e "  ${YELLOW}→ See 00-prerequisites/install-guide.md for help${RESET}"
  # Exit with a non-zero status so CI/CD pipelines catch this failure
  exit 1
fi
echo ""
