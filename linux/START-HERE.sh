#!/usr/bin/env bash
# K8s Local Deployment (kind + cloud-provider-kind) — Linux
# Auto-detects folder — works on any path (no editing required)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CPC_IMAGE="registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.11.1"
ENVOY_IMAGE="envoyproxy/envoy:v1.33.2"
NGINX_IMAGE="nginx:latest"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pause_menu() {
  echo
  read -r -p "Press Enter to return to menu..." _
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

arch_kind() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "amd64" ;;
  esac
}

install_bin() {
  local src="$1" dest="$2"
  chmod +x "$src"
  if [[ -w "$(dirname "$dest")" ]]; then
    mv "$src" "$dest"
  else
    echo "Need sudo to install to $dest"
    sudo mv "$src" "$dest"
  fi
}

# ---------------------------------------------------------------------------
# Image / cleanup helpers
# ---------------------------------------------------------------------------

pull_images() {
  echo "Pulling kindest/node (via kind)..."
  if ! kind pull node-image; then
    echo "[WARN] kind pull node-image failed — cluster create will retry download."
  fi
  echo "Pulling ${CPC_IMAGE}..."
  docker pull "${CPC_IMAGE}" || { echo "[ERROR] Failed to pull cloud-provider-kind."; return 1; }
  echo "Pulling ${ENVOY_IMAGE}..."
  docker pull "${ENVOY_IMAGE}" || { echo "[ERROR] Failed to pull envoy."; return 1; }
  echo "[OK] All required images pulled."
}

pull_nginx() {
  docker image inspect "${NGINX_IMAGE}" >/dev/null 2>&1 && return 0
  echo "Pulling ${NGINX_IMAGE}..."
  docker pull "${NGINX_IMAGE}"
}

stop_all_containers() {
  (cd "$SCRIPT_DIR" && docker compose down >/dev/null 2>&1) || true
  docker rm -f cloud-provider-kind >/dev/null 2>&1 || true
  local ids
  ids="$(docker ps -a --filter "name=kindccm" -q 2>/dev/null || true)"
  [[ -n "$ids" ]] && docker rm -f $ids >/dev/null 2>&1 || true
}

delete_all_k8s_apps() {
  if ! kubectl get nodes >/dev/null 2>&1; then
    echo "  No cluster reachable — skipping kubectl cleanup."
    return 0
  fi
  echo "  Deleting user deployments and services..."
  local skip="kube-system local-path-storage kube-public kube-node-lease" ns
  for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    if [[ " $skip " != *" $ns "* ]]; then
      echo "    namespace: $ns"
      kubectl delete deployment,svc,ingress --all -n "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    fi
  done
}

delete_kubectl_context() {
  kubectl config delete-context "kind-$1" >/dev/null 2>&1 || true
  kubectl config delete-cluster "kind-$1" >/dev/null 2>&1 || true
}

