# Mirador Security Findings: kube-proxy and S3 CSI Driver

**Date:** 2026-08-11 (originally 2026-06-30)
**Cluster:** `ComfyUI-on-EKS-Cluster` (EKS 1.35, us-west-2, account 479780966925)
**Affected images:**
- `602401143452.dkr.ecr.us-west-2.amazonaws.com/eks/kube-proxy:v1.35.3-eksbuild.13`
- `public.ecr.aws/mountpoint-s3-csi-driver/aws-mountpoint-s3-csi-driver:v2.7.0`

---

## 2026-08-11 remediation round

Two finding categories were reviewed against the 2026-08-11 Mirador export:

**1. Container remediation (AWS-managed images)**

| Component | Was | Now pinned | Latest available (1.35) | Action |
|-----------|-----|-----------|-------------------------|--------|
| kube-proxy | `v1.35.3-eksbuild.13` | **`v1.35.3-eksbuild.18`** | `v1.35.3-eksbuild.18` | Bumped in `lib/comfyui-on-eks-stack.ts`; 5 eksbuild increments = refreshed distroless base, clears the `openssl-libs` / Debian-layer findings |
| aws-mountpoint-s3-csi-driver | `v2.7.0` | `v2.7.0` (`-eksbuild.1`) | `v2.7.0-eksbuild.1` | Already the newest build. Finding persists purely due to AWS image-rebuild lag (see below) — nothing to bump |

**2. OS patching (host / NAWS)** — nodes running an AL2023 AMI older than the current release:

| Node group | Was | Rolled to | Mechanism |
|-----------|-----|-----------|-----------|
| Managed `comfyui-on-eks-mng-lw` (t3a.xlarge x2) | AMI release `1.35.6-20260625` | `1.35.6-20260801` (latest) | `aws eks update-nodegroup-version` — rolling replace |
| Karpenter GPU (`node-gpu`, g6.2xlarge) | AMI drifted | `al2023@latest` on relaunch | node cycled so Karpenter reprovisions on newest AMI; `NodePool.expireAfter: 168h` keeps it fresh |

The ComfyUI application image built by this repo does **not** appear in the findings — its `Dockerfile` already runs `apt-get upgrade` and is rebuilt weekly.

---

## What we did and why findings still persist

We are running the latest available version of both components:

| Component | Current | Latest available |
|-----------|---------|-----------------|
| kube-proxy | `v1.35.3-eksbuild.13` | `v1.35.3-eksbuild.13` |
| aws-mountpoint-s3-csi-driver | `v2.6.0` | `v2.6.0` |

Both were upgraded on 2026-06-25 as part of active security remediation. The findings persist not because we are behind — we are at the latest available release — but because **AWS has not yet rebuilt these images against the latest patched packages**.

---

## Root cause: AWS release cadence lags behind ALAS advisories

Amazon Linux 2023 security advisories (ALAS) are published continuously — multiple times per week. When an ALAS is published, the AL2023 package repositories are updated immediately. However, **EKS-distributed container images are only rebuilt at discrete intervals**, triggered by:

- New Kubernetes patch versions (e.g., 1.35.3 → 1.35.4)
- `eksbuild` increments — batched base-image-tag refreshes, not tied to individual package updates
- Feature releases of add-ons (e.g., CSI driver v2.6.0)

This creates a structural lag:

```
ALAS advisory published  →  AL2023 repo updated  →  [gap]  →  Image rebuild
      (immediate)                (immediate)                   (days to weeks)
```

AWS's documentation states that EKS add-ons "include the latest security patches" — this is true at time of publication, but it does not guarantee packages stay current between releases. The lag between an ALAS advisory and an image rebuild is not publicly documented; community observation puts it at days to several weeks.

---

## Specific unpatched CVEs confirmed

### aws-mountpoint-s3-csi-driver:v2.6.0

Confirmed via direct inspection of the image's RPM database. The image runs Amazon Linux 2023 minimal.

**openssl-libs 3.5.5-1.amzn2023.0.4 is installed.** ALAS2023-2026-1853 (published June 22, 2026 — 8 days before this writing) requires **0.5** and covers 15 CVEs. The image was built before June 22 and has not been updated.

| CVE | Severity | Description | Fixed in |
|-----|----------|-------------|---------|
| CVE-2026-45447 | **High** | Heap use-after-free in `PKCS7_verify()` — exploitable during PKCS#7 signature verification with an empty `digestAlgorithms` field | openssl 0.5 |
| CVE-2026-34183 | Moderate (CVSS 7.5) | Remote unauthenticated QUIC `PATH_CHALLENGE` handler causes unbounded heap memory growth — denial of service, no auth required | openssl 0.5 |
| CVE-2026-45445 | Moderate | AES-OCB IV ignored on `EVP_Cipher()` path — nonce reuse vulnerability | openssl 0.5 |
| CVE-2026-34182 | Moderate | CMS `AuthEnvelopedData` accepts forged messages | openssl 0.5 |
| CVE-2026-42764 | Moderate | QUIC NULL dereference | openssl 0.5 |
| +10 more | Low | Various OpenSSL Low severity | openssl 0.5 |

