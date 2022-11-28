#!/bin/bash
#
# script to run SnowToday Step3:
#   update all westernUS SCF_SCD statistics files
#   for region paritions (full region, States, HUC2, etc)
#   for the current year
#   kick off Step4 for today
#

#SBATCH --qos normal
#SBATCH --partition amilan
#SBATCH --job-name 3SnTo
#SBATCH --account=ucb-general
#SBATCH --time=08:00:00
# Assumes 3.74 GB/per node for total of 89.76 GB RAM
#SBATCH --ntasks-per-node=24
#SBATCH --nodes=1
#SBATCH -o /scratch/alpine/%u/slurm_out_SnowToday/%x-%A_%a.out
# Set the system up to notify upon completion
#SBATCH --mail-type FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,STAGE_OUT
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
    echo "Usage: ${PROGNAME} [-h] [-n] [-L LABEL] WATERYR" 1>&2
    echo "  Calculates ST statistics files to date for this WATERYR" 1>&2
    echo "  Job array for each region group (10=westUS, 11=States, 12=HUC2)" 1>&2
    echo "Options: "  1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "  -n: no pipeline: suppress starting next pipeline step" 1>&2
    echo "  -L LABEL: string with version label for directories" 1>&2
    echo "     e.g. for operational processing, use -L v2023.x" 1>&2
    echo "Arguments: " 1>&2
    echo "  WATERYR : stats will be calculated for this WATERYR (begins Oct 1 of WATERYR-1)" 1>&2
    echo "Output: " 1>&2
    echo "  Output location is controlled in Matlab scripts and -L LABEL" 1>&2
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

noPipeline=
LABEL=

while getopts "hnL:" opt
do
    case $opt in
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

[[ "$#" -eq 1 ]] || error_exit "Line $LINENO: Unexpected number of arguments."

if [ $noPipeline ]; then
    echo "${PROGNAME}: noPipeline mode: this script will not continue pipeline"
fi

WATERYR=$1

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
echo "${PROGNAME}: Begin on hostname=$thisHost on $thisDate for WATERYR=$WATERYR and options=$options"
echo "${PROGNAME}: SLURM_SCRATCH=$SLURM_SCRATCH"
echo "${PROGNAME}: SLURM_JOB_ID=$SLURM_JOB_ID"
echo "${PROGNAME}: SLURM_ARRAY_JOB_ID=$SLURM_ARRAY_JOB_ID"

#Make a unique temporary directory for matlab job storage
#Set TMPDIR/TMP to this location so job array uses it for tmp location
tmpDir=/scratch/alpine/${USER}/.matlabTmp/alpine-$SLURM_ARRAY_JOB_ID
mkdir -p $tmpDir
export TMPDIR=$tmpDir
export TMP=$tmpDir

#Go to parent of this script, so that correct pathdef.m file is used
cd "${thisScriptDir}/../"

# Do the scratch shuffle on daily Mosaics from input water year
# and for historical regional-stats files (to scratch for speed)
REGIONNAME='westernUS'
yearStart=$(( $WATERYR - 1 ))
for dataType in regional_stats/scagdrfs_mat variables/scagdrfs_mat; do
    ${thisScriptDir}/scratchShuffle.sh -b ${yearStart} -e ${WATERYR} \
		    TO ${dataType}_$LABEL ${REGIONNAME} || \
	error_exit "Line $LINENO: scratchShuffle error ${dataType} ${LABEL} ${REGIONNAME}"
done

# Do scratch shuffle for required ancillary data
${thisScriptDir}/scratchShuffleAncillary.sh || \
    error_exit "Line $LINENO: scratchShuffleAncillary error"

echo "${PROGNAME}: Done with shuffle TO scratch..."

# Make the year-to-date Statistics files
# Make the csv versions of the stats in historical context
# (only for main region array=10), make geotiffs for that last available date
matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"espEnv = ESPEnv(); "\
"mData = MODISData($options); "\
"partitionName = Regions.getPartitionNameFor("${SLURM_ARRAY_TASK_ID}"); "\
"region = Regions('"${REGIONNAME}"', partitionName, espEnv, mData); "\
"minSCP = minSCPForLinePlots(); "\
"minZ = minZForLinePlots(); "\
"runStatsForLinePlots(region, ${WATERYR}, ${WATERYR}, minSCP, minZ); "\
"waterYearDate = WaterYearDate(); "\
"region.runWriteStats(waterYearDate); "\
"if "${SLURM_ARRAY_TASK_ID}" == 10; "\
"mosaic = Mosaic(region); "\
"waterYearDate = WaterYearDate(mosaic.getMostRecentMosaicDt(waterYearDate), 0); "\
"region.runWriteGeotiffs(waterYearDate); "\
"end; "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

# Do the scratch shuffle on output regional_stats, csv files and geotiffs  back from scratch
echo "${PROGNAME}: Doing with shuffle FROM scratch..."
for dataType in regional_stats/scagdrfs_mat regional_stats/scagdrfs_csv variables/scagdrfs_geotiff; do
    ${thisScriptDir}/scratchShuffle.sh FROM ${dataType}_$LABEL ${REGIONNAME} || \
	error_exit "Line $LINENO: scratchShuffle FROM error ${dataType} ${LABEL} ${REGIONNAME}"
done
echo "${PROGNAME}: Done with shuffle FROM scratch..."

#schedule next job in pipeline to run after entire job array completes
if [ $isBatch ] && [ ! $noPipeline ]; then
    
    # get current slurm info for mail-user and stdout
    # Don't assume they are the same as at the top of this file,
    # because they can be overridden at the command line
    MAIL=`${thisScriptDir}/getSlurmMail.sh ${SLURM_JOB_ID}`
    stdoutDir=$( dirname `${thisScriptDir}/getSlurmStdout.sh ${SLURM_JOB_ID}` )

    if [ "$SLURM_ARRAY_TASK_ID" -eq "10" ]; then

	STDOUT_STEP4="${stdoutDir}/4SnTo-%j.out"
	
	#schedule Step 4 to make today's plots after this set of array jobs complete
	sbatch --dependency=afterok:$SLURM_ARRAY_JOB_ID \
	       --mail-user=${MAIL} \
	       --output=${STDOUT_STEP4} \
	       ${thisScriptDir}/runSnowTodayStep4.sh -L $LABEL $WATERYR

    fi
    
fi

#Clean up temporary directory for matlab job storage
echo "${PROGNAME}: Removing TMPDIR=$TMPDIR..."
rm -rf $TMPDIR

# Stop the stopwatch and report elapsed time
elapsedSeconds=$SECONDS
duration=$(TZ=UTC0 printf 'Duration: %(%H:%M:%S)T\n' "$elapsedSeconds")

thisDate=$(date)
echo "${PROGNAME}: Done on hostname=$thisHost on $thisDate [${duration}]"