remove_all_images() {
  echo "  Removing kindest/node..."
  docker images kindest/node -q 2>/dev/null | xargs -r docker rmi -f >/dev/null 2>&1 || true
  echo "  Removing cloud-provider-kind..."
  docker rmi -f "${CPC_IMAGE}" >/dev/null 2>&1 || true
  docker images registry.k8s.io/cloud-provider-kind/cloud-controller-manager -q 2>/dev/null | xargs -r docker rmi -f >/dev/null 2>&1 || true
  echo "  Removing envoyproxy/envoy..."
  docker rmi -f "${ENVOY_IMAGE}" >/dev/null 2>&1 || true
  docker images envoyproxy/envoy -q 2>/dev/null | xargs -r docker rmi -f >/dev/null 2>&1 || true
  echo "  Removing nginx..."
  docker rmi -f "${NGINX_IMAGE}" >/dev/null 2>&1 || true
  docker images nginx -q 2>/dev/null | xargs -r docker rmi -f >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Installers (used by menu [1])
# ---------------------------------------------------------------------------

install_docker_engine() {
  echo "Installing Docker Engine (get.docker.com)..."
  need_cmd curl || { echo "[ERROR] curl required."; return 1; }
  curl -fsSL https://get.docker.com | sudo sh
  sudo systemctl enable --now docker
  sudo usermod -aG docker "$USER" 2>/dev/null || true
  echo "[INFO] Added $USER to docker group — log out/in or run: newgrp docker"
}

install_compose_plugin() {
  echo "Installing Docker Compose plugin..."
  if need_cmd apt-get; then
    sudo apt-get update -y
    sudo apt-get install -y docker-compose-plugin
  elif need_cmd dnf; then
    sudo dnf install -y docker-compose-plugin
  elif need_cmd yum; then
    sudo yum install -y docker-compose-plugin
  else
    echo "[ERROR] Cannot auto-install compose plugin on this distro."
    echo "        Install package: docker-compose-plugin"
    return 1
  fi
  docker compose version
}

install_kind_binary() {
  local ver="v0.29.0" arch url tmp
  arch="$(arch_kind)"
  url="https://kind.sigs.k8s.io/dl/${ver}/kind-linux-${arch}"
  tmp="$(mktemp)"
  echo "Downloading kind ${ver} (${arch})..."
  curl -fsSL -o "$tmp" "$url" || { rm -f "$tmp"; echo "[ERROR] kind download failed."; return 1; }
  install_bin "$tmp" /usr/local/bin/kind
  kind version
}

install_kubectl_binary() {
  local ver arch url tmp
  arch="$(arch_kind)"
  ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  url="https://dl.k8s.io/release/${ver}/bin/linux/${arch}/kubectl"
  tmp="$(mktemp)"
  echo "Downloading kubectl ${ver} (${arch})..."
  curl -fsSL -o "$tmp" "$url" || { rm -f "$tmp"; echo "[ERROR] kubectl download failed."; return 1; }
  install_bin "$tmp" /usr/local/bin/kubectl
  kubectl version --client
}

# ---------------------------------------------------------------------------
# [1] Prerequisites — check, then install if missing
# ---------------------------------------------------------------------------

menu_prereq() {
  clear
  echo "============================================================"
  echo "  [1] CHECK & INSTALL PREREQUISITES"
  echo "============================================================"
  echo "  Checks system resources and tools."
  echo "  Missing tools are offered for install automatically."
  echo

  local OK=1

  # --- resources ---
  echo "---------- SYSTEM RESOURCES ----------"
  echo
  echo "[1/8] Linux architecture"
  echo "  OS: $(uname -s) $(uname -r) ($(uname -m))"
  case "$(uname -m)" in
    x86_64|amd64|aarch64|arm64) echo "[OK] Supported." ;;
    *) echo "[FAIL] Unsupported architecture."; OK=0 ;;
  esac
  echo

  echo "[2/8] Virtualization (optional for kind)"
  if grep -Eq 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
    echo "[OK] CPU virtualization flags present."
  else
    echo "[WARN] No vmx/svm — often fine for kind on cloud/nested VMs."
  fi
  [[ -e /dev/kvm ]] && echo "[OK] /dev/kvm present." || echo "[INFO] /dev/kvm not found (OK for kind)."
  echo

  echo "[3/8] Disk space (15 GB free minimum)"
  local free_gb
  free_gb="$(df -BG --output=avail "$SCRIPT_DIR" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)"
  echo "  Free: ${free_gb} GB"
  if [[ "${free_gb}" -ge 15 ]]; then
    echo "[OK] Enough disk."
  else
    echo "[WARN] Less than 15 GB free."
    OK=0
  fi
  echo

  echo "[4/8] RAM (8 GB minimum, 16 GB recommended)"
  local ram_gb
  ram_gb="$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)"
  echo "  Total: ${ram_gb} GB"
  if [[ "${ram_gb}" -ge 8 ]]; then
    echo "[OK] RAM OK."
  else
    echo "[FAIL] Less than 8 GB RAM."
    OK=0
  fi
  echo

  # --- tools ---
  echo "---------- REQUIRED TOOLS ----------"
  echo

  echo "[5/8] Docker Engine"
  if ! need_cmd docker; then
    echo "[MISSING] Docker not found."
    read -r -p "  Install Docker Engine now? [Y/n]: " ans
    if [[ ! "${ans:-Y}" =~ ^[Nn]$ ]]; then
      install_docker_engine || OK=0
    else
      OK=0
    fi
  fi
  if need_cmd docker; then
    if docker info >/dev/null 2>&1; then
      echo "[OK] Docker installed and running."
      docker version --format '  Client {{.Client.Version}} / Server {{.Server.Version}}' 2>/dev/null || true
    else
      echo "[WARN] Docker CLI found but daemon not running."
      echo "       Try: sudo systemctl start docker"
      echo "       Or:  newgrp docker   (after docker group change)"
      OK=0
    fi
  else
    OK=0
  fi
  echo

  echo "[6/8] Docker Compose"
  if need_cmd docker && docker compose version >/dev/null 2>&1; then
    echo "[OK] docker compose available."
    docker compose version 2>/dev/null | head -n 1 || true
  elif need_cmd docker-compose; then
    echo "[OK] docker-compose (legacy) found."
  else
    echo "[MISSING] Docker Compose not found."
    read -r -p "  Install docker-compose-plugin now? [Y/n]: " ans
    if [[ ! "${ans:-Y}" =~ ^[Nn]$ ]]; then
      install_compose_plugin || OK=0
    else
      OK=0
    fi
    if need_cmd docker && docker compose version >/dev/null 2>&1; then
      echo "[OK] docker compose installed."
    elif ! need_cmd docker-compose; then
      OK=0
    fi
  fi
  echo

  echo "[7/8] kind CLI"
  if ! need_cmd kind; then
    echo "[MISSING] kind not found."
    read -r -p "  Install kind to /usr/local/bin now? [Y/n]: " ans
    if [[ ! "${ans:-Y}" =~ ^[Nn]$ ]]; then
      install_kind_binary || OK=0
    else
      OK=0
    fi
  fi
  if need_cmd kind; then
    echo "[OK] kind installed."
    kind version 2>/dev/null || true
  else
    OK=0
  fi
  echo

  echo "[8/8] kubectl"
  if ! need_cmd kubectl; then
    echo "[MISSING] kubectl not found."
    read -r -p "  Install kubectl to /usr/local/bin now? [Y/n]: " ans
    if [[ ! "${ans:-Y}" =~ ^[Nn]$ ]]; then
      install_kubectl_binary || OK=0
    else
      OK=0
    fi
  fi
  if need_cmd kubectl; then
    echo "[OK] kubectl installed."
    kubectl version --client 2>/dev/null | head -n 1 || true
  else
    OK=0
  fi
  echo

  echo "============================================================"
  echo "  SUMMARY"
  echo "============================================================"
  if [[ "$OK" -eq 1 ]]; then
    echo "[OK] All prerequisites ready."
    echo "     Next: menu [2] Create cluster + cloud-provider-kind"
  else
    echo "[ACTION NEEDED] Fix items above, then run [1] again."
    echo "  - Docker must be running before [2]"
    echo "  - After docker group change: log out/in or newgrp docker"
  fi
  echo
  read -r -p "Continue to [2] Create cluster now? [y/N]: " go
  if [[ "${go:-N}" =~ ^[Yy]$ ]]; then
    menu_install
  else
    pause_menu
  fi
}

