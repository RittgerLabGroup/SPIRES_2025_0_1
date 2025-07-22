#!/bin/bash
#
# script to get all mod09ga files from DAAC for specific tiles and range of dates.
# Read bash/configurationForHelp.sh for all options and arguments.
#
#SBATCH --constraint=spsc
#SBATCH --export=NONE
#SBATCH --mail-type=FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,ARRAY_TASKS

export SLURM_EXPORT_ENV=ALL

# Core script.
########################################################################################
# Main script constants. 
# Can be overriden by pipeline parameters in configuration.sh, itself can be overriden
# by main script options.
scriptId=mod09gaI
defaultSlurmArrayTaskId=292
expectedCountOfArguments=
inputDataLabels=(mod09ga)
outputDataLabels=(mod09ga)
filterConfLabel=
mainBashSource=${BASH_SOURCE}
mainProgramName=${BASH_SOURCE[0]}
  # overriden by slurm in toolsStart.sh
beginTime=(19:45:00)

# Following can be overriden by pipeling configuration.sh
thisRegionType=0
thisSequence=
thisSequenceMultiplierToIndices=
thisMonthWindow=2

source bash/toolsStart.sh
if [ $? -eq 1 ]; then
  exit 1
fi

# Argument setting.
# None.

log_level_1 "start"

# Launch the ingest.
########################################################################################
# Token personal to user, in environment variable in .~/.bshrc
nrtDownloadToken=$nrt3ModapsEosdisNasaGovToken

checkFileAlreadyPresent=1
theseDates=$(seq  $(date -d "$startDate" +%s) 86400 $(date -d "$endDate + 1 day" +%s))
# I dont know why seq doesnt include the $endDate and we need to add a day for that.
# If we want an array, we add outer (), like ($(seq  $(date -d "$startDate" +%s) 86400 $(date -d "$endDate" +%s)))
# But in that case we cannot use for in anymore.


directoryPath=${scratchPath}modis/input/mod09ga/v006/
printf "Import to ${directoryPath}...\n"

cloudLpDaacDirectoryUrl="https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/MOD09GA.061/"

# Core.
########################################################################################
# Debug only (easier to handle arrays vs sequences:
# theseDates=(${theseDates})
# thisDate=${theseDates[0]}
IFS=$'\n'
alias rm=rm # To remove the lock without confirmation.
for thisDate in $theseDates; do
  # Directories of pages of url lists and of files.
  histUrlListDirectoryPath="${directoryPath}histUrlList/$(date -d @"$thisDate" +%Y)/"
  if [ ! -d ${histUrlListDirectoryPath} ]; then
    mkdir -p ${histUrlListDirectoryPath}
  fi
  histUrlListFileName="index_$(date -d   @"$thisDate" +%Y%j).html"

  thisDirectoryPath="${directoryPath}${regionName}/$(date -d @"$thisDate" +%Y)/"
  if [ ! -d ${thisDirectoryPath} ]; then
    mkdir -p ${thisDirectoryPath}
  fi

  # Check file present...
  if [[ "$checkFileAlreadyPresent" -eq 1 ]]; then
    filePresent=$(ls ${thisDirectoryPath} | grep ".A$(date -d @"$thisDate" +%Y%j).h" | grep -v ".met" | grep -v ".xml" | grep -v "NRT" | sort -r | head -n 1);

    if [ $filePresent ]; then
      printf "Skipping ${filePresent}.\n"
      continue
    fi
  fi
  printf "\n\n\n\n-----------------------------------------------------------------\n"
  printf "TIME: $(date +%Y-%m-%dT%H:%M:%S).\n"
  printf "Destination directory: ${thisDirectoryPath}.\n"
  printf "Date: ${thisDate} - $(date -d @"$thisDate" +%Y%j)."
  printf "\n-----------------------------------------------------------------\n\n"

  # Check if we already have the list of urls from previous get for the day otherwise
  # Get the list of urls for tile/day either with a new get...
  # NB: we could optimize this, because we ask the list for each tile each day
  # while the page covers all available tile for a day.                            @todo

  # NB: To be modified. Sometimes daac doesnt update the page, which leads to errors.
  # To be replaced by looking for a json
  # wget -c --no-proxy --server-response -O /${scratchPath}/20230316.json #"https://cmr.earthdata.nasa.gov/search/granules.json?echo_collection_id=C2202497474-LPCLOUD&page_num=1&page_size=500&temporal=2023-03-16T00:00:00.000Z,2023-03-16T23:59:59.999Z&sort_key=producer_granule_id"
  # and then the tile path can be filtered by
  # histListContent=$(cat /rc_scratch/sele7124/20230316.json)
  # pattern=[^@]+(https\:\/\/[a-z\/\.\-]+\/MOD09GA\.061\/MOD09GA\.A2023075\.h00v08\.061\.[0-9]+\/MOD09GA\.A2023075\.h00v08\.061\.[0-9]+\.hdf)[^@]+
  # echo $histListContent | sed -r "s~${pattern}~\1~g"
  # Beware because sometimes in the page there are tiles of the day before too!
  #                                                                                @todo

  histDirectoryUrl="https://e4ftl01.cr.usgs.gov/MOLT/MOD09GA.061/$(date -d @"$thisDate" +%Y.%m.%d)/"
  modificationDate=$(date -r /${scratchPath}/modis/input/mod09ga/v006/histUrlList/2024/index_2024085.html +%s)

  printf "\nChecking .lock file ${histUrlListDirectoryPath}${histUrlListFileName}.lock and waiting unlock...\n"
  while [[ -f ${histUrlListDirectoryPath}${histUrlListFileName}.lock ]]; do
    sleep 1
  done

  if [[ ! -s ${histUrlListDirectoryPath}${histUrlListFileName} ]] || \
