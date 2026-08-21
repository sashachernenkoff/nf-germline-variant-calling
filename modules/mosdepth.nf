// ============================================================
// MOSDEPTH
// Per-sample coverage QC. The summary file is consumed downstream
// in main.nf to filter samples below the coverage threshold.
//
// Input channel item:  tuple(sample_id, bam, bai)
// Output channel item: tuple(sample_id, summary_txt)
// ============================================================

process MOSDEPTH {

    container params.mosdepth_container

    tag "${sample_id}"

    label 'cpu_8'
    label 'mem_16g'
    label 'time_12h'

    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    tuple val(sample_id), path(bam), path(bai)
    path interval_lists

    output:
    tuple val(sample_id), path("${sample_id}.mosdepth.summary.txt"), emit: summary
    path "${sample_id}.mosdepth.*"

    script:
    """
    # BED of the calling regions, so coverage is measured where variants
    # are actually called (reported as the summary's total_region row).
    cat ${interval_lists} \\
        | grep -v '^@' \\
        | awk 'BEGIN{OFS="\\t"} {print \$1, \$2-1, \$3}' \\
        | sort -k1,1 -k2,2n > targets.bed

    mosdepth \\
        --threads ${task.cpus} \\
        --no-per-base \\
        --by targets.bed \\
        ${sample_id} \\
        ${bam}
    """
}
