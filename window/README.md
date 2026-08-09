# Windows — kind + LoadBalancer

## Start

Double-click **`START-HERE.bat`**

## Steps

1. **`[1]`** Check & install prerequisites  
   - Installs if missing: Docker Desktop, Compose, kind, kubectl  
2. **`[2]`** Create cluster + cloud-provider-kind  
3. Browser → **http://127.0.0.1**

After reboot: open Docker Desktop → run script → **`[3]`**

## Menu

```
[1] Prerequisites     [5] Status
[2] Create cluster    [6] Stop cloud-provider-kind
[3] Start services    [7] Remove cluster (keep images)
[4] Deploy nginx LB   [8] Remove everything
[H] Help  [R] README  [Q] Quit
```

## Examples

```powershell
kubectl apply -f example/nginx-loadbalancer.yaml
kubectl apply -f example/ingress-demo.yaml
```

## Ingress hostname (`demo-app`)

The Ingress in `example/ingress-demo.yaml` uses host **`demo.local`**.  
Your PC must map that name to localhost before the browser can open it.

1. Apply the demo (cluster + cloud-provider-kind already running):

```powershell
kubectl apply -f example/ingress-demo.yaml
kubectl get ingress
```

2. Add the hostname (Admin Notepad):

- Open: `C:\Windows\System32\drivers\etc\hosts`
- Add this line:

```
127.0.0.1  demo.local
```

3. Check the Ingress / proxy port:

```powershell
kubectl get ingress demo-ingress
docker ps --filter name=kindccm
```

4. Open in browser: **http://demo.local**  
   (If it fails, try the port shown under `kindccm` PORTS, e.g. `http://demo.local:xxxxx`)

To use another hostname, change `host:` in `ingress-demo.yaml` and use the same name in the hosts file.

More detail: `GUIDE.txt`
