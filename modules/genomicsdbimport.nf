// ============================================================
// GENOMICS_DB_IMPORT
// Merges per-sample GVCFs into a GenomicsDB workspace, scattered
// across interval shards. Each shard receives all sample GVCFs.
//
// Input channel item:  tuple(shard_name, interval, [gvcfs], [tbis])
// Output channel item: tuple(shard_name, genomicsdb_dir)
//
// The variant_args block builds one --variant flag per GVCF using
// a Groovy expression inside the script string.
// ============================================================

process GENOMICS_DB_IMPORT {

    container 'broadinstitute/gatk:4.5.0.0'

    tag "${shard_name}"

    label 'cpu_4'
    label 'mem_32g'
    label 'time_72h'

    input:
    tuple val(shard_name), path(interval), path(gvcfs), path(tbis)

    output:
    tuple val(shard_name), path("gendb_${shard_name}")

    script:
    def variant_args = (gvcfs instanceof List ? gvcfs : [gvcfs])
        .collect { "-V ${it}" }
        .join(" \\\n        ")
    """
    gatk GenomicsDBImport \\
        ${variant_args} \\
        --genomicsdb-workspace-path gendb_${shard_name} \\
        -L ${interval} \\
        --batch-size 50 \\
        --genomicsdb-shared-posixfs-optimizations true \\
        --tmp-dir . \\
        --java-options "-Xmx24g -XX:ParallelGCThreads=2"
    """
}
