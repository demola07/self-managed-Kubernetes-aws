# Container Recovery in Kubernetes - Concise Breakdown

## 🔄 Recovery Flow (30 seconds)

```
Container Crashes → Kubelet Detects → Checks RestartPolicy → Tells containerd → New Container Starts
     (T0)              (T1: <1s)           (T2: instant)        (T3: 1-5s)         (T4: Ready)
```

## 🎯 Components & Roles

| Component | Role |
|-----------|------|
| **Kubelet** | Detects crash, decides to restart, executes restart |
| **containerd** | Actually starts/stops containers |
| **API Server** | Stores pod state |
| **Controller Manager** | Recreates pods if deleted (not for container restarts) |

## 📊 Visual Flow

```
┌─────────────┐
│  Container  │
│   Crashes   │ ──┐
└─────────────┘   │
                  │
                  ▼
         ┌────────────────┐
         │    Kubelet     │ ◄── Monitors via probes/runtime
         │  (Worker Node) │
         └────────┬───────┘
                  │
                  │ Checks RestartPolicy: Always/OnFailure/Never
                  │
                  ▼
         ┌────────────────┐
         │  containerd    │
         │   (Runtime)    │
         └────────┬───────┘
                  │
                  │ Pull image → Create → Start
                  │
                  ▼
         ┌────────────────┐
         │  New Container │
         │    Running ✓   │
         └────────────────┘
```

## 🧪 Quick Simulation

```bash
# Create pod
kubectl run test --image=nginx

# Kill it
kubectl exec test -- kill 1

# Watch restart
kubectl get pod test --watch
# STATUS: Running → Error → Running
# RESTARTS: 0 → 1
```

## 📋 View Logs

```bash
# Pod events
kubectl describe pod test

# Kubelet logs (on worker node)
sudo journalctl -u kubelet -f | grep test

# Container logs (before crash)
kubectl logs test --previous
```

## ⏱️ Timeline

```
T0: Container exits
T1: Kubelet detects (within 1 second)
T2: Restart decision (immediate)
T3: New container starts (1-5 seconds)
T4: Container ready
```

## 🔑 Key Points

1. **Kubelet** does everything - detection, decision, execution
2. **RestartPolicy** controls behavior (default: Always)
3. **Restart count** increments each time
4. **Automatic** - no human intervention needed
5. **Backoff** if repeated crashes: 0s → 10s → 20s → 40s → max 5min

---

## 📖 Detailed Component Breakdown

### Kubelet (Primary Recovery Agent)

**Location**: Runs on every worker node

**Responsibilities**:
- Monitors container health via liveness/readiness probes
- Receives container state changes from containerd
- Decides whether to restart based on RestartPolicy
- Instructs containerd to create/start new containers
- Reports pod/container status to API Server

**Key Actions**:
1. Detects container exit/crash
2. Checks pod's `restartPolicy` field
3. If `Always` or `OnFailure` (with non-zero exit), initiates restart
4. Increments restart counter
5. Applies exponential backoff if repeated failures

### containerd (Container Runtime)

**Location**: Runs on every worker node

**Responsibilities**:
- Manages actual container lifecycle
- Pulls container images
- Creates and starts containers
- Monitors container processes
- Notifies kubelet of state changes

**Key Actions**:
1. Receives restart command from kubelet
2. Pulls image if not cached
3. Creates new container with same spec
4. Starts the container
5. Reports success/failure to kubelet

### API Server

**Location**: Control plane

**Responsibilities**:
- Stores cluster state in etcd
- Provides REST API for cluster operations
- Validates and persists pod/container status updates

**Key Actions**:
1. Receives status updates from kubelet
2. Updates pod status in etcd
3. Serves current state to kubectl/controllers

### Controller Manager (For Pod-Level Recovery)

**Location**: Control plane

**Responsibilities**:
- Ensures desired state matches actual state
- Recreates pods if they're deleted
- Manages ReplicaSets, Deployments, etc.

**Note**: Controller Manager does NOT restart containers - that's kubelet's job. It only recreates entire pods.

---

## 🔍 Restart Policies Explained

| Policy | Behavior | Use Case |
|--------|----------|----------|
| **Always** | Restart on any exit (even success) | Long-running services (default) |
| **OnFailure** | Restart only if exit code ≠ 0 | Batch jobs that should retry on failure |
| **Never** | Never restart | One-time tasks, debugging |

### Example:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  restartPolicy: Always  # ← This controls restart behavior
  containers:
  - name: app
    image: nginx
```

---

## 📊 Exponential Backoff Strategy

When a container repeatedly crashes, Kubernetes applies exponential backoff to prevent resource thrashing:

```
Attempt 1: Restart immediately (0 seconds)
Attempt 2: Wait 10 seconds
Attempt 3: Wait 20 seconds
Attempt 4: Wait 40 seconds
Attempt 5: Wait 80 seconds
Attempt 6: Wait 160 seconds (capped at 5 minutes)
Attempt 7+: Wait 300 seconds (5 minutes max)
```

**Status during backoff**: `CrashLoopBackOff`

**Check backoff status**:
```bash
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}'
```

---

## 🎯 Complete Recovery Example

### Scenario: nginx container crashes

**Initial State**:
```bash
$ kubectl get pod nginx-pod
NAME        READY   STATUS    RESTARTS   AGE
nginx-pod   1/1     Running   0          2m
```

**Crash Event**:
```bash
$ kubectl exec nginx-pod -- kill 1
```

**Recovery Timeline**:

```
T+0s:   Container process exits (PID 1 killed)
        └─ containerd detects process exit
        └─ Notifies kubelet

