SPLIT_FILES_NUMBER = 100


def getSplitNumber():
    split = SPLIT_FILES_NUMBER

    if "global" in config:
        if "assignments" in config["global"]:
            if "split_number" in config["global"]["assignments"]:
                split = config["global"]["assignments"]["split_number"]

    return split


rule assignment_getInputs:
    input:
        lambda wc: config["assignments"][wc.assignment][wc.R],
    output:
        R1=temp("results/assignment/{assignment}/fastq/{R}.fastq.gz"),
    shell:
        """
        zcat {input} | gzip -c > {output}
        """


rule assignment_fastq_split:
    input:
        "results/assignment/{assignment}/fastq/{R}.fastq.gz",
    output:
        temp(
            expand(
                "results/assignment/{{assignment}}/fastq/splits/{{R}}.split{split}.fastq.gz",
                split=range(0, getSplitNumber()),
            ),
        ),
    conda:
        "../envs/fastqsplitter.yaml"
    params:
        files=lambda wc: " ".join(
            [
                "-o %s" % i
                for i in expand(
                    "results/assignment/{assignment}/fastq/splits/{R}.split{split}.fastq.gz",
                    assignment=wc.assignment,
                    R=wc.R,
                    split=range(0, getSplitNumber()),
                )
            ]
        ),
    shell:
        """
        fastqsplitter -i {input} -t 10 {params.files} 
        """


rule assignment_merge:
    input:
        R1="results/assignment/{assignment}/fastq/splits/R1.split{split}.fastq.gz",
        R2="results/assignment/{assignment}/fastq/splits/R2.split{split}.fastq.gz",
        R3="results/assignment/{assignment}/fastq/splits/R3.split{split}.fastq.gz",
    output:
        bam=temp("results/assignment/{assignment}/bam/merge_split{split}.bam"),
    conda:
        "../envs/mpraflow_py27.yaml"
    shell:
        """
        paste <( zcat {input.R1} ) <( zcat {input.R2} ) <( zcat {input.R3} ) | \
        awk '{{ 
            count+=1; 
            if ((count == 1) || (count == 3)) {{ 
                print $1 
            }} else {{
                print $1$2$3 
            }}; 
            if (count == 4) {{
                count=0 
            }} 
        }}' | \
        python {SCRIPTS_DIR}/count/FastQ2doubleIndexBAM.py -p -s 162 -l 15 -m 0 | \
        python {SCRIPTS_DIR}/count/MergeTrimReadsBAM.py -c '' -f CATTGCGTGAACCGACAATTCGTCGAGGGACCTAATAAC -s AGTTGATCCGGTCCTAGGTCTAGAGCGGGCCCTGGCAGA --mergeoverlap -p > {output}
        """


assignment_bwa_dicts = ["bwt", "sa", "pac", "ann", "amb"]


rule assignment_bwa_ref:
    input:
        lambda wc: config["assignments"][wc.assignment]["reference"],
    output:
        ref="results/assignment/{assignment}/reference/reference.fa",
        bwa=expand(
            "results/assignment/{{assignment}}/reference/reference.fa.{ext}",
            ext=["fai"] + assignment_bwa_dicts,
        ),
        d="results/assignment/{assignment}/reference/reference.fa.dict",
    conda:
        "../envs/bwa.yaml"
    shell:
        """
        cp {input} {output.ref};
        bwa index -a bwtsw {output.ref};
        samtools faidx {output.ref};
        picard CreateSequenceDictionary REFERENCE={output.ref} OUTPUT={output.d}
        """


rule assignment_mapping:
    input:
        bams=expand(
            "results/assignment/{{assignment}}/bam/merge_split{split}.bam",
            split=range(0, getSplitNumber()),
        ),
        reference="results/assignment/{assignment}/reference/reference.fa",
        bwa_index=expand(
            "results/assignment/{{assignment}}/reference/reference.fa.{ext}",
            ext=["fai", "dict"] + assignment_bwa_dicts,
        ),
    output:
        "results/assignment/{assignment}/aligned_merged_reads.bam",
    conda:
        "../envs/bwa.yaml"
    shell:
        """
        bwa mem -t 30 -L 80 -M -C {input.reference} <(
            samtools cat {input.bams} | \
            samtools view -F 514 | \
            awk 'BEGIN{{ OFS="\\n"; FS="\\t" }}{{ print "@"$1" "$12","$13,$10,"+",$11 }}';
        ) | \
        samtools view -Su | \
        samtools sort > {output}
        """


rule assignment_idx_bam:
    input:
        "results/assignment/{assignment}/aligned_merged_reads.bam",
    output:
        "results/assignment/{assignment}/aligned_merged_reads.bam.bai",
    conda:
        "../envs/mpraflow_py36.yaml"
    shell:
        """
        samtools index {input}
        """


rule assignment_flagstat:
    input:
        bam="results/assignment/{assignment}/aligned_merged_reads.bam",
        idx="results/assignment/{assignment}/aligned_merged_reads.bam.bai",
    output:
        "results/assignment/{assignment}/stats/assignment/bam_stats.txt",
    conda:
        "../envs/mpraflow_py36.yaml"
    shell:
        """
        samtools flagstat {input.bam} > {output}
        """


# TODO hard coded lengths of reference sequence (expected 200 bp match)
rule assignment_getBCs:
    input:
        "results/assignment/{assignment}/aligned_merged_reads.bam",
    output:
        "results/assignment/{assignment}/barcodes_incl_other.sorted.tsv.gz",
    conda:
        "../envs/mpraflow_py36.yaml"
    shell:
        """
        samtools view -F 1792 {input} | \
        awk -v "OFS=\t" '{{
            split($(NF-1),a,":");
            if (a[3] !~ /N/) {{
                if (($5 > 0) && ($4 >= 15) && ($4 <= 17) && (length($10) >= 195) && (length($10) <= 205)) {{
                    print a[3],$3,$4";"$6";"$12";"$13";"$5 
                }} else {{
                    print a[3],"other","NA" 
                }}
            }}
        }}' | sort -k1,1 -k2,2 -k3,3 | gzip -c > {output}
        """


rule assignment_filter:
    input:
        "results/assignment/{assignment}/barcodes_incl_other.sorted.tsv.gz",
    output:
        "results/assignment/{assignment}/assignment_barcodes_incl_other.{assignment_config}.sorted.tsv.gz",
    conda:
        "../envs/mpraflow_py36.yaml"
    params:
        min_support=lambda wc: config["assignments"][wc.assignment]["configs"][
            wc.assignment_config
        ]["min_support"],
        fraction=lambda wc: config["assignments"][wc.assignment]["configs"][
            wc.assignment_config
        ]["fraction"],
        unknown_other=lambda wc: "-o"
        if "unknown_other"
        in config["assignments"][wc.assignment]["configs"][wc.assignment_config]
        else "",
    shell:
        """
        zcat  {input} | \
        python {SCRIPTS_DIR}/assignment/filterAssignmentTsv.py -m {params.min_support} -f {params.fraction} {params.unknown_other} | \
        gzip -c > {output}
        """
