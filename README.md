# K8s Local Deployment

Local Kubernetes with **kind** + **cloud-provider-kind** (LoadBalancer on localhost).

| OS | Folder | Start |
|----|--------|--------|
| Windows | [`window/`](window/) | Double-click `START-HERE.bat` |
| Linux | [`linux/`](linux/) | `chmod +x START-HERE.sh && ./START-HERE.sh` |

## First-time flow

1. Open the folder for your OS  
2. Run the start script  
3. **`[1]`** Check & install prerequisites (Docker, Compose, kind, kubectl)  
4. **`[2]`** Create cluster + cloud-provider-kind  
5. Open **http://127.0.0.1**

## Menu (same on both OS)

```
[1] Check & install prerequisites
[2] Create cluster + cloud-provider-kind
[3] Start services (after reboot)
[4] Deploy LoadBalancer demo (nginx)
[5] Show status
[6] Stop cloud-provider-kind
[7] Remove cluster (keep images)
[8] Remove everything (+ images)
[H] Help   [R] README   [Q] Quit
```

See each folder’s `GUIDE.txt` for a short step-by-step.
