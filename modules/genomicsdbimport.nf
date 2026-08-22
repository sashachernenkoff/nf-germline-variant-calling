// ============================================================
// GENOMICS_DB_IMPORT
// Merge per-sample GVCFs into a GenomicsDB workspace, one job per
// interval shard (each shard receives all sample GVCFs).
//
// in:  (shard_name, interval), gvcfs list, tbis list
// out: (shard_name, genomicsdb_dir)
// ============================================================

process GENOMICS_DB_IMPORT {

    container params.gatk_container

    tag "${shard_name}"

    label 'cpu_4'
    label 'mem_32g'
    label 'time_72h'

    input:
    tuple val(shard_name), path(interval)
    path gvcfs
    path tbis

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
        --java-options "-Xmx${(task.memory.toGiga() - 2).intValue()}g"
    """
}
