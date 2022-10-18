#!/bin/bash
#
# script to run SnowToday Step4:
#   Make today's SnowToday line and map plots
#   kick off Step5 for today
#

#SBATCH --qos normal
#SBATCH --partition amilan
#SBATCH --job-name 4SnTo
#SBATCH --account ucb-general
#SBATCH --time 02:00:00
# Assumes 3.74 GB/per node for total of xx GB RAM
#SBATCH --ntasks-per-node 22
#SBATCH --nodes 1
#SBATCH -o /scratch/alpine/%u/slurm_out_SnowToday/%x-%A_%a.out
# Set the system up to notify upon completion
#SBATCH --mail-type END,FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,STAGE_OUT
#SBATCH --mail-user brodzik@colorado.edu
#SBATCH --array=10-12

# Grab the full path to this script
# depends on whether it's running as sbatch job
isBatch=
if [[ ${BASH_SOURCE} == *"slurm_script"* ]]; then
    # Running as slurm
    echo "Running as sbatch job..."
    PROGNAME=(`scontrol show job ${SLURM_JOB_ID} | grep Command | tr -s ' ' | cut -d = -f 2`)
    isBatch=1
else
    echo "Not running as sbatch..."
    PROGNAME=${BASH_SOURCE[0]}
fi
thisScriptDir="$( cd "$( dirname "${PROGNAME}" )" && pwd )"

usage() {
    echo "" 1>&2
    echo "Usage: ${PROGNAME} [-h] [-n] [-L LABEL] [-d YYYYMMDD] " 1>&2
    echo "  Calculates ST statistics files to date for this WATERYR" 1>&2
    echo "  Job array for each region group (10=westUS, 11=States, 12=HUC2)" 1>&2
    echo "Options: "  1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "  -n: no pipeline: suppress starting next pipeline step" 1>&2
    echo "  -L LABEL: string with version label for directories" 1>&2
    echo "     e.g. for operational processing, use -L v2023.x" 1>&2
    echo "  -d YYYYMMDD: analysis date, defaults to today" 1>&2
    echo "Arguments: n/a " 1>&2
    echo "Output: " 1>&2
    echo "  Output location is controlled in Matlab scripts " 1>&2
    echo "Notes: " 1>&2
    echo "  Scripts stdout/stderr are written to user's scratch " 1>&2
    echo "  where directory /scratch/alpine/$USER/slurm_out_SnowToday/ " 1>&2
    echo "  is assumed to exist" 1>&2
}

error_exit() {
    # Use for fatal program error
    # Argument:
    #   optional string containing descriptive error message
    #   if no error message, prints "Unknown Error"

    echo "${PROGNAME}: ERROR: ${1:-"Unknown Error"}" 1>&2
    exit 1
}

yyyymmdd=
noPipeline=
LABEL=

while getopts "d:hnL:" opt
do
    case $opt in
	d) yyyymmdd="$OPTARG";;
	h) usage
	   exit 1;;
	n) noPipeline=1;;
	L) LABEL="$OPTARG";;
	?) printf "Unknown option %s\n" $opt
	   usage
           exit 1;;
	esac
done

shift $(($OPTIND - 1))

[[ "$#" -eq 0 ]] || error_exit "Line $LINENO: Unexpected number of arguments."

if [ $noPipeline ]; then
    echo "${PROGNAME}: noPipeline mode: this script will not continue pipeline"
fi

if [ ! $yyyymmdd ]; then
    yyyymmdd=$(date +'%Y%m%d')
fi
echo "${PROGNAME}: Analysis date will be: $yyyymmdd"

options=""
if [ $LABEL ]; then
    options="'label', '$LABEL'"
fi

module purge
ml matlab/R2021b

# Start the stopwatch
SECONDS=0

