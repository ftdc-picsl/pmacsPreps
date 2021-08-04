# pmacsPreps
*prep wrapper scripts for the PMACS cluster

## Usage

The executable scripts are stored in `bin/`, eg

```
bin/runprep.sh [args]
```

runs a container of the form `containers/modalityprep-version.sif`.

The containers are not included in this repository.

The generic script `runprep.sh` is designed to run any prep; more specialized,
specific scripts may be added later.


## Container information

The shared installation on

```
/project/bsc/shared/pmacsPreps
```

contains Singularity images built directly from DockerHub images, on a Ubuntu VM.
Details can be found by running

```
singularity inspect containers/container-version.sif
```

This container information is written to the standard output at run time, and
will be available in job logs.


## templateflow

The compute nodes cannot access the Internet, so templateflow must be installed
locally and the desired templates must be pre-fetched. A shared installation for
BSC users is used by default. This can be changed with the `-t` option.


## Container sources

Current containers installed in

```
/project/bsc/shared/pmacsPreps/containers
```

include:

* fmriprep from [nipreps](https://hub.docker.com/r/nipreps/fmriprep)
* qsiprep from [pennbbl](https://hub.docker.com/r/pennbbl/qsiprep)
* aslprep from [pennlinc](https://hub.docker.com/r/pennlinc/aslprep)

