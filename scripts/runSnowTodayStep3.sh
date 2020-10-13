#!/bin/bash
#
# script to run SnowToday Step3:
#   update all westernUS SCF_SCD statistics files
#   for the current year
#   kick off Step4 for today
#

#SBATCH --qos normal
#SBATCH --job-name runSnowTodayStep3
#SBATCH --account=ucb135_summit2
#SBATCH --time=00:30:00
#SBATCH --ntasks-per-node=20
#SBATCH --mem=90G
#SBATCH --nodes=1
#SBATCH -o /pl/active/rittger_esp/modis/archive_status/slurm_output/runSnowTodayStep3-%j.out
# Set the system up to notify upon completion
#SBATCH --mail-type=END,FAIL,REQUEUE,STAGE_OUT
#SBATCH --mail-user=brodzik@nsidc.org

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

#Make a unique temporary directory for matlab job storage
mkdir -p $SLURM_SCRATCH/$SLURM_JOB_ID

minSCF=10
minZ=800

#Go here so that correct pathdef.m file is used
#cd /projects/brodzik/Documents/MATLAB/esp_SnowToday_ops
cd /projects/brodzik/Documents/MATLAB/esp
matlab -nodesktop -nodisplay -r "clear; "\
"runSummarizeSCA_SCDForLinePlots('westernUS', ${waterYr}, ${waterYr}, "\
"${minSCF}, ${minZ}, ${mindays}, "\
"["${northZthresh}" "${southZthresh}"]); "\
"exit(0);"

#schedule Step 4 to make today's plots
sbatch --dependency=afterok:$SLURM_JOB_ID scripts/runSnowTodayStep4.sh $mindays $northZthresh $southZthresh $minSCF $minZ

#Clean up temporary directory for matlab job storage
rm -rf $SLURM_SCRATCH/$SLURM_JOB_ID

thisDate=$(date)
echo "$0: Done on hostname=$thisHost on $thisDate"