# ---------------------------------------------------------------------------
# [2] Create cluster
# ---------------------------------------------------------------------------

menu_install() {
  clear
  echo "============================================================"
  echo "  [2] CREATE CLUSTER + CLOUD-PROVIDER-KIND"
  echo "============================================================"
  echo

  if ! need_cmd docker || ! docker info >/dev/null 2>&1; then
    echo "[ERROR] Docker not running. Run menu [1] first."
    pause_menu; return
  fi
  if ! need_cmd kind; then
    echo "[ERROR] kind missing. Run menu [1] first."
    pause_menu; return
  fi
  if ! need_cmd kubectl; then
    echo "[ERROR] kubectl missing. Run menu [1] first."
    pause_menu; return
  fi
  if ! docker compose version >/dev/null 2>&1 && ! need_cmd docker-compose; then
    echo "[ERROR] docker compose missing. Run menu [1] first."
    pause_menu; return
  fi
  echo "[OK] Docker, Compose, kind, kubectl ready."
  echo

  local CLUSTER_NAME WORKERS
  echo "Cluster settings"
  echo "  0 workers = 1 node (recommended for laptops)"
  echo "  1 worker  = 2 nodes total"
  echo
  read -r -p "Cluster name [default: local]: " CLUSTER_NAME
  CLUSTER_NAME="${CLUSTER_NAME:-local}"
  read -r -p "Worker nodes [default: 0]: " WORKERS
  WORKERS="${WORKERS:-0}"
  echo
  echo "  → ${CLUSTER_NAME}  (1 control-plane + ${WORKERS} worker(s))"
  echo

  if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    echo "[WARNING] Cluster \"${CLUSTER_NAME}\" already exists."
    read -r -p "Delete and recreate? [y/N]: " recreate
    if [[ "${recreate:-N}" =~ ^[Yy]$ ]]; then
      kind delete cluster --name "${CLUSTER_NAME}"
      sleep 3
    else
      echo "Keeping existing cluster."
      start_cpc_and_demo "${CLUSTER_NAME}"
      return
    fi
  fi

  echo "Generating kind-config.yaml..."
  {
    echo "kind: Cluster"
    echo "apiVersion: kind.x-k8s.io/v1alpha4"
    echo "name: ${CLUSTER_NAME}"
    echo "nodes:"
    echo "  - role: control-plane"
    local i
    for ((i = 1; i <= WORKERS; i++)); do
      echo "  - role: worker"
    done
  } > "${SCRIPT_DIR}/kind-config.yaml"
  cat "${SCRIPT_DIR}/kind-config.yaml"
  echo

  read -r -p "Pull required images now? [Y/n]: " pull
  if [[ ! "${pull:-Y}" =~ ^[Nn]$ ]]; then
    pull_images || { pause_menu; return; }
  fi
  echo

  read -r -p "Create kind cluster now? [Y/n]: " confirm
  if [[ "${confirm:-Y}" =~ ^[Nn]$ ]]; then
    pause_menu; return
  fi

  if ! kind create cluster --config "${SCRIPT_DIR}/kind-config.yaml"; then
    echo "[ERROR] Cluster creation failed."
    pause_menu; return
  fi
  echo "[OK] Cluster created."

  start_cpc_and_demo "${CLUSTER_NAME}"
}

