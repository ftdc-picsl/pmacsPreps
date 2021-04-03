# pmacsPreps
*prep wrapper scripts for the PMACS cluster

## Usage

The executable scripts are stored in `bin/`, eg

```
bin/fmriprep.sh [args]
```

runs a container of the form `containers/fmriprep-version.sif`.

The containers are not included in this repository.


## Container information

Singularity containers are built from DockerHub on a Ubuntu VM. Details can be
found by running

```
singularity inspect containers/container-version.sif
```

## Container sources

fmriprep from [nipreps](https://hub.docker.com/u/nipreps)

