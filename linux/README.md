# Linux — kind + LoadBalancer

## Start

```bash
chmod +x START-HERE.sh
./START-HERE.sh
```

## Steps

1. **`[1]`** Check & install prerequisites  
   - Installs if missing: Docker, Compose, kind, kubectl  
2. **`[2]`** Create cluster + cloud-provider-kind  
3. Browser → **http://127.0.0.1**

After reboot: `sudo systemctl start docker` → run script → **`[3]`**

## Menu

```
[1] Prerequisites     [5] Status
[2] Create cluster    [6] Stop cloud-provider-kind
[3] Start services    [7] Remove cluster (keep images)
[4] Deploy nginx LB   [8] Remove everything
[H] Help  [R] README  [Q] Quit
```

## Examples

```bash
kubectl apply -f example/nginx-loadbalancer.yaml
kubectl apply -f example/ingress-demo.yaml
```

## Ingress hostname (`demo-app`)

The Ingress in `example/ingress-demo.yaml` uses host **`demo.local`**.  
Your machine must map that name to localhost before the browser can open it.

1. Apply the demo (cluster + cloud-provider-kind already running):

```bash
kubectl apply -f example/ingress-demo.yaml
kubectl get ingress
```

2. Add the hostname:

```bash
echo "127.0.0.1  demo.local" | sudo tee -a /etc/hosts
```

Or edit `/etc/hosts` and add:

```
127.0.0.1  demo.local
```

3. Check the Ingress / proxy port:

```bash
kubectl get ingress demo-ingress
docker ps --filter name=kindccm
```

4. Open in browser: **http://demo.local**  
   (If it fails, try the port shown under `kindccm` PORTS, e.g. `http://demo.local:xxxxx`)

To use another hostname, change `host:` in `ingress-demo.yaml` and use the same name in `/etc/hosts`.

More detail: `GUIDE.txt`
