#!/bin/bash
#
# script to run SnowToday Step4:
#   Make today's SnowToday line and map plots
#   kick off Step5 for today
#

#SBATCH --qos normal
#SBATCH --job-name runSnowTodayStep4
#SBATCH --account=ucb135_summit1
#SBATCH --time=02:00:00
#SBATCH --ntasks-per-node=20
#SBATCH --nodes=1
#SBATCH --mem=90G
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

#Make a unique temporary directory for matlab job storage
mkdir -p $SLURM_SCRATCH/$SLURM_JOB_ID

threshSCF=10
threshZ=1200

#Go here so that correct pathdef.m file is used
cd /projects/brodzik/Documents/MATLAB/esp_SnowToday_ops
#cd /projects/brodzik/Documents/MATLAB/esp
matlab -nodesktop -nodisplay -r "clear; todayDt = datetime; plotAnnualSCA_SCDInContext('westernUS', todayDt, ${threshSCF}, ${threshZ}, ${mindays}); showSCF_SCD('westernUS', todayDt, ${threshSCF}, ${threshZ}, ${mindays}); exit(0);"

#use Step 5 to push plots to NSIDC (no need for slurm)
creationDate=$(date +'%Y%m%d')
 . ./scripts/runSnowTodayStep5.sh $creationDate $mindays

#Clean up temporary directory for matlab job storage
rm -rf $SLURM_SCRATCH/$SLURM_JOB_ID

thisDate=$(date)
echo "$0: Done on hostname=$thisHost on $thisDate"

