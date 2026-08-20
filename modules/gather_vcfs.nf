// ============================================================
// GATHER_VCFS
// Merges the 100 per-shard genotyped VCFs into a single cohort VCF.
// Input must be sorted by shard name (genomic order) before calling.
//
// Input channel item:  tuple([vcf_list], [tbi_list])
// Output channel item: tuple(cohort_vcf, cohort_tbi)
// ============================================================

process GATHER_VCFS {

    container 'broadinstitute/gatk:4.5.0.0'

    label 'cpu_4'
    label 'mem_16g'
    label 'time_12h'

    publishDir "${params.outdir}/filtered", mode: 'copy'

    input:
    tuple path(vcfs), path(tbis)

    output:
    tuple path("cohort.raw.vcf.gz"), path("cohort.raw.vcf.gz.tbi")

    script:
    def input_args = (vcfs instanceof List ? vcfs : [vcfs])
        .collect { "--INPUT ${it}" }
        .join(" \\\n        ")
    """
    gatk GatherVcfs \\
        ${input_args} \\
        --OUTPUT cohort.raw.vcf.gz \\
        --TMP_DIR . \\
        --java-options "-Xmx12g"

    gatk IndexFeatureFile --input cohort.raw.vcf.gz
    """
}
