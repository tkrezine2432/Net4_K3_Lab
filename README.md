# Networking 4 — K3s Lab and PiCube Cluster Project

A teaching repository for Mid-State Technical College's Networking 4 course, covering Kubernetes fundamentals through a hands-on lab progression that culminates in a publicly-accessible web service deployed across a Raspberry Pi cluster with full CI/CD automation.

Built and maintained by Troy Krezine.

---

## What's in This Repository

This repo contains everything needed to deploy and maintain a small Kubernetes cluster running on a three-node Raspberry Pi setup. The contents fall into two categories:

**Lab content** — used in earlier weeks of the course to introduce Kubernetes concepts:

- `helloworld.yaml` — deployment of the Rancher hello-world container ("the cow demo")
- `helloworld_nodeport.yaml` — NodePort service exposing the hello-world deployment
- `helloworld_ingress.yaml` — ingress rule routing a hostname to the hello-world service

**Final project content** — the capstone for the course:

- `Dockerfile` — recipe for building a custom container image from nginx Alpine base
- `index.html` — the HTML document the custom container serves
- `webserver.yaml` — deployment of the custom container with seven replicas
- `webserver_nodeport.yaml` — NodePort service exposing the custom deployment

**Automation:**

- `.github/workflows/deploy.yml` — GitHub Actions workflow that builds, pushes, and deploys on every commit to main

---

## Architecture Overview

A Raspberry Pi cluster runs K3s — a lightweight Kubernetes distribution. The cluster is powered through Power-over-Ethernet from an integrated switch inside the chassis. All three nodes participate in scheduling workloads.

The custom website project demonstrates the full production pattern for shipping a containerized application:

1. HTML source code lives in this repository
2. A Dockerfile defines how to build a container image containing the HTML
3. A GitHub Actions workflow watches for commits and builds the image automatically
4. The built image is pushed to a public container registry (Docker Hub)
5. The cluster pulls the image and runs seven replicas across the available nodes
6. A service distributes incoming traffic across the replicas
7. An ingress controller routes external HTTP traffic to the service based on hostname

The container image is published at `tkrezine2432/piweb` on Docker Hub.

---

## Engineering Decisions

The Dockerfile and workflow were written with several deliberate choices worth understanding before modifying them.

### Pinned base image version

The Dockerfile uses `nginx:1.28.3-alpine` rather than the moving tag `nginx:stable` or `nginx:latest`. Pinning to a specific version makes builds reproducible — building this Dockerfile a year from now produces the same image as building it today. The trade-off is that security updates do not arrive automatically; bumping the version is a deliberate maintenance action.

When updating the base image, the safe sequence is:
1. Check the current stable nginx version on Docker Hub
2. Update the `FROM` line in `Dockerfile`
3. Commit and let the pipeline rebuild
4. Verify the new image deploys correctly before considering the change done

### Alpine variant

The image is built on Alpine Linux rather than the default Debian base. The Alpine variant is roughly one-eighth the size of the Debian variant. Smaller images push and pull faster, consume less disk on each cluster node, and present a smaller surface area for security vulnerabilities.

This choice is safe for nginx serving static content. Some application stacks have compatibility issues with Alpine's `musl` libc — if you ever switch to running dynamic application code (Python, Node, etc.), test on Alpine before adopting it broadly.

### OCI metadata labels

The Dockerfile attaches Open Container Initiative standard metadata labels to the image: title, description, authors, source repository, image URL, and license. These labels are visible to anyone who inspects the image and make it self-documenting. They do not affect runtime behavior.

### Instruction ordering in the Dockerfile

The Dockerfile instructions are deliberately ordered so that stable content (the base image and metadata) appears before volatile content (the HTML copy). This maximizes Docker's build cache: when the HTML changes, only the final layer is rebuilt; the base image and labels stay cached. For a small project this saves a few seconds; for larger projects with package installations, the same pattern can save minutes per build.

### Use of `:latest` tag with forced rollout

The deployment YAML references the image as `tkrezine2432/piweb:latest`. Because the tag does not change between builds, applying the deployment YAML alone does not trigger a rollout — Kubernetes sees "same spec, nothing to update." The workflow explicitly runs `kubectl rollout restart deployment/nginx` after pushing the new image to force pods to pull the new version.

A more production-correct approach would use unique version tags per build (e.g., `:v1.0.1`, `:v1.0.2`) and update the deployment YAML to reference each new tag. The forced restart is intentionally used here to keep the workflow simpler for teaching purposes.

---

