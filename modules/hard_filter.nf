// ============================================================
// HARD_FILTER
// GATK recommended hard filters for small cohorts where VQSR
// lacks sufficient training data. Applies separate filter
// expressions to SNPs and INDELs then merges the results.
//
// Input channel item:  tuple(cohort_vcf, cohort_tbi)
// Output channel item: tuple(filtered_vcf, filtered_tbi)
// ============================================================

process HARD_FILTER {

    container params.gatk_container

    label 'cpu_4'
    label 'mem_16g'
    label 'time_12h'

    publishDir "${params.outdir}/filtered", mode: 'copy'

    input:
    tuple path(vcf), path(vcf_tbi)
    path ref
    path ref_fai
    path ref_dict

    output:
    tuple path("cohort.filtered.vcf.gz"), path("cohort.filtered.vcf.gz.tbi")

    script:
    """
    # --- Select and filter SNPs ---
    gatk SelectVariants \\
        --reference ${ref} \\
        --variant ${vcf} \\
        --select-type-to-include SNP \\
        --output snps.vcf.gz \\
        --tmp-dir . \\
        --java-options "-Xmx12g"

    gatk VariantFiltration \\
        --reference ${ref} \\
        --variant snps.vcf.gz \\
        --filter-expression "QD < 2.0"            --filter-name "QD2" \\
        --filter-expression "MQ < 40.0"           --filter-name "MQ40" \\
        --filter-expression "FS > 60.0"           --filter-name "FS60" \\
        --filter-expression "SOR > 3.0"           --filter-name "SOR3" \\
        --filter-expression "MQRankSum < -12.5"   --filter-name "MQRankSum-12.5" \\
        --filter-expression "ReadPosRankSum < -8.0" --filter-name "ReadPosRankSum-8" \\
        --output snps.filtered.vcf.gz \\
        --tmp-dir . \\
        --java-options "-Xmx12g"

    # --- Select and filter INDELs ---
    gatk SelectVariants \\
        --reference ${ref} \\
        --variant ${vcf} \\
        --select-type-to-include INDEL \\
        --output indels.vcf.gz \\
        --tmp-dir . \\
        --java-options "-Xmx12g"

    gatk VariantFiltration \\
        --reference ${ref} \\
        --variant indels.vcf.gz \\
        --filter-expression "QD < 2.0"              --filter-name "QD2" \\
        --filter-expression "FS > 200.0"            --filter-name "FS200" \\
        --filter-expression "SOR > 10.0"            --filter-name "SOR10" \\
        --filter-expression "ReadPosRankSum < -20.0" --filter-name "ReadPosRankSum-20" \\
        --output indels.filtered.vcf.gz \\
        --tmp-dir . \\
        --java-options "-Xmx12g"

    # --- Merge filtered SNPs and INDELs ---
    gatk MergeVcfs \\
        --INPUT snps.filtered.vcf.gz \\
        --INPUT indels.filtered.vcf.gz \\
        --OUTPUT cohort.filtered.vcf.gz \\
        --TMP_DIR . \\
        --java-options "-Xmx12g"
    """
}
