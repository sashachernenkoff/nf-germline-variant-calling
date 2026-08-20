# nf-germline-variant-calling

A Nextflow DSL2 pipeline for GATK4 best-practices germline variant calling from whole-genome sequencing data.

> Originally developed and validated on the CPTAC LUAD cohort during MSc thesis research; this public version runs against GIAB reference samples for reproducibility.

---

## Pipeline overview

```
BAM input (per sample)
    │
    ▼
MarkDuplicates          - flag PCR and optical duplicates
    │
    ▼
BQSR                    - recalibrate base quality scores
    │
    ▼
mosdepth                - coverage QC; samples below threshold are excluded
    │
    ▼
HaplotypeCaller         - call variants in GVCF mode (per sample, AS annotations)
    │
    ▼
GenomicsDBImport        - merge GVCFs across samples (scattered across 100 intervals)
    │
    ▼
GenotypeGVCFs           - joint genotyping (per interval shard)
    │
    ▼
Variant filtering       - hard filtering (default) or AS-VQSR (--vqsr, large cohorts)
    │
    ▼
cohort.filtered.vcf.gz
```

---

## Requirements

- [Nextflow](https://www.nextflow.io/) ≥ 23.04
- [Docker](https://www.docker.com/)
- Java 11 or later (required by Nextflow)

---

## Quick start

**Small cohort / demo (hard filtering):**

```bash
nextflow run main.nf \
  -profile local \
  --input   sample_sheet.tsv \
  --ref     /path/to/GRCh38.fa \
  --outdir  results \
  --dbsnp   /path/to/dbsnp138.vcf.gz \
  --mills   /path/to/mills.vcf.gz \
  --onekg   /path/to/1000G_phase1.snps.hg38.vcf.gz \
  --intervals_dir /path/to/scattered_intervals/
```

**Large cohort with AS-VQSR (≥30 samples recommended):**

```bash
nextflow run main.nf \
  -profile aws \
  --input   sample_sheet.tsv \
  --ref     s3://your-bucket/ref/GRCh38.fa \
  --outdir  s3://your-bucket/results \
  --dbsnp   s3://your-bucket/known-sites/dbsnp138.vcf.gz \
  --mills   s3://your-bucket/known-sites/mills.vcf.gz \
  --onekg   s3://your-bucket/known-sites/1000G_phase1.snps.hg38.vcf.gz \
  --hapmap  s3://your-bucket/known-sites/hapmap_3.3.hg38.vcf.gz \
  --omni    s3://your-bucket/known-sites/1000G_omni2.5.hg38.vcf.gz \
  --intervals_dir s3://your-bucket/intervals/ \
  --vqsr
```

`--hapmap` and `--omni` are required when `--vqsr` is set; they are the truth/training resources for the SNP recalibration model.

---

## Input

### Sample sheet

Tab-separated, with header. One row per sample.

```
sample_id	bam
HG001	/path/to/HG001.bam
HG002	/path/to/HG002.bam
HG003	/path/to/HG003.bam
```

BAI index files must exist alongside each BAM (`<bam>.bai`).

### Reference files

| File | Description | Required |
|------|-------------|----------|
| `--ref` | GRCh38 reference FASTA (must have `.fai` and `.dict`) | Yes |
| `--dbsnp` | `Homo_sapiens_assembly38.dbsnp138.vcf.gz` | Yes |
| `--mills` | `Mills_and_1000G_gold_standard.indels.hg38.vcf.gz` | Yes |
| `--onekg` | `1000G_phase1.snps.high_confidence.hg38.vcf.gz` | Yes |
| `--hapmap` | `hapmap_3.3.hg38.vcf.gz` | AS-VQSR only |
| `--omni` | `1000G_omni2.5.hg38.vcf.gz` | AS-VQSR only |

All GATK resource bundle files are available from the [Broad public bucket](https://console.cloud.google.com/storage/browser/genomics-public-data/resources/broad/hg38/v0).

### Scatter intervals

The pipeline scatters GenomicsDBImport and GenotypeGVCFs across 100 interval shards. Generate them once with:

```bash
gatk SplitIntervals \
  -R GRCh38.fa \
  --scatter-count 100 \
  -O intervals/
```

Then pass the output directory with `--intervals_dir intervals/`.

---

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--input` | *required* | Path to sample sheet TSV |
| `--ref` | *required* | Path/URI to reference FASTA |
| `--outdir` | `results` | Output directory |
| `--dbsnp` | *required* | dbSNP VCF |
| `--mills` | *required* | Mills indels VCF |
| `--onekg` | *required* | 1000G SNPs VCF |
| `--hapmap` | - | HapMap VCF (AS-VQSR only) |
| `--omni` | - | Omni VCF (AS-VQSR only) |
| `--intervals_dir` | *required* | Directory of scattered `.interval_list` files |
| `--vqsr` | `false` | Use AS-VQSR instead of hard filtering |
| `--optical_dup_pixel_dist` | `2500` | `2500` for patterned flowcells (NovaSeq); `100` for unpatterned |

---

## Profiles

| Profile | Executor | Use case |
|---------|----------|----------|
| `local` | Local machine | Development and testing |
| `aws` | AWS Batch | Production runs |

```bash
# Run locally
nextflow run main.nf -profile local ...

# Run on AWS Batch
nextflow run main.nf -profile aws ...
```

---

## Output

```
results/
├── markdup/
│   ├── HG001.markdup.bam
│   └── HG001.markdup_metrics.txt
├── bqsr/
│   └── HG001.bqsr.bam
├── qc/
│   └── HG001.mosdepth.summary.txt
├── gvcfs/
│   └── HG001.g.vcf.gz
├── genomicsdb/
│   └── shard_001/ ... shard_100/
├── genotyped/
│   └── shard_001.genotyped.vcf.gz ... shard_100.genotyped.vcf.gz
└── filtered/
    └── cohort.filtered.vcf.gz
```

---

## Demo dataset

Public demo runs use three [GIAB](https://www.nist.gov/programs-projects/genome-bottle) reference samples (HG001/HG002/HG003), which are freely available and have NIST-validated truth variant sets for benchmarking call accuracy.

---

## Containers

All processes run in pinned Docker images. No local tool installation required beyond Nextflow and Docker.

| Process | Image |
|---------|-------|
| MarkDuplicates, BQSR, HaplotypeCaller, GenomicsDBImport, GenotypeGVCFs, GatherVcfs, VQSR, HardFilter, ValidateVcf | `broadinstitute/gatk:4.5.0.0` |
| mosdepth | `quay.io/biocontainers/mosdepth:0.3.8--hd299d5a_0` |
| VcfStats | `quay.io/biocontainers/bcftools:1.18--h8b25389_0` |
