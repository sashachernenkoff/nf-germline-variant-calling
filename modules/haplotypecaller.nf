// ============================================================
// HAPLOTYPE_CALLER
// Per-sample variant calling in GVCF mode with allele-specific
// annotations required for AS-VQSR downstream.
//
// Input channel item:  tuple(sample_id, bam, bai)
// Output channel item: tuple(sample_id, gvcf, gvcf_tbi)
// ============================================================

process HAPLOTYPE_CALLER {

    container 'broadinstitute/gatk:4.5.0.0'

    tag "${sample_id}"

    label 'cpu_4'
    label 'mem_32g'
    label 'time_48h'

    publishDir "${params.outdir}/gvcfs", mode: 'copy'

    input:
    tuple val(sample_id), path(bam), path(bai)
    path ref
    path ref_fai
    path ref_dict
    tuple path(dbsnp), path(dbsnp_tbi)

    output:
    tuple val(sample_id), path("${sample_id}.g.vcf.gz"), path("${sample_id}.g.vcf.gz.tbi")

    script:
    """
    gatk HaplotypeCaller \\
        --input ${bam} \\
        --output ${sample_id}.g.vcf.gz \\
        --reference ${ref} \\
        --dbsnp ${dbsnp} \\
        --emit-ref-confidence GVCF \\
        --pcr-indel-model CONSERVATIVE \\
        --sample-ploidy 2 \\
        --native-pair-hmm-threads ${task.cpus} \\
        -G StandardAnnotation \\
        -G AS_StandardAnnotation \\
        -G StandardHCAnnotation \\
        --tmp-dir . \\
        --java-options "-Xmx28g -XX:ParallelGCThreads=4"
    """
}
