#!/bin/bash

module load singularity/3.8.3

bkillJob=0
cleanupTmp="1" # can be a path
fsDir="/appl/freesurfer-7.1.1"
useGPU=0
templateflowHome="/project/ftdc_pipeline/templateflow"

scriptPath=$(readlink -f "$0")
scriptDir=$(dirname "${scriptPath}")
# Repo base dir under which we find bin/ and containers/
repoDir=${scriptDir%/bin}

function usage() {
  echo "Usage:
  $0 [-h] [-B src:dest,...,src:dest] [-c 1/0] [-e VAR=value] [-f /path/to/fsSubjectsDir] \\
    -m modality -v prepVersion -i /path/to/bids -o /path/to/outputDir -- [prep args]

  Use the -h option to see detailed help.

"
}

function help() {
    usage
  echo "This script handles various configuration options and bind points needed to run containerized preps
on the cluster. Requires singularity (module load DEV/singularity).

Use absolute paths, as these have to be mounted in the container. Participant BIDS data
should exist under /path/to/bids.

Using the options below, specify paths on the local file system. These will be bound automatically
to locations inside the container. If needed, you can add extra mount points with '-B'.

prep args after the '--' should reference paths within the container. For example, if
you want to use '--config-file FILE', FILE should be a path inside the container.

Currently installed preps:

`ls -1 ${repoDir}/containers | grep ".sif"`


Required args:

  -i /path/to/bids
    Input BIDS directory on the local file system. Will be bound to /data/input inside the container.

  -o /path/to/outputDir
    Output directory on the local files system. Will be bound to /data/output inside the container.

  -m modality
    One of 'fmri', 'qsi', 'asl'.

  -v version
     prep version. The script will look for containers/modalityprep-[version].sif.


Options:

  -B src:dest[,src:dest,...,src:dest]
     Use this to add mount points to bind inside the container, that aren't handled by other options.
     'src' is an absolute path on the local file system and 'dest' is an absolute path inside the container.
     Several bind points are always defined inside the container including \$HOME, \$PWD (where script is
     executed from), and /tmp (more on this below). Additionally, BIDS input (-i), output (-o), and FreeSurfer
     output dirs (-f) are bound automatically.

  -c 1/0 | /path/to/save/tmpdir
     Cleanup the working dir after running the prep (default = $cleanupTmp). This is different from the prep
     option '--clean-workdir', which deletes the contents of the working directory BEFORE running anything.

     If the argument is a path, the working dir will be copied there. This should be a path on the local file
     system.

  -e VAR=value[,VAR=value,...,VAR=value]
     Comma-separated list of environment variables to pass to singularity.

  -f /path/to/fsSubjectsDir
     Base directory of FreeSurfer recon-all output, on the local file system. Will be mounted inside the
     container and passed to the prep with the '--fs-subjects-dir' option. This only works if you have FS data
     organized in a BIDS-like way. The preps will look for:
       <fs-subjects-dir>/
                        fsaverage{,5,6}/
                                       mri/
                                       surf/
                                       ...
                        sub-<participant>/
                                         mri/
                                         surf/
                                         ...

     fsaverage needs to be an actual copy of the fsaverage data, not a symbolic link.

     If your data is not organized this way, you can create your own mount points (-B) and then pass
     `--fs-subjects-dir` to the prep yourself.

  -g 1/0
     Run containers with CUDA GPU support (default = $useGPU).

  -h
     Prints this help message.

  -k 0/1
     Kill the job in which this script runs after the container exits. This is useful for qsiprep, which sometimes leaves
     processes running after the container exits (default = $bkillJob).

  -t /path/to/templateflow
     Path to a local installation of templateflow (default = ${templateflowHome}).
     The required templates must be pre-downloaded on sciget, run-time template installation will not work.
     The default path has 'tpl-MNI152NLin2009cAsym' and 'tpl-OASIS30ANTs' downloaded.


*** Hard-coded prep configuration ***

A shared templateflow path is passed to the container via the environment variable TEMPLATEFLOW_HOME.

The FreeSurfer license file is sourced from ${fsDir} .

BIDS validation is performed by default, skip by passing '--skip-bids-validation' in the prep args.

The singularity module sets the singularity temp dir to be on /scratch. To avoid conflicts with other jobs,
the script makes a temp dir specifically for this prep job under /scratch. By default it is removed after
the prep finishes, but this can be disabled with '-c 0'.

The singularity command includes '--no-home', which avoids mounting the user home directory. This prevents caching
or config files in the user home directory from conflicting with those inside the container.

The actual call to the prep is equivalent to

<aprep> \\
  --fs-license-file /freesurfer/license.txt \\
  --notrack \\
  --nthreads numProcs \\
  --omp-nthreads numOMPThreads \\
  --work-dir [job temp dir on /scratch] \\
  --stop-on-first-crash \\
  --verbose \\
  [prep args] \\
  /data/input /data/output participant

where [prep args] are anything following `--` in the call to this script.

*** Multi-threading and memory use ***

The number of available cores (numProcs) is derived from the environment variable \${LSB_DJOB_NUMPROC},
which is the number of slots reserved in the call to bsub. If numProcs > 1, we pass to the prep
'--nthreads numProcs --omp-nthreads numProcs'. This default may be overriden by passing the two options above as prep args.

Individual workflows may differ in performance, some may benefit from '--nthreads numProcs --omp-nthreads (numProcs - 1)',
enabling one core to run another task in parallel while a multi-threaded process uses the rest. However, in practice the
most efficient method relies upon numProcs, the host environment, and the total number of processors and jobs.

The performance gains of multi-threading fall off sharply with omp-nthreads > 8. In some contexts, it may be possible
to run jobs in parallel, eg with '--nthreads 16 --omp-nthreads 8'.

Memory use is not controlled by this script, as it is not simple to parse from the job environment. The
maximum memory (in Mb) used by the preps can be controlled with '--mem-mb'. The amount of memory required will
depend on the size of the input data, the processing options selected, and the number of threads used.


*** Additional prep args ***

See usage for the individual programs. At a minimum, you will need to set '--participant_label <participant>'.

https://aslprep.readthedocs.io/en/latest/usage.html

https://fmriprep.org/en/0.6.3/usage.html

https://qsiprep.readthedocs.io/en/latest/usage.html

"
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

fsSubjectsDir=""
userBindPoints=""

modality=""
containerVersion=""

singularityEvars=""

while getopts "B:c:e:f:g:i:k:m:o:t:v:h" opt; do
  case $opt in
    B) userBindPoints=$OPTARG;;
    c) cleanupTmp=$OPTARG;;
    e) singularityEvars=$OPTARG;;
    f) fsSubjectsDir=$OPTARG;;
    g) useGPU=$OPTARG;;
    h) help; exit 1;;
    i) bidsDir=$OPTARG;;
    k) bkillJob=$OPTARG;;
    m) modality=$OPTARG;;
    o) outputDir=$OPTARG;;
    t) templateflowHome=$OPTARG;;
    v) containerVersion=$OPTARG;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;
  esac