start_cpc_and_demo() {
  local CLUSTER_NAME="${1:-local}"

  echo
  read -r -p "Start cloud-provider-kind (LoadBalancer)? [Y/n]: " start_cpc
  if [[ ! "${start_cpc:-Y}" =~ ^[Nn]$ ]]; then
    docker rm -f cloud-provider-kind >/dev/null 2>&1 || true
    if ! (cd "$SCRIPT_DIR" && docker compose up -d); then
      echo "[ERROR] docker compose failed."
      pause_menu; return
    fi
    echo "[OK] cloud-provider-kind started."
    sleep 5
  fi

  echo
  read -r -p "Deploy test nginx LoadBalancer? [Y/n]: " deploy
  if [[ ! "${deploy:-Y}" =~ ^[Nn]$ ]]; then
    pull_nginx
    kubectl create deployment test-nginx --image="${NGINX_IMAGE}" 2>/dev/null || true
    kubectl expose deployment test-nginx --port=80 --type=LoadBalancer 2>/dev/null || true
    echo "Waiting 30s for LoadBalancer..."
    sleep 30
    kubectl get svc test-nginx 2>/dev/null || true
    docker ps --filter "name=kindccm" --format "table {{.Names}}\t{{.Ports}}"
  fi

  echo
  echo "============================================================"
  echo "  INSTALL COMPLETE"
  echo "============================================================"
  echo "  Context: kind-${CLUSTER_NAME}"
  echo "  Demo URL: http://127.0.0.1"
  echo "  After reboot: menu [3] Start services"
  echo
  pause_menu
}

# ---------------------------------------------------------------------------
# [3] Start services
# ---------------------------------------------------------------------------

menu_start() {
  clear
  echo "============================================================"
  echo "  [3] START SERVICES (after reboot)"
  echo "============================================================"
  echo

  if ! docker info >/dev/null 2>&1; then
    echo "[ERROR] Docker not running. Try: sudo systemctl start docker"
    pause_menu; return
  fi

  local CLUSTER
  read -r -p "Cluster name [default: local]: " CLUSTER
  CLUSTER="${CLUSTER:-local}"

  local NODE
  NODE="$(docker ps -a --filter "name=${CLUSTER}-control-plane" --format '{{.Names}}' 2>/dev/null | head -n 1 || true)"
  if [[ -n "$NODE" ]]; then
    docker start "$NODE" >/dev/null 2>&1 || true
    echo "[OK] Started: $NODE"
    sleep 10
  else
    echo "[WARNING] No ${CLUSTER}-control-plane found. Run [2] first."
  fi

  docker rm -f cloud-provider-kind >/dev/null 2>&1 || true
  if ! (cd "$SCRIPT_DIR" && docker compose up -d); then
    echo "[ERROR] docker compose failed."
    pause_menu; return
  fi

  echo "[OK] Services started."
  kubectl get nodes --context "kind-${CLUSTER}" 2>/dev/null || true
  kubectl get svc -A 2>/dev/null || true
  echo
  pause_menu
}

