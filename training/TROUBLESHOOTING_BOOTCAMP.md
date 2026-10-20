# Kubernetes Troubleshooting Bootcamp

8-week program for developers new to Kubernetes. Each session: you break the environment before they arrive, they diagnose and fix it. Target time: 45–60 minutes per session.

**Stack context**: EKS cluster, helmfile deployments, AWS Secrets Manager CSI for secrets.  
**Namespace for all app pods**: `notification-canada-ca`

---

## Participant Command Reference

Hand this out at the first session. Add commands each week as they're introduced.

```bash
# === CORE INSPECTION ===
kubectl get pods -n notification-canada-ca
kubectl get pods -n notification-canada-ca -w              # watch live
kubectl get all -n notification-canada-ca                  # pods + services + deployments + HPAs
kubectl describe pod <pod-name> -n notification-canada-ca  # full detail + events
kubectl logs <pod-name> -n notification-canada-ca
kubectl logs <pod-name> -n notification-canada-ca --previous   # last crashed container's logs

# === EXEC INTO A RUNNING POD ===
kubectl exec -it <pod-name> -n notification-canada-ca -- /bin/sh

# === SERVICES & NETWORKING ===
kubectl get svc -n notification-canada-ca
kubectl get endpoints -n notification-canada-ca
kubectl port-forward <pod-name> 8080:6011 -n notification-canada-ca

# === RESOURCES ===
kubectl top pods -n notification-canada-ca
kubectl top nodes

# === DEPLOYMENTS & ROLLOUTS ===
kubectl get deployments -n notification-canada-ca
kubectl rollout status deployment/<name> -n notification-canada-ca
kubectl rollout undo deployment/<name> -n notification-canada-ca

# === POLICY ===
kubectl get pdb -n notification-canada-ca
kubectl describe pdb <name> -n notification-canada-ca
kubectl get hpa -n notification-canada-ca

# === SECRETS (CSI) ===
kubectl get secretproviderclass -n notification-canada-ca
kubectl describe secretproviderclass <name> -n notification-canada-ca

# === EVENTS (timeline view) ===
kubectl get events -n notification-canada-ca --sort-by='.lastTimestamp'

# === HELMFILE — deploying changes ===
helmfile -e <env> list                              # see all releases and their sync status
helmfile -e <env> diff   -l app=notify-api          # preview what will change before applying
helmfile -e <env> apply  -l app=notify-api          # deploy a specific app
helmfile -e <env> apply  -l "app in (notify-api,notify-admin)"  # deploy multiple
helmfile -e <env> template -l app=notify-api        # render to raw K8s YAML (no deploy)
helmfile -e <env> template -l app=notify-api > /tmp/rendered.yaml  # save for inspection

# === HELM — inspecting what is currently deployed ===
# (helmfile wraps helm; these commands query the live cluster state)
helm list -n notification-canada-ca                              # all releases + chart versions
helm get values notify-api -n notification-canada-ca            # values used in the live deployment
helm get values notify-api -n notification-canada-ca --all      # includes chart defaults
helm history notify-api -n notification-canada-ca               # full deployment history
helm rollback notify-api -n notification-canada-ca              # roll back to previous revision
helm rollback notify-api 3 -n notification-canada-ca            # roll back to specific revision
```

---

## Week 1 — "Why Won't It Start?"

**Difficulty**: ★☆☆☆☆  
**Concepts**: Pod lifecycle, image pulls, reading Events  
**New commands**: `kubectl get pods`, `kubectl describe pod`

### The Break

In `helmfile/charts/notify-admin/values.yaml`, change the image tag to something that does not exist in the registry:

```yaml
# Before:
image:
  tag: "latest"

# After:
image:
  tag: "v9.9.9-does-not-exist"
```

Redeploy: `helmfile -e <env> apply -l app=notify-admin`

### What They Will See

- `kubectl get pods` shows `notify-admin-*` pods stuck in `ImagePullBackOff` or `ErrImagePull`
- No notify-admin pod ever reaches `Running`
- The admin UI is unreachable

### Hints (use if stuck after 10 min)

1. "What does the STATUS column tell you? Is that normal?"
2. "Run `kubectl describe pod <name>`. Scroll all the way to the bottom. What does the Events section say?"
3. "The error mentions an image. What image is it trying to pull?"
4. "Where in the repo is the image tag configured?"