done

shift $((OPTIND-1))

whichPrep="${modality}prep"

image="${repoDir}/containers/${whichPrep}-${containerVersion}.sif"

if [[ ! -f $image ]]; then
  echo "Cannot find requested container $image"
  exit 1
fi

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

if [[ ! -d "$outputDir" ]]; then
  mkdir -p "$outputDir"
fi

if [[ ! -d "${outputDir}" ]]; then
  echo "Could not find or create output directory ${outputDir}"
  exit 1
fi

# Set a job-specific temp dir
if [[ ! -d "$SINGULARITY_TMPDIR" ]]; then
  echo "Setting SINGULARITY_TMPDIR=/scratch"
  export SINGULARITY_TMPDIR=/scratch
fi

jobTmpDir=$( mktemp -d -p ${SINGULARITY_TMPDIR} ${whichPrep}.${LSB_JOBID}.XXXXXXXX.tmpdir )

if [[ ! -d "$jobTmpDir" ]]; then
  echo "Could not create job temp dir ${jobTmpDir}"
  exit 1
fi

# Not all software uses TMPDIR
# module DEV/singularity sets SINGULARITYENV_TMPDIR=/scratch
# We will make a temp dir there and bind to /tmp in the container
export SINGULARITYENV_TMPDIR="/tmp"