# ---------------------------------------------------------------------------
# [4] Deploy demo
# ---------------------------------------------------------------------------

menu_deploy() {
  clear
  echo "============================================================"
  echo "  [4] DEPLOY LOADBALANCER DEMO (nginx)"
  echo "============================================================"
  echo

  if ! kubectl get nodes >/dev/null 2>&1; then
    echo "[ERROR] Cluster not reachable. Run [2] or [3] first."
    pause_menu; return
  fi

  local APP_NAME
  read -r -p "App name [default: test-nginx]: " APP_NAME
  APP_NAME="${APP_NAME:-test-nginx}"

  pull_nginx
  kubectl create deployment "${APP_NAME}" --image="${NGINX_IMAGE}" 2>/dev/null || true
  kubectl expose deployment "${APP_NAME}" --port=80 --type=LoadBalancer 2>/dev/null || true
  echo "Waiting 30s..."
  sleep 30

  kubectl get svc "${APP_NAME}"
  docker ps --filter "name=kindccm" --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"
  echo
  echo "Browser: http://127.0.0.1  (check PORTS column above)"
  echo
  pause_menu
}

# ---------------------------------------------------------------------------
# [5] Status
# ---------------------------------------------------------------------------

menu_status() {
  clear
  echo "============================================================"
  echo "  [5] STATUS"
  echo "============================================================"
  echo
  echo "--- kind clusters ---"
  kind get clusters 2>/dev/null || true
  echo
  echo "--- nodes ---"
  kubectl get nodes 2>/dev/null || true
  echo
  echo "--- services ---"
  kubectl get svc -A 2>/dev/null || true
  echo
  echo "--- containers ---"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | grep -Ei "control-plane|cloud-provider|kindccm|NAMES" || true
  echo
  echo "--- images ---"
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null | grep -Ei "kindest|cloud-provider|envoy|NAMES" || true
  echo
  echo "--- disk ---"
  docker system df 2>/dev/null || true
  echo
  pause_menu
}

# ---------------------------------------------------------------------------
# [6] Stop CPC
# ---------------------------------------------------------------------------

menu_stop() {
  clear
  echo "============================================================"
  echo "  [6] STOP cloud-provider-kind"
  echo "============================================================"
  echo "  kind cluster keeps running."
  echo
  (cd "$SCRIPT_DIR" && docker compose down) || true
  echo "[OK] Stopped. Run [3] to start again."
  echo
  pause_menu
}

# ---------------------------------------------------------------------------
# [7] Remove cluster
# ---------------------------------------------------------------------------

menu_delete() {
  clear
  echo "============================================================"
  echo "  [7] REMOVE CLUSTER (keep images)"
  echo "============================================================"
  echo "  Removes kind cluster + cloud-provider-kind + apps."
  echo "  Keeps Docker images for fast reinstall via [2]."
  echo

  local CLUSTER
  read -r -p "Cluster name [default: local]: " CLUSTER
  CLUSTER="${CLUSTER:-local}"

  read -r -p "Remove cluster \"${CLUSTER}\"? [y/N]: " confirm
  if [[ ! "${confirm:-N}" =~ ^[Yy]$ ]]; then
    return
  fi

  delete_all_k8s_apps
  stop_all_containers
  kind delete cluster --name "${CLUSTER}" 2>/dev/null || true
  delete_kubectl_context "${CLUSTER}"

  echo "[OK] Cluster removed. Images kept. Run [2] to install again."
  echo
  pause_menu
}

# ---------------------------------------------------------------------------
# [8] Full remove
# ---------------------------------------------------------------------------

