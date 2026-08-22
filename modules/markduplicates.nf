// ============================================================
// MARK_DUPLICATES
// Input channel item:  tuple(sample_id, bam_file, bai_file)
// Output channel item: tuple(sample_id, markdup_bam, markdup_bai)
// ============================================================

process MARK_DUPLICATES {

    container params.gatk_container

    tag "${sample_id}"          // labels log lines: [MARK_DUPLICATES/HG001]

    label 'cpu_8'
    label 'mem_32g'
    label 'time_24h'

    // Publish only the QC metrics; the BAM flows to BQSR via the work dir.
    publishDir "${params.outdir}/markdup", mode: 'copy', pattern: '*_metrics.txt'

    input:
    tuple val(sample_id), path(bam), path(bai)   // bai staged alongside bam so GATK can find it

    output:
    tuple val(sample_id), path("${sample_id}.markdup.bam"), path("${sample_id}.markdup.bai"), emit: bam
    path "${sample_id}.markdup_metrics.txt",                                                   emit: metrics

    script:
    """
    gatk MarkDuplicates \\
        --INPUT ${bam} \\
        --OUTPUT ${sample_id}.markdup.bam \\
        --METRICS_FILE ${sample_id}.markdup_metrics.txt \\
        --REMOVE_DUPLICATES false \\
        --OPTICAL_DUPLICATE_PIXEL_DISTANCE ${params.optical_dup_pixel_dist} \\
        --CREATE_INDEX true \\
        --TMP_DIR . \\
        --java-options "-Xmx${(task.memory.toGiga() - 2).intValue()}g"
    """
}
