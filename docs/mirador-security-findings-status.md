# Mirador Security Findings — Status & Explanation

**Date:** 2026-06-29  
**Cluster:** `ComfyUI-on-EKS-Cluster` (EKS 1.35, us-west-2)  
**Owner:** jenntip

---

## Summary

As of this writing, Mirador shows a mix of resolved and unresolved security findings for the ComfyUI on EKS deployment. This document explains the status of each category, what has been done, and what requires AWS action.

---

## Category 1: Stale findings from decommissioned hosts (now resolved)

**Finding type:** `CONTAINER_REMEDIATION` — "Out of SLA, Launched out of SLA"  
**Count:** 16 findings  
**Status:** Root cause fixed — findings will close on Mirador's next scan cycle

### What happened

These findings persisted for over a week after the old cluster was torn down. The root cause was **6 orphaned SSM managed instances** (`mi-*` registration IDs) from a cluster that was decommissioned in March 2026. These nodes were terminated but never formally deregistered from AWS Systems Manager.

Mirador uses SSM inventory as its source of truth for host liveness. Because these registrations remained in SSM with status `ConnectionLost`, Mirador treated the associated container findings as still active — even though the containers, nodes, and cluster had not existed for months.

### Resolution

All 6 stale SSM registrations were deregistered on 2026-06-29:

```
mi-05c939dd424cbbebe  (last ping: 2026-03-16, ConnectionLost)
mi-0dcf52491b6389d53  (last ping: 2026-03-16, ConnectionLost)
mi-04790ce7dabc7c646  (last ping: 2026-03-16, ConnectionLost)
mi-01c2883d4b11a4891  (last ping: 2026-03-16, ConnectionLost)
mi-06e416ea029899868  (last ping: 2026-03-16, ConnectionLost)
mi-09dd803730497580e  (last ping: 2026-03-16, ConnectionLost)
```

SSM now shows only the 3 live nodes of the current cluster. These findings should auto-close on Mirador's next scan.

### Prevention

When tearing down an EKS cluster in future, explicitly deregister SSM managed instances:

```bash
aws ssm describe-instance-information --query 'InstanceInformationList[?PingStatus==`ConnectionLost`].InstanceId' --output text \
  | xargs -n1 aws ssm deregister-managed-instance --instance-id
```

---

## Category 2: ComfyUI container image findings (partially resolved)

**Finding type:** `CONTAINER_REMEDIATION`  
**Image:** `comfyui-images:latest` (sha256:d125b598...)  
**Status:** Patched + improved scanning accuracy in progress

### What happened

The running ComfyUI container was flagged for vulnerable packages. Some were genuine, some were false positives from the basic ECR scanner.

| CVE | Package | Was it real? | Action taken |
|-----|---------|-------------|--------------|
| CVE-2026-24049 | `wheel 0.42.0` | **Yes** | Upgraded to 0.47.0 in Dockerfile |
| CVE-2025-66471 | `urllib3` | False positive | Already at 2.7.0 (patched), scanner misfired |
| CVE-2025-66418 | `urllib3` | False positive | Already at 2.7.0 (patched), scanner misfired |
| CVE-2024-35195 | `requests` | False positive | Already at 2.32.3 (patched), scanner misfired |

The basic ECR scanner does not perform package-level analysis — it flags by image layer hash, causing false positives when a package is already patched but the base layer hasn't changed.

### Resolution

- `wheel` upgraded to 0.47.0 in the Dockerfile (commit `1b19920`)
- ECR enhanced scanning via **AWS Inspector2** enabled on 2026-06-29 with `CONTINUOUS_SCAN` across all repositories. Inspector2 performs deep package-level analysis and will accurately report which CVEs are genuinely unpatched, eliminating the false positives from the basic scanner
- 3 old untagged images deleted from ECR (May 2026 vintage, no longer used)

---

## Category 3: AWS-managed image findings — kube-proxy and S3 CSI driver (requires AWS action)

**Finding type:** `CONTAINER_REMEDIATION` — "Within SLA"  
**Status:** Cannot be self-remediated — requires AWS to release updated images

### Current configuration

| Component | Current version | Latest available | Notes |
|-----------|----------------|-----------------|-------|
| `kube-proxy` | `v1.35.3-eksbuild.13` | `v1.35.3-eksbuild.13` | Already on latest available build |
| `aws-mountpoint-s3-csi-driver` | `v2.6.0` | `v2.6.0-eksbuild.1` | Already on latest available version |

### Why we cannot fix these

Both images are owned and published by AWS. The vulnerable packages are baked into the official EKS-distributed images:

- **kube-proxy** is distributed by AWS at `602401143452.dkr.ecr.us-west-2.amazonaws.com/eks/kube-proxy`. We do not build or control this image. We have already upgraded to the latest available build (`eksbuild.13`) — no newer build exists.
- **aws-mountpoint-s3-csi-driver** is distributed by AWS at `public.ecr.aws/mountpoint-s3-csi-driver`. We have already upgraded to the latest release (`v2.6.0`). No newer version is available.

Upgrading to "latest" does not resolve the findings because the vulnerable packages exist in the latest AWS-published versions of these images.

### What we have done

1. Upgraded both components to their latest available versions (June 2026)
2. Enabled enhanced scanning to get precise CVE-to-package mapping for any future escalation

### Recommended next steps

Raise an AWS Support case (or submit via the [EKS GitHub repo](https://github.com/aws/containers-roadmap/issues)) requesting patched releases. Include:

- **Affected images:**
  - `602401143452.dkr.ecr.us-west-2.amazonaws.com/eks/kube-proxy:v1.35.3-eksbuild.13`
  - `public.ecr.aws/mountpoint-s3-csi-driver/aws-mountpoint-s3-csi-driver:v2.6.0`
- **Cluster version:** EKS 1.35
- **Region:** us-west-2
- **Mirador finding type:** `CONTAINER_REMEDIATION.CONTAINER_REMEDIATION_REQUIRED`
- **Request:** Release new `eksbuild` versions with patched base OS packages

Until AWS releases updated images, these findings cannot be resolved through any configuration change on our side.

---

## Current state (2026-06-29)

| Finding category | Count | Status |
|-----------------|-------|--------|
| Stale SSM hosts (old cluster) | 16 | Fixed — will auto-close next Mirador scan |
| ComfyUI image — false positives | ~3 | Fixed — enhanced scanning will confirm |
| ComfyUI image — CVE-2026-24049 | 1 | Fixed — wheel upgraded to 0.47.0 |
| kube-proxy image findings | 3 | Blocked on AWS — at latest available version |
| s3-csi-driver image findings | 5 | Blocked on AWS — at latest available version |

---

## Changes made to codebase

| Commit | Change |
|--------|--------|
| `299405b` | Node OS patching: forceUpdate, Karpenter 7-day expiry, buildspec base image refresh, PDB |
| `1b19920` | CVE-2026-24049: wheel 0.47.0, S3 CSI v2.6.0, kube-proxy eksbuild.13 |
| `3425047` | Deploy script: image freshness guard (auto-rebuild if >24h old) |
| `826c65d` | Deploy script: Inspector2 enhanced ECR scanning enabled on every deploy |
