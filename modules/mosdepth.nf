// ============================================================
// MOSDEPTH
// Per-sample coverage QC. The summary file is consumed downstream
// in main.nf to filter samples below the coverage threshold.
//
// Input channel item:  tuple(sample_id, bam, bai)
// Output channel item: tuple(sample_id, summary_txt)
// ============================================================

process MOSDEPTH {

    container 'quay.io/biocontainers/mosdepth:0.3.8--hd299d5a_0'

    tag "${sample_id}"

    label 'cpu_8'
    label 'mem_16g'
    label 'time_12h'

    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    tuple val(sample_id), path(bam), path(bai)

    output:
    tuple val(sample_id), path("${sample_id}.mosdepth.summary.txt"), emit: summary
    path "${sample_id}.mosdepth.*"

    script:
    """
    mosdepth \\
        --threads ${task.cpus} \\
        --no-per-base \\
        --quantize 0:5:15:20:500: \\
        ${sample_id} \\
        ${bam}
    """
}
