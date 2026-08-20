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

    // --------------------------------------------------------
    // Sample channel - one tuple per row of the sample sheet.
    // --------------------------------------------------------

    samples_ch = Channel
        .fromPath(params.input, checkIfExists: true)
        .splitCsv(header: true, sep: '\t')
        .map { row -> tuple(row.sample_id, file(row.bam), file(row.bam + '.bai')) }

    // --------------------------------------------------------
    // Reference file channels - Channel.value() emits the same
    // file(s) to every process invocation without re-staging.
    // Index files are paired with their parent so Nextflow stages
    // both into the same work directory; GATK finds them automatically.
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
    // Step 1: MarkDuplicates
    // --------------------------------------------------------

    markdup_ch = MARK_DUPLICATES(samples_ch)

    // --------------------------------------------------------
    // Step 2: BQSR
    // --------------------------------------------------------

    bqsr_ch = BQSR(
        markdup_ch,
        ref_ch,
        ref_fai_ch,
        ref_dict_ch,
        dbsnp_ch,
        mills_ch,
        onekg_ch
    )

    // --------------------------------------------------------
    // Step 3: mosdepth coverage QC
    // --------------------------------------------------------

    mosdepth_ch = MOSDEPTH(bqsr_ch)

    // --------------------------------------------------------
    // Coverage filter (replaces the 03b collect_qc shell script).
    // Join bqsr output with mosdepth summary on sample_id, parse
    // mean coverage from the summary file, drop failing samples.
    // --------------------------------------------------------

    pass_bqsr_ch = bqsr_ch
        .join(mosdepth_ch.summary)
        .filter { sample_id, bam, bai, summary ->
            def mean_cov = summary.text
                .readLines()
                .find { it.startsWith('total') }
                ?.split('\t')[3]
                ?.toFloat() ?: 0
            if (mean_cov < params.min_coverage) {
                log.warn "COVERAGE FAIL: ${sample_id} mean coverage ${mean_cov}x < ${params.min_coverage}x - excluded from variant calling"
                return false
            }
            return true
        }
        .map { sample_id, bam, bai, summary -> tuple(sample_id, bam, bai) }

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
    // Scatter setup: collect all GVCFs, combine with intervals.
    //
    // gvcf_ch emits N items (one per sample). After collect(),
    // one item is emitted: a list of [gvcf, tbi] pairs.
    // The .map() separates those into two flat lists.
    // combine() pairs each of the 100 intervals with both lists,
    // producing 100 channel items - one GenomicsDBImport job each.
    // --------------------------------------------------------

    collected_ch = gvcf_ch
        .map { sample_id, gvcf, tbi -> [ gvcf, tbi ] }
        .collect()
        .map { pairs -> [ pairs.collect { it[0] }, pairs.collect { it[1] } ] }

    intervals_ch = Channel
        .fromPath("${params.intervals_dir}/*.interval_list", checkIfExists: true)
        .map { f -> tuple(f.baseName, f) }

    // --------------------------------------------------------
    // Step 5: GenomicsDBImport - one job per interval shard
    // --------------------------------------------------------

    genomicsdb_ch = GENOMICS_DB_IMPORT(
        intervals_ch.combine(collected_ch)
    )

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
    // Gather: collect all 100 shard VCFs sorted by shard name
    // (alphabetical = genomic order from SplitIntervals naming).
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
