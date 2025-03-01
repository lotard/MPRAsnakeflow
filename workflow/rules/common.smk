################################
#### Global functions       ####
################################
from snakemake.workflow import srcdir

SCRIPTS_DIR = srcdir("../scripts")


def getScript(name):
    return "%s/%s" % (SCRIPTS_DIR, name)


################################
#### HELPERS AND EXCEPTIONS ####
################################


##### Exceptions #####
class MissingAssignmentInConfigException(Exception):
    """
    Exception raised for if no assignment file is set in the config.

    Args:
        Exception ([type]): Exception class cast

    Attributes:
        config_name (string): name of the configuration which assignment is missing.
    """

    def __init__(self, config_name):
        self.config_name = config_name

    def __str__(self):
        return "Config %s has no assignment file defined!" % (self.config_name)


class MissingVariantInConfigException(Exception):
    """
    Exception raised for if no variants config.

    Args:
        Exception ([type]): Exception class cast

    Attributes:
        config_name (string): name of the configuration which assignment is missing.
    """

    def __init__(self, config_name):
        self.config_name = config_name

    def __str__(self):
        return "Config %s has no variants defined!" % (self.config_name)


##### get helpers for different things (like Conditions etc) #####
def getAssignments():
    if "assignments" in config:
        return list(config["assignments"].keys())
    else:
        return []


def getAssignmentFile(project, assignment):
    if config["experiments"][project]["assignments"][assignment]["type"] == "file":
        return config["experiments"][project]["assignments"][assignment][
            "assignment_file"
        ]
    if config["experiments"][project]["assignments"][assignment]["type"] == "config":
        conf = config["experiments"][project]["assignments"][assignment][
            "assignment_config"
        ]
        name = config["experiments"][project]["assignments"][assignment][
            "assignment_name"
        ]
        return expand(
            "results/assignment/{assignment}/assignment_barcodes.{config}.sorted.tsv.gz",
            assignment=name,
            config=conf,
        )


def getProjects():
    if "experiments" in config:
        return list(config["experiments"].keys())
    else:
        return []


def getExperiments(project):
    experiments = pd.read_csv(config["experiments"][project]["experiment_file"])
    return experiments


def getConditions(project):
    exp = getExperiments(project)
    return list(exp.Condition.unique())


def getProjectAssignments(project):
    if (
        "assignments" in config["experiments"][project]
        and len(config["experiments"][project]["assignments"]) > 0
    ):
        return list(config["experiments"][project]["assignments"].keys())
    else:
        raise MissingAssignmentInConfigException(project)


def getVariants(project):
    if "variants" in config["experiments"][project]:
        return config["experiments"][project]["variants"]
    else:
        raise MissingVariantInConfigException(project)


def getReplicatesOfCondition(project, condition):
    exp = getExperiments(project)
    exp = exp[exp.Condition == condition]
    return list(exp.Replicate.astype(str))


def getVariantsBCThreshold(project):
    return getVariants(project)["min_barcodes"]


def getFW(project, condition, replicate, rnaDna_type):
    exp = getExperiments(project)
    exp = exp[exp.Condition == condition]
    exp = exp[exp.Replicate.astype(str) == replicate]
    return "%s/%s" % (
        config["experiments"][project]["data_folder"],
        exp["%s_BC_F" % rnaDna_type].iloc[0],
    )


def getFWWithIndex(project):
    return [
        "%s%s" % (config["experiments"][project]["data_folder"], f)
        for f in getExperiments(project).BC_F.iloc[0].split(";")
    ]


def getRev(project, condition, replicate, rnaDna_type):
    exp = getExperiments(project)
    exp = exp[exp.Condition == condition]
    exp = exp[exp.Replicate.astype(str) == replicate]
    return "%s/%s" % (
        config["experiments"][project]["data_folder"],
        exp["%s_BC_R" % rnaDna_type].iloc[0],
    )


