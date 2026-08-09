@echo off
setlocal EnableDelayedExpansion
title K8s Local Deployment (kind + cloud-provider-kind)

REM Auto-detect folder — works on any PC, any path (no editing required)
set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

REM Pinned Docker images
set "CPC_IMAGE=registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.11.1"
set "ENVOY_IMAGE=envoyproxy/envoy:v1.33.2"
set "NGINX_IMAGE=nginx:latest"

:MENU
cls
echo ============================================================
echo   K8s Local Deployment
echo   kind + cloud-provider-kind + LoadBalancer  ^|  Windows
echo ============================================================
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.
echo   FIRST TIME / SETUP
echo   [1] Check ^& install prerequisites
echo       Docker Desktop, Docker Compose, kind, kubectl
echo   [2] Create cluster + cloud-provider-kind
echo   [3] Start services ^(after reboot^)
echo   [4] Deploy LoadBalancer demo ^(nginx^)
echo.
echo   DAILY USE
echo   [5] Show status
echo   [6] Stop cloud-provider-kind
echo.
echo   REMOVE
echo   [7] Remove cluster ^(keep images^)
echo   [8] Remove everything ^(+ images^)
echo.
echo   [H] Help    [R] README    [Q] Quit
echo.
set "CHOICE="
set /p CHOICE="Enter choice: "
if "%CHOICE%"=="1" goto PREREQ
if "%CHOICE%"=="2" goto INSTALL
if "%CHOICE%"=="3" goto START_SVC
if "%CHOICE%"=="4" goto DEPLOY
if "%CHOICE%"=="5" goto STATUS
if "%CHOICE%"=="6" goto STOP_SVC
if "%CHOICE%"=="7" goto DELETE
if "%CHOICE%"=="8" goto FULL_REMOVE
if /i "%CHOICE%"=="H" goto HELP
if /i "%CHOICE%"=="R" start "" "%SCRIPT_DIR%README.md" & goto MENU
if /i "%CHOICE%"=="Q" exit /b 0
echo Invalid choice.
goto MENU_PAUSE

:MENU_PAUSE
pause
goto MENU

REM ============================================================
REM  [1] CHECK & INSTALL PREREQUISITES
REM ============================================================
:PREREQ
cls
echo ============================================================
echo   [1] CHECK ^& INSTALL PREREQUISITES
echo ============================================================
echo   Checks system resources and tools.
echo   Missing tools are offered for install automatically.
echo.

set "PREREQ_OK=1"

echo ---------- SYSTEM RESOURCES ----------
echo.

echo [1/8] Windows version
for /f "delims=" %%o in ('powershell -nop -c "(Get-CimInstance Win32_OperatingSystem).Caption" 2^>nul') do set "OS_NAME=%%o"
echo   OS: !OS_NAME!
echo !OS_NAME! | findstr /i "Windows 10 Windows 11" >nul 2>&1
if errorlevel 1 (
    echo [FAIL] Windows 10 or 11 required.
    set "PREREQ_OK=0"
) else (
    echo [OK] Supported.
)
echo.

echo [2/8] Virtualization
set "VIRT_OK=0"
systeminfo 2>nul | findstr /i "Virtualization Enabled In Firmware: Yes" >nul 2>&1
if not errorlevel 1 set "VIRT_OK=1"
systeminfo 2>nul | findstr /i "A hypervisor has been detected" >nul 2>&1
if not errorlevel 1 set "VIRT_OK=1"
if "!VIRT_OK!"=="1" (
    echo [OK] Virtualization / hypervisor detected.
) else (
    echo [WARN] Virtualization not confirmed.
    echo        Enable Intel VT-x / AMD-V in BIOS if Docker/kind fails.
)
echo.

echo [3/8] Disk space ^(15 GB free minimum^)
set "DISK_GB=0"
for /f "delims=" %%d in ('powershell -nop -c "[math]::Round((Get-PSDrive C).Free/1GB,1)" 2^>nul') do set "DISK_GB=%%d"
echo   C: free: !DISK_GB! GB
powershell -nop -c "(Get-PSDrive C).Free/1GB -ge 15" 2>nul | findstr True >nul 2>&1
if errorlevel 1 (
    echo [WARN] Less than 15 GB free.
    set "PREREQ_OK=0"
) else (
    echo [OK] Enough disk.
)
echo.