thisHost=$(hostname)
thisDate=$(date)
echo "${PROGNAME}: Begin on hostname=$thisHost on $thisDate for "
echo "${PROGNAME}:    analysis date=$yyyymmdd "
echo "${PROGNAME}:    partitionNum=$SLURM_ARRAY_TASK_ID and "
echo "${PROGNAME}:    options=$options"
echo "${PROGNAME}: SLURM_SCRATCH=$SLURM_SCRATCH"
echo "${PROGNAME}: SLURM_JOB_ID=$SLURM_JOB_ID"
echo "${PROGNAME}: SLURM_ARRAY_JOB_ID=$SLURM_ARRAY_JOB_ID"

#Make a unique temporary directory for matlab job storage
#Set TMPDIR/TMP to this location so job array uses it for tmp location
tmpDir=/scratch/alpine/${USER}/matlabTmp/alpine-$SLURM_ARRAY_JOB_ID
mkdir -p $tmpDir
export TMPDIR=$tmpDir
export TMP=$tmpDir

#SCD minimum days to include in the plots
minSCD=14

#Other values for plots--will need to be updated for RF and DV plots
minSCF=10
minZ=800

#Go to parent of this script, so that correct pathdef.m file is used
cd "${thisScriptDir}/../"

# Do the scratch shuffle on input daily Mosaics (to scratch for speed)
regionName='westernUS'
for dataType in scagdrfs; do
    ${thisScriptDir}/scratchShuffle.sh TO ${dataType}_$LABEL ${regionName} \
		    ${yearStart} ${yearStop} || \
	error_exit "Line $LINENO: scratchShuffle error ${dataType} ${LABEL} ${regionName}"
done

#showSCF_SCD will only work on the SCD parts, now
#use showMostRecentVarMap for all but SCD
#use showMostRecentVarInContext for all varNames
matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"espEnv = ESPEnv(); "\
"mData = MODISData($options); "\
"myDt = datetime('"$yyyymmdd"', 'InputFormat', 'yyyyMMdd'); "\
"showSCF_SCD(espEnv, mData, 'westernUS', "$SLURM_ARRAY_TASK_ID", myDt, "\
"${minSCF}, ${minSCD}, ${minZ}); "\
"vNs = {'SCD', 'snow_fraction', 'albedo_observed_muZ', 'radiative_forcing'}; "\
"for v=1:length(vNs); "\
"showMostRecentVarMap(espEnv, mData, 'westernUS', "$SLURM_ARRAY_TASK_ID", "\
"vNs{v}, myDt, ${minSCF}); "\
"end; "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

# Do the scratch shuffle to copy the geotiffs back from scratch to archive
#TBD

#schedule next job in pipeline to run after entire job array completes
if [ $isBatch ] && [ ! $noPipeline ]; then
    
    # get current slurm info for mail-user and stdout
    # Don't assume they are the same as at the top of this file,
    # because they can be overridden at the command line
    MAIL=`${thisScriptDir}/getSlurmMail.sh ${SLURM_JOB_ID}`
    stdoutDir=$( dirname `${thisScriptDir}/getSlurmStdout.sh ${SLURM_JOB_ID}` )

    if [ "$SLURM_ARRAY_TASK_ID" -eq "10" ]; then

	STDOUT_STEP5="${stdoutDir}/runSnowTodayStep5-%j.out"

	#schedule Step 5 to push all plots to NSIDC
	creationDate=$(date +'%Y%m%d')
	sbatch --dependency=afterok:$SLURM_ARRAY_JOB_ID \
	       --mail-user=${MAIL} \
	       --output=${STDOUT_STEP5} \
	       ${thisScriptDir}/runSnowTodayStep5.sh \
	       -L LABEL $creationDate

    fi
fi

#Clean up temporary directory for matlab job storage
echo "${PROGNAME}: Removing TMPDIR=$TMPDIR..."
rm -rf $TMPDIR

# Stop the stopwatch and report elapsed time
elapsedSeconds=$SECONDS
TZ=UTC0 printf '${PROGNAME}: Duration: %(%H:%M:%S)T\n' "$elapsedSeconds"

thisDate=$(date)
echo "${PROGNAME}: Done on hostname=$thisHost on $thisDate"