## CI/CD Pipeline

The workflow file at `.github/workflows/deploy.yml` defines an eight-step pipeline that runs on every push to the `main` branch:

1. **Check out repository** — clones the repo onto the self-hosted runner
2. **Log in to Docker Hub** — authenticates using credentials stored as repository secrets
3. **Build container image** — runs `docker build` using the Dockerfile in the repo root
4. **Push container image to Docker Hub** — uploads the new image
5. **Apply manifests to cluster** — runs `kubectl apply` on all YAML files
6. **Force deployment to pull new image** — runs `kubectl rollout restart` on the nginx deployment
7. **Verify rollout** — waits for both deployments to complete their rollouts
8. **Show running pods** — prints diagnostic output of all pods in the namespace

The workflow uses a **self-hosted runner** installed on the cluster's control plane node. This is necessary because the runner needs direct access to the cluster's API server, which is not accessible from outside the home network. GitHub-hosted cloud runners cannot reach the cluster.

### Repository secrets

Two secrets must exist in the repository's Actions secrets configuration for the workflow to function:

- `DOCKERHUB_USERNAME` — the Docker Hub account name
- `DOCKERHUB_TOKEN` — a Docker Hub Personal Access Token (PAT) with read/write/delete permissions

Tokens are preferred over passwords because they are scoped, revocable, and do not require disabling 2FA. Tokens can be regenerated at `hub.docker.com/settings/security` if compromised or expired.

### Workflow file discovery

GitHub Actions automatically discovers any YAML files placed in `.github/workflows/`. The filename is arbitrary — `deploy.yml`, `pipeline.yml`, or any other name would work identically. GitHub watches the directory for changes; adding a new file there immediately makes it an active workflow.

---

## Public Reachability

When live for demonstrations, the cluster is reachable from the internet via:

1. A dynamic DNS hostname pointing at the home network's current public IP
2. A single port forward on the home router sending inbound HTTP traffic to the cluster's control plane node
3. The cluster's ingress controller (Traefik, built into K3s) which routes traffic to the appropriate service based on hostname

The hostname, IP address, port specifics, and router model are not documented here for security reasons. Specifics are kept in a separate runbook document not committed to this repository.

When not actively in use for demonstrations, the port forward is disabled at the router to minimize public exposure.

---

## Known Gotchas and Lessons Learned

These are issues that bit during the build and are worth being aware of when picking this up again later.

### Self-hosted runner registration auto-deletion

GitHub automatically deletes self-hosted runner registrations after a period of inactivity (around 14 days). If the cluster is powered down for an extended period — semester break, vacation, etc. — the runner registration will be removed and the workflow will fail with "Runner offline" status.

Recovery requires:
1. SSH to the control plane node
2. Stop and uninstall the existing runner service (`sudo ./svc.sh stop && sudo ./svc.sh uninstall` from the runner directory)
3. Generate a new registration token from the repository's Settings → Actions → Runners
4. Re-register the runner using the token
5. Reinstall the runner as a systemd service

### K3s requires a default route at startup

K3s checks the routing table at startup to determine which IP to advertise as the node IP. On a multi-homed system, K3s expects a default route to exist. If the network providing the default route (typically Wi-Fi to the home network) is down, K3s startup fails with `level=fatal msg="Error: no default routes found in /proc/net/route or /proc/net/ipv6_route"` and enters a crash loop.

This bit hard when the home Wi-Fi SSID changed. The fix was to reconfigure Wi-Fi on the cluster nodes via `nmcli` so the default route was restored.

A longer-term fix is to set `--node-ip` explicitly in K3s configuration so it does not depend on the routing table. This is in the "future improvements" list.

### TLS certificate SAN includes only IPs present at install time

K3s auto-generates an API server TLS certificate at install, listing the node's current IPs as Subject Alternative Names. The certificate freezes with that snapshot. If you later attempt to access the API server via an IP that was not present at install time, you will get a TLS certificate validation error.

The fix is to add the missing IP to `/etc/rancher/k3s/config.yaml` under `tls-san:` and delete the cached `serving-kube-apiserver.crt` and `serving-kube-apiserver.key` files so K3s regenerates them on restart.

### NodePort port range restriction

Kubernetes NodePort services are restricted to ports 30000-32767 by default. The lab YAMLs use port 30080 for the webserver service and 31080 for the helloworld service. Attempting to use port 80 directly via NodePort will fail. Public-facing port 80 access is achieved via the ingress controller, not NodePort.

### Worker nodes also need the default route fixed