echo [4/8] RAM ^(8 GB minimum, 16 GB recommended^)
set "RAM_GB=0"
for /f "delims=" %%r in ('powershell -nop -c "[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB,1)" 2^>nul') do set "RAM_GB=%%r"
echo   Total: !RAM_GB! GB
powershell -nop -c "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB -ge 7.5" 2>nul | findstr True >nul 2>&1
if errorlevel 1 (
    echo [FAIL] Less than 8 GB RAM.
    set "PREREQ_OK=0"
) else (
    echo [OK] RAM OK.
)
echo.

echo ---------- REQUIRED TOOLS ----------
echo.

echo [5/8] Docker Desktop
where docker >nul 2>&1
if errorlevel 1 (
    echo [MISSING] Docker Desktop not found.
    set /p INST_DOCKER="  Install Docker Desktop via winget? [Y/n]: "
    if /i not "!INST_DOCKER!"=="n" (
        where winget >nul 2>&1
        if errorlevel 1 (
            echo [ERROR] winget not found. Install manually:
            echo         https://www.docker.com/products/docker-desktop/
            set "PREREQ_OK=0"
        ) else (
            echo Installing Docker.DockerDesktop...
            winget install Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
            echo.
            echo [INFO] Restart PC if prompted, open Docker Desktop,
            echo        enable Start when you log in.
            set "PATH=%PATH%;C:\Program Files\Docker\Docker\resources\bin"
        )
    ) else (
        set "PREREQ_OK=0"
    )
)
where docker >nul 2>&1
if errorlevel 1 (
    set "PREREQ_OK=0"
) else (
    docker version >nul 2>&1
    if errorlevel 1 (
        echo [WARN] docker CLI found but daemon not running.
        echo        Open Docker Desktop and wait for Engine running.
        set "PREREQ_OK=0"
    ) else (
        echo [OK] Docker installed and running.
        docker version 2>nul | findstr /i "Version"
    )
)
echo.

echo [6/8] Docker Compose
docker compose version >nul 2>&1
if errorlevel 1 (
    where docker-compose >nul 2>&1
    if errorlevel 1 (
        echo [MISSING] Docker Compose not found.
        echo           Comes with Docker Desktop — open Desktop, then re-run [1].
        set "PREREQ_OK=0"
    ) else (
        echo [OK] docker-compose ^(legacy^) found.
    )
) else (
    echo [OK] docker compose available.
    docker compose version 2>nul
)
echo.

echo [7/8] kind CLI
where kind >nul 2>&1
if errorlevel 1 (
    echo [MISSING] kind not found.
    set /p INST_KIND="  Install kind via winget? [Y/n]: "
    if /i not "!INST_KIND!"=="n" (
        where winget >nul 2>&1
        if errorlevel 1 (
            echo [ERROR] winget not found:
            echo         https://github.com/kubernetes-sigs/kind/releases
            set "PREREQ_OK=0"
        ) else (
            echo Installing Kubernetes.kind...
            winget install Kubernetes.kind --accept-package-agreements --accept-source-agreements
            set "PATH=%PATH%;%ProgramFiles%\kind;%LOCALAPPDATA%\Microsoft\WindowsApps"
        )
    ) else (
        set "PREREQ_OK=0"
    )
)
where kind >nul 2>&1
if errorlevel 1 (
    set "PREREQ_OK=0"
) else (
    echo [OK] kind installed.
    kind version 2>nul
)
echo.

echo [8/8] kubectl
where kubectl >nul 2>&1
if errorlevel 1 (
    echo [MISSING] kubectl not found.
    set /p INST_KUBECTL="  Install kubectl via winget? [Y/n]: "
    if /i not "!INST_KUBECTL!"=="n" (
        where winget >nul 2>&1
        if errorlevel 1 (
            echo [ERROR] winget not found. Try:
            echo         winget install Kubernetes.kubectl
            set "PREREQ_OK=0"
        ) else (
            echo Installing Kubernetes.kubectl...
            winget install Kubernetes.kubectl --accept-package-agreements --accept-source-agreements
            set "PATH=%PATH%;C:\Program Files\Docker\Docker\resources\bin;%LOCALAPPDATA%\Microsoft\WindowsApps"
        )
    ) else (
        set "PREREQ_OK=0"
    )
)
where kubectl >nul 2>&1
if errorlevel 1 (
    set "PREREQ_OK=0"
) else (
    echo [OK] kubectl installed.
    kubectl version --client 2>nul | findstr /i "Client Version"
)
echo.

