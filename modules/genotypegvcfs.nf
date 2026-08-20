// ============================================================
// GENOTYPE_GVCFS
// Joint genotyping from GenomicsDB, one job per interval shard.
//
// Input channel item:  tuple(shard_name, genomicsdb_dir)
// Output channel item: tuple(shard_name, vcf, vcf_tbi)
// ============================================================

process GENOTYPE_GVCFS {

    container 'broadinstitute/gatk:4.5.0.0'

    tag "${shard_name}"

    label 'cpu_4'
    label 'mem_64g'
    label 'time_72h'

    publishDir "${params.outdir}/genotyped", mode: 'copy'

    input:
    tuple val(shard_name), path(genomicsdb)
    path ref
    path ref_fai
    path ref_dict
    tuple path(dbsnp), path(dbsnp_tbi)

    output:
    tuple val(shard_name), path("${shard_name}.genotyped.vcf.gz"), path("${shard_name}.genotyped.vcf.gz.tbi")

    script:
    """
    gatk GenotypeGVCFs \\
        --reference ${ref} \\
        --variant gendb://${genomicsdb} \\
        --output ${shard_name}.genotyped.vcf.gz \\
        --dbsnp ${dbsnp} \\
        -G StandardAnnotation \\
        -G AS_StandardAnnotation \\
        --tmp-dir . \\
        --java-options "-Xmx56g -XX:ParallelGCThreads=4"
    """
}