[[ ! -s ${histUrlListDirectoryPath}${histUrlListFileName} && $(( $(date +%s) - $modificationDate )) > 3600 ]]; then
    printf "\nCreate .lock file ${histUrlListDirectoryPath}${histUrlListFileName}.lock.\n"
    touch ${histUrlListDirectoryPath}${histUrlListFileName}.lock
    printf "\n\nwget -c --no-proxy --server-response -O ${histUrlListDirectoryPath}${histUrlListFileName} ${histDirectoryUrl}...\n"
    for counterIdx in {1..600}; do
      wgetReturn="A"$(wget -c --no-proxy --server-response -O ${histUrlListDirectoryPath}${histUrlListFileName} ${histDirectoryUrl} 2>&1)
      isError503=$(printf "${wgetReturn}" | grep "HTTP/1.1 503 Service Unavailable" | wc -c)
      # We could have used printf "%s" to escape characters which might be understand as options by printf.
      # Here I preferred adding a "A" at the start of the reponses (to escape potential initial --).
      is202=$(printf "${wgetReturn}" | grep "HTTP/1.1 200 OK" | wc -c)
      if [[ "$isError503" -gt 0 && counterIdx -ne 600 ]]; then
        printf "${wgetReturn}"
        printf "\nRETRY #${counterIdx} in 15 sec...\n"
        sleep 15
      elif [[ "$isError503" -gt 0 && counterIdx -eq 600 ]]; then
        printf "${wgetReturn}"
        printf "\nFAILED. Max number of retrys reached.\n\n"
      elif [[ "$is202" -eq 0 ]]; then
        printf "${wgetReturn}"
        printf "\nFAILED.\n\n"
        break
      else
        printf "Done wget ${histDirectoryUrl}.\n"
        break
      fi
    done
    rm ${histUrlListDirectoryPath}${histUrlListFileName}.lock
    printf "\nDeleted .lock file ${histUrlListDirectoryPath}${histUrlListFileName}.lock.\n"
  fi