### The Fix

Restore `image.tag: "latest"` in `helmfile/charts/notify-admin/values.yaml` and redeploy.

### Debrief

- What's the difference between `ErrImagePull` and `ImagePullBackOff`? (Hint: backoff = K8s is slowing down retries)
- Where does K8s pull images from? What would break if the registry was unreachable?
- In production, a bad image was just deployed. What's the fastest way to recover?

### If They Finish Early

**Variant: Wrong pull policy**

Instead of a bad tag, change `pullPolicy` to `Never` while using a tag that doesn't exist on the node:

```yaml
image:
  tag: "latest"
  pullPolicy: Never   # was: Always
```

This produces a different error — `ErrImageNeverPull` — because K8s refuses to pull at all and only looks for a locally cached image. The pod is stuck in `Pending` with a different message than ImagePullBackOff. Ask them: *same symptom (pod won't start), different root cause — how do you tell them apart?*

Restore `pullPolicy: Always` to fix.

---

## Week 2 — "It Starts But Then Dies"

**Difficulty**: ★★☆☆☆  
**Concepts**: CrashLoopBackOff, application startup errors, environment variables  
**New commands**: `kubectl logs --previous`, reading Env in `kubectl describe pod`

### The Break

In `helmfile/overrides/notify/api.yaml.gotmpl`, add a line that sets `GUNICORN_WORKERS` to an invalid value. Add it at the top of the `api:` block so it overrides the templated value:

```yaml
api:
  GUNICORN_WORKERS: "not-a-number"   # <-- add this line
  GUNICORN_THREADS: "{{ .StateValues.API_GUNICORN_THREADS }}"
  # ... rest of file unchanged
```

Gunicorn expects an integer here. It will crash immediately at startup.

Redeploy: `helmfile -e <env> apply -l app=notify-api`

### What They Will See

- Pods briefly transition to `Running`, then start restarting
- `kubectl get pods` shows increasing `RESTARTS` count and status `CrashLoopBackOff`
- `kubectl logs <pod>` may show empty output (the pod died too fast)

### Hints

1. "The pod is starting and then stopping. What would you look at to see what happened right before it stopped?"
2. "Try adding `--previous` to your logs command — it shows the last crashed container's output."
3. "The error is in the startup sequence. What command starts the API? (Look for 'gunicorn' in the logs)"
4. "Use `kubectl describe pod` and scroll to the Env section. Does `GUNICORN_WORKERS` look right?"

### The Fix

Remove the `GUNICORN_WORKERS: "not-a-number"` line from `helmfile/overrides/notify/api.yaml.gotmpl` and redeploy.

### Debrief

- What's the difference between a pod in `CrashLoopBackOff` vs `ImagePullBackOff`?
- Why does `kubectl logs` sometimes return nothing for a crashing pod?
- How do you see all environment variables currently set in a running pod?

### If They Finish Early

**Variant: Application can't find its entry point**

In `helmfile/overrides/notify/api.yaml.gotmpl`, override `FLASK_APP` with a file that doesn't exist:

```yaml
api:
  FLASK_APP: "this_module_does_not_exist.py"   # was: application.py
```

Gunicorn will start, then immediately fail trying to import the app module — a `ModuleNotFoundError` in the logs. The CrashLoopBackOff pattern looks identical from `kubectl get pods`, but the log output is completely different. Ask them: *how do you know if it's a config problem vs a code problem?*

Remove the override to fix.

---

## Week 3 — "It Works Fine, Then Dies Randomly"

**Difficulty**: ★★☆☆☆  
**Concepts**: OOMKilled, resource requests vs limits, `kubectl top`  
**New commands**: `kubectl top pods`, reading `Last State: OOMKilled` in describe

### The Break

In `helmfile/charts/notify-api/values.yaml`, lower the memory limit to something impossibly small:

```yaml
# Before:
resources:
  requests:
    cpu: "250m"
    memory: "700Mi"
  limits:
    cpu: "1200m"
    memory: "900Mi"

# After:
resources:
  requests:
    cpu: "250m"
    memory: "50Mi"
  limits:
    cpu: "1200m"
    memory: "50Mi"
```

Redeploy: `helmfile -e <env> apply -l app=notify-api`

### What They Will See

- Pods start, briefly work, then die — repeatedly
- `kubectl get pods` shows high `RESTARTS` count
- `kubectl logs` shows *no application error* — the process was killed externally
- `kubectl describe pod` shows `Last State: Terminated` with `Reason: OOMKilled`

### Hints

1. "It crashes but there are no error logs. That's important — what else can kill a process without a log entry?"
2. "Check `kubectl describe pod`. Look at the section called 'Last State'. What Reason is listed?"
3. "OOMKilled means Out Of Memory Killed. The kernel killed the process. Now run `kubectl top pods` — what do you see?"
4. "What is the configured memory limit for notify-api? Is that enough for a Python/Gunicorn app?"

### The Fix

Restore `memory: "900Mi"` for both request and limit in `helmfile/charts/notify-api/values.yaml` and redeploy.

### Debrief

- What's the difference between a resource *request* and a *limit*?
- What exit code does OOMKilled produce, and why? (137 = 128 + SIGKILL signal 9)
- When a pod OOMKills, does traffic automatically shift away from it? What role does the readiness probe play?

### If They Finish Early

**Variant: CPU starvation (the app lives but suffers)**

Restore normal memory limits but crush the CPU limit:

```yaml
resources:
  requests:
    cpu: "250m"
    memory: "700Mi"
  limits:
    cpu: "10m"    # 10 millicores — absurdly low
    memory: "900Mi"
```

The pod will start, pass its readiness probe, and look completely healthy in `kubectl get pods`. But every request will be agonizingly slow because the container is CPU-throttled by the kernel. No OOMKill, no crash, no obvious error — just a degraded app. Ask them to use `kubectl top pods` and compare the CPU *usage* against the *limit* column in `kubectl describe pod`. This teaches that `kubectl get pods` showing `1/1 Running` does not mean the pod is actually performing well.

Restore `cpu: "1200m"` to fix.

---

## Week 4 — "Pods Are Running But Nobody Can Reach Them"

**Difficulty**: ★★★☆☆  
**Concepts**: Readiness vs liveness, health probes, traffic routing, endpoints  
**New commands**: `kubectl get endpoints`, `kubectl port-forward`, `curl`

### The Break

In `helmfile/charts/notify-api/values.yaml`, change the readiness probe path to something that returns a 404:

```yaml
# Before:
readinessProbe:
  initialDelaySeconds: 45
  httpGet:
    path: /_status?simple=true
    port: 6011

# After:
readinessProbe:
  initialDelaySeconds: 45
  httpGet:
    path: /_this_path_does_not_exist
    port: 6011
```

Leave the liveness probe unchanged so pods don't get killed — they should just stay unready.

Redeploy: `helmfile -e <env> apply -l app=notify-api`

### What They Will See

- `kubectl get pods` shows notify-api pods as `Running` but the READY column shows `0/1`
- API requests fail or time out — no traffic is being served
- Nothing looks obviously broken at first glance ("the pods are running!")

### Hints

1. "The pods say Running. But look at the READY column — what does 0/1 mean?"
2. "Run `kubectl describe pod`. Look at the Events section. What failure is being reported repeatedly?"
3. "What is a readiness probe and why does K8s have one? How is it different from a liveness probe?"
4. "Run `kubectl get endpoints notify-api -n notification-canada-ca`. Are any pod IPs listed? Why not?"
5. "Can you port-forward directly to a pod and hit the probe path yourself? `kubectl port-forward <pod> 8080:6011`"

### The Fix

Restore `path: /_status?simple=true` in `helmfile/charts/notify-api/values.yaml` and redeploy.

### Debrief

- What's the practical difference between a readiness probe and a liveness probe?
- What happens if the readiness probe is too strict? Too lenient?
- If the app takes 2 minutes to start up, how would you configure the probe? (initialDelaySeconds, failureThreshold)

### If They Finish Early

**Variant: Liveness probe kills what readiness spared**

Instead of only breaking the readiness probe, also break the liveness probe path:

```yaml
readinessProbe:
  initialDelaySeconds: 45
  httpGet:
    path: /_this_path_does_not_exist
    port: 6011

livenessProbe:
  initialDelaySeconds: 45
  httpGet:
    path: /_this_path_does_not_exist
    port: 6011
```

Now the behaviour changes significantly: instead of pods sitting at `0/1 Running` indefinitely, they will be *killed and restarted* by the liveness probe — producing a `CrashLoopBackOff`-adjacent pattern but with a different root cause. The key question to ask: *Week 2 also showed CrashLoopBackOff — how is this different? Check the Events section closely.* (`kubectl describe pod` will show `Liveness probe failed` in Events, not an application exit). The lesson is that liveness vs readiness failure looks similar on the surface but has different implications.

Restore both probe paths to `/_status?simple=true` to fix.

---

## Week 5 — "Deployment Is Stuck — Nothing Is Updating"

**Difficulty**: ★★★☆☆  
**Concepts**: Rolling updates, Pod Disruption Budgets, rollback  
**New commands**: `kubectl rollout status`, `kubectl get pdb`, `kubectl describe pdb`, `kubectl rollout undo`

### The Break

This scenario requires two changes:

**Step 1**: In `helmfile/charts/notify-api/values.yaml`, set the PDB `minAvailable` higher than the replica count:

```yaml
# Before:
replicaCount: 2

pdb:
  enabled: true
  minAvailable: 2

# After:
replicaCount: 2

pdb:
  enabled: true
  minAvailable: 3   # impossible: you can never have 3 available from 2 replicas
```

**Step 2**: Make a trivial change to trigger a rollout. Add an innocuous env var in `helmfile/overrides/notify/api.yaml.gotmpl`:

```yaml
api:
  HELM_TEST_API: "HELM-IS-RADICAL!-API-V2"   # change from existing value to force rollout
```

Redeploy: `helmfile -e <env> apply -l app=notify-api`

### What They Will See

- A new pod is created and becomes Ready (the surge pod)
- `kubectl rollout status deployment/notify-api` hangs indefinitely
- The old pod(s) cannot be terminated — the rollout is frozen with both old and new pods running
- `kubectl get pdb` shows the disruption budget exists
- `kubectl describe pdb notify-api` shows `Allowed Disruptions: 0`

### Hints

1. "Something is updating but not finishing. How do you watch a deployment rollout?"
2. "Try `kubectl rollout status deployment/notify-api -n notification-canada-ca`"
3. "K8s won't kill the old pod. What feature protects pods from being terminated? `kubectl get pdb`"
4. "Run `kubectl describe pdb notify-api -n notification-canada-ca`. How many disruptions are allowed right now?"
5. "You have 2 replicas. How many must be 'available' according to the PDB? Is that achievable?"

### The Fix

1. If the rollout is mid-flight, first undo it: `kubectl rollout undo deployment/notify-api -n notification-canada-ca`
2. Fix `pdb.minAvailable: 2` in `helmfile/charts/notify-api/values.yaml`
3. Redeploy cleanly: `helmfile -e <env> apply -l app=notify-api`

### Debrief

- Why do PDBs exist? What real-world event are they protecting against? (node drain during maintenance, cluster upgrades)
- What is a safe `minAvailable` value relative to `replicaCount`? (rule of thumb: `replicaCount - 1`)
- When might you temporarily bypass a PDB in an emergency? How would you do it?

### If They Finish Early

**Variant: The update strategy itself is broken**

Restore the PDB to `minAvailable: 2`, but now break the rolling update strategy:

```yaml
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 0       # can't create any new pods before removing old ones
    maxUnavailable: 0 # can't remove any old pods either
```

With both set to 0, K8s literally cannot make progress on a rolling update — it can neither add nor remove a pod. Trigger a rollout with a trivial change. The deployment update will be blocked before any new pod is created, unlike the PDB scenario where you could *see* the new pod sitting alongside the old one. Ask them: *how is this different from the PDB scenario? What do `kubectl rollout status` and `kubectl describe deployment` tell you?*

Restore `maxSurge: 25%` and `maxUnavailable: 25%` to fix.

---

## Week 6 — "Pod Won't Start at All — Not Even an Error"

**Difficulty**: ★★★★☆  
**Concepts**: CSI secret driver, volume mounts, AWS Secrets Manager, pod initialization  
**New commands**: `kubectl get secretproviderclass`, deeper `kubectl describe pod` reading

### The Break

In `helmfile/charts/notify-api/values.yaml`, change the AWS Secrets Manager object name in the `secretProviderClass` to one that doesn't exist:

```yaml
# Before:
secretProviderClass:
  secretname: notify-api
  enabled: true
  provider: aws
  parameters:
    objects: |
      - objectName: INTERNAL_DNS_KEY_BASE64
        objectType: "secretsmanager"

# After:
secretProviderClass:
  secretname: notify-api
  enabled: true
  provider: aws
  parameters:
    objects: |
      - objectName: INTERNAL_DNS_KEY_BASE64_DOES_NOT_EXIST
        objectType: "secretsmanager"
```

Redeploy: `helmfile -e <env> apply -l app=notify-api`

### What They Will See

- New pods are stuck in `ContainerCreating` — they never progress past this state
- `kubectl logs` returns nothing (the container never started)
- `kubectl describe pod` shows an error in the Events section about a CSI volume mount failure
- Old pods (if they survived the rollout) may still be running fine

### Hints

1. "The pod never starts — but it's not an image issue. What else could block a container from starting before it even runs?"
2. "Look at `kubectl describe pod` very carefully. Read the `Events` section and the `Volumes` section."
3. "The error mentions a CSI volume. How does this application receive its secrets? (Not as K8s Secrets — look at the chart)"
4. "Run `kubectl get secretproviderclass -n notification-canada-ca`. What does that object do?"
5. "Compare the `objectName` in the SecretProviderClass to what actually exists in AWS Secrets Manager."

### The Fix

Restore `objectName: INTERNAL_DNS_KEY_BASE64` in `helmfile/charts/notify-api/values.yaml` and redeploy.

### Debrief

- How is this secrets approach different from a K8s native Secret? What are the tradeoffs?
- The pod needed an IAM role to read from Secrets Manager. Where is that configured? (IRSA, ServiceAccount annotations)
- How would you verify a specific secret name actually exists in AWS Secrets Manager from the command line?

---

## Week 7 — "The App Works But Notifications Aren't Being Sent"

**Difficulty**: ★★★★☆  
**Concepts**: Multi-component architecture, message queues, log correlation across pods  
**New commands**: `kubectl logs -l`, `kubectl logs -f`, `kubectl exec` for connectivity testing

### The Break

In `helmfile/overrides/notify/celery.yaml.gotmpl`, override `CELERY_CONCURRENCY` with a value that breaks the Celery pool configuration. More reliably: add a bad `REDIS_URL` override that points celery workers to a non-existent Redis host.

Add to the `celeryCommon:` block:

```yaml
celeryCommon:
  REDIS_URL: "redis://this-redis-host-does-not-exist:6379/0"   # <-- add this line
  # ... rest of file unchanged
```

Redeploy: `helmfile -e <env> apply -l app=notify-celery`

### What They Will See

- `kubectl get pods` — API and admin pods look completely normal
- Celery worker pods are in `CrashLoopBackOff` or restarting with errors
- The application appears to work (you can log in, create notifications) but nothing is actually sent
- The failure is *silent* from the user's perspective — no obvious error on screen

### Hints

1. "The API is healthy and accepts requests. But emails and SMS are never sent. Which component actually sends them?"
2. "Check the celery pods specifically: `kubectl get pods -n notification-canada-ca | grep celery`"
3. "Pull logs from all celery pods at once: `kubectl logs -l app=notify-celery -n notification-canada-ca`"
4. "What error are the workers throwing? It's a connection error — to what?"
5. "Exec into a celery pod and test the connection manually: `kubectl exec -it <pod> -- sh`, then try `redis-cli -u $REDIS_URL ping`"

### The Fix

Remove the `REDIS_URL: "redis://this-redis-host-does-not-exist:6379/0"` line from `helmfile/overrides/notify/celery.yaml.gotmpl` and redeploy.

### Debrief

- How would you know in production that the celery queue is backing up? What would you look at? (queue depth metrics, CloudWatch, SigNoz)
- If celery workers all crash while the queue has 10,000 jobs in it, what happens to those jobs when workers come back up?
- What is celery `beat` and what would happen if just the beat pod crashed? (Scheduled tasks stop, but queue processing continues)

---

## Week 8 — "Full System Triage"

**Difficulty**: ★★★★★  
**Concepts**: Incident response, systematic triage, parallel debugging, root cause analysis  
**New commands**: `kubectl get all`, combining everything from previous weeks

### The Break (set up *before* the session — don't tell them what you changed)

Make **three** simultaneous changes:

**Break 1** — Obvious (admin is down): `helmfile/charts/notify-admin/values.yaml`
```yaml
image:
  tag: "v9.9.9-incident-drill"   # ImagePullBackOff
```

**Break 2** — Subtle (API looks healthy but can't serve traffic): `helmfile/charts/notify-api/values.yaml`
```yaml
readinessProbe:
  initialDelaySeconds: 45
  httpGet:
    path: /_broken_for_drill      # was: /_status?simple=true
    port: 6011
```

**Break 3** — Silent (no scheduled tasks, everything else looks fine): `helmfile/charts/notify-celery/values.yaml`
```yaml
nodes:
  beat:
    deployment:
      replicas: 0                 # was: 3 — beat scheduler is gone
```

Redeploy all three: `helmfile -e <env> apply -l "app in (notify-admin,notify-api,notify-celery)"`

### What They Will See

- Everything seems broken at once
- Admin: completely unreachable
- API: pods show `Running` but aren't serving traffic
- Celery beat: silently gone — scheduled tasks just stop running
- The team may feel overwhelmed and not know where to start

### Facilitator Guidance

- Give them 10–15 minutes of unguided struggle — this is deliberate
- If completely frozen, give one prompt: "Start with a full picture. Run `kubectl get all -n notification-canada-ca`"
- **Do not reveal there are 3 separate issues** — let them discover this
- Watch how they organize. Do they parallelize? Do they communicate clearly?
- Good teams fix admin (easy win) → fix API → then notice beat is missing

### Fix Order (suggested)

1. **Admin image** — fastest to spot and fix, restores the UI
2. **API readiness probe** — restores core API functionality
3. **Celery beat** — requires understanding what beat does and why 0 replicas is wrong

### The Fix

Revert all three changes and redeploy.

### Debrief (most important session — spend time here)

- How did you decide what to fix first? What was your triage process?
- Did you communicate clearly about what was broken vs what was working?
- Which of the three breaks was hardest to find? Why? (The silent one — beat at 0 replicas)
- What monitoring or alerting would have caught these *before* someone had to manually look?
- What runbook would you want to have existed before this incident?
- Design a 5-minute "health check" script that would catch all three of these issues automatically.

---

## Appendix: Helmfile & Helm Quick Reference

```bash
# --- BEFORE you change anything ---
helmfile -e <env> list                               # what's deployed and is it in sync?
helmfile -e <env> diff -l app=notify-api             # what will change if you apply?

# --- Deploy ---
helmfile -e <env> apply -l app=notify-api            # single app
helmfile -e <env> apply -l "app in (notify-api,notify-admin)"  # multiple apps
helmfile -e <env> apply -l step=5                    # all app-tier releases
helmfile -e <env> sync  -l app=notify-api            # force sync regardless of diff

# --- Inspect rendered output without deploying ---
helmfile -e <env> template -l app=notify-api                        # print to stdout
helmfile -e <env> template -l app=notify-api > /tmp/rendered.yaml   # save to file

# --- Inspect what is live on the cluster (helm commands) ---
helm list -n notification-canada-ca                          # all releases, versions, status
helm get values notify-api -n notification-canada-ca         # values currently deployed
helm get values notify-api -n notification-canada-ca --all   # includes chart defaults
helm get manifest notify-api -n notification-canada-ca       # full K8s YAML as deployed
helm history notify-api -n notification-canada-ca            # deployment history with revisions

# --- Roll back ---
helm rollback notify-api -n notification-canada-ca           # back to previous revision
helm rollback notify-api 3 -n notification-canada-ca         # back to specific revision
# (or via kubectl for the deployment only:)
kubectl rollout undo deployment/notify-api -n notification-canada-ca
```

## Appendix: Reading Pod Status at a Glance

| STATUS | READY | What it means |
|---|---|---|
| `Pending` | `0/1` | Waiting for a node, or volume can't mount |
| `ContainerCreating` | `0/1` | Node found, pulling image or mounting volumes |
| `ImagePullBackOff` | `0/1` | Can't pull the container image |
| `Init:Error` | `0/1` | Init container failed (often volume/secret mount) |
| `Running` | `0/1` | Container running but readiness probe failing |
| `Running` | `1/1` | Healthy — receiving traffic |
| `CrashLoopBackOff` | `0/1` | App keeps crashing at startup |
| `OOMKilled` | `0/1` | Killed by kernel for using too much memory |
| `Terminating` | `1/1` | Being gracefully shut down |
| `Completed` | `0/1` | Job/init container finished successfully |