def getRevWithIndex(project):
    return [
        "%s%s" % (config["experiments"][project]["data_folder"], f)
        for f in getExperiments(project).BC_R.iloc[0].split(";")
    ]


def getUMI(project, condition, replicate, rnaDna_type):
    exp = getExperiments(project)
    exp = exp[exp.Condition == condition]
    exp = exp[exp.Replicate.astype(str) == replicate]
    return "%s/%s" % (
        config["experiments"][project]["data_folder"],
        exp["%s_UMI" % rnaDna_type].iloc[0],
    )


def getUMIWithIndex(project):
    return [
        config["experiments"][project]["data_folder"] + f
        for f in getExperiments(project).UMI.iloc[0].split(";")
    ]


def getIndexWithIndex(project):
    return [
        config["experiments"][project]["data_folder"] + f
        for f in getExperiments(project).INDEX.iloc[0].split(";")
    ]


def hasReplicates(project, condition=None):
    if condition == None:
        conditions = getConditions(project)
        for condition in conditions:
            if len(getReplicatesOfCondition(project, condition)) <= 1:
                return False
    else:
        return len(getReplicatesOfCondition(project, condition)) > 1
    return True


def getConfigs(project):
    return list(config["experiments"][project]["configs"].keys())


##### Helper to create output files #####
def getOutputConditionReplicateType_helper(file, project, skip={}):
    """
    Inserts {condition}, {replicate} and {type} from config into given file.
    Can skip projects with the given config set by skip.
    """
    output = []

    for key, value in skip.items():
        if config["experiments"][project][key] == value:
            return []
    conditions = getConditions(project)
    for condition in conditions:
        replicates = getReplicatesOfCondition(project, condition)
        output += expand(
            file,
            project=project,
            condition=condition,
            replicate=replicates,
            type=["RNA", "DNA"],
        )
    return output


def getOutputProjectConditionReplicateType_helper(file, skip={}):
    """
    Inserts {project}, {condition}, {replicate} and {type} from config into given file.
    Can skip projects with the given config set by skip.
    """
    output = []
    projects = getProjects()
    for project in projects:
        # skip projects with the following config
        output += getOutputConditionReplicateType_helper(
            expand(
                file,
                project=project,
                condition="{condition}",
                replicate="{replicate}",
                type="{type}",
            ),
            project,
            skip,
        )
    return output


def getOutputProjectConditionType_helper(file):
    """
    Inserts {project}, {condition} and {type} from config into given file.
    """
    output = []
    projects = getProjects()
    for project in projects:
        conditions = getConditions(project)
        for condition in conditions:
            output += expand(
                file,
                project=project,
                condition=condition,
                type=["DNA", "RNA"],
            )
    return output


def getOutputProjectConditionAssignmentConfig_helper(file):
    """
    Inserts {project}, {condition}, {assignment} and {config} (from configs of project) from config into given file.
    """
    output = []
    projects = getProjects()
    for project in projects:
        try:
            conditions = getConditions(project)
            for condition in conditions:
                output += expand(
                    file,
                    project=project,
                    condition=condition,
                    assignment=getProjectAssignments(project),
                    config=getConfigs(project),
                )
        except MissingAssignmentInConfigException:
            continue
    return output


def getOutputProjectAssignmentConfig_helper(file, betweenReplicates=False):
    """
    Inserts {project}, {assignment} and {config} (from configs of project) from config into given file.
    When betweenReplicates is True skips projects without replicates in one condition.
    """
    output = []
    projects = getProjects()
    for project in projects:
        if not betweenReplicates or hasReplicates(project):
            try:
                output += expand(
                    file,
                    project=project,
                    assignment=getProjectAssignments(project),
                    config=getConfigs(project),
                )
            except MissingAssignmentInConfigException:
                continue
    return output


def getOutputProjectConfig_helper(file, betweenReplicates=False):
    """
    Inserts {project}, {config} from config into given file.
    When betweenReplicates is True skips projects without replicates in one condition.
    """
    output = []
    projects = getProjects()
    for project in projects:
        if not betweenReplicates or hasReplicates(project):
            output += expand(
                file,
                project=project,
                config=getConfigs(project),
            )
    return output


