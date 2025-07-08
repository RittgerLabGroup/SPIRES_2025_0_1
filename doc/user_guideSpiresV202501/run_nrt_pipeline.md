# Daily job submission

This page presents the submission of the daily update of near-real-time (NRT) snow property data from the collection of input products to the export of output products for the Snow-Today web-app and for other users (netcdf data files).

## Run as a beginner.

The entry script to launch submission is `bash/submitNrt.sh`. This script submits a submit line using the script `bash/runSubmitter.sh` for a job to a slurm cluster. When slurm starts the job, `runSubmitter.sh` monitors the submission to slurm of a sequence of secondary, operational jobs to carry out the generation of data and achieve the full run ([code interactions](code_organization.md#Code_interactions_within_a_submission_to_Slurm)). This generation is carried out in a sequence of several steps, each step corresponding to a series of parallel jobs.

The near real time jobs use the same scripts for each step as for the [historic jobs](run_historic_step.md), with different parameters and in a automatized sequential way, which is not the case for the historics, which are run each step individually.

To run the full pipeline in ***production***, the user first connect to a login node. After `cd` to the root of this project, the user executes:
`bash/submitNrt.sh -E SpiresV202501 -Z 3`.

WARNING: This command is for production only. See the procedure for [testing in integration](#run_for_testing).

The scripts prints the options given and load some configuration, and then it shows the submitLine that will be submitted to slurm and ask confirmation:

```bash
sbatch   --account=XX --qos=XX -o XX/slurm_out/%x_%a_%A.out --job-name=spnr2410 --ntasks-per-node=1 --mem=1G --time=11:30:00 --array=1 bash/runSubmitter.sh "sbatch  --account=XX --qos=XX -o XX/slurm_out/%x_%a_%A.out --job-name=mod09gaI --cpus-per-task=1 --ntasks-per-node=1 --mem=1G --time=01:30:00 --array=1057,1093 ./bash/runGetMod09gaFiles.sh -A v3.2 -L v061 -O v061 -p mod09ga.061 -w 0 -x XX -y XX -Z 3"
Do you want to proceed? (y/n)
```

The user confirms `y` and the script submits the job and prints:
```
Submission...
Submitted batch job 20164305
```

The user notes the job id of the `runSubmitter.sh`, here `20164305` and can follow its execution:
- with the help of [slurm](https://slurm.schedmd.com/documentation.html) commands `squeue`, `sacct`, `scontrol`,
- and with the help of the [logs](checking_log.md).

To run it without the prompt:
`bash/submitNrt.sh -E SpiresV202501 -v 10 -Z 3`. The script will achieve without waiting the user's input and will submit the job.


## Run for testing.

The production command launches a series of steps, which includes the update of the production archive and the production snow-today web-app with the output data.

For testing, the user should first `rsync` the folders `modis_ancillary`, `modis`, and `mod09ga` from the production archive (`$espArchiveDirOps` defined in `.bashrc`) to their scratch (`$espScratchDir` defined in `.bashrc`).

Then the user can execute:
`bash/submitNrt.sh -E SpiresV202501 -W 1 -y ${espScratchDir} -Z 3`.

With that command, the update of the production archive is neutralized (no rsync to there) and the output data are sent to the integration web-app (this may be an issue if another user works on integration too).


## Options and argument for submitNrt

We already saw that `submitNrt.sh` has 2 obligatory "options":
- `-E thisEnvironment`: String, obligatory. E.g. SpiresV202501, Dev. Gives the environment version, to distinguish between different version of the algorithm used to calculate snow properties.
- `-Z pipelineId`: Int, obligatory. E.g. 1. Should refer to a pipelineId defined in `configurationSpiresV202501.sh`.

Except for advanced use, the user does not have to change the values for these options. Here `-E SpiresV202501` indicates the code to take first any configuration that was updated specifically for this project. `-Z 3` indicates the code to take the pipeline configuration of pipeline `3` configured in `bash/configurationSpiresV202501`, which is the pipeline using SPIReS v2025.0.1 for the region `OCNewZealand` and potentially others.

For testing use, two other options are also used:
- `-y archivePath`: String, optional. Default `$espArchiveDirOps` defined in `.bashrc`. Directory path of the archive from which are collected the most up-to-date data of previous days to the scratch of the user, and to which output data are rsync from this scratch.
- `-W espWebExportConfId`: Int, optional. Configuration id of the target of web export server. 0: Prod (default), 1: Integration, 2: QA. So 

 So then, for testing we set `-W 1 -y ${espScratchDir}`, which means that the code will export the data to the integration website and will rsync the data from the user's scratch to the user's scratch, in short will not do any rsync.


Other optional options are available for various scenarios. 

Scenario 1: Imagine the pipeline run broke, and you need to resubmit it. If a part of the steps were correctly executed, you can resubmit the pipeline starting at a step farther in the pipeline than the first step (default). This is done by adding an argument:
- `scriptId`: String, optional. Default: First script of the pipeline. Code of the script to start the pipeline with. Should have values in `$pipeLineScriptIds${pipelineId}` defined in `configurationSpiresV202501.sh`.

For instance: `bash/submitNrt.sh -E SpiresV202501 -Z 3 daStatis`, to start at the generation of statistics step.

Scenario 2: If you want only to run one step and not the full pipeline, you can use:
- `-U thisStepOnly`: Int, optional. Default: 0, all steps after the script `scriptId` will be executed. 1: only the given step will be executed (=break the pipeline after the step).

Scenario 3: If you want to lower or increase the slurm wall-time of the pipeline:
- `-T controlTime`: String format 00:00:00, optional. Wall-time of the `runSubmitter.sh` execution, beyond which the monitoring of the pipeline will be stopped. By default, time indicated in `configurationSpiresV202501.sh` for the pipeline, `$pipeLineControlTime3` for `$pipelineId` = 3.

Scenario 4: you want to automatize the launch of the script, for instance using a chron:
- `-v verbosity`: Int, optional. Default: 0, all logs, including prompts. 10: all logs,
  but no prompt, the script will execute until the end without waiting user's input.
    
## What the script does.    

The script starts by printing the current directory (working directory). Then it collects the option and argument values and print a synthesis, with default values if necessary.

Then it loads `bash/configurationSpiresV202401.sh`, `SpiresV202501` being the option `-E thisEnvironment` given to `submitNrt.sh`. That script first loads `env/.matlabEnvironmentVariablesSpiresV202501`, where all matlab paths are configured for this project. And then it instantiates the configuration of each step of the pipeline `3`, given by the parameter `-Z pipelineId`. The configuration includes the configuration of the pipeline itself, that is (1) the sequence of scripts to execute, given by `pipeLineScriptIds3` for `pipelineId=3`, (2) the big regions for which data will be generated (not too many regions can be added to a pipeline, it sometimes requires to create an additional pipeline), but also (3) individual slurm step submission options such as task number, memory, time-wall.

Once done, the script loads `bash/toolsRegion.sh`. That script instantiates all the region configuration, mainly from `conf/configuration_of_regions.csv`, with a few hard-coded variables.

Then, the script indicates where the pipeline will start, here it should indicate the first step, `mod09gaI`.

Then, the scripts shows the submitLine that will be submitted to slurm and ask confirmation:

```bash
sbatch   --account=XX --qos=XX -o XX/slurm_out/%x_%a_%A.out --job-name=spnr2410 --ntasks-per-node=1 --mem=1G --time=11:30:00 --array=1 bash/runSubmitter.sh "sbatch  --account=XX --qos=XX -o XX/slurm_out/%x_%a_%A.out --job-name=mod09gaI --cpus-per-task=1 --ntasks-per-node=1 --mem=1G --time=01:30:00 --array=1057,1093 ./bash/runGetMod09gaFiles.sh -A v3.2 -L v061 -O v061 -p mod09ga.061 -w 0 -x XX -y XX -Z 3"
Do you want to proceed? (y/n) y
```

In this submitLine 1, there is a part submitting `bash/runSubmitter.sh` with its options and another submitLine 2, which is the argument of `runSubmitter.sh`:
```bash
sbatch  --account=XX --qos=XX -o XX/slurm_out/%x_%a_%A.out --job-name=mod09gaI --cpus-per-task=1 --ntasks-per-node=1 --mem=1G --time=01:30:00 --array=1057,1093 ./bash/runGetMod09gaFiles.sh -A v3.2 -L v061 -O v061 -p mod09ga.061 -w 0 -x XX -y XX -Z 3
```

This second submitLine will be the submission of the first step of the pipeline. 

After the user's reply "y", `runSubmitter.sh` job is submitted. Once started, it will submit the submitLine 2, which will launch a set of jobs corresponding to the first step (or the step given in argument). Then, this step N will submit the next step N+1, with a dependency of the correct execution of step N. And so on sequentially. All along the execution, `runSubmitter.sh` monitors the correct execution of the jobs, update their last line once they achieved, to have a track that they correctly achieved, track that you can scan with the tips in [checking_log](checking_log.md). If a job failed, and if the failure belongs to a set of specific errors, `runSubmitter.sh` will automatically resubmit the job.

(Step 1) It starts by submitting the jobs to download the mod09ga files. Then it submits the 2 steps (Step 2 and Step 3) of the SPIReS v2025.0.1 algorithm in a row, generating 2 intermediary types of files (`spiInver` and `spiTimeI`). Then (Steps 4 to 7), it submits the steps handling complementary calculation and the generation of the output files (netcdfs, statistics, web-app files). Last (step 8 and 9), it will submit the job rsyncing the output files to the archive and determine the regions to send to the web-app and send them the data.

## Requirements

- The submission should be done on a login node that can submit jobs to a slurm cluster (and not directly from a node of the cluster).

- The submission script **must** be executed once the user is at the root of the project.

- The user needs to have environment variable and alias definition files stored in their home directory: `~.bashrc`, `~.netrc`, `env/.matlabEnvironmentVariablesSpiresV202501`.

- For production (= data that have the potential to be published), the log directory should be unique among all users and users should have r/w access to it, see [installation](install.md#Initialize_the_environment_file_bashrc)

## Previous data generation requirements

The pipeline has some expectations over the input and intermediary data available.

- For a water year N (westernUS), the `SpiresInversor` data **must** have been generated starting Sept, N - 1 until date of today - 2 months. For instance, if date of today = 03/15/2025, the data must have been generated from 09/01/2024 to 01/31/2025.

- The `dailycsv` statistic files of previous years **must** have been generated, for a correct display on the snow-today website.

- The output .netcdf and `dailycsv` files are generated for the full ongoing water year, from 10/1 until date of today - 1. The geotiffs for the web-app are only generated for the last day.

## Location of input, intermediary, and output data.

Filepaths are determined in a central way by a dedicated DataManager class, `ESPEnv`. `ESPEnv` also handles I/O operations. Each type of file has a specific label, `dataLabel`. The associated file path pattern is configured in `conf/configuration_of_filepathsSpires.csv`. And the DataManager transforms this pattern in an actual filepath by replacing the variables contained in the pattern by their value. This notably includes the region or tile, the date, the year, or the wateryear. For instance, respectively `h08v04`, `20250625` for the date `06-25-2025`, `2025`, `WY2025` for waterYear 2025.

For SPIReS v2025.0.1, one step, `daGeoBig`, is not handled by `ESPEnv` and the files are hard-coded in the scripts.

Here are the input and output dataLabels used for each step of the pipeline:

| # | scriptId | inputDataLabel | outputDataLabel |
|---|---|---|---|
| 1 | mod09gaI |  | mod09ga |
|---|---|---|---|
| 2 | spiInver | mod09ga | modspiresdailytifsinu |
|   |   |   | modspiresdailymetadatajson |
|---|---|---|---|
| 3 | spiTimeI | modspiresdailytifsinu | modspirestimebycell |
|   |   | modspiresdailymetadatajson| |
|---|---|---|---|
| 4 | moSpires | modspirestimebycell | VariablesMatlab |
|---|---|---|---|
| 5 | daNetCDF | VariablesMatlab | outputnetcdf |
|---|---|---|---|
| 6 | daGeoBig | VariablesMatlab | VariablesGeotiff |
|---|---|---|---|
| 7 | daStatis | VariablesMatlab | SubdivisionStatsDailyCsv |
|   |   |  | SubdivisionStatsAggregCsv |
|   |   |  | SubdivisionStatsWebJson |
|   |   |  | SubdivisionStatsWebCsvv20231 |
|---|---|---|---|
| 8 | ftpExpor |  | modisspiresfill |
|   |   |  | VariablesMatlab |
|   |   |  | outputnetcdf |
|   |   |  | VariablesGeotiff |
|   |   |  | SubdivisionStatsWebCsvv20231 |
|   |   |  | SubdivisionStatsAggregCsv |
|---|---|---|---|
| 9 | webExpSn | VariablesGeotiff |  |
|   |   | SubdivisionStatsWebJson |  |
|   |   | SubdivisionStatsWebCsvv20231 |  |
|---|---|---|---|


The current (2025-07-07) directories where the files are located:
| dataLabel | directoryPath | comment |
|---|---|---|
| mod09ga | modis/input/mog09ga.061/v006/{objectName}/{thisYear}/ | |
|---|---|---|
| modspiresdailytifsinu | {inputProduct}.{inputProductVersion},spires,{version},int_day,{objectName},{thisYear},{thisDate}/ | |
|---|---|---|
| modspiresdailymetadatajson | {inputProduct}.{inputProductVersion},spires,{version},int_day,{objectName},{thisYear},{thisDate} | |
|---|---|---|
| modspirestimebycell | {inputProduct}.{inputProductVersion},spires,{version},int_timebycell,{objectName}/ | |
|---|---|---|
| VariablesMatlab | modis/variables/scagdrfs_mat_{version}/v006/{objectName}/{thisYear}/ | on `$espArchiveDirOps`: output/mod09ga.061/spires/${dataLabel}/mat/ |
|---|---|---|
| outputnetcdf | output/{inputProduct}/{inputProductVersion}/{algorithm}/{version}/netcdf/{objectName}/{thisYear}/ | on `$espArchiveDirOps`: output/mod09ga.061/spires/${dataLabel}/netcdf/ |
|---|---|---|
| VariablesGeotiff | modis/variables/scagdrfs_geotiff_(version}/v006/{objectName}/EPSG_3857/LZW/{thisYear}/ | on `$espArchiveDirOps`: output/mod09ga.061/spires/${dataLabel}/tif_EPSG3857/ |
|---|---|---|
| SubdivisionStatsDailyCsv | modis/subdivisionstats/scagdrfs_dailycsv_{version}/v006/{objectId_1000}/{thisYear}/ | |
|---|---|---|
| SubdivisionStatsAggregCsv | modis/subdivisionstats/scagdrfs_aggregcsv_{version}/v006/{objectId_1000} | on `$espArchiveDirOps`: output/mod09ga.061/spires/${dataLabel}/aggregcsv/ |
|---|---|---|
| SubdivisionStatsWebJson | modis/subdivisionstats/scagdrfs_webjson_{version}/v006/{objectId_1000}/{objectId}/{thisYear} | |
|---|---|---|
| SubdivisionStatsWebCsvv20231 | modis/regional_stats/scagdrfs_csv_{version}/v006/{sourceRegionName}/WY{thisYear}/ | on `$espArchiveDirOps`: output/mod09ga.061/spires/${dataLabel}/csv/ |
|---|---|---|

where:
- {algorithm} = spires
- {inputProduct} = mod09ga
- {inputProductVersion} = 061
- {objectId_1000} = 26, if objectId = 26014 (the objectIds are configured in `conf/configuration_of_landsubdivisions.csv`)
- {objectName} = h08v04 or OCNewZealand
- {sourceRegionName} = OCNewZealand
- {thisDate} = 20250625
- {thisYear} = 2025
- {version} = v2025.0.1.

## More advanced remarks

No other option or argument is available for this submission script. That implies that when specific changes of parametering should be done, either or both `bash/submitNrt.sh` and `bash/configurationSpiresV202501.sh` should be edited locally, as explained for the examples below.

(1) Occasionally, some nodes are to be excluded from the run because they don't work as expected, notably for access to scratch or some libraries or performance issues. For instance, if the nodes are toto and titi, this is done in the script `bash/submitNrt.sh` by changing the line `exclude="";` into `exclude="--exclude=toto,titi";`. The two nodes **must** be part of the slurm cluster.

(2) Some jobs associated to specific steps can occasionally be killed because their necessary execution time is longer than the expected time (wall-time) or they can run into an out of memory error. It's possible to edit the wall-time of a step by editing, in the script `bash/configurationSpiresV202501.sh`, the variable `pipeLineTimes3` (time in hours) and `pipeLineMems3`, respectively. **Important**: increasing memory often requires increasing the number of cpus.



<br><br><br>
