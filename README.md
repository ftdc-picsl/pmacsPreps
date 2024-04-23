# pmacsPreps
*prep wrapper scripts for the PMACS cluster

## Usage

The executable scripts are stored in `bin/`, eg

```
bin/runprep.sh -m modality -v version [args]
```

runs a container at the path `containers/modalityprep-version.sif`.

The containers are not included in this repository because they are too large.

The generic script `runprep.sh` is designed to run any prep, and has been tested on [qsi
,fmri, asl]prep.


## Cluster usage

The script detects the number of slots requested with `bsub -n`, and will set multi-threading parameters accordingly. It does not look for memory resource requests, which are much harder to extract from the environment. 

The preps accept the arg `--mem_mb <number>` which help with subprocess scheduling, but memory usage can sometimes exceed this value. Submission scripts can add a hard memory limit with `-M` and make resource requests with `-R "rusage[mem=<number>]"`. For example

```
# Hard limit above which job is terminated immediately
MEM_LIMIT_GB=16
# Memory we think we need, scheduler will wait for this
# much memory to be available before running job
MEM_REQUEST_GB=8

MEM_LIMIT_MB=$((MEM_LIMIT_GB*1024))
MEM_REQUEST_MB=$((MEM_REQUEST_GB*1024))

bsub -M ${MEM_LIMIT_MB} -R "rusage[mem=${MEM_REQUEST_MB}]" ... bin/runPrep.sh ... -- --mem_mb ${MEM_REQUEST_MB}
```

## Container information

The shared installation on

```
/project/ftdc_pipeline/pmacsPreps
```

contains Singularity images built directly from DockerHub images, on a Ubuntu VM , or on
`singularity01`. Details can be found by running

```
singularity inspect containers/container-version.sif
```

This container information is written to the standard output at run time, and
will be available in job logs.


## templateflow

The compute nodes cannot access the Internet, so templateflow must be installed
locally and the desired templates must be pre-fetched. A shared installation for
FTDC users is used by default, which contains the 'tpl-MNI152NLin2009cAsym' (for
normalization) and 'tpl-OASIS30ANTs' (for brain extraction).


## Container sources

Current containers installed in

```
/project/ftdc_pipeline/pmacsPreps/containers
```

include:

* fmriprep from [nipreps](https://hub.docker.com/r/nipreps/fmriprep)
* qsiprep from [pennbbl](https://hub.docker.com/r/pennbbl/qsiprep)

