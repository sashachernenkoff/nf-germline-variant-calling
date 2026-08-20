// ============================================================
// nf-germline-variant-calling
// GATK4 best-practices germline variant calling pipeline.
// Originally developed for the CPTAC LUAD cohort; demo runs on GIAB (HG001/HG002/HG003).
//
// Usage:
//   nextflow run main.nf -profile local \
//     --input  sample_sheet.tsv \
//     --ref    /path/to/GRCh38.fa \
//     --outdir results \
//     --dbsnp  /path/to/dbsnp138.vcf.gz \
//     --mills  /path/to/mills.vcf.gz \
//     --onekg  /path/to/1000G.vcf.gz \
//     --intervals_dir /path/to/scattered_intervals/
// ============================================================

nextflow.enable.dsl = 2

include { MARK_DUPLICATES } from './modules/markduplicates'

// ============================================================
// Input validation
// ============================================================

def check_required(param, name) {
    if (param == null) {
        error "Missing required parameter: --${name}"
    }
}

// ============================================================
// Workflow
// ============================================================

workflow {

    check_required(params.input,        'input')
    check_required(params.ref,          'ref')
    check_required(params.dbsnp,        'dbsnp')
    check_required(params.mills,        'mills')
    check_required(params.onekg,        'onekg')
    check_required(params.intervals_dir,'intervals_dir')

    // --------------------------------------------------------
    // Build the sample channel from the input TSV.
    //
    // Expected columns (tab-separated, with header):
    //   sample_id   bam   bai
    //
    // Each row becomes one tuple emitted into the channel.
    // This replaces the SLURM array index → manifest lookup.
    // --------------------------------------------------------

    samples_ch = Channel
        .fromPath(params.input, checkIfExists: true)
        .splitCsv(header: true, sep: '\t')
        .map { row -> tuple(row.sample_id, file(row.bam), file(row.bam + '.bai')) }

    // --------------------------------------------------------
    // Step 1: MarkDuplicates - runs once per sample in parallel.
    // --------------------------------------------------------

    markdup_ch = MARK_DUPLICATES(samples_ch)

    // Steps 2–8 will be added here as we build each module.
}