def getOutputProjectAssignmentConfig_helper(file, betweenReplicates=False):
    """
    Inserts {project}, {assignment}, {config} from config into given file.
    When betweenReplicates is True skips projects without replicates in one condition.
    """
    output = []
    projects = getProjects()
    for project in projects:
        if not betweenReplicates or hasReplicates(project):
            try:
                output += expand(
                    file,
                    project=project,
                    assignment=getProjectAssignments(project),
                    config=getConfigs(project),
                )
            except MissingAssignmentInConfigException:
                continue
    return output


def getOutputVariants_helper(file, betweenReplicates=False):
    """
    Only when variants are set in config file
    Inserts {project}, {condition}, {assignment} and {config} (from configs of project) from config into given file.
    When betweenReplicates is True skips project/condition without replicates in a condition.
    """
    output = []
    projects = getProjects()
    for project in projects:
        conditions = getConditions(project)
        for condition in conditions:
            if "variants" in config["experiments"][project]:
                if hasReplicates(project, condition):
                    output += expand(
                        file,
                        project=project,
                        condition=condition,
                        assignment=getProjectAssignments(project),
                        config=list(config["experiments"][project]["configs"].keys()),
                    )
    return output


def getAssignment_helper(file):
    return expand(
        file,
        assignment=getAssignments(),
    )


def getAssignmentConfig_helper(file):
    output = []
    for assignment in getAssignments():
        output += expand(
            file,
            assignment=assignment,
            config=config["assignments"][assignment]["configs"].keys(),
        )
    return output


# config functions


def useSampling(project, conf, dna_or_rna):
    return (
        "sampling" in config["experiments"][project]["configs"][conf]
        and dna_or_rna in config["experiments"][project]["configs"][conf]["sampling"]
    )


def withoutZeros(project, conf):
    return (
        config["experiments"][project]["configs"][conf]["filter"]["DNA"]["min_counts"]
        > 0
        and config["experiments"][project]["configs"][conf]["filter"]["RNA"][
            "min_counts"
        ]
        > 0
    )


# assignment.smk specific functions


def getSplitNumber():
    split = SPLIT_FILES_NUMBER

    if "global" in config:
        if "assignments" in config["global"]:
            if "split_number" in config["global"]["assignments"]:
                split = config["global"]["assignments"]["split_number"]

    return split


# count.smk specific functions


def getBamFile(project, condition, replicate, type):
    """
    gelper to get the correct BAM file (demultiplexed or not)
    """
    if config["experiments"][project]["demultiplex"]:
        return "results/%s/counts/merged_demultiplex_%s_%s_%s.bam" % (
            project,
            condition,
            replicate,
            type,
        )
    else:
        return "results/experiments/%s/counts/%s_%s_%s.bam" % (
            project,
            condition,
            replicate,
            type,
        )


def counts_aggregate_demultiplex_input(project):
    output = []
    conditions = getConditions(project)
    for condition in conditions:
        replicates = getReplicatesOfCondition(project, condition)
        names = expand(
            "{condition}_{replicate}_{type}",
            condition=condition,
            replicate=replicates,
            type=["DNA", "RNA"],
        )
        for name in names:
            with checkpoints.counts_demultiplexed_BAM_umi.get(
                project=project, name=name
            ).output[0].open() as f:
                output += [f.name]
    return output


def counts_getFilterConfig(project, conf, dna_or_rna, command):
    value = config["experiments"][project]["configs"][conf]["filter"][dna_or_rna][
        command
    ]
    if isinstance(value, int):
        return "--%s %d" % (command, value)
    else:
        return "--%s %f" % (command, value)