The Wi-Fi reconfiguration applies to all three cluster nodes, not just the control plane. Worker nodes also need their wlan0 connection updated when the home SSID changes.

---

## Future Improvements

Items deferred from the original build, in rough priority order:

### Pin the K3s node IP explicitly

Currently K3s determines the node IP at startup by walking the routing table. This creates an unnecessary dependency on the Wi-Fi network being up. Setting `node-ip: <static-IP>` in `/etc/rancher/k3s/config.yaml` would eliminate this dependency. Should be applied to all three nodes with their respective IPs.

### Namespaces

All current workloads live in the `default` namespace. As more projects are added, namespace separation (`piweb`, `picraft`, etc.) would make it easier to manage workloads independently and would model better practice for students learning the concept.

### Resource requests and limits

Pod specifications currently lack explicit `resources.requests` and `resources.limits`. For static HTML on nginx this is fine. As more workloads share the cluster — particularly hungry ones like Minecraft servers — explicit resource constraints become important to prevent the cluster from running out of memory and OOM-killing pods at random.

### Version tags instead of `:latest`

Move from the simple `:latest` tag to commit-SHA or semantic version tags. This eliminates the need for forced rollout restarts and makes deployments fully declarative.

### Dev/prod separation

A future-state architecture would separate development and production environments, possibly across separate namespaces, separate branches in this repository, and separate domains. Both environments should be as identical as possible in structure so changes validated in dev predict well in prod.

### Network policies

K3s ships with Flannel as its CNI, which does not enforce Kubernetes NetworkPolicies by default. For production multi-workload deployment, replacing Flannel with Calico (or another policy-enforcing CNI) would allow pod-to-pod traffic restrictions — important once workloads include sensitive services like databases alongside public-facing services.

### TLS for public access

The current setup serves over plain HTTP. For real production use, cert-manager with Let's Encrypt would provide automated TLS certificates with the ingress controller terminating HTTPS. Modern browsers increasingly warn users about plain HTTP sites.

### Build runner not on a cluster node

Currently the GitHub Actions runner lives on the K3s control plane node. This is operationally convenient but creates a coupling — if the control plane is unhealthy, the runner is also unhealthy. A more resilient design would put the runner on a separate machine (a dedicated build host, or even a different cluster node) so build infrastructure and cluster control are independent.

### Image build outside the cluster

Building container images on a cluster node uses cluster resources for non-cluster work. A more production-correct design would move builds to a dedicated build host or to GitHub's hosted runners (which would require restructuring how the cluster is contacted for the deploy step).

---

## Operating This Repository

### To deploy a content change

1. Edit `index.html` directly in the GitHub web UI, or locally and push
2. Commit to the `main` branch
3. Watch the workflow run at `https://github.com/tkrezine2432/Net4_K3_Lab/actions`
4. After the run completes (green), the change is live on the cluster

### To update the base image

1. Check Docker Hub for the current stable nginx version
2. Update the `FROM` line in `Dockerfile`
3. Commit to `main`
4. Pipeline rebuilds and deploys

### To inspect a built image's metadata

On any machine with the image pulled:
```
docker inspect tkrezine2432/piweb:latest --format '{{json .Config.Labels}}'
```

### To verify pods are running the latest image

```
kubectl get pods
kubectl describe pod <pod-name> | grep -i image
```

### To force a rollout without changing anything

```
kubectl rollout restart deployment/nginx
```

Useful for testing the rollout behavior or recovering from a stuck state.

### To temporarily disable public access

At the home router's port forwarding configuration, change the destination internal IP to a non-existent address (e.g., `.250` instead of the cluster control plane's address). Public requests will time out without reaching the cluster. To re-enable, change back to the real internal address.

This approach preserves the forwarding rule for quick re-enablement, unlike deleting the rule entirely.

---

## Course Context

This work was developed as the final project for Mid-State Technical College's Networking 4 course, building on concepts introduced earlier in the program:

- **Networking 1-3:** routing, switching, addressing fundamentals
- **Networking 4:** Kubernetes orchestration, containerization, CI/CD

The hello-world content in this repository is the entry-level Kubernetes introduction used in earlier weeks of Networking 4. The custom website project demonstrates the next level of Kubernetes literacy — building and shipping custom images through automated pipelines.

Students completing this course should be able to explain the full traffic path from a visitor's browser to a running pod, understand why each component of the stack exists, and have hands-on experience modifying both the application content and the deployment automation.

---

## License

MIT — see image label and Dockerfile metadata.