echo ============================================================
echo   SUMMARY
echo ============================================================
if "!PREREQ_OK!"=="1" (
    echo [OK] All prerequisites ready.
    echo      Next: menu [2] Create cluster + cloud-provider-kind
) else (
    echo [ACTION NEEDED] Fix items above, then re-run [1].
    echo   - Docker Desktop must be running before [2]
    echo   - Restart this window after winget installs ^(refresh PATH^)
)
echo.
set /p GO_INSTALL="Continue to [2] Create cluster now? [y/N]: "
if /i "!GO_INSTALL!"=="y" goto INSTALL
goto MENU_PAUSE

REM ============================================================
REM  [2] CREATE CLUSTER
REM ============================================================
:INSTALL
cls
echo ============================================================
echo   [2] CREATE CLUSTER + CLOUD-PROVIDER-KIND
echo ============================================================
echo.

where docker >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker not found. Run menu [1] first.
    goto MENU_PAUSE
)
docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker Desktop is not running.
    goto MENU_PAUSE
)
echo [OK] Docker is running.

where kind >nul 2>&1
if errorlevel 1 (
    echo [ERROR] kind not found. Run menu [1] first.
    goto MENU_PAUSE
)
echo [OK] kind is installed.

where kubectl >nul 2>&1
if errorlevel 1 (
    echo [ERROR] kubectl not found. Run menu [1] first.
    goto MENU_PAUSE
)
echo [OK] kubectl is installed.

docker compose version >nul 2>&1
if errorlevel 1 (
    where docker-compose >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] docker compose missing. Run menu [1] first.
        goto MENU_PAUSE
    )
)
echo [OK] Docker Compose ready.
echo.

echo Cluster settings
echo   0 workers = 1 node ^(recommended for laptops^)
echo   1 worker  = 2 nodes total
echo.

set "CLUSTER_NAME=local"
set /p CLUSTER_NAME="Cluster name [default: local]: "
if "!CLUSTER_NAME!"=="" set "CLUSTER_NAME=local"

set "WORKERS=0"
set /p WORKERS="Worker nodes [default: 0]: "
if "!WORKERS!"=="" set "WORKERS=0"

echo.
echo   -^> !CLUSTER_NAME!  ^(1 control-plane + !WORKERS! worker^(s^)^)
echo.

kind get clusters 2>nul | findstr /x "!CLUSTER_NAME!" >nul 2>&1
if not errorlevel 1 (
    echo [WARNING] Cluster "!CLUSTER_NAME!" already exists.
    set /p RECREATE="Delete and recreate? [y/N]: "
    if /i "!RECREATE!"=="y" (
        echo Deleting...
        kind delete cluster --name !CLUSTER_NAME!
        timeout /t 3 /nobreak >nul
    ) else (
        echo Keeping existing cluster.
        goto INSTALL_CPC
    )
)

echo Generating kind-config.yaml...
(
echo kind: Cluster
echo apiVersion: kind.x-k8s.io/v1alpha4
echo name: !CLUSTER_NAME!
echo nodes:
echo   - role: control-plane
) > "%SCRIPT_DIR%kind-config.yaml"
for /L %%i in (1,1,!WORKERS!) do echo   - role: worker>> "%SCRIPT_DIR%kind-config.yaml"
type "%SCRIPT_DIR%kind-config.yaml"
echo.

set /p PULL="Pull required images now? [Y/n]: "
if /i not "!PULL!"=="n" call :PULL_IMAGES
echo.

set /p CONFIRM="Create kind cluster now? [Y/n]: "
if /i "!CONFIRM!"=="n" goto MENU

kind create cluster --config "%SCRIPT_DIR%kind-config.yaml"
if errorlevel 1 (
    echo [ERROR] Cluster creation failed.
    goto MENU_PAUSE
)
echo [OK] Cluster created.

