#!/bin/bash
#
# script to run SnowToday Step2:
#   update westernUS daily mosaic files for this year for all variables
#   kick off Step3 for today
#

#SBATCH --qos normal
#SBATCH --job-name runSnowTodayStep2
#SBATCH --account=ucb188_summit1
#SBATCH --time=02:00:00
#SBATCH --ntasks-per-node=10
#SBATCH --nodes=1
#SBATCH --mem=40G
#SBATCH -o /pl/active/rittger_esp/modis/archive_status/slurm_output/runSnowTodayStep2-%j.out
# Set the system up to notify upon completion
#SBATCH --mail-type=FAIL,REQUEUE,STAGE_OUT
#SBATCH --mail-user=brodzik@nsidc.org

module purge
ml matlab/R2019b
date

yr=$1
mindays=$2
northZthresh=$3
southZthresh=$4
monthStart=$5
monthStop=$6

thisHost=$(hostname)
thisDate=$(date)
echo "$0: Begin on hostname=$thisHost on $thisDate for yr=$yr and mindays=$mindays"
echo "SLURM_SCRATCH=$SLURM_SCRATCH"
echo "SLURM_JOB_ID=$SLURM_JOB_ID"

#Make a unique temporary directory for matlab job storage
mkdir -p $SLURM_SCRATCH/$SLURM_JOB_ID
mkdir -p $SLURM_SCRATCH/$SLURM_JOB_ID/tmp
export TMP=$SLURM_SCRATCH/$SLURM_JOB_ID/tmp

#Go here so that correct pathdef.m file is used
cd /projects/brodzik/Documents/MATLAB/esp_SnowToday_ops
#cd /projects/brodzik/Documents/MATLAB/esp_staging

matlab -nodesktop -nodisplay -r "clear; "\
"varNames={'snow_fraction', 'viewable_snow_fraction', 'grain_size', "\
"'drfs_grnsz', 'deltavis', 'radiative_forcing', "\
"'albedo_clean_mu0', 'albedo_observed_mu0', "\
"'albedo_clean_muZ', 'albedo_observed_muZ'}; "\
"updateMosaicFor('westernUS', ${yr}, varNames, ${mindays}, "\
"'monthStart', ${monthStart}, 'monthStop', ${monthStop}, "\
"'zthresh', ["${northZthresh}" "${southZthresh}"]); "\
"exit(0);"

#schedule Step 3 to update stats
thisMonth=$(date +'%m')
waterYr=$yr
if (( "$thisMonth" > "9" )); then
    waterYr=$(( $waterYr + 1 ))
fi
sbatch --dependency=afterok:$SLURM_JOB_ID scripts/runSnowTodayStep3.sh $waterYr $mindays $northZthresh $southZthresh

#Clean up temporary directory for matlab job storage
rm -rf $TMP

thisDate=$(date)
echo "$0: Done on hostname=$thisHost on $thisDate"

