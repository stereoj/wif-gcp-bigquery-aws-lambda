# DESIGN.md — AWS Lambda to GCP BigQuery via Workload Identity Federation

## Scope and assumptions

- Single AWS account, single GCP project, one Lambda function as the
  reference implementation. The pattern generalizes directly to N functions
  or N GCP projects by repeating the provider/binding block, but I kept the
  reference deployment to one function so the trust boundary is easy to read
  start-to-end.
- I assumed the target is BigQuery specifically (read + parameterized query
  execution), not "any GCP API." The credential layer is API-agnostic, but
  the reference IAM grants and handler are scoped to BigQuery only, in line
  with least privilege.
- Region: `us-east-1` for Lambda and `US` multi-region for BigQuery in the
  example config; both are variables.

## Why Workload Identity Federation over a static service account key

A GCP service account JSON key is a long-lived bearer credential: whoever
holds the file can act as that identity, from anywhere, until someone
notices and rotates it. Shipped into Lambda, it ends up in the deployment
package, in environment variables, or in Secrets Manager as one more thing
to rotate and audit. WIF removes the credential entirely — there is nothing
to leak, because the GCP access token is minted per-invocation from a
cryptographic proof of the calling AWS identity, and it expires in under an
hour by default.

The trade-off is real: WIF has more moving parts to configure correctly (the
trust relationship, the attribute condition, and the impersonation binding
all have to agree, and a misconfiguration usually fails closed with a fairly
generic error — see "Handling silent failures" below). I think that's worth
it for an unattended, automated workload like Lambda. For a one-off script
run by a human on a laptop, a scoped, short-lived key with a real rotation
policy is genuinely less setup than WIF — it's Lambda's unattended nature
that changes the calculus.

## Why service-account impersonation instead of granting BigQuery roles directly to the AWS principal

There are two ways to wire the GCP side:

1. Grant BigQuery IAM roles directly to the WIF principal (a
   `principalSet://...attribute.aws_role/<role-arn>` member).
2. Grant the WIF principal only `roles/iam.workloadIdentityUser` on one
   dedicated GCP service account, and grant BigQuery roles to that service
   account instead.

This project uses (2). It adds one extra hop, but it means BigQuery
permissions live in exactly the same place every other GCP-native workload's
permissions live — the service account's IAM bindings — rather than a
second, AWS-specific authorization path someone auditing the project later
has to know to check. It also means revoking Lambda's access specifically
(say, during an incident) is a one-line binding removal on the service
account, without touching the trust relationship other workloads might
depend on if the pool is ever shared across teams.

## Security hardening

- **Attribute condition scoped to one exact ARN.** The workload identity
  pool provider's `attribute_condition` checks
  `assertion.arn == "<exact Lambda execution role ARN>"` — not the AWS
  account, not a wildcard role path. A different IAM role in the same AWS
  account, even one owned by the same team, cannot exchange for a token.
- **Minimal AWS-side permissions.** The Lambda execution role has exactly
  `sts:GetCallerIdentity` (needed to produce the signed request WIF
  verifies) and CloudWatch Logs — nothing else. It has no direct AWS
  data-plane permissions beyond what it needs to prove its own identity.
- **Token lifetime is short and never persisted.** The default token TTL is
  under an hour. The handler requests a fresh one via the standard
  `google-auth` library and lets the library handle refresh; nothing writes
  a token to disk or logs it.
- **`credential-config.json` is safe to make public.** This is the file
  people instinctively worry about — it looks like a credential but isn't
  one. It contains only the audience (the pool/provider resource name), the
  STS token exchange URL, and where to find AWS's identity metadata. There
  is no secret material in it. This repo still doesn't commit the
  environment-specific one (`lambda/credential-config.json` is gitignored),
  but that's hygiene to keep the repo generic across deployments, not a
  security requirement — see `credential-config.template.json`.
- **Every exchange is auditable.** Token exchanges and impersonation calls
  are visible in GCP Cloud Audit Logs, attributed to the specific AWS role
  ARN via the principal. "Which AWS identity touched this BigQuery dataset,
  and when" is answerable with no custom logging.

## Handling silent failures

1. **Attribute-condition mismatch fails closed, but the error is generic.**
   If the Lambda execution role ARN doesn't match what the provider expects
   — for example, if the role gets recreated with a different name during a
   refactor — GCP's STS rejects the exchange with a permission-denied error
   that doesn't say which condition failed. The handler's credential-refresh
   path catches this case and logs a specific "workload identity trust
   mismatch — check the provider's attribute condition against the current
   execution role ARN" message, because the raw error alone isn't
   actionable.
2. **Token caching across warm invocations.** Lambda execution environments
   are reused across invocations for performance. If a cached GCP access
   token were naively reused past its expiry, calls would start failing
   intermittently in a way that's easy to misdiagnose as "BigQuery is
   flaky." `google-auth`'s credential object handles refresh internally, but
   the handler still treats every credential fetch as fallible (with retry
   and backoff) rather than assuming a warm client is always still valid.
3. **BigQuery quota and permission errors get conflated if you're not
   careful.** A 403 from BigQuery can mean either "the service account lost
   its role" (an incident) or "the query references something it was never
   granted" (often a bug, not an incident). The handler reads the specific
   `reason` field in the API error body to tell these apart, rather than
   logging every 403 identically.
4. **A slow cold start could, in principle, race the AWS credential
   lookup.** This hasn't been observed in practice, but the credential
   fetch is wrapped in an explicit retry (3 attempts, exponential backoff)
   rather than relying on default library behavior to silently absorb a
   transient failure as added latency.

## What I'd do differently with more time / real access to the team

- Add a scheduled canary invocation (EventBridge) purely to alert on WIF
  trust breakage before a real workload hits it, instead of finding out from
  a user-facing error.
- Replace the project-wide `roles/bigquery.dataViewer` fallback with a
  narrower, dataset- or table-scoped custom role once I know exactly which
  data this workload needs. It's project-wide here only so the reference
  deployment is runnable without also asking the reader to create a
  dataset.
- Add a second, separately audited workload identity pool provider for a
  break-glass path — a human assuming a role via `aws sts assume-role` plus
  a short MFA session, exchanging for the same GCP identity during an
  incident, logged distinctly from the automated Lambda path.
