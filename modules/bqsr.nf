// ============================================================
// BQSR
// BaseRecalibrator → ApplyBQSR (per sample)
//
// Input channel item:  tuple(sample_id, bam, bai)
// Output channel item: tuple(sample_id, bqsr_bam, bqsr_bai)
//
// Reference files are passed as Channel.value() in main.nf -
// the same files are reused across all samples without re-staging.
// ============================================================

process BQSR {

    container params.gatk_container

    tag "${sample_id}"

    label 'cpu_8'
    label 'mem_32g'
    label 'time_24h'

    publishDir "${params.outdir}/bqsr", mode: 'copy'

    input:
    tuple val(sample_id), path(bam), path(bai)
    path ref
    path ref_fai      // staged alongside ref so GATK can find the index
    path ref_dict     // staged alongside ref so GATK can find the sequence dictionary
    tuple path(dbsnp), path(dbsnp_tbi)
    tuple path(mills), path(mills_tbi)
    tuple path(onekg), path(onekg_tbi)

    output:
    tuple val(sample_id), path("${sample_id}.bqsr.bam"), path("${sample_id}.bqsr.bai")

    script:
    """
    gatk BaseRecalibrator \\
        --input ${bam} \\
        --reference ${ref} \\
        --known-sites ${dbsnp} \\
        --known-sites ${mills} \\
        --known-sites ${onekg} \\
        --output ${sample_id}.recal.table \\
        --tmp-dir . \\
        --java-options "-Xmx${(task.memory.toGiga() - 2).intValue()}g"

    gatk ApplyBQSR \\
        --input ${bam} \\
        --reference ${ref} \\
        --bqsr-recal-file ${sample_id}.recal.table \\
        --output ${sample_id}.bqsr.bam \\
        --create-output-bam-index true \\
        --tmp-dir . \\
        --java-options "-Xmx${(task.memory.toGiga() - 2).intValue()}g"
    """
}
