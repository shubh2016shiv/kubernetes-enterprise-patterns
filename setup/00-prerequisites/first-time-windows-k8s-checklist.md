# First-Time Windows Kubernetes Checklist

This file is the shortest possible “just tell me what to do” version for a first-time learner on Windows.

## Before You Type Anything

1. Open Docker Desktop on Windows.
2. Open Ubuntu in WSL2.
3. Go to the repository:

```bash
cd "/mnt/d/Generative AI Portfolio Projects/kubernetes_architure"
```

## Check What Is Missing

```bash
bash setup/00-prerequisites/check-prerequisites.sh
```

If `kind` is missing, install it before anything else.

## Install The Required Tool First

```bash
mkdir -p "$HOME/.local/bin" "$HOME/.local/share"
if ! grep -q 'HOME/.local/bin' "$HOME/.bashrc"; then
  printf '\n# Local CLI tools for Kubernetes learning\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc"
fi
export PATH="$HOME/.local/bin:$PATH"
[ "$(uname -m)" = "x86_64" ] && ARCH=amd64 || ARCH=arm64
curl -fsSL -o "$HOME/.local/bin/kind" "https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-${ARCH}"
chmod +x "$HOME/.local/bin/kind"
kind version
```

## Install The Recommended Tools

```bash
export HELM_INSTALL_DIR="$HOME/.local/bin"
export USE_SUDO=false
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

git clone https://github.com/ahmetb/kubectx "$HOME/.local/share/kubectx"
ln -sf "$HOME/.local/share/kubectx/kubectx" "$HOME/.local/bin/kubectx"
ln -sf "$HOME/.local/share/kubectx/kubens" "$HOME/.local/bin/kubens"

curl -fsSL https://webinstall.dev/k9s | bash
source ~/.bashrc
```

## Re-Check

```bash
bash setup/00-prerequisites/check-prerequisites.sh
```

## Start Kubernetes

```bash
bash setup/01-cluster-setup/create-cluster.sh
bash setup/01-cluster-setup/verify-cluster.sh
```

## If You Get Lost

Open:
- [README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/00-prerequisites/README.md)
- [install-guide.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/00-prerequisites/install-guide.md)
- [windows-wsl2/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/00-prerequisites/platform-guides/windows-wsl2/README.md)