menu_full_remove() {
  clear
  echo "============================================================"
  echo "  [8] REMOVE EVERYTHING (+ images)"
  echo "============================================================"
  echo "  Deletes clusters, containers, and project images."
  echo "  *** CANNOT BE UNDONE ***"
  echo

  read -r -p "Type YES to continue: " confirm1
  [[ "${confirm1}" == "YES" ]] || return

  echo
  echo "[1/9] Delete apps..."
  delete_all_k8s_apps
  echo "[2/9] Stop containers..."
  stop_all_containers
  echo "[3/9] Delete kind clusters..."
  local c
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    echo "  Deleting: $c"
    kind delete cluster --name "$c" 2>/dev/null || true
  done < <(kind get clusters 2>/dev/null || true)
  echo "[4/9] Remove leftover node containers..."
  docker ps -a --filter "name=control-plane" -q 2>/dev/null | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker ps -a --filter "name=worker" -q 2>/dev/null | xargs -r docker rm -f >/dev/null 2>&1 || true
  echo "[5/9] Remove kubectl kind contexts..."
  local ctx cl
  while IFS= read -r ctx; do
    [[ -z "$ctx" ]] && continue
    kubectl config delete-context "$ctx" >/dev/null 2>&1 || true
  done < <(kubectl config get-contexts -o name 2>/dev/null | grep -i 'kind-' || true)
  while IFS= read -r cl; do
    [[ -z "$cl" ]] && continue
    kubectl config delete-cluster "$cl" >/dev/null 2>&1 || true
  done < <(kubectl config get-clusters 2>/dev/null | grep -i 'kind-' || true)
  echo "[6/9] Remove images..."
  remove_all_images
  echo "[7/9] Remove kind-config.yaml..."
  rm -f "${SCRIPT_DIR}/kind-config.yaml"
  echo "[8/9] Remove kind network..."
  docker network rm kind >/dev/null 2>&1 || true
  echo "[9/9] Docker prune..."
  docker system prune -f >/dev/null 2>&1 || true

  echo
  echo "[OK] Full removal complete."
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null | grep -Ei "kindest|cloud-provider|envoyproxy|nginx|NAMES" || true
  echo
  pause_menu
}

# ---------------------------------------------------------------------------
# [H] Help
# ---------------------------------------------------------------------------

menu_help() {
  clear
  echo "============================================================"
  echo "  HELP"
  echo "============================================================"
  echo
  echo "Recommended first-time flow:"
  echo "  [1] Check & install prerequisites"
  echo "      → Docker, Docker Compose, kind, kubectl"
  echo "  [2] Create cluster + cloud-provider-kind"
  echo "  Open browser: http://127.0.0.1"
  echo
  echo "After reboot:"
  echo "  sudo systemctl start docker"
  echo "  ./START-HERE.sh → [3]"
  echo
  echo "LoadBalancer:"
  echo "  cloud-provider-kind assigns EXTERNAL-IP"
  echo "  kindccm (Envoy) proxies to localhost"
  echo
  echo "Docs:"
  echo "  ${SCRIPT_DIR}/README.md"
  echo "  ${SCRIPT_DIR}/GUIDE.txt"
  echo "  ${SCRIPT_DIR}/example/"
  echo
  pause_menu
}

open_readme() {
  if need_cmd xdg-open; then
    xdg-open "${SCRIPT_DIR}/README.md" >/dev/null 2>&1 || true
  elif need_cmd less; then
    less "${SCRIPT_DIR}/README.md"
  else
    cat "${SCRIPT_DIR}/README.md"
  fi
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------

main_menu() {
  while true; do
    clear
    echo "============================================================"
    echo "  K8s Local Deployment"
    echo "  kind + cloud-provider-kind + LoadBalancer  |  Linux"
    echo "============================================================"
    echo "  Folder: ${SCRIPT_DIR}"
    echo "============================================================"
    echo
    echo "  FIRST TIME / SETUP"
    echo "  [1] Check & install prerequisites"
    echo "      Docker, Docker Compose, kind, kubectl"
    echo "  [2] Create cluster + cloud-provider-kind"
    echo "  [3] Start services (after reboot)"
    echo "  [4] Deploy LoadBalancer demo (nginx)"
    echo
    echo "  DAILY USE"
    echo "  [5] Show status"
    echo "  [6] Stop cloud-provider-kind"
    echo
    echo "  REMOVE"
    echo "  [7] Remove cluster (keep images)"
    echo "  [8] Remove everything (+ images)"
    echo
    echo "  [H] Help    [R] README    [Q] Quit"
    echo
    local CHOICE
    read -r -p "Enter choice: " CHOICE
    case "${CHOICE}" in
      1) menu_prereq ;;
      2) menu_install ;;
      3) menu_start ;;
      4) menu_deploy ;;
      5) menu_status ;;
      6) menu_stop ;;
      7) menu_delete ;;
      8) menu_full_remove ;;
      H|h) menu_help ;;
      R|r) open_readme ;;
      Q|q) exit 0 ;;
      *)
        echo "Invalid choice."
        pause_menu
        ;;
    esac
  done
}

main_menu