def counts_getSamplingConfig(project, conf, dna_or_rna, command):
    if useSampling(project, conf, dna_or_rna):
        if dna_or_rna in config["experiments"][project]["configs"][conf]["sampling"]:
            if (
                command
                in config["experiments"][project]["configs"][conf]["sampling"][
                    dna_or_rna
                ]
            ):
                value = config["experiments"][project]["configs"][conf]["sampling"][
                    dna_or_rna
                ][command]
                if isinstance(value, int):
                    return "--%s %d" % (command, value)
                else:
                    return "--%s %f" % (command, value)

    return ""


def getFinalCounts(project, conf, rna_or_dna, raw_or_assigned):
    output = ""
    if raw_or_assigned == "counts":
        if useSampling(project, conf, rna_or_dna):
            output = (
                "results/experiments/{project}/%s/{condition}_{replicate}_%s_final_counts.sampling.{config}.tsv.gz"
                % (raw_or_assigned, rna_or_dna)
            )

        else:
            output = (
                "results/experiments/{project}/%s/{condition}_{replicate}_%s_final_counts.tsv.gz"
                % (raw_or_assigned, rna_or_dna)
            )
    else:
        output = (
            "results/experiments/{project}/%s/{condition}_{replicate}_%s_final_counts.config.{config}.tsv.gz"
            % (raw_or_assigned, rna_or_dna)
        )
    return output


# assigned_counts.smk specific functions


def assignedCounts_getAssignmentSamplingConfig(project, assignment, command):
    if "sampling" in config["experiments"][project]["assignments"][assignment]:
        if (
            command
            in config["experiments"][project]["assignments"][assignment]["sampling"]
        ):
            value = config["experiments"][project]["assignments"][assignment][
                "sampling"
            ][command]
            if isinstance(value, int):
                return "--%s %d" % (command, value)
            else:
                return "--%s %f" % (command, value)

    return ""


# statistic.smk specific functions


# get all counts of experiment (rule statistic_counts)
def getCountStats(project, countType):
    exp = getExperiments(project)
    output = []
    for index, row in exp.iterrows():
        output += expand(
            "results/experiments/{{project}}/statistic/counts/{condition}_{replicate}_{type}_{{countType}}_counts.tsv.gz",
            condition=row["Condition"],
            replicate=row["Replicate"],
            type=["DNA", "RNA"],
        )
    return output


# get all barcodes of experiment (rule statistic_BC_in_RNA_DNA)
def getBCinRNADNAStats(wc):
    exp = getExperiments(wc.project)
    output = []
    for index, row in exp.iterrows():
        output += expand(
            "results/experiments/{project}/statistic/counts/{condition}_{replicate}_{countType}_BC_in_RNA_DNA.tsv.gz",
            project=wc.project,
            condition=row["Condition"],
            replicate=row["Replicate"],
            countType=wc.countType,
        )
    return output


def getAssignedCountsStatistic(project, assignment, conf, condition):
    exp = getExperiments(project)
    exp = exp[exp.Condition == condition]
    output = []
    for index, row in exp.iterrows():
        output += [
            "--statistic %s results/experiments/%s/statistic/assigned_counts/%s/%s/%s_%s_merged_assigned_counts.statistic.tsv.gz"
            % (
                str(row["Replicate"]),
                project,
                assignment,
                conf,
                condition,
                str(row["Replicate"]),
            )
        ]
    return output


# get all barcodes of experiment (rule dna_rna_merge_counts_withoutZeros or rule dna_rna_merge_counts_withZeros)
def getMergedCounts(project, raw_or_assigned, condition, conf):
    exp = getExperiments(project)
    exp = exp[exp.Condition == condition]
    files = []
    replicates = []
    for index, row in exp.iterrows():
        files += expand(
            "results/experiments/{project}/{raw_or_assigned}/{condition}_{replicate}.merged.config.{config}.tsv.gz",
            raw_or_assigned=raw_or_assigned,
            project=project,
            condition=condition,
            replicate=row["Replicate"],
            config=conf,
        )
        replicates += str(row["Replicate"])
    return [files, replicates]
