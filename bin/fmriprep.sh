#!/bin/bash -e

containerVersion=20.2.1
fsDir=/appl/freesurfer-7.1.1
cleanup=1

if [[ $# -eq 0 ]]; then
  echo "
  $0 [options] -i /path/to/bids -o /path/to/outputDir -- [fmriprep args]    

This script handles various configuration options and bind points needed to run fmriprep on the cluster. 

Requires absolute paths, as these have to be mounted in the container. Participant BIDS data 
should exist under /path/to/bids.

Using the options below, specify paths on the local file system. These will be bound automatically
to locations inside the container. If needed, you can add extra mount points with '-B'.

fmriprep args after the '--' should reference paths within the container. For example, if 
you want to use '--config-file FILE', FILE should be a path inside the container. 

Required args:

  -i /path/to/bids
    Input BIDS directory on the local file system. Will be bound to /data/input inside the container.

  -o /path/to/OutputDir
    Output directory on the local files system. Will be bound to /data/output inside the container.

Options:

  -B src:dest[,src:dest,...,src:dest]
     Use this to add mount points to bind inside the container, that aren't handled by other options. 
     'src' is an absolute path on the local file system and 'dest' is an absolute path inside the container. 
     Several bind points are always defined inside the container including \$HOME, \$PWD (where script is 
     executed from), and /tmp (more on this below). Additionally, BIDS input (-i), output (-o), and FreeSurfer 
     output dirs (-f) are bound automatically. 

  -c 1/0
     Cleanup the working dir after running fmriprep (default = $cleanup). This is different from the fmriprep
     option '--clean-workdir', which deletes the contents of the working directory BEFORE running anything. 
     
  -f /path/to/fsSubjectsDir
     Base directory of FreeSurfer recon-all output, on the local file system. Will be mounted inside the 
     container and passed to fmriprep with the '--fs-subjects-dir' option.


*** Hard-coded fmriprep configuration ***

A shared templateflow path is passed to the container via the environment variable TEMPLATEFLOW_HOME.

The FreeSurfer license file is sourced from ${fsDir} .

BIDS validation is skipped because the fmriprep validator is too strict.

The DEV/singularity module sets the singularity temp dir to be on /scratch. To avoid conflicts with other jobs,
the script makes a temp dir specifically for this fmirprep job under /scratch. By default it is removed after
fmriprep finishes, but this can be disabled with '-c 0'.

The actual call to fmriprep is equivalent to

fmriprep --notrack \\
         --fs-license-file /freesurfer/license.txt \\
         --work-dir [job temp dir on /scratch] \\
         --skip_bids_validation \\
         --stop-on-first-crash \\
         [your args] \\
         /data/input /data/output participant


Available fmriprep args (taken directly from fmriprep):

                [-h] [--version] [--skip_bids_validation]
                [--participant-label PARTICIPANT_LABEL [PARTICIPANT_LABEL ...]]
                [-t TASK_ID] [--echo-idx ECHO_IDX] [--bids-filter-file FILE]
                [--anat-derivatives PATH] [--bids-database-dir PATH]
                [--nprocs NPROCS] [--omp-nthreads OMP_NTHREADS]
                [--mem MEMORY_GB] [--low-mem] [--use-plugin FILE]
                [--anat-only] [--boilerplate_only] [--md-only-boilerplate]
                [--error-on-aroma-warnings] [-v]
                [--ignore {fieldmaps,slicetiming,sbref,t2w,flair} [{fieldmaps,slicetiming,sbref,t2w,flair} ...]]
                [--longitudinal]
                [--output-spaces [OUTPUT_SPACES [OUTPUT_SPACES ...]]]
                [--bold2t1w-init {register,header}] [--bold2t1w-dof {6,9,12}]
                [--force-bbr] [--force-no-bbr] [--medial-surface-nan]
                [--dummy-scans DUMMY_SCANS] [--random-seed _RANDOM_SEED]
                [--use-aroma]
                [--aroma-melodic-dimensionality AROMA_MELODIC_DIM]
                [--return-all-components]
                [--fd-spike-threshold REGRESSORS_FD_TH]
                [--dvars-spike-threshold REGRESSORS_DVARS_TH]
                [--skull-strip-template SKULL_STRIP_TEMPLATE]
                [--skull-strip-fixed-seed]
                [--skull-strip-t1w {auto,skip,force}] [--fmap-bspline]
                [--fmap-no-demean] [--use-syn-sdc] [--force-syn]
                [--fs-license-file FILE] [--fs-subjects-dir PATH]
                [--no-submm-recon] [--cifti-output [{91k,170k}] |
                --fs-no-reconall] [--output-layout {bids,legacy}]
                [-w WORK_DIR] [--clean-workdir] [--resource-monitor]
                [--reports-only] [--config-file FILE] [--write-graph]
                [--stop-on-first-crash] [--notrack]
                [--debug {compcor,all} [{compcor,all} ...]] [--sloppy]

Requires singularity

"

  exit 1

fi

scriptDir=$( dirname $0 )

fsSubjectsDir=""
userBindPoints=""

while getopts "B:c:f:i:o:" opt; do
  case $opt in
    B) userBindPoints=$OPTARG;;
    c) cleanup=$OPTARG;;
    f) fsSubjectsDir=$OPTARG;;
    i) bidsDir=$OPTARG;;
    o) outputDir=$OPTARG;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;
  esac