# This tells preps to look for templateflow here inside the container
export SINGULARITYENV_TEMPLATEFLOW_HOME=/opt/templateflow

if [[ ! -d "${templateflowHome}" ]]; then
  echo "Could not find templateflow at ${templateflowHome}"
  exit 1
fi

# singularity args
singularityArgs="--cleanenv \
  --no-home \
  -B ${jobTmpDir}:/tmp \
  -B ${templateflowHome}:${SINGULARITYENV_TEMPLATEFLOW_HOME} \
  -B ${fsDir}/license.txt:/freesurfer/license.txt:ro \
  -B ${bidsDir}:/data/input:ro \
  -B ${outputDir}:/data/output"

numProcs=$LSB_DJOB_NUMPROC
numOMPThreads=$LSB_DJOB_NUMPROC

# Script-defined args to the prep
prepScriptArgs="--fs-license-file /freesurfer/license.txt \
  --notrack \
  --nthreads $numProcs \
  --omp-nthreads $numOMPThreads \
  --work-dir ${SINGULARITYENV_TMPDIR} \
  --stop-on-first-crash \
  --verbose"

if [[ $useGPU -gt 0 ]]; then
    singularityArgs="$singularityArgs \
    --nv"
fi

if [[ -n "$fsSubjectsDir" ]]; then
  singularityArgs="$singularityArgs \
  -B ${fsSubjectsDir}:/data/fs_subjects"
  prepScriptArgs="$prepScriptArgs \
  --fs-subjects-dir /data/fs_subjects"
fi

if [[ -n "$userBindPoints" ]]; then
  singularityArgs="$singularityArgs \
  -B $userBindPoints"
fi

if [[ -n "$singularityEvars" ]]; then
  singularityArgs="$singularityArgs \
  --env $singularityEvars"
fi

prepUserArgs="$*"

echo "
--- args passed through to prep ---
$*
---
"

echo "
--- Script options ---
prep image             : $image
BIDS directory         : $bidsDir
Output directory       : $outputDir
Cleanup temp           : $cleanupTmp
User bind points       : $userBindPoints
User environment vars  : $singularityEvars
FreeSurfer subject dir : $fsSubjectsDir
Number of cores        : $numProcs
OMP threads            : $numOMPThreads
Use GPU                : $useGPU
---
"

echo "
--- Container details ---"
singularity inspect $image
echo "---
"

cmd="singularity run \
  $singularityArgs \
  $image \
  /data/input /data/output participant \
  $prepScriptArgs \
  $prepUserArgs"

echo "
--- prep command ---
$cmd
---
"

# function to clean up tmp and report errors at exit
function cleanup {
  EXIT_CODE=$?
  LAST_CMD=${BASH_COMMAND}
  set +e # disable termination on error

  if [[ "$cleanupTmp" =~ ^/ ]]; then
    echo "Copying temp dir ${jobTmpDir} to ${cleanupTmp}"
    mkdir -p $(dirname ${cleanupTmp})
    cp -r ${jobTmpDir} ${cleanupTmp}
    rm -rf ${jobTmpDir}
  elif [[ "$cleanupTmp" == "1" ]]; then
    echo "Removing temp dir ${jobTmpDir}"
    rm -rf ${jobTmpDir}
  else
    echo "Leaving working directory ${jobTmpDir}"
  fi

  if [[ ${EXIT_CODE} -gt 0 ]]; then
    echo "
  $0 EXITED ON ERROR - PROCESSING MAY BE INCOMPLETE"
    echo "
  The command \"${LAST_CMD}\" exited with code ${EXIT_CODE}
"
  fi

  exit $EXIT_CODE
}

trap cleanup EXIT

# Exits, triggering cleanup, on CTRL+C
function sigintCleanup {
   exit $?
}

trap sigintCleanup SIGINT

$cmd
singExit=$?

if [[ $singExit -ne 0 ]]; then
  echo "Container exited with non-zero code $singExit"
fi

if [[ $bkillJob -eq 1 ]]; then
  # qsiprep plotting code leaves processes running, so we have to kill the job
  echo "Exiting by killing job ${LSB_JOBID}"
  bkill $LSB_JOBID
fi

exit $singExit
