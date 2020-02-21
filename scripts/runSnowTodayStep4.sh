#!/bin/bash
#
# script to run SnowToday Step4:
#   Make today's SnowToday line and map plots
#   kick off Step5 for today
#

#SBATCH --qos normal
#SBATCH --job-name runSnowTodayStep2
#SBATCH --account=ucb135_summit1
#SBATCH --time=00:30:00
#SBATCH --ntasks-per-node=1
#SBATCH --nodes=1
#SBATCH -o /pl/active/rittger_esp/modis/archive_status/slurm_output/runSnowTodayStep4-%j.out
# Set the system up to notify upon completion
#SBATCH --mail-type=END,FAIL,REQUEUE,STAGE_OUT
#SBATCH --mail-user=brodzik@nsidc.org

module purge
ml matlab
date

yr=$1
mindays=$2

thisHost=$(hostname)
thisDate=$(date)
echo "$0: Begin on hostname=$thisHost on $thisDate for yr=$yr and mindays=$mindays"
echo "SLURM_SCRATCH=$SLURM_SCRATCH"
echo "SLURM_JOB_ID=$SLURM_JOB_ID"

threshSCF=10
threshZ=1200

#Go here so that correct pathdef.m file is used
cd /projects/brodzik/Documents/MATLAB/esp_SnowToday_ops
#cd /projects/brodzik/Documents/MATLAB/esp
matlab -nodesktop -nodisplay -r "clear; todayDt = datetime; plotAnnualSCA_SCDInContext('westernUS', todayDt, ${threshSCF}, ${threshZ}, ${mindays}); exit(0);"

#schedule Step 5 to push plots to NSIDC
#sbatch --dependency=afterok:$SLURM_JOB_ID scripts/runSnowTodayStep5.sh $creationDate $mindays

thisDate=$(date)
echo "$0: Done on hostname=$thisHost on $thisDate"

