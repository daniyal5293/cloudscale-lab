# Optional Phase: Automated Deployment with GitHub OIDC

**Status: documented only, not enabled.** The core project deploys with a reviewed, manual `terraform apply`.
This phase shows how the pipeline *could* roll out each new image automatically without storing AWS keys in GitHub.

## Why OIDC instead of access keys?

| Long-lived access keys in GitHub Secrets | GitHub OIDC → IAM role |
|---|---|
| Valid until someone rotates or deletes them | Short-lived (1 h) credentials issued per workflow run |
| Leak = attacker has your AWS access | Nothing long-lived to leak |
| Usable from anywhere | Usable only by **your repo, your branch** (trust-policy conditions) |

GitHub signs a token saying "this is workflow X in repo Y on branch Z". AWS STS checks the signature against
the registered OIDC provider and the role's trust policy, then hands back temporary credentials.

## What would be automated

The smallest useful step: after CI pushes `sha-<commit>`, trigger an **instance refresh** so the ASG replaces
instances one by one with ones that pull the new image. This needs:

1. The launch template to reference the new tag. Simplest approach: `container_image = ...:latest` plus an
   instance refresh (new instances pull `latest`). The more rigorous approach runs `terraform apply` in CI with
   remote state, which is out of scope here because it would require an S3 backend.
2. Permission to call `autoscaling:StartInstanceRefresh` on this one ASG.

## Setup (one-time, AWS Console or Terraform)

1. IAM → **Identity providers** → *Add provider* → OpenID Connect
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`
2. IAM → Roles → *Create role* → Web identity → the provider above. Trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:<GITHUB_USER>/cloudscale-lab:ref:refs/heads/main"
      }
    }
  }]
}
```

3. Permissions policy for the role (only this action, only this ASG):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["autoscaling:StartInstanceRefresh", "autoscaling:DescribeInstanceRefreshes"],
    "Resource": "*",
    "Condition": { "StringEquals": { "autoscaling:ResourceTag/Project": "cloudscale-lab" } }
  }]
}
```
(`DescribeInstanceRefreshes` does not support resource conditions; split it into its own statement if AWS
reports a policy validation warning.)

4. GitHub repo → Settings → Variables → Actions: add `AWS_ROLE_ARN` (a variable, not a secret; it's not sensitive)
   and `ASG_NAME` = `cloudscale-lab-demo-asg`.

## Workflow job (add to `ci.yml` after the `docker` job)

```yaml
  deploy:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main' && vars.AWS_ROLE_ARN != ''
    needs: docker
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # allows requesting the OIDC token
      contents: read
    steps:
      - uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: us-east-1
      - run: |
          aws autoscaling start-instance-refresh \
            --auto-scaling-group-name "${{ vars.ASG_NAME }}" \
            --preferences '{"MinHealthyPercentage":100,"MaxHealthyPercentage":200,"InstanceWarmup":120}'
```

The job is skipped automatically when `AWS_ROLE_ARN` isn't set, so it's harmless when infrastructure is destroyed.

## Cost note

OIDC, IAM and instance refresh are free. A refresh briefly runs one extra instance (max-healthy 200%), which costs
a few cents per refresh at most.