T+0.5s: Kubelet receives notification
        └─ Checks restartPolicy: Always
        └─ Decision: RESTART
        └─ Marks container as "Terminated"

T+1s:   Kubelet instructs containerd
        └─ containerd pulls image (if needed)
        └─ Creates new container
        └─ Starts container

T+3s:   Container starts successfully
        └─ Runs startup probes (if configured)
        └─ Container marked as "Running"

T+5s:   Kubelet updates API Server
        └─ restartCount: 0 → 1
        └─ status: Running
        └─ lastState: Terminated (exit code: 137)
```

**Final State**:
```bash
$ kubectl get pod nginx-pod
NAME        READY   STATUS    RESTARTS   AGE
nginx-pod   1/1     Running   1          2m30s
                              ↑
                        Restart count incremented
```

---

## 🧪 Hands-On Lab: Simulate & Observe Recovery

### Lab 1: Basic Container Restart

```bash
# Step 1: Create a test pod
kubectl run crash-test --image=nginx

# Step 2: Open 3 terminals

# Terminal 1: Watch pod status
watch -n 1 'kubectl get pod crash-test'

# Terminal 2: Watch events
kubectl get events --watch --field-selector involvedObject.name=crash-test

# Terminal 3: Kill the container
kubectl exec crash-test -- kill 1

# Observe:
# - Pod status: Running → Error → Running
# - Restart count: 0 → 1
# - Events: "Killing container" → "Started container"
```

### Lab 2: CrashLoopBackOff Simulation

```bash
# Create a pod that crashes repeatedly
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: crashloop-test
spec:
  containers:
  - name: crash
    image: busybox
    command: ["sh", "-c", "echo 'Crashing...'; exit 1"]
  restartPolicy: Always
EOF

# Watch the backoff in action
kubectl get pod crashloop-test --watch

# Output:
# NAME             READY   STATUS             RESTARTS   AGE
# crashloop-test   0/1     CrashLoopBackOff   1          12s
# crashloop-test   0/1     CrashLoopBackOff   2          22s
# crashloop-test   0/1     CrashLoopBackOff   3          42s
# crashloop-test   0/1     CrashLoopBackOff   4          82s
#                                              ↑
#                         Notice increasing restart intervals
```

### Lab 3: Liveness Probe Triggered Restart

```bash
# Create pod with failing liveness probe
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: liveness-test
spec:
  containers:
  - name: app
    image: nginx
    livenessProbe:
      httpGet:
        path: /healthz  # This endpoint doesn't exist
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
      failureThreshold: 2
  restartPolicy: Always
EOF

# Watch kubelet restart the container due to failed probe
kubectl get pod liveness-test --watch

# View probe failure events
kubectl describe pod liveness-test | grep -A 5 Events
```

---

## 📋 Debugging Commands Cheat Sheet

### Check Pod Status
```bash
# Basic status
kubectl get pod <pod-name>

# Detailed status with events
kubectl describe pod <pod-name>

# Watch status changes
kubectl get pod <pod-name> --watch

# JSON output for scripting
kubectl get pod <pod-name> -o json | jq '.status.containerStatuses[0]'
```

### View Logs
```bash
# Current container logs
kubectl logs <pod-name>

# Previous container logs (after restart)
kubectl logs <pod-name> --previous

# Follow logs in real-time
kubectl logs <pod-name> -f

# Logs from specific container in multi-container pod
kubectl logs <pod-name> -c <container-name>

# Last 50 lines
kubectl logs <pod-name> --tail=50
```

### Check Restart Information
```bash
# Restart count
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[0].restartCount}'

# Last termination reason
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'

# Current state
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[0].state}'
```

### View Events
```bash
# All events for a pod
kubectl get events --field-selector involvedObject.name=<pod-name>

# Watch events in real-time
kubectl get events --watch

# Sort by timestamp
kubectl get events --sort-by='.lastTimestamp'
```

### Node-Level Debugging (SSH to worker node)
```bash
# Kubelet logs
sudo journalctl -u kubelet -f

# Filter for specific pod
sudo journalctl -u kubelet | grep <pod-name>

# containerd logs
sudo journalctl -u containerd -f

# List containers on node
sudo crictl ps -a

# Inspect specific container
sudo crictl inspect <container-id>
```

---

## 🎓 Summary

### The Recovery Process in One Sentence
**When a container crashes, the kubelet on that node detects it, checks the restart policy, and tells containerd to create and start a new container.**

### Key Takeaways

1. ✅ **Kubelet is the hero** - It handles all container-level recovery
2. ✅ **Automatic by default** - RestartPolicy: Always means hands-free recovery
3. ✅ **Fast recovery** - Usually completes in 1-5 seconds
4. ✅ **Smart backoff** - Prevents infinite restart loops
5. ✅ **Transparent** - Restart count and events show what happened
6. ✅ **No control plane needed** - Recovery works even if control plane is down

### When Recovery Happens

- ✅ Container process exits/crashes
- ✅ Liveness probe fails
- ✅ OOM (Out of Memory) kill
- ✅ Manual kill (kubectl exec ... kill)

### When Recovery Doesn't Happen

- ❌ Pod is deleted (Controller Manager recreates pod, not container)
- ❌ Node fails (Scheduler places pod on new node)
- ❌ RestartPolicy: Never
- ❌ Deployment rollout (new pods created, old ones terminated)

---

**Document Version**: 1.0  
**Last Updated**: October 2025  
**Author**: Kubernetes Infrastructure Guide
