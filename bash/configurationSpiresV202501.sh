#!/bin/bash
#
# Initialize all configuration parameters, including versions of files.

# Script core.
########################################################################################
source env/.matlabEnvironmentVariablesSpiresV202501

# Configuration of scriptIds associated to script relative filePaths.
########################################################################################
# scriptIds=(mod09gaI spiFillC spiSmooC moSpires scdInCub daMosaic snoStep3 webExpSn)
declare -A scriptIdFilePathAssociations
scriptIdFilePathAssociations[mod09gaI]="./bash/runGetMod09gaFiles.sh"
scriptIdFilePathAssociations[spiInges]="./bashSpiresV202501/runSpiresInversor.sh"
  # Same script as spiInver.
scriptIdFilePathAssociations[spiBackg]="./bashSpiresV202501/runSpiresAncillary.sh"
scriptIdFilePathAssociations[spiInver]="./bashSpiresV202501/runSpiresInversor.sh"
scriptIdFilePathAssociations[spiTimeI]="./bashSpiresV202501/runSpiresTimeInterpolator.sh"
scriptIdFilePathAssociations[moSpires]="./bash/runUpdateMosaicWithSpiresData.sh"
scriptIdFilePathAssociations[daNetCDF]="./bash/runESPNetCDF.sh"
scriptIdFilePathAssociations[daMosBig]="./bash/runUpdateMosaicBigRegion.sh"
scriptIdFilePathAssociations[daGeoBig]="./bash/runUpdateGeotiffBigRegion.sh"
scriptIdFilePathAssociations[daStatis]="./bash/runUpdateDailyStatistics.sh"
scriptIdFilePathAssociations[webExpSn]="./bash/runWebExportSnowToday.sh"
scriptIdFilePathAssociations[ftpExpor]="./bash/runFtpExport.sh"
scriptIdFilePathAssociations[rSynchro]="./bash/runSync.sh"

########################################################################################
# Versions of ancillary data.
########################################################################################
declare -A thoseVersionsOfAncillary
# For all regions.
defaultVersionOfAncillary=v3.2
# but specific case for regions: h08v04 h08v05 h09v04 h09v05 h10v04 westernUS.
thoseVersionsOfAncillary[292]=v3.1
thoseVersionsOfAncillary[293]=v3.1
thoseVersionsOfAncillary[328]=v3.1
thoseVersionsOfAncillary[329]=v3.1
thoseVersionsOfAncillary[364]=v3.1
thoseVersionsOfAncillary[5]=v3.1

########################################################################################
# Month/monthwindow configuration for generation of historics.
########################################################################################

declare -A monthsForConfOfMonths
monthsForConfOfMonths[10]="3 6 9 12"
monthsForConfOfMonths[11]="1 2 3 4 5 6 7 8 9 10 11 12"
monthsForConfOfMonths[20]="12"
monthsForConfOfMonths[21]="10 11 12"
monthsForConfOfMonths[30]="3 6 9"
monthsForConfOfMonths[31]="1 2 3 4 5 6 7 8 9"
monthsForConfOfMonths[41]="6 7 8 9"
monthsForConfOfMonths[51]="9"
monthsForConfOfMonths[120]="3"
monthsForConfOfMonths[121]="1 2 3"
monthsForConfOfMonths[130]="6 9 12"
monthsForConfOfMonths[131]="4 5 6 7 8 9 10 11 12"
monthsForConfOfMonths[141]="12"

declare -A monthWindowsForConfOfMonths
monthWindowsForConfOfMonths[10]=3
monthWindowsForConfOfMonths[11]=1
monthWindowsForConfOfMonths[20]=3
monthWindowsForConfOfMonths[21]=1
monthWindowsForConfOfMonths[30]=3
monthWindowsForConfOfMonths[31]=1
monthWindowsForConfOfMonths[41]=1
monthWindowsForConfOfMonths[51]=12
monthWindowsForConfOfMonths[120]=3
monthWindowsForConfOfMonths[121]=1
monthWindowsForConfOfMonths[130]=3
monthWindowsForConfOfMonths[131]=1
monthWindowsForConfOfMonths[141]=1