The fix exists — `openssl-libs-3.5.5-1.amzn2023.0.5` is available in the AL2023 package repository. AWS simply needs to rebuild the image.

### kube-proxy:v1.35.3-eksbuild.13

This image is **distroless** (no shell, no package manager). It is built on a Debian-derived base (`gcr.io/distroless/base` via `kube-proxy-base:v0.18.0-eks-1-35-N`), not Amazon Linux.

CVE exposure in this image comes from Debian-layer packages (`glibc`, `libssl`, `ca-certificates`), not AL2023 RPMs. Each `eksbuild` increment is typically a rebuild against a newer Debian snapshot, which picks up Debian security patches. The specific CVEs flagged by Mirador are Debian-layer issues that require AWS to issue a new `eksbuild` pulling a newer distroless base. We cannot inspect or fix these packages ourselves — the image contains no tools to do so.

---

## What we cannot do

Both images are built, signed, and distributed exclusively by AWS. We have no ability to:

- Rebuild or modify either image
- Apply OS package updates inside either container (kube-proxy has no package manager; S3 CSI has one but modifying a managed image would break image verification)
- Pin to a patched version that does not yet exist

---

## Current mitigations in place

1. **ECR Enhanced Scanning (Inspector2)** enabled on 2026-06-29 with `CONTINUOUS_SCAN`. This provides package-level CVE attribution so findings can be precisely linked to specific packages and versions, rather than relying on layer-hash matching. This improves visibility but does not remediate the underlying issue.

2. **Karpenter node expiry set to 7 days** — GPU nodes are replaced weekly, ensuring they always run the latest AL2023 AMI for the underlying node OS. This addresses host-level findings separately from container-level ones.

3. **Weekly container image rebuild** scheduled via EventBridge/CodeBuild, ensuring the ComfyUI application image stays current. This does not apply to AWS-managed images.

---

## Remediation path

The only path to resolving these findings is **AWS releasing updated image builds**:

| Image | Required action by AWS | Expected trigger |
|-------|----------------------|-----------------|
| `kube-proxy` | New `eksbuild` increment (e.g., `eksbuild.14`) pulling newer distroless base | Kubernetes patch release or scheduled base refresh |
| `aws-mountpoint-s3-csi-driver` | New patch release (e.g., `v2.6.1`) with `openssl-libs 0.5` | AWS CSI driver patch cycle |

### Recommended escalation

Raise an AWS Support case with the following details:

**Subject:** EKS-managed images behind on AL2023/Debian security patches — ALAS2023-2026-1853 not reflected

**Body:**
> We are running the latest available versions of kube-proxy (v1.35.3-eksbuild.13) and aws-mountpoint-s3-csi-driver (v2.6.0) on EKS 1.35 in us-west-2. Both images are generating Mirador CONTAINER_REMEDIATION findings that we cannot resolve ourselves as these are AWS-managed images.
>
> For aws-mountpoint-s3-csi-driver:v2.6.0: the image contains openssl-libs-3.5.5-1.amzn2023.0.4. ALAS2023-2026-1853 (published 2026-06-22) requires 0.5 and covers CVE-2026-45447 (High), CVE-2026-34183 (Moderate, CVSS 7.5), and 13 additional CVEs. The patched package is available in AL2023 repos but has not been incorporated into a new CSI driver release.
>
> For kube-proxy:v1.35.3-eksbuild.13: the distroless base image contains Debian-layer CVEs. A new eksbuild pulling a refreshed distroless snapshot would resolve these.
>
> Please advise on the expected timeline for updated releases and confirm whether there is a process to request expedited builds for critical ALAS advisories.

Once AWS releases updated images, the fix on our side is a single command per component:

```bash
# kube-proxy — update to new eksbuild once available
kubectl set image ds/kube-proxy -n kube-system \
  kube-proxy=602401143452.dkr.ecr.us-west-2.amazonaws.com/eks/kube-proxy:v1.35.3-eksbuild.XX

# S3 CSI driver — update CDK version and redeploy
# In lib/comfyui-on-eks-stack.ts, bump S3CSIDriverAddOn version to v2.6.1 (or next patch)
# then: npx cdk deploy ComfyUI-on-EKS-Cluster
```
