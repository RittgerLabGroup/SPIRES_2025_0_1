#!/bin/bash
#
# script to run SnowToday Step3 historical:
#   update all westernUS SCF_SCD statistics files
#   for region paritions (full region, States, HUC2, etc)
#   for prior history to the current year
#

#SBATCH --qos normal
#SBATCH --job-name runSnowTodayStep3Historical
#SBATCH --account=ucb188_summit1
#SBATCH --time=02:30:00
#SBATCH --ntasks-per-node=20
#SBATCH --mem=90G
#SBATCH --nodes=1
#SBATCH -o /pl/active/rittger_esp/modis/archive_status/slurm_output/runSnowTodayStep3Historical-%j.out
# Set the system up to notify upon completion
#SBATCH --mail-type=END,FAIL,REQUEUE,STAGE_OUT
#SBATCH --mail-user=brodzik@nsidc.org
#SBATCH --array=10-12

module purge
ml matlab/R2019b
date

waterYr=$1
mindays=$2
northZthresh=$3
southZthresh=$4

startWaterYr=2001
stopWaterYr=$(( $waterYr - 1 ))

thisHost=$(hostname)
thisDate=$(date)
echo "$0: Begin on hostname=$thisHost on $thisDate for array job=$SLURM_ARRAY_JOB_ID and WY=$startWaterYr to $stopWaterYr and mindays=$mindays, zthresh=[$northZthresh $southZthresh]"
echo "SLURM_SCRATCH=$SLURM_SCRATCH"
echo "SLURM_JOB_ID=$SLURM_JOB_ID"
echo "SLURM_ARRAY_JOB_ID=$SLURM_ARRAY_JOB_ID"

#Make a unique temporary directory for matlab job storage
mkdir -p $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID

minSCF=10
minZ=800

#Go here so that correct pathdef.m file is used
cd /projects/brodzik/Documents/MATLAB/esp_staging
matlab -nodesktop -nodisplay -r "clear; "\
"runSummarizeSCA_SCDForLinePlots('westernUS', "$SLURM_ARRAY_TASK_ID", "\
"${startWaterYr}, ${stopWaterYr}, "\
"${minSCF}, ${minZ}, ${mindays}, "\
"["${northZthresh}" "${southZthresh}"]); "\
"exit(0);"

#Clean up temporary directory for matlab job storage
rm -rf $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID

thisDate=$(date)
echo "$0: Done on hostname=$thisHost on $thisDate"