:INSTALL_CPC
echo.
set /p START_CPC="Start cloud-provider-kind ^(LoadBalancer^)? [Y/n]: "
if /i "!START_CPC!"=="n" goto INSTALL_DEPLOY

docker rm -f cloud-provider-kind >nul 2>&1
pushd "%SCRIPT_DIR%"
docker compose up -d
set "COMPOSE_ERR=!errorlevel!"
popd
if !COMPOSE_ERR! neq 0 (
    echo [ERROR] docker compose failed.
    goto MENU_PAUSE
)
echo [OK] cloud-provider-kind started.
timeout /t 5 /nobreak >nul

:INSTALL_DEPLOY
echo.
set /p DEPLOY="Deploy test nginx LoadBalancer? [Y/n]: "
if /i "!DEPLOY!"=="n" goto INSTALL_DONE

call :PULL_NGINX
kubectl create deployment test-nginx --image=!NGINX_IMAGE! 2>nul
kubectl expose deployment test-nginx --port=80 --type=LoadBalancer 2>nul
echo Waiting 30s for LoadBalancer...
timeout /t 30 /nobreak >nul
kubectl get svc test-nginx 2>nul
docker ps --filter "name=kindccm" --format "table {{.Names}}\t{{.Ports}}"

:INSTALL_DONE
echo.
echo ============================================================
echo   INSTALL COMPLETE
echo ============================================================
echo   Context: kind-!CLUSTER_NAME!
echo   Demo URL: http://127.0.0.1
echo   After reboot: menu [3] Start services
echo.
goto MENU_PAUSE

REM ============================================================
REM  [3] START SERVICES
REM ============================================================
:START_SVC
cls
echo ============================================================
echo   [3] START SERVICES ^(after reboot^)
echo ============================================================
echo.

docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker Desktop is not running.
    goto MENU_PAUSE
)

set "CLUSTER=local"
set /p CLUSTER="Cluster name [default: local]: "
if "!CLUSTER!"=="" set "CLUSTER=local"

set "NODE="
for /f "tokens=*" %%c in ('docker ps -a --filter "name=!CLUSTER!-control-plane" --format "{{.Names}}" 2^>nul') do set "NODE=%%c"
if defined NODE (
    docker start !NODE! >nul 2>&1
    echo [OK] Started: !NODE!
    timeout /t 10 /nobreak >nul
) else (
    echo [WARNING] No !CLUSTER!-control-plane found. Run [2] first.
)

docker rm -f cloud-provider-kind >nul 2>&1
pushd "%SCRIPT_DIR%"
docker compose up -d
set "COMPOSE_ERR=!errorlevel!"
popd
if !COMPOSE_ERR! neq 0 (
    echo [ERROR] docker compose failed.
    goto MENU_PAUSE
)

echo [OK] Services started.
kubectl get nodes --context kind-!CLUSTER! 2>nul
kubectl get svc -A 2>nul
echo.
goto MENU_PAUSE

REM ============================================================
REM  [4] DEPLOY DEMO
REM ============================================================
:DEPLOY
cls
echo ============================================================
echo   [4] DEPLOY LOADBALANCER DEMO ^(nginx^)
echo ============================================================
echo.

kubectl get nodes >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Cluster not reachable. Run [2] or [3] first.
    goto MENU_PAUSE
)

set "APP_NAME=test-nginx"
set /p APP_NAME="App name [default: test-nginx]: "
if "!APP_NAME!"=="" set "APP_NAME=test-nginx"

call :PULL_NGINX
kubectl create deployment !APP_NAME! --image=!NGINX_IMAGE! 2>nul
kubectl expose deployment !APP_NAME! --port=80 --type=LoadBalancer 2>nul
echo Waiting 30s...
timeout /t 30 /nobreak >nul

kubectl get svc !APP_NAME!
docker ps --filter "name=kindccm" --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"
echo.
echo Browser: http://127.0.0.1  ^(check PORTS column above^)
echo.
goto MENU_PAUSE

