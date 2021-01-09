#!/bin/bash
#
# script to run SnowToday Step3:
#   update all westernUS SCF_SCD statistics files
#   for region paritions (full region, States, HUC2, etc)
#   for the current year
#   kick off Step4 for today
#

#SBATCH --qos normal
#SBATCH --job-name runSnowTodayStep3
#SBATCH --account=ucb188_summit1
#SBATCH --time=01:30:00
#SBATCH --ntasks-per-node=20
#SBATCH --mem=90G
#SBATCH --nodes=1
#SBATCH -o /pl/active/rittger_esp/modis/archive_status/slurm_output/runSnowTodayStep3-%j.out
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

thisHost=$(hostname)
thisDate=$(date)
echo "$0: Begin on hostname=$thisHost on $thisDate for waterYr=$waterYr and mindays=$mindays, zthresh=[$northZthresh $southZthresh]"
echo "SLURM_SCRATCH=$SLURM_SCRATCH"
echo "SLURM_JOB_ID=$SLURM_JOB_ID"
echo "SLURM_ARRAY_JOB_ID=$SLURM_ARRAY_JOB_ID"

#Make a unique temporary directory for matlab job storage
mkdir -p $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID
mkdir -p $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID/tmp
export TMP=$SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID/tmp
export TMPDIR=$SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID/tmp

minSCF=10
minZ=800

#Go here so that correct pathdef.m file is used
cd /projects/brodzik/Documents/MATLAB/esp_staging
matlab -nodesktop -nodisplay -r "clear; "\
"runSummarizeSCA_SCDForLinePlots('westernUS', "$SLURM_ARRAY_TASK_ID", "\
"${waterYr}, ${waterYr}, "\
"${minSCF}, ${minZ}, ${mindays}, "\
"["${northZthresh}" "${southZthresh}"]); "\
"exit(0);"

if [ "$SLURM_ARRAY_TASK_ID" -eq "10" ]; then
    
    #schedule Step 4 to make today's plots after all these array jobs complete
    sbatch --dependency=afterok:$SLURM_ARRAY_JOB_ID scripts/runSnowTodayStep4.sh $mindays $northZthresh $southZthresh $minSCF $minZ

    #schedule Step 3 to run this set of stats/plots the next time clock strikes 4pm
    sbatch --begin=16:00:00 scripts/runSnowTodayStep3.sh $waterYr $mindays $northZthresh $southZthresh
    
fi

#Clean up temporary directory for matlab job storage
rm -rf $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID

thisDate=$(date)
echo "$0: Done on hostname=$thisHost on $thisDate"

