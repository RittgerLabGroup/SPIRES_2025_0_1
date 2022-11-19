#!/bin/bash
#
# script to run SnowToday Step2:
#   update westernUS daily mosaic files for this year for all variables
#   kick off Step3 for today
#

#SBATCH --qos normal
#SBATCH --partition amilan
#SBATCH --job-name 2SnTo
#SBATCH --account ucb-general
#SBATCH --time=02:00:00
#SBATCH --ntasks-per-node=20
#SBATCH --nodes=1
#SBATCH -o /scratch/alpine/%u/slurm_out_SnowToday/%x-%A_%a.out
# Set the system up to notify upon completion
#SBATCH --mail-type FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,STAGE_OUT
#SBATCH --mail-user brodzik@colorado.edu,crumlyd@nsidc.org

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
    echo "Usage: ${PROGNAME} [-h] [-n] [-L LABEL] " 1>&2
    echo "       YEARSTART MONTHSTART YEARSTOP MONTHSTOP DAYSTOP" 1>&2
    echo "  Runs Step2 in SnowToday pipeline" 1>&2
    echo "  Updates WesternUS daily mosaic files for all variables" 1>&2
    echo "    and the requested time period" 1>&2
    echo "  If called by slurm:" 1>&2
    echo "    starts SnowTodayStep3 for today" 1>&2
    echo "Options: "  1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "  -n: no pipeline: suppress starting next pipeline step" 1>&2
    echo "  -L LABEL: string with version label for directories" 1>&2
    echo "     e.g. for operational processing, use -L v2023.x" 1>&2
    echo "Arguments: " 1>&2
    echo "  YEARSTART : year to begin" 1>&2
    echo "  MONTHSTART : month to begin" 1>&2
    echo "  YEARSTOP : year to stop" 1>&2
    echo "  MONTHSTOP : month to stop" 1>&2
    echo "  DAYSTOP : day to stop" 1>&2
    echo "Output: " 1>&2
    echo "  Output location is controlled in Matlab scripts and -L LABEL " 1>&2
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

[[ "$#" -eq 5 ]] || error_exit "Line $LINENO: Unexpected number of arguments."

if [ $noPipeline ]; then
    echo "${PROGNAME}: noPipeline mode: this script will not continue pipeline"
fi

yearStart=$1
monthStart=$2
yearStop=$3
monthStop=$4
dayStop=$5

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
echo "${PROGNAME}: Begin on hostname=$thisHost on $thisDate for options=$options"
echo "${PROGNAME}: Start = $yearStart, $monthStart"
echo "${PROGNAME}: Stop  = $yearStop, $monthStop, $dayStop"
echo "${PROGNAME}: SLURM_SCRATCH=$SLURM_SCRATCH"
echo "${PROGNAME}: SLURM_JOB_ID=$SLURM_JOB_ID"

#Make a unique temporary directory for matlab job storage
#Set TMPDIR/TMP to this location so job array uses it for tmp location
tmpDir=/scratch/alpine/${USER}/.matlabTmp/alpine-$SLURM_JOB_ID
mkdir -p $tmpDir
export TMPDIR=$tmpDir
export TMP=$tmpDir

#Go to parent of this script, so that correct pathdef.m file is used
cd "${thisScriptDir}/../"

# Do the scratch shuffle on required STC inputs
for dataType in scagdrfs_stc; do
    for tile in h08v04 h08v05 h09v04 h09v05 h10v04; do
	${thisScriptDir}/scratchShuffle.sh -b ${yearStart} -e ${yearStop} \
			TO intermediary/${dataType}_$LABEL ${tile} || \
	    error_exit "Line $LINENO: scratchShuffle error ${dataType} ${tile}"
    done
done

# Do scratch shuffle for required ancillary data
${thisScriptDir}/scratchShuffleAncillary.sh || \
    error_exit "Line $LINENO: scratchShuffleAncilllary error"

echo "${PROGNAME}: Done with shuffle TO scratch, doing Step2 processing..."

REGIONNAME='westernUS'

if (( "$yearStart" == "$yearStop" )); then
    monthWindow=$(( $monthStop - $monthStart + 1 ))
else
    monthWindow=$(( 12 - $monthStart + 1 + $monthStop))
fi
if (( "$monthWindow" > 12 )); then
    echo "Limiting monthWindow to 12"
    monthWindow=12
fi
if (( "$monthWindow" < 1 )); then
    error_exit "Invalid monthWindow, please check inputs."
fi

echo "${PROGNAME}: monthWindow=${monthWindow}"

matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"espEnv = ESPEnv(); "\
"mData = MODISData($options); "\
"region = Regions('"$REGIONNAME"', '"$REGIONNAME"_mask', espEnv, mData); "\
"waterYearDate = WaterYearDate(datetime("${yearStop}", "${monthStop}", "${dayStop}"), "${monthWindow}"); "\
"mosaic = Mosaic(region); "\
"mosaic.runWriteFiles(waterYearDate); "\
"variables = Variables(region); "\
"variables.calcAlbedos(waterYearDate); "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

# Do the scratch shuffle on output daily Mosaics (back from scratch to archive)
for dataType in scagdrfs_mat; do
    ${thisScriptDir}/scratchShuffle.sh -b ${yearStart} -e ${yearStop} \
		    FROM variables/${dataType}_$LABEL ${REGIONNAME} || \
	error_exit "Line $LINENO: scratchShuffle error ${dataType} ${LABEL} ${regionName}"
done

# FORCE NO PIPELINE FOR NOW
noPipeline=1

if [ $isBatch ] && [ ! $noPipeline ]; then
    
    # get current slurm info for mail-user and stdout
    # Don't assume they are the same as at the top of this file,
    # because they can be overridden at the command line
    MAIL=`${thisScriptDir}/getSlurmMail.sh ${SLURM_JOB_ID}`

    stdoutDir=$( dirname `${thisScriptDir}/getSlurmStdout.sh ${SLURM_JOB_ID}` )
    STDOUT_STEP3="${stdoutDir}/3SnTo-%A_%a.out"

    #schedule Step 3 to update stats
    waterYr=$yearStop
    if (( "$monthStop" > "9" )); then
	waterYr=$(( $waterYr + 1 ))
    fi
    sbatch --dependency=afterok:$SLURM_JOB_ID \
	   --mail-user=${MAIL} \
	   --output=${STDOUT_STEP3} \
	   ${thisScriptDir}/runSnowTodayStep3.sh -L $LABEL $waterYr

else
    
    echo "${PROGNAME}: Not continuing pipeline for non-sbatch call."

fi


#Clean up temporary directory for matlab job storage
echo "${PROGNAME}: Removing TMPDIR=$TMPDIR..."
rm -rf $TMPDIR

# Stop the stopwatch and report elapsed time
elapsedSeconds=$SECONDS
duration=$(TZ=UTC0 printf 'Duration: %(%H:%M:%S)T\n' "$elapsedSeconds")

thisDate=$(date)
echo "${PROGNAME}: Done on hostname=$thisHost on $thisDate [${duration}]"

