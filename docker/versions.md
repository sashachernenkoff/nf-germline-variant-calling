# Container image versions

The pipeline's tool images are built from the Dockerfiles in this directory and
pushed to ECR by `build_and_push.sh`. Base images are pinned by digest so builds
are reproducible over time and across accounts.

| Image | Tool | Base image |
|-------|------|------------|
| `nf-germline-gatk:4.5.0.0-aws` | GATK 4.5.0.0 (bundles samtools 1.13) | `broadinstitute/gatk:4.5.0.0` |
| `nf-germline-mosdepth:0.3.8-aws` | mosdepth 0.3.8 | `quay.io/biocontainers/mosdepth:0.3.8--hd299d5a_0` |
| `nf-germline-bcftools:1.18-aws` | bcftools 1.18 | `quay.io/biocontainers/bcftools:1.18--h8b25389_0` |

All three add the AWS CLI (for S3 staging on AWS Batch), copied from
`amazon/aws-cli:2.36.28`.

## Pinned base image digests

- `amazon/aws-cli:2.36.28`
  `sha256:9e94ede8b677fe5456a152fd6698a6726810160497882123bfd9dd40a5671d74`
- `broadinstitute/gatk:4.5.0.0`
  `sha256:8a29403b528a417cd1630c33affe82726019788e24e4dfe00e2586c6b4195e9f`
- `quay.io/biocontainers/mosdepth:0.3.8--hd299d5a_0`
  `sha256:2decf63be02007796b4d1ab8389e99564a8c2eebeb5bad6983bdb1d7a99a657f`
- `quay.io/biocontainers/bcftools:1.18--h8b25389_0`
  `sha256:f3497f167d499a90db55f2c82b3d93ebe06bbaa85760883b323cc2bb0123658e`

## Rebuilding

```bash
bash docker/build_and_push.sh
```

To update a base image, refresh its digest with
`docker buildx imagetools inspect <image> --format '{{.Manifest.Digest}}'`,
update the `FROM` line in the corresponding Dockerfile and the digest above,
then rebuild.
