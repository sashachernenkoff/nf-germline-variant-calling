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

include { NORMALIZE_BAM      } from './modules/normalize'
include { MARK_DUPLICATES    } from './modules/markduplicates'
include { BQSR               } from './modules/bqsr'
include { MOSDEPTH           } from './modules/mosdepth'
include { HAPLOTYPE_CALLER   } from './modules/haplotypecaller'
include { GENOMICS_DB_IMPORT } from './modules/genomicsdbimport'
include { GENOTYPE_GVCFS     } from './modules/genotypegvcfs'
include { GATHER_VCFS        } from './modules/gather_vcfs'
include { VQSR               } from './modules/vqsr'
include { HARD_FILTER        } from './modules/hard_filter'
include { VALIDATE_VCF       } from './modules/final_qc'
include { VCF_STATS          } from './modules/final_qc'

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

    check_required(params.input,         'input')
    check_required(params.ref,           'ref')
    check_required(params.dbsnp,         'dbsnp')
    check_required(params.mills,         'mills')
    check_required(params.onekg,         'onekg')
    check_required(params.intervals_dir, 'intervals_dir')
    if (params.vqsr) {
        check_required(params.hapmap, 'hapmap')
        check_required(params.omni,   'omni')
    }

    // AWS Batch deployment settings (from env vars or --params); see conf/aws.config
    if (workflow.profile.tokenize(',').contains('aws')) {
        check_required(params.ecr_registry,   'ecr_registry (set NF_ECR_REGISTRY)')
        check_required(params.batch_queue,    'batch_queue (set NF_BATCH_QUEUE)')
        check_required(params.batch_job_role, 'batch_job_role (set NF_BATCH_JOB_ROLE)')
    }

    // --------------------------------------------------------
    // Sample channel - one tuple per row of the sample sheet.
    // --------------------------------------------------------

    samples_ch = Channel
        .fromPath(params.input, checkIfExists: true)
        .splitCsv(header: true, sep: '\t')
        .map { row -> tuple(row.sample_id, file(row.bam), file(row.bam + '.bai')) }

    // --------------------------------------------------------
    // Reference and known-sites value channels (reused across all
    // samples). Index/dict files travel with their parent file.
    // --------------------------------------------------------

    ref_ch      = Channel.value(file(params.ref))
    ref_fai_ch  = Channel.value(file(params.ref + '.fai'))
    ref_dict_ch = Channel.value(file(params.ref.replaceAll('\\.fa(sta)?$', '.dict')))

    dbsnp_ch = Channel.value([ file(params.dbsnp), file(params.dbsnp + '.tbi') ])
    mills_ch = Channel.value([ file(params.mills),  file(params.mills  + '.tbi') ])
    onekg_ch = Channel.value([ file(params.onekg),  file(params.onekg  + '.tbi') ])

    hapmap_ch = params.vqsr
        ? Channel.value([ file(params.hapmap), file(params.hapmap + '.tbi') ])
        : Channel.empty()
    omni_ch = params.vqsr
        ? Channel.value([ file(params.omni), file(params.omni + '.tbi') ])
        : Channel.empty()

    // --------------------------------------------------------
    // Preprocessing: normalise every input BAM (coordinate sort +
    // ensure a read group + index) so the downstream GATK steps get
    // valid input, whatever state the aligner produced.
    // --------------------------------------------------------

    normalized_ch = NORMALIZE_BAM(samples_ch)

    // --------------------------------------------------------
    // Step 1: MarkDuplicates
    // --------------------------------------------------------

    markdup_ch = MARK_DUPLICATES(normalized_ch.bam)

    // --------------------------------------------------------
    // Step 2: BQSR
    // --------------------------------------------------------

    bqsr_ch = BQSR(
        markdup_ch.bam,
        ref_ch,
        ref_fai_ch,
        ref_dict_ch,
        dbsnp_ch,
        mills_ch,
        onekg_ch
    )

    // --------------------------------------------------------
    // Step 3: mosdepth coverage QC, measured over the calling regions
    // so the threshold reflects depth where variants are called.
    // --------------------------------------------------------

    target_intervals_ch = Channel
        .fromPath("${params.intervals_dir}/*.interval_list", checkIfExists: true)
        .collect()

    mosdepth_ch = MOSDEPTH(bqsr_ch, target_intervals_ch)

    // --------------------------------------------------------
    // Coverage filter: join BQSR output with mosdepth summary on
    // sample_id, read the mean depth over the target regions
    // (total_region row), drop samples below threshold. Fail fast if
    // no sample survives, rather than passing an empty cohort downstream.
    // --------------------------------------------------------

    pass_bqsr_ch = bqsr_ch
        .join(mosdepth_ch.summary)
        .filter { sample_id, bam, bai, summary ->
            def mean_cov = summary.text
                .readLines()
                .find { it.startsWith('total_region') }
                ?.split('\t')[3]
                ?.toFloat() ?: 0
            if (mean_cov < params.min_coverage) {
                log.warn "COVERAGE FAIL: ${sample_id} mean coverage ${mean_cov}x < ${params.min_coverage}x - excluded from variant calling"
                return false
            }
            return true
        }
        .map { sample_id, bam, bai, summary -> tuple(sample_id, bam, bai) }
        .ifEmpty { error "No samples passed the coverage filter (min_coverage=${params.min_coverage}x); nothing to genotype." }

    // --------------------------------------------------------
    // Step 4: HaplotypeCaller - per sample, coverage-filtered
    // --------------------------------------------------------

    gvcf_ch = HAPLOTYPE_CALLER(
        pass_bqsr_ch,
        ref_ch,
        ref_fai_ch,
        ref_dict_ch,
        dbsnp_ch
    )

    // --------------------------------------------------------
    // Scatter setup: collect all sample GVCFs (and their indexes) into
    // flat lists, reused across every interval shard.
    // --------------------------------------------------------

    gvcfs_ch = gvcf_ch.map { sample_id, gvcf, tbi -> gvcf }.collect()
    tbis_ch  = gvcf_ch.map { sample_id, gvcf, tbi -> tbi }.collect()

    intervals_ch = Channel
        .fromPath("${params.intervals_dir}/*.interval_list", checkIfExists: true)
        .map { f -> tuple(f.baseName, f) }

    // --------------------------------------------------------
    // Step 5: GenomicsDBImport - one job per interval shard
    // --------------------------------------------------------

    genomicsdb_ch = GENOMICS_DB_IMPORT(intervals_ch, gvcfs_ch, tbis_ch)

    // --------------------------------------------------------
    // Step 6: GenotypeGVCFs - one job per interval shard
    // --------------------------------------------------------

    genotyped_ch = GENOTYPE_GVCFS(
        genomicsdb_ch,
        ref_ch,
        ref_fai_ch,
        ref_dict_ch,
        dbsnp_ch
    )

    // --------------------------------------------------------
    // Gather per-shard VCFs in genomic order (shard names from
    // SplitIntervals sort into genomic order).
    // --------------------------------------------------------

    gathered_input_ch = genotyped_ch
        .toSortedList { a, b -> a[0] <=> b[0] }
        .map { shards -> [ shards.collect { it[1] }, shards.collect { it[2] } ] }

    gathered_ch = GATHER_VCFS(gathered_input_ch)

    // --------------------------------------------------------
    // Step 7: Variant filtering - VQSR or hard filter
    // --------------------------------------------------------

    filtered_ch = params.vqsr
        ? VQSR(gathered_ch, ref_ch, ref_fai_ch, ref_dict_ch, dbsnp_ch, mills_ch, onekg_ch, hapmap_ch, omni_ch)
        : HARD_FILTER(gathered_ch, ref_ch, ref_fai_ch, ref_dict_ch)

    // --------------------------------------------------------
    // Step 8: Final QC - runs in parallel on the filtered VCF
    // --------------------------------------------------------

    VALIDATE_VCF(filtered_ch, ref_ch, ref_fai_ch, ref_dict_ch)
    VCF_STATS(filtered_ch)

}