REM ============================================================
REM  [5] STATUS
REM ============================================================
:STATUS
cls
echo ============================================================
echo   [5] STATUS
echo ============================================================
echo.
echo --- kind clusters ---
kind get clusters 2>nul
echo.
echo --- nodes ---
kubectl get nodes 2>nul
echo.
echo --- services ---
kubectl get svc -A 2>nul
echo.
echo --- containers ---
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>nul | findstr /i "control-plane cloud-provider kindccm NAMES"
echo.
echo --- images ---
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>nul | findstr /i "kindest cloud-provider envoy NAMES"
echo.
echo --- disk ---
docker system df 2>nul
echo.
goto MENU_PAUSE

REM ============================================================
REM  [6] STOP
REM ============================================================
:STOP_SVC
cls
echo ============================================================
echo   [6] STOP cloud-provider-kind
echo ============================================================
echo   kind cluster keeps running.
echo.
pushd "%SCRIPT_DIR%"
docker compose down
popd
echo [OK] Stopped. Run [3] to start again.
echo.
goto MENU_PAUSE

REM ============================================================
REM  [7] DELETE CLUSTER
REM ============================================================
:DELETE
cls
echo ============================================================
echo   [7] REMOVE CLUSTER ^(keep images^)
echo ============================================================
echo   Removes kind cluster + cloud-provider-kind + apps.
echo   Keeps Docker images for fast reinstall via [2].
echo.

set "CLUSTER=local"
set /p CLUSTER="Cluster name [default: local]: "
if "!CLUSTER!"=="" set "CLUSTER=local"

echo WARNING: Removes kind cluster "!CLUSTER!" and all apps inside.
set /p CONFIRM="Are you sure? [y/N]: "
if /i not "!CONFIRM!"=="y" goto MENU

call :DELETE_ALL_K8S_APPS
call :STOP_ALL_CONTAINERS
kind delete cluster --name !CLUSTER! 2>nul
call :DELETE_KUBECTL_CONTEXT !CLUSTER!

echo [OK] Cluster removed. Images kept. Run [2] to install again.
echo.
goto MENU_PAUSE

REM ============================================================
REM  [8] FULL REMOVAL
REM ============================================================
:FULL_REMOVE
cls
echo ============================================================
echo   [8] REMOVE EVERYTHING ^(+ images^)
echo ============================================================
echo   Deletes clusters, containers, and project images.
echo   *** CANNOT BE UNDONE ***
echo.

set /p CONFIRM1="Type YES to continue: "
if /i not "!CONFIRM1!"=="YES" goto MENU

echo.
echo [1/9] Delete apps...
call :DELETE_ALL_K8S_APPS
echo [2/9] Stop containers...
call :STOP_ALL_CONTAINERS
echo [3/9] Delete kind clusters...
for /f "tokens=*" %%c in ('kind get clusters 2^>nul') do (
    echo   Deleting: %%c
    kind delete cluster --name %%c 2>nul
)
echo [4/9] Remove leftover node containers...
for /f "tokens=*" %%i in ('docker ps -a --filter "name=control-plane" -q 2^>nul') do docker rm -f %%i >nul 2>&1
for /f "tokens=*" %%i in ('docker ps -a --filter "name=worker" -q 2^>nul') do docker rm -f %%i >nul 2>&1
echo [5/9] Remove kubectl kind contexts...
for /f "tokens=*" %%c in ('kubectl config get-contexts -o name 2^>nul ^| findstr /i "kind-"') do (
    kubectl config delete-context %%c >nul 2>&1
)
for /f "tokens=*" %%c in ('kubectl config get-clusters 2^>nul ^| findstr /i "kind-"') do (
    kubectl config delete-cluster %%c >nul 2>&1
)
echo [6/9] Remove images...
call :REMOVE_ALL_IMAGES
echo [7/9] Remove kind-config.yaml...
if exist "%SCRIPT_DIR%kind-config.yaml" del /f /q "%SCRIPT_DIR%kind-config.yaml"
echo [8/9] Remove kind network...
docker network rm kind >nul 2>&1
echo [9/9] Docker prune...
docker system prune -f >nul 2>&1

echo.
echo [OK] Full removal complete.
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>nul | findstr /i "kindest cloud-provider envoyproxy nginx NAMES"
echo.
goto MENU_PAUSE