########################################################################################
# Configuration of pipelines with succession of scripts and versions of file data.
########################################################################################
# Implemented like this because not possible to put arrays in values of a dictionary.

########################################################################################
# Pipeline 3, for regions with implementation >= v2025.0.1.
########################################################################################
# pipeLineScriptIds3=(mod09gaI spiInver spiSmooC moSpires daNetCDF daGeoBig daStatis webExpSn ftpExpor)
pipeLineBigRegionId3=7 # New Zealand.
pipeLineVersionOfAncillary3=v3.2
pipeLineInputProductAndVersion3=mod09ga.061
pipeLineControlScriptId3=snr25017
pipeLineControlTime3=11:30:00
thatLabel=v2025.0.1;
pipeLineScriptIds3=(mod09gaI spiInver spiTimeI moSpires daNetCDF daGeoBig daStatis ftpExpor webExpSn)
pipeLineLabels3=(v061 ${thatLabel} ${thatLabel} ${thatLabel} ${thatLabel} ${thatLabel} ${thatLabel} ${thatLabel} ${thatLabel}) 
pipeLineRegionTypes3=(0 0 0 0 0 1 1 1 10)
  # 0: tile, 1: big region, 10: all regions.
pipeLineSequences3=(0 0 001-036 0 0 0 999 0 0)
  # NB: probably need to adapt the number of sequences for daStatis dynamically as a
  # function of the nb of subdivisions. Chose 001 for New Zealand.                 @todo
  # 999 indicates that the sequence will be updated during the run by toolStart.sh as
  # a function of landsubdivisions available per bigRegion.
pipeLineSequenceMultiplierToIndices3=(1 1 1 1 1 1 3 1 1)
pipeLineMonthWindows3=(2 2 12 12 12 0 12 12 12)
pipeLineParallelWorkersNb3=(0 14 10 14 2 0 0 0 0) # moSpires temporarily to 14 rather than 10 

# sbatch parameters
pipeLineTasksPerNode3=(1 14 10 18 2 1 1 1 1) # moSpires temporarily to 18 rather than 10 
pipeLineMems3=(1G 44G 60G 60G 5G 8G 8G 1G 3G) # spiTimeI: set temporarily 60G rather than 30G. to confirm!! spiMo: set temporarily to 60G rather than 40G.
pipeLineTimes3=(01:30:00 01:45:00 02:30:00 04:30:00 00:30:00 00:20:00 04:00:00 01:30:00 01:30:00) # mosaic temporarily to 4:30 rather than 0:30
# NB: daGeoBig: time for generation of the last day only.
# NB: daStatis: time for 3 subdivisions only.

# Bypassing the unavailability of declare -n in bash 4.2.
# declare -n could have been used in toolsStart.sh to reference these arrays, but
# it's only available in bash 4.4, while blanca/login/alpine nodes are in bash 4.2
printf -v pipeLineScriptIdsString3 '%s ' ${pipeLineScriptIds3[@]}
printf -v pipeLineLabelsString3 '%s ' ${pipeLineLabels3[@]}
printf -v pipeLineRegionTypesString3 '%s ' ${pipeLineRegionTypes3[@]}
printf -v pipeLineSequencesString3 '%s ' ${pipeLineSequences3[@]}
printf -v pipeLineSequenceMultiplierToIndicesString3 '%s ' ${pipeLineSequenceMultiplierToIndices3[@]}
printf -v pipeLineMonthWindowsString3 '%s ' ${pipeLineMonthWindows3[@]}
printf -v pipeLineParallelWorkersNbString3 '%s ' ${pipeLineParallelWorkersNb3[@]}
printf -v pipeLineTasksPerNodeString3 '%s ' ${pipeLineTasksPerNode3[@]}
printf -v pipeLineMemsString3 '%s ' ${pipeLineMems3[@]}
printf -v pipeLineTimesString3 '%s ' ${pipeLineTimes3[@]}