##################################
### Assign BCs and afterwards ###
##################################


rule assigned_counts_filterAssignment:
    """
    Use only unique assignments and do sampling if needed.
    """
    conda:
        "../envs/python3.yaml"
    input:
        assignment=lambda wc: getAssignmentFile(wc.project, wc.assignment),
        script=getScript("count/samplerer_assignment.py"),
    output:
        "results/experiments/{project}/assignment/{assignment}.tsv.gz",
    params:
        samplingprop=lambda wc: assignedCounts_getAssignmentSamplingConfig(
            wc.project, wc.assignment, "prop"
        ),
        samplingtotal=lambda wc: assignedCounts_getAssignmentSamplingConfig(
            wc.project, wc.assignment, "total"
        ),
        seed=lambda wc: assignedCounts_getAssignmentSamplingConfig(
            wc.project, wc.assignment, "seed"
        ),
    log:
        temp("results/logs/assigned_counts/filterAssignment.{project}.{assignment}.log"),
    shell:
        """
        python {input.script} \
        --input {input.assignment} \
        {params.samplingprop} \
        {params.samplingtotal} \
        {params.seed} \
        --output {output} &> {log}
        """


rule assigned_counts_createAssignmentPickleFile:
    conda:
        "../envs/python3.yaml"
    input:
        files="results/experiments/{project}/assignment/{assignment}.tsv.gz",
        script=getScript("count/create_pickle.py"),
    output:
        "results/experiments/{project}/assignment/{assignment}.pickle",
    log:
        temp(
            "results/logs/assigned_counts/assignment/createAssignmentPickleFile.{project}.{assignment}.log"
        ),
    shell:
        """
        python {input.script} -i {input.files} -o {output} &> {log}
        """


rule assigned_counts_assignBarcodes:
    """
    Assign RNA and DNA barcodes seperately to make the statistic for assigned
    """
    conda:
        "../envs/python3.yaml"
    input:
        counts=lambda wc: getFinalCounts(wc.project, wc.config, wc.type, "counts"),
        association="results/experiments/{project}/assignment/{assignment}.tsv.gz",
        script=getScript("count/merge_BC_and_assignment.py"),
    output:
        counts="results/experiments/{project}/assigned_counts/{assignment}/{condition}_{replicate}_{type}_final_counts.config.{config}.tsv.gz",
        stats="results/experiments/{project}/statistic/assigned_counts/{assignment}/{condition}_{replicate}_{type}_{config}.statistic.tsv.gz",
    params:
        name="{condition}_{replicate}_{type}",
    log:
        temp(
            "results/logs/assigned_counts/assignBarcodes.{project}.{condition}.{replicate}.{type}.{config}.{assignment}.log"
        ),
    shell:
        """
        python {input.script} --counts {input.counts} \
        --assignment {input.association} \
        --output {output.counts} \
        --statistic {output.stats} \
        --name {params.name} &> {log}
        """


rule assigned_counts_dna_rna_merge:
    """
    Assign merged RNA/DNA barcodes. Filter BC depending on the min_counts option.
    """
    conda:
        "../envs/python3.yaml"
    input:
        counts="results/experiments/{project}/counts/{condition}_{replicate}.merged.config.{config}.tsv.gz",
        association="results/experiments/{project}/assignment/{assignment}.tsv.gz",
        script=getScript("count/merge_label.py"),
    output:
        counts="results/experiments/{project}/assigned_counts/{assignment}/{config}/{condition}_{replicate}_merged_assigned_counts.tsv.gz",
        stats="results/experiments/{project}/statistic/assigned_counts/{assignment}/{config}/{condition}_{replicate}_merged_assigned_counts.statistic.tsv.gz",
    params:
        minRNACounts=lambda wc: config["experiments"][wc.project]["configs"][
            wc.config
        ]["filter"]["RNA"]["min_counts"],
        minDNACounts=lambda wc: config["experiments"][wc.project]["configs"][
            wc.config
        ]["filter"]["DNA"]["min_counts"],
    log:
        temp(
            "results/logs/assigned_counts/{assignment}/dna_rna_merge.{project}.{condition}.{replicate}.{config}.log"
        ),
    shell:
        """
        python {input.script} --counts {input.counts} \
        --minRNACounts {params.minRNACounts} --minDNACounts {params.minDNACounts} \
        --assignment {input.association} \
        --output {output.counts} \
        --statistic {output.stats} &> {log}
        """


rule assigned_counts_make_master_tables:
    """
    Final master table with all replicates combined. With and without threshold.
    """
    conda:
        "../envs/r.yaml"
    input:
        counts=lambda wc: expand(
            "results/experiments/{{project}}/assigned_counts/{{assignment}}/{{config}}/{{condition}}_{replicate}_merged_assigned_counts.tsv.gz",
            replicate=getReplicatesOfCondition(wc.project, wc.condition),
        ),
        script=getScript("count/make_master_tables.R"),
    output:
        statistic="results/experiments/{project}/statistic/assigned_counts/{assignment}/{config}/{condition}_average_allreps_merged.tsv.gz",
        all="results/experiments/{project}/assigned_counts/{assignment}/{config}/{condition}_allreps_merged.tsv.gz",
        thresh="results/experiments/{project}/assigned_counts/{assignment}/{config}/{condition}_allreps_minThreshold_merged.tsv.gz",
    params:
        cond="{condition}",
        files=lambda wc: ",".join(
            expand(
                "results/experiments/{project}/assigned_counts/{assignment}/{config}/{condition}_{replicate}_merged_assigned_counts.tsv.gz",
                replicate=getReplicatesOfCondition(wc.project, wc.condition),
                project=wc.project,
                condition=wc.condition,
                assignment=wc.assignment,
                config=wc.config,
            )
        ),
        replicates=lambda wc: ",".join(
            getReplicatesOfCondition(wc.project, wc.condition)
        ),
        thresh=lambda wc: config["experiments"][wc.project]["configs"][wc.config][
            "filter"
        ]["bc_threshold"],
    log:
        temp(
            "results/logs/assigned_counts/make_master_tables.{project}.{condition}.{config}.{assignment}.log"
        ),
    shell:
        """
        Rscript {input.script} \
        --condition {params.cond} \
        --threshold {params.thresh} \
        --files {params.files} \
        --replicates {params.replicates} \
        --output {output.thresh} \
        --output-all {output.all} \
        --statistic {output.statistic} &> {log}
        """
