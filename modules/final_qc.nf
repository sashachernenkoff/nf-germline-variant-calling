// ============================================================
// VALIDATE_VCF
// Structural validation of the final filtered VCF and generation
// of a sites-only VCF for downstream annotation workflows.
//
// Input channel item:  tuple(filtered_vcf, filtered_tbi)
// Output channel item: tuple(sites_only_vcf, sites_only_tbi)
// ============================================================

process VALIDATE_VCF {

    container 'broadinstitute/gatk:4.5.0.0'

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
    tuple path("cohort.filtered.sites_only.vcf.gz"), path("cohort.filtered.sites_only.vcf.gz.tbi")

    script:
    """
    gatk ValidateVariants \\
        --reference ${ref} \\
        --variant ${vcf} \\
        --validation-type-to-exclude ALLELES \\
        --java-options "-Xmx12g"

    gatk MakeSitesOnlyVcf \\
        --INPUT ${vcf} \\
        --OUTPUT cohort.filtered.sites_only.vcf.gz \\
        --java-options "-Xmx12g"

    gatk IndexFeatureFile --input cohort.filtered.sites_only.vcf.gz
    """
}


// ============================================================
// VCF_STATS
// bcftools stats on the final filtered VCF. Produces a summary
// report and PASS-only SNP/INDEL counts written to stdout
// (captured automatically by Nextflow to the work dir log).
//
// Input channel item:  tuple(filtered_vcf, filtered_tbi)
// Output channel item: path(stats_file)
// ============================================================

process VCF_STATS {

    container 'quay.io/biocontainers/bcftools:1.18--h8b25389_0'

    label 'cpu_4'
    label 'mem_16g'
    label 'time_12h'

    publishDir "${params.outdir}/filtered", mode: 'copy'

    input:
    tuple path(vcf), path(vcf_tbi)

    output:
    path "cohort.filtered.stats.txt"

    script:
    """
    bcftools stats --threads ${task.cpus} ${vcf} > cohort.filtered.stats.txt

    echo ""
    echo "--- PASS variant counts ---"
    echo -n "  SNPs (PASS):   "
    bcftools view --type snps --apply-filters PASS ${vcf} | \\
        bcftools stats | grep "^SN.*number of SNPs" | awk '{print \$4}'
    echo -n "  INDELs (PASS): "
    bcftools view --type indels --apply-filters PASS ${vcf} | \\
        bcftools stats | grep "^SN.*number of indels" | awk '{print \$4}'
    """
}
