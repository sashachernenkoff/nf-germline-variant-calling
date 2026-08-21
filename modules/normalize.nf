// ============================================================
// NORMALIZE_BAM
// Coordinate-sort the input BAM, ensure a read group (derived from the
// sample id only when absent, preserving existing ones), and index -
// so any input BAM is valid for the downstream GATK steps.
//
// in:  tuple(sample_id, bam, bai)
// out: tuple(sample_id, sorted_bam, sorted_bai)
// ============================================================

process NORMALIZE_BAM {

    container params.gatk_container

    tag "${sample_id}"

    label 'cpu_4'
    label 'mem_16g'
    label 'time_24h'

    input:
    tuple val(sample_id), path(bam), path(bai)

    output:
    tuple val(sample_id), path("${sample_id}.sorted.bam"), path("${sample_id}.sorted.bam.bai"), emit: bam

    script:
    """
    if samtools view -H ${bam} | grep -q '^@RG'; then
        # Read groups already present: just coordinate-sort.
        samtools sort -@ ${task.cpus} -m 1G -o ${sample_id}.sorted.bam ${bam}
    else
        # No read groups: add one derived from the sample id and
        # coordinate-sort in the same pass.
        gatk AddOrReplaceReadGroups \\
            --INPUT ${bam} \\
            --OUTPUT ${sample_id}.sorted.bam \\
            --SORT_ORDER coordinate \\
            --RGID ${sample_id} \\
            --RGSM ${sample_id} \\
            --RGLB ${sample_id} \\
            --RGPL ILLUMINA \\
            --RGPU ${sample_id} \\
            --TMP_DIR . \\
            --java-options "-Xmx${(task.memory.toGiga() - 2).intValue()}g"
    fi
    samtools index -@ ${task.cpus} ${sample_id}.sorted.bam
    """
}