# NB: We could mutualize this way to call wget.                                      @todo
  # From the list of historic urls we get the url of the tile/day.
  tileFileList=()
  # reinitialization of tileFileList important because we use ${tileFileList[@]} in
  # the lines below, which could have kept the files of the previous date.
  if [ -s ${histUrlListDirectoryPath}${histUrlListFileName} ]; then
    histListContent=$(cat ${histUrlListDirectoryPath}${histUrlListFileName})
    thisTitle=$(echo "$histListContent" | grep "<title>" | head -1)
    printf "Title: ${thisTitle}.\n"

    histFileList=$(echo "$histListContent" | sed -r 's/^<img(.*\="MOD.*)/@@@\1/' | sed -r 's/^[^@][^@][^@][^\r^\n].*//' | sed '/^[[:space:]]*$/d' | sed -r 's/@@@[^>]*>[^>]*>(M[^ ^<]*)<\/a>[ ]*([0-9][0-9\-]* [0-9\:]*)[^<]*$/\1/')

    tileFileList=$(echo "$histFileList" | grep $regionName | grep ".A$(date -d @"$thisDate" +%Y%j).h")
    tileFileList=$(echo "${tileFileList[@]}" | tr ' ' '\n' | sort -u)
    # Sometimes the url list contains several times the same file. 2024-03-25.
  else
    printf "No file ${histUrlListDirectoryPath}${histUrlListFileName}.\n"
  fi

  # Case historic files are unavailable, we take nrt if available...
  uploadIsHistoric=1
  nrtIsAvailable=$([[ $thisDate -ge $(date --date "7 days ago" +'%s') ]] && echo 1 || echo 0)
  nrtDirectoryUrl="https://nrt3.modaps.eosdis.nasa.gov/api/v2/content/archives/allData/61/MOD09GA/$(date -d @"$thisDate" +%Y)/$(date -d @"$thisDate" +%j)/"
  if [[ -z $tileFileList && $nrtIsAvailable -eq 1 ]]; then
    uploadIsHistoric=
    # Beware, testing the condition [ $nrtIsAvailable ] is not the same, because
    # that tests if var exists.
    # We get the nrt list even if we already did before (for other tiles)
    # When we'll increase the number of tiles, maybe it should be stored         @todo
    printf "\n\nwget -qO- --no-proxy --server-response ${nrtDirectoryUrl}...\n"
    for counterIdx in {1..600}; do
      nrtListContent="A"$(wget -qO- --no-proxy --server-response ${nrtDirectoryUrl}  2>&1)
      isError503=$(printf "${nrtListContent}" | grep "HTTP/1.1 503 Service Unavailable" | wc -c)
      is202=$(printf "${nrtListContent}" | grep "HTTP/1.1 200 OK" | wc -c)
      if [[ "$isError503" -gt 0 && counterIdx -ne 600 ]]; then
        printf "${nrtListContent}"
        printf "\nRETRY #${counterIdx} in 15 sec...\n"
        sleep 15
      elif [[ "$isError503" -gt 0 && counterIdx -eq 600 ]]; then
        printf "${nrtListContent}"
        printf "\nFAILED. Max number of retrys reached.\n\n"
      elif [[ "$is202" -eq 0 ]]; then
        printf "${nrtListContent}"
        printf "\nFAILED.\n\n"
        break
      else
        break
      fi
    done
    printf "Done wget ${nrtDirectoryUrl}.\n"

    nrtFileList=$(echo "$nrtListContent" | sed -r 's/^<td><a href="([^"]*)"[^\r]*$/@@@\1/' | sed -r 's/^[^@][^@][^@][^\r^\n].*//' | sed '/^[[:space:]]*$/d' | sed -r 's/@@@([^@]*)/\1/')
    tileFileList=$(echo "$nrtFileList" | grep $regionName | grep ".A$(date -d @"$thisDate" +%Y%j).h")
  fi

  # We then download the files, the main file and the metadata file, .hdf.xml or hdf.met...
  set -o noglob
  IFS=$'\n'
  tileFileList=($tileFileList)
  set +o noglob

  if [[ ${#tileFileList[@]} -eq 0 ]]; then
    printf "NO file for ${thisDate}.\n---------------------------------------------------------------\n\n"
    continue;
  fi

  for (( fileIdx=0; fileIdx<${#tileFileList[@]}; fileIdx++ )); do
    thisFileName=${tileFileList[fileIdx]}
    if [[ ${uploadIsHistoric} -eq 1 && ${thisFileName:(-4)} == ".hdf" ]]; then
      thisFileUrl=${cloudLpDaacDirectoryUrl}${thisFileName:0:-4}/${thisFileName}
    elif [[ ${uploadIsHistoric} -eq 1 ]]; then
      thisFileUrl=${histDirectoryUrl}${thisFileName}
    else
      thisFileUrl=${thisFileName}
      # the filename here contains the directory path.
    fi
    for counterIdx in {1..600}; do
      # Retrieve historics. If earthdatacloud, dont use --no-proxy option
      # (cannot find the host in that case)
      if [[ ${uploadIsHistoric} -eq 1 && ${thisFileName:(-4)} == ".hdf" ]]; then
        printf "wget -c -t 20 --random-wait --progress=dot:giga --server-response -P ${thisDirectoryPath} ${thisFileUrl} ...\n"
        wgetReturn="A"$(wget -c -t 20 --random-wait --progress=dot:giga --server-response -P ${thisDirectoryPath} ${thisFileUrl} 2>&1)
          # can't use -N since modification header is not sent by server
          # use .netrc for domain login pwd
      elif [[ ${uploadIsHistoric} -eq 1 ]]; then
        printf "wget -c -t 20 --random-wait --no-proxy --progress=dot:giga --server-response -P ${thisDirectoryPath} ${thisFileUrl}...\n"
        wgetReturn="A"$(wget -c -t 20 --random-wait --no-proxy --progress=dot:giga --server-response -P ${thisDirectoryPath} ${thisFileUrl} 2>&1)
          # can't use -N since modification header is not sent by server
          # use .netrc for domain login pwd
      else
         printf "wget -c -t 20 --random-wait --no-proxy --progress=dot:giga --server-response -P ${thisDirectoryPath} ${thisFileUrl}...\n"
         wgetReturn="A"$(wget -c -t 20 --random-wait --no-proxy --progress=dot:giga --server-response -P ${thisDirectoryPath} ${thisFileUrl} --header "Authorization: Bearer ${nrtDownloadToken}" 2>&1)
         # For nrt, need special additional header (doesn't work for historics)
      fi

      isError503=$(printf "%s" "${wgetReturn}" | grep "HTTP/1.1 503 Service Unavailable" | wc -c)
      isError404=$(printf "%s" "${wgetReturn}" | grep "HTTP/1.1 404 Not Found" | wc -c)
      is202=$(printf "%s" "${wgetReturn}" | grep "HTTP/1.1 200 OK" | wc -c)
      # We could also catch other errors...                                  @todo
      # First case is when daac are not updated to the clouds. Did happen week of the 2024-03-20/25
      if [[ "$isError404" -gt 0 && ${uploadIsHistoric} -eq 1 && ${thisFileName:(-4)} == ".hdf" ]]; then
        thisFileUrl=${histDirectoryUrl}${thisFileName}
        echo "${wgetReturn}"
        printf "\nRETRY #${counterIdx} in 15 sec with new url ${thisFileUrl}...\n"
      elif [[ "$isError503" -gt 0 && counterIdx -ne 600 ]]; then
        echo "${wgetReturn}"
        printf "\nRETRY #${counterIdx} in 15 sec...\n"
        sleep 15
      elif [[ "$isError503" -gt 0 && counterIdx -eq 600 ]]; then
        echo "${wgetReturn}"
        printf "\nFAILED. Max number of retrys reached.\n---------------------------------------------------------------\n\n"
      elif [[ "$is202" -eq 0 ]]; then
        echo "${wgetReturn}"
        printf "\nFAILED.\n\n"
        break
      else
        printf "\nDONE wget ${thisFileUrl}.\n---------------------------------------------------------------\n\n"
        break
      fi
    done
  done
  # rsync if tile from westernUS.
  if  [[ $tilesForBigRegion[5] == *"${objectId}"* ]]; then
    /bin/rsync -HpvxrltoDu --chmod=ug+rw,o-w,+X,Dg+s ${thisDirectoryPath} ${thisDirectoryPath/${scratchPath}/${archivePath}}
    printf "\n rsync to archive.\n---------------------------------------------------------------\n\n"
  fi
done

source bash/toolsStop.sh