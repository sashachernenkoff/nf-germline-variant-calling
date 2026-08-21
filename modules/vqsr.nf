// ============================================================
// VQSR
// Allele-specific VQSR: SNP pass followed by INDEL pass.
// Requires a large cohort (>=30 samples recommended for SNPs).
// Enable with --vqsr; requires --hapmap and --omni in addition
// to the standard known-sites resources.
//
// Input channel item:  tuple(cohort_vcf, cohort_tbi)
// Output channel item: tuple(filtered_vcf, filtered_tbi)
// ============================================================

process VQSR {

    container 'broadinstitute/gatk:4.5.0.0'

    label 'cpu_4'
    label 'mem_64g'
    label 'time_24h'

    publishDir "${params.outdir}/filtered", mode: 'copy'

    input:
    tuple path(vcf), path(vcf_tbi)
    path ref
    path ref_fai
    path ref_dict
    tuple path(dbsnp),  path(dbsnp_tbi)
    tuple path(mills),  path(mills_tbi)
    tuple path(onekg),  path(onekg_tbi)
    tuple path(hapmap), path(hapmap_tbi)
    tuple path(omni),   path(omni_tbi)

    output:
    tuple path("cohort.filtered.vcf.gz"), path("cohort.filtered.vcf.gz.tbi")

    script:
    """
    # --- SNP AS-VQSR ---
    gatk VariantRecalibrator \\
        --reference ${ref} \\
        --variant ${vcf} \\
        --use-allele-specific-annotations \\
        --resource:hapmap,known=false,training=true,truth=true,prior=15.0 ${hapmap} \\
        --resource:omni,known=false,training=true,truth=false,prior=12.0 ${omni} \\
        --resource:1000G,known=false,training=true,truth=false,prior=10.0 ${onekg} \\
        --resource:dbsnp,known=true,training=false,truth=false,prior=2.0 ${dbsnp} \\
        --use-annotation AS_QD \\
        --use-annotation AS_MQRankSum \\
        --use-annotation AS_ReadPosRankSum \\
        --use-annotation AS_FS \\
        --use-annotation AS_SOR \\
        --use-annotation AS_MQ \\
        --mode SNP \\
        --truth-sensitivity-tranche 100.0 \\
        --truth-sensitivity-tranche 99.9 \\
        --truth-sensitivity-tranche 99.0 \\
        --truth-sensitivity-tranche 95.0 \\
        --output cohort.snp.recal \\
        --tranches-file cohort.snp.tranches \\
        --tmp-dir . \\
        --java-options "-Xmx${(task.memory.toGiga() - 2).intValue()}g"

    gatk ApplyVQSR \\
        --reference ${ref} \\
        --variant ${vcf} \\
        --output cohort.snp_applied.vcf.gz \\
        --use-allele-specific-annotations \\
        --recal-file cohort.snp.recal \\
        --tranches-file cohort.snp.tranches \\
        --truth-sensitivity-filter-level 99.0 \\
        --mode SNP \\
        --tmp-dir . \\
        --java-options "-Xmx${(task.memory.toGiga() - 2).intValue()}g"

    # --- INDEL AS-VQSR ---
    gatk VariantRecalibrator \\
        --reference ${ref} \\
        --variant cohort.snp_applied.vcf.gz \\
        --use-allele-specific-annotations \\
        --resource:mills,known=false,training=true,truth=true,prior=12.0 ${mills} \\
        --resource:dbsnp,known=true,training=false,truth=false,prior=2.0 ${dbsnp} \\
        --use-annotation AS_QD \\
        --use-annotation AS_MQRankSum \\
        --use-annotation AS_ReadPosRankSum \\
        --use-annotation AS_FS \\
        --use-annotation AS_SOR \\
        --mode INDEL \\
        --max-gaussians 4 \\
        --truth-sensitivity-tranche 100.0 \\
        --truth-sensitivity-tranche 99.9 \\
        --truth-sensitivity-tranche 99.0 \\
        --truth-sensitivity-tranche 95.0 \\
        --output cohort.indel.recal \\
        --tranches-file cohort.indel.tranches \\
        --tmp-dir . \\
        --java-options "-Xmx${(task.memory.toGiga() - 2).intValue()}g"

    gatk ApplyVQSR \\
        --reference ${ref} \\
        --variant cohort.snp_applied.vcf.gz \\
        --output cohort.filtered.vcf.gz \\
        --use-allele-specific-annotations \\
        --recal-file cohort.indel.recal \\
        --tranches-file cohort.indel.tranches \\
        --truth-sensitivity-filter-level 99.0 \\
        --mode INDEL \\
        --tmp-dir . \\
        --java-options "-Xmx${(task.memory.toGiga() - 2).intValue()}g"
    """
}