done

shift $((OPTIND-1))

if [[ -z "${LSB_JOBID}" ]]; then
  echo "This script must be run within a (batch or interactive) LSF job"
  exit 1
fi

sngl=$( which singularity ) || 
    ( echo "Cannot find singularity executable. Try module load DEV/singularity"; exit 1 )


if [[ ! -d "$bidsDir" ]]; then
  echo "Cannot find input BIDS directory $bidsDir"
  exit 1
fi

if [[ ! -d "${outputDir}" ]]; then
  mkdir -p $outputDir
fi

if [[ ! -d "${outputDir}" ]]; then
  echo "Could not find or create output directory ${outputDir}"
  exit 1
fi

# Set a job-specific temp dir
jobTmpDir=$( mktemp -d -p ${SINGULARITY_TMPDIR} fmriprep.${LSB_JOBID}.XXXXXXXX.tmpdir ) || 
    ( echo "Could not create job temp dir ${jobTmpDir}"; exit 1 )

# Not all software uses TMPDIR
# module DEV/singularity sets SINGULARITYENV_TMPDIR=/scratch
# We will make a temp dir there and bind to /tmp in the container
export SINGULARITYENV_TMPDIR="/tmp"

# This tells fmriprep to look for templateflow here
export SINGULARITYENV_TEMPLATEFLOW_HOME=/opt/templateflow

# singularity args
singularityArgs="--cleanenv \
  -B ${jobTmpDir}:/tmp \
  -B /project/ftdc_pipeline/templateflow:${SINGULARITYENV_TEMPLATEFLOW_HOME} \
  -B ${fsDir}:/freesurfer \
  -B ${bidsDir}:/data/input \
  -B ${outputDir}:/data/output"

if [[ -n "$fsSubjectsDir" ]]; then
  singularityArgs="$singularityArgs \
  -B ${fsSubjectsDir}:/data/fs_subjects"
  fmriprepScriptArgs="$fmriprepScriptArgs \
  --fs-subjects-dir /data/fs_subjects"
fi

if [[ -n "$userBindPoints" ]]; then
  singularityArgs="$singularityArgs \
    -B $userBindPoints"
fi

# Script-defined args to fmriprep
fmriprepScriptArgs="--fs-license-file /freesurfer/license.txt \
  --notrack \
  --nprocs $LSB_DJOB_NUMPROC \ 
  --omp-nthreads $LSB_DJOB_NUMPROC \
  --work-dir ${SINGULARITYENV_TMPDIR} \
  --skip_bids_validation \
  --stop-on-first-crash"

fmriprepUserArgs="$*"

echo "
--- args passed through to fmriprep ---
$*
---
"

image="${scriptDir}/containers/fmriprep-${containerVersion}.sif"

echo "
--- Script options ---
fmriprep image         : $image
BIDS directory         : $bidsDir
Output directory       : $outputDir
Cleanup temp           : $clean
User bind points       : $userBindPoints
FreeSurfer subject dir : $fsSubjectsDir
---  
"

echo "
--- Container details ---
"
singularity inspect $image
echo "---"


cmd="singularity run \
  $singularityArgs \
  $image \
  $fmriprepScriptArgs \
  $fmriprepUserArgs \
  /data/input /data/output participant
"

echo "
--- fmriprep command ---
$cmd
---
"

singExit=0

( $cmd ) || singExit=$?

if [[ $singExit -eq 0 ]]; then
  echo "Container exited with status 0"
fi

if [[ $cleanup -eq 1 ]]; then
  echo "Removing temp dir ${jobTmpDir}"
  rm -rf ${jobTmpDir}
else
  echo "Leaving temp dir ${jobTmpDir}"
fi

exit $singExit