REM ============================================================
REM  SHARED HELPERS
REM ============================================================
:PULL_IMAGES
echo Pulling kindest/node ^(via kind^)...
kind pull node-image
if errorlevel 1 echo [WARN] kind pull node-image failed — create will retry.
echo Pulling !CPC_IMAGE!...
docker pull !CPC_IMAGE!
if errorlevel 1 (
    echo [ERROR] Failed to pull cloud-provider-kind image.
    exit /b 1
)
echo Pulling !ENVOY_IMAGE!...
docker pull !ENVOY_IMAGE!
if errorlevel 1 (
    echo [ERROR] Failed to pull envoy image.
    exit /b 1
)
echo [OK] All required images pulled.
exit /b 0

:PULL_NGINX
docker image inspect !NGINX_IMAGE! >nul 2>&1
if not errorlevel 1 exit /b 0
echo Pulling !NGINX_IMAGE!...
docker pull !NGINX_IMAGE!
exit /b 0

:STOP_ALL_CONTAINERS
pushd "%SCRIPT_DIR%"
docker compose down >nul 2>&1
popd
docker rm -f cloud-provider-kind >nul 2>&1
for /f "tokens=*" %%i in ('docker ps -a --filter "name=kindccm" -q 2^>nul') do docker rm -f %%i >nul 2>&1
exit /b 0

:DELETE_ALL_K8S_APPS
kubectl get nodes >nul 2>&1
if errorlevel 1 (
    echo   No cluster reachable — skipping kubectl cleanup.
    exit /b 0
)
echo   Deleting user deployments and services...
powershell -nop -c "$skip=@('kube-system','local-path-storage','kube-public','kube-node-lease'); foreach ($ns in (kubectl get ns -o jsonpath='{.items[*].metadata.name}') -split ' ') { if ($skip -notcontains $ns) { Write-Host ('    namespace: ' + $ns); kubectl delete deployment,svc,ingress --all -n $ns --ignore-not-found --wait=false 2>$null | Out-Null } }"
exit /b 0

:DELETE_KUBECTL_CONTEXT
kubectl config delete-context kind-%~1 >nul 2>&1
kubectl config delete-cluster kind-%~1 >nul 2>&1
exit /b 0

:REMOVE_ALL_IMAGES
echo   Removing kindest/node...
for /f "tokens=*" %%i in ('docker images kindest/node -q 2^>nul') do docker rmi -f %%i >nul 2>&1
for /f "tokens=*" %%i in ('docker images --format "{{.ID}}" --filter "reference=kindest/node" 2^>nul') do docker rmi -f %%i >nul 2>&1
echo   Removing cloud-provider-kind...
docker rmi -f !CPC_IMAGE! >nul 2>&1
for /f "tokens=*" %%i in ('docker images registry.k8s.io/cloud-provider-kind/cloud-controller-manager -q 2^>nul') do docker rmi -f %%i >nul 2>&1
echo   Removing envoyproxy/envoy...
docker rmi -f !ENVOY_IMAGE! >nul 2>&1
for /f "tokens=*" %%i in ('docker images envoyproxy/envoy -q 2^>nul') do docker rmi -f %%i >nul 2>&1
echo   Removing nginx...
docker rmi -f !NGINX_IMAGE! >nul 2>&1
for /f "tokens=*" %%i in ('docker images nginx -q 2^>nul') do docker rmi -f %%i >nul 2>&1
exit /b 0

REM ============================================================
REM  [H] HELP
REM ============================================================
:HELP
cls
echo ============================================================
echo   HELP
echo ============================================================
echo.
echo Recommended first-time flow:
echo   [1] Check ^& install prerequisites
echo       -^> Docker Desktop, Docker Compose, kind, kubectl
echo   [2] Create cluster + cloud-provider-kind
echo   Open browser: http://127.0.0.1
echo.
echo After reboot:
echo   1. Open Docker Desktop
echo   2. Double-click START-HERE.bat
echo   3. Choose [3] Start services
echo.
echo LoadBalancer:
echo   cloud-provider-kind assigns EXTERNAL-IP
echo   kindccm ^(Envoy^) proxies to localhost
echo.
echo Docs:
echo   %SCRIPT_DIR%README.md
echo   %SCRIPT_DIR%GUIDE.txt
echo   %SCRIPT_DIR%example\
echo.
goto MENU_PAUSE
