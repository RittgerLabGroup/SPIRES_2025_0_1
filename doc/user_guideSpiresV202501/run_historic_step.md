# Historicals job submission

This page presents the submission of the update of historical snow property data from the collection of input products to the generation of output products for users (netcdf data files) and for the [daily near real time (NRT) update](run_nrt_pipeline.md) to the snow-today website (dailycsv statistic files for plots).

## Preamble and vocabulary.

We advise to read the [Preamble of the NRT pipeline doc](run_nrt_pipeline.md#preamble-and-vocabulary) and more generally the NRT documentation in that page. We also advise to recheck the install and requirements [here](install.md), particularly about the environment variables.

The historicals step process is a production chain which goal is to generate and deliver output historical data for previous time, usually a previous water year (`waterYear`), for a set of big regions (see [vocabulary](run_nrt_pipeline.md#preamble-and-vocabulary)). For SPIReS v2025.0.1, several big regions can be run, list in `conf/configuration_of_regions.csv`, filtering the column type=bigRegion.

Note that *historical* in *historical steps* is a label for the use of this chain to generate a full set of data covering the historical record. It's not to be confused with the *NRT* and *historical* labels for the input data (e.g. MOD09GA data files), which are determined by the providers of remote sensing products. The historical production chain ingest most of the time historical input data, but also, if they are not availabel, can ingest NRT input data.

To carry out this objective, we use the same [code architecture](code_organization.md) and scripts (with a different configuration) as the [NRT pipeline](run_nrt_pipeline.md#preamble-and-vocabulary). However, contrary to the NRT pipeline, here, the workload is not divided sequentially, and each step is executed individually.

## Data spaces and file synchronization.

The file spaces are similar to what is described in the [NRT pipeline](run_nrt_pipeline.md#data-spaces-and-file-synchronization). However, as explained in [file synchronization](run_nrt_pipeline.md#data-spaces-and-file-synchronization), synchronization of output files should be done manually.

## Run as a beginner

For a beginner user, we strongly advise to handle a waterYear after another waterYear for a big region, starting by the older waterYear of the record (2001 for MODIS in this project), and not trying to run everything simultaneously. Indeed, the production chain, for SPIReS v2025.0.1, can submit a *minimum* total of more than 270 jobs per year, which makes a minimum of 6,900 jobs for the full MODIS record for the 5 tiles of the big region westernUS in summer 2025. We say minimum, because the jobs can be resubmitted in case of failure.

Beyond these numbers, thanks to the code implementation, the user will only have to supervise (actively) 13-14 jobs per waterYear, which carry out the monitoring task of all these jobs. As an additional remark, Slurm by default sends an email each time a job ends, more information/suggestions [here](run_nrt_pipeline.md#preamble-and-vocabulary).

The entry script to launch submission is `bash/submitHistoric.sh`. This script submits a job to a Slurm cluster, with a submit line including the script `bash/runSubmitter.sh` (see [Run as a beginner for the NRT pipeline](run_nrt_pipeline.md#run_as_a_beginner) and [code interactions](code_organization.md#code_interactions_within_a_submission_to_slurm)). 

The historical jobs use the same scripts for each [step](run_nrt_pipeline.md#preamble-and-vocabulary) as for the [NRT jobs](run_nrt_pipeline.md). However, while the NRT pipeline has an automatized sequence of jobs from input to delivery of output data files, the user should follow a different procedure to run the historics:

1. The user submits each step at a time, according to instructions below,
2. The user monitors the execution of the step, using [checking log](checking_log.md),
3. Once the step has been achieved correctly and generated the data files, the user can submit the next step.
4. Once all steps have been carried out, the user might check some of the output files and, in case of doubt, their content, and then [synchronize to archive](run_nrt_pipeline.md#data-spaces-and-file-synchronization)

In the following, we only present the instructions for point 1., since the other points are documented elsewhere as indicated.

### Global view of submission (point 1.).

To run a specific step ([list of steps](run_nrt_pipeline.md#steps-and-scriptid)) as asked for in 1., the user first connects to a login node. After `cd` to the root of this project (**IMPORTANT**), the user executes a command such as
```bash
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment -f $endYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

The script prints the options given and loads some configuration, and then it shows the submitLine that will be submitted to Slurm and asks for confirmation:

```
Do you want to proceed submission? (y/n)
```

The user confirms `y` and the script submits the job and prints:
```
Submission...
Submitted batch job 20164305
```

The user notes the job id of the `runSubmitter.sh`, here `20164305` and can follow its execution:
- with the help of [Slurm](https://slurm.schedmd.com/documentation.html) commands `squeue`, `sacct`, `scontrol`,
- and with the help of the [logs](checking_log.md).

All input files are downloaded to the [user's scratch](run_nrt_pipeline.md#data-spaces-and-file-synchronization) and intermediary and output files are generated in that data space. After the last checks at the end of the process, and except for the remote sensing input files (publicly available), the user can synchronize the files [back to the archive](run_nrt_pipeline.md#runrsync).


### Detailed instructions for submission.**

In the following instructions, we focus on the production chain for `westernUS` waterYear 2024 for the Northern Hemisphere, and for `OCNewZealand` waterYear 2024 for the Southern Hemisphere. The options described in the process make it similar to running other complete waterYears.

The procedure for the Southern Hemisphere is the same as for the Northern Hemisphere, except for the parametering of the options `bigRegionId`, `confOfMonthId`, `optionForWaterYearDateString`, and `optionForEndYear`.

**Step `mod09ga`**. First, the user needs to download the input remote sensing data to their scratch. For this, the user submits (1) a series of jobs that cover the first part of the waterYear N, from October to December of the year N-1 for the Northern Hemisphere, as defined in this project, and (2) a series of jobs that cover the second part of the waterYear N, from January to September of the year N for the Northern Hemisphere. 

For the Southern Hemisphere, (1) covers April to December N-1, and (2) covers January to March N.

In both cases, for instance for waterYear 2024, (1) covers the end of 2023, and (2) covers the start of 2024.

*For the Northern Hemisphere*:

The set of commands for (1) is:
```bash
# Values for options.
bigRegionId=5
  # bigRegionId=5 is the id of the big region on which the work is carried out. For western US, bigRegionId=5, as indicated in conf/configuration_of_regions.csv, column "id". For OCNewZealand, bigRegionId=7.
confOfMonthId=20
  # confOfMonthId=30 is the code for the period to cover in the year indicated by $endYear.
  # For the Northern Hemisphere, to cover a full waterYear, we use confOfMonthId=20 for October to December, and confOfMonthId=30 for January to September. For the first waterYear of the record, we also need the 4 months before the start of the waterYear and we use confOfMonthId=41 for June to September.
  # For the Southern Hemisphere, to cover a full waterYear, we use confOfMonthId=130 for April to December, and confOfMonthId=120 for January to March. For the first waterYear of the record, we need the 3 months (rather than 4, because we do not have that early December of data for all Southern tiles) before the start of the waterYear and we use confOfMonthId=120.
  # 
  # For most steps later in the production chain, the work needs to be done over a full waterYear in the same job. In that case, confOfMonthId=0 and $optionForWaterYearDateString should be assigned.
optionForWaterYearDateString=
  # This option is used preferredly when the calculations should not be split and should cover a full waterYear, as it is the case for most steps later in the production chain. The syntax is optionForWaterYearDateString="-D yyyy-mm-dd-mw", for instance optionForWaterYearDateString="-D 2024-09-30-12" to cover the waterYear 2024 for the Northern Hemisphere, with yyyy, mm, dd, the year, month, day of the last day of the waterYear, and 12 the month window, that is the number of months covered before the last day included.
thisEnvironment=SpiresV202501
  # For this project MUST be SpiresV202501.
optionForEndYear="-f 2023"
  # Year considered for the work. Here, since confOfMonthId=20, the work will cover October to December of 2023, which corresponds to the first part of the waterYear 2024 in the Northern Hemisphere as defined for this project. If the user want the second part, the user should set confOfMonthId=30 and optionForEndYear="-f 2024".
scriptId=mod09gaI
  # Code of the step/script to use. Full list of codes is in the variable $authorizedScriptIds defined in conf/configurationForHistoricsSpiresV202501.sh.
optionForLagTimeBetweenSubmissionOfYears=
  # Most steps don't require this option. But occasionally, in particular for steps handling interpolation (for SPIReS v2025.0.1 step spiTimeI), the number of jobs to submit for the step is just too big, and we need to insert a lag between submission to avoid to overwhelm slurm and have jobs rejected. In that case, the syntax is optionForLagTimeBetweenSubmissionOfYears="-t 1h" for instance, to have a lag of 1 h between the various submissions required when the user launches the command below, or optionForLagTimeBetweenSubmissionOfYears="-t 30m" for a lag of 30 minutes.

# Command.
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

The set of commands for (2) is:
```bash
bigRegionId=5
confOfMonthId=30
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2024"
scriptId=mod09gaI
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

*For the Southern Hemisphere*:
The set of commands for (1) is:
```bash
bigRegionId=7
confOfMonthId=130
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2023"
scriptId=mod09gaI
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

The set of commands for (2) is:
```bash
bigRegionId=7
confOfMonthId=120
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2024"
scriptId=mod09gaI
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

The 2 sets of commands can be submitted in a row.

Warning: As missing files were noticed in the past, we advise running these 2 sets a second time, once the first time has been achieved.

Note that for this step, the (historical) input files collected do not need to be synchronized back from the user's scratch to archive, since they are available from a public source.

**More insight to know for job monitoring**
For this step, the set of jobs submitted for (1) handles the full trimester. Contrastingly, the set of jobs for (2) has 3 subsets of jobs, each of them covering 1 trimester. The common period of run covered by each step and more information is detailed [here](run_nrt_pipeline.md#steps-and-scriptid). So there are a total of 4 subsets of jobs for 1 waterYear.

At a lower level, the set of jobs submitted for (1) and (2) has as many jobs as the number of individual tiles form the big region. For `westernUS`, there are 5 individual MODIS tiles (as defined in `conf/configuration_of_regionsSpires.csv`).

At the highest level, each set of jobs is monitored by a job running on Slurm with the script `bash/runSubmitter.sh`. These monitoring jobs automatically resubmit jobs that fail, except for a few reasons that were encoded.

In total, to handle the step `mod09ga` for `westernUS` for waterYear 2024, a minimum of 4x(1+5)=24 jobs are submitted to Slurm.



**Step `mod09ga` first waterYear only**. In this project, the first waterYear for MODIS is 2001. In addition to the step `mod09ga` previously run for that year, the user also needs to collect the files of the months before the start of the waterYear (4 for the Northern Hemisphere, 3 for the Southern one). These data are necessary for the determination of the background reflectance (~=snow-free) data that will be used by SPIReS v2025.0.1 for the waterYear.

*For the Northern Hemisphere*, the commands are:
```bash
bigRegionId=5
confOfMonthId=41
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2000"
scriptId=mod09gaI
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

*For the Southern Hemisphere*, the commands are:
```bash
bigRegionId=7
confOfMonthId=120
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2000"
scriptId=mod09gaI
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```


**Step `spiInges` first waterYear only**. This step is to be run only for the first waterYear of the record. In this project for MODIS, the first waterYear is 2001. The step ingests the data of the months before the first waterYear, but does not run the spectral unmixing of SPIReS on them.

Crucially, before submitting this step, the user MUST have monitored the outcome of the previous step `mod09ga` first waterYear only, as indicated [above](#run-as-a-beginner).

*For the Northern Hemisphere*, the commands are:
```bash
bigRegionId=5
confOfMonthId=41
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2000"
scriptId=spiInges
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

*For the Southern Hemisphere*, the commands are:
```bash
bigRegionId=7
confOfMonthId=120
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2000"
scriptId=spiInges
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

**Step `spiBackg`**. Two cases occur. 

(1) For all waterYears except the first waterYear, the user has already generated the data of the previous waterYear, because it's what we recommend [here](#run-as-a-beginner). He therefore has to make sure that they are on the user's scratch before starting this step.

(2) For the first waterYear, the user has run the step `spiInges` and the data produced will be used by this step.

*For the Northern Hemisphere*, the commands are:
```bash
bigRegionId=5
confOfMonthId=0
optionForWaterYearDateString=2024-09-30-4
thisEnvironment=SpiresV202501
optionForEndYear=""
scriptId=spiBackg
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

*For the Southern Hemisphere*, the commands are:
```bash
bigRegionId=7
confOfMonthId=0
optionForWaterYearDateString=2024-03-31-4
thisEnvironment=SpiresV202501
optionForEndYear=""
scriptId=spiBackg
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

In both cases, the same commands should be used for the first waterYear, by adapting `optionForWaterYearDateString=2000-09-30-4` for the Northern Hemisphere, and `optionForWaterYearDateString=2000-03-31-3` for the Southern Hemisphere.



**Step `spiInver`**. Crucially, before submitting this step, the user MUST have monitored the outcome of the previous step `mod09ga` and `spiBackg`, as indicated [above](#run-as-a-beginner). This duty is to be carried out for each step.

This step is almost similar to `mod09ga`, including in the number of jobs submitted, but can need much more time to be executed.

*For the Northern Hemisphere*, the commands are:
```bash
bigRegionId=5
confOfMonthId=20
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2023"
scriptId=spiInver
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears=
```

And 30 minutes later:
```bash
bigRegionId=5
confOfMonthId=30
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2024"
scriptId=spiInver
optionForLagTimeBetweenSubmissionOfYears="-t 30m"
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

Here, this second set of commands launches the 1st set of submissions immediately (for the 1st trimester), and then for each of the 2 other trimesters, launches the set of jobs 30 minutes later. Each of these 3 sets of submissions will display a message `Submitted batch job 20164305` with the indication of the jobId, that the user needs to note so as to monitor more easily his submissions, as required [here](#run-as-a-beginner). It is therefore **IMPORTANT** that the user lets his login session open until the end of the last submission; otherwise, the user takes the risk of having only part of the submissions done.

*For the Northern Hemisphere for the first waterYear*, we also need to apply spectral unmixing on the 3 months before the start of the waterYear, because the temporal interpolation done in the next step takes the data of these previous months. The commands are:
```bash
bigRegionId=5
confOfMonthId=41
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2000"
scriptId=spiInver
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears=
```


*For the Southern Hemisphere*, the commands are:
```bash
bigRegionId=7
confOfMonthId=130
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2023"
scriptId=spiInver
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears=
```

And 30 minutes later:
```bash
bigRegionId=7
confOfMonthId=120
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2024"
scriptId=spiInver
optionForLagTimeBetweenSubmissionOfYears="-t 30m"
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

*For the Southern Hemisphere for the first waterYear*, the commands are:
```bash
bigRegionId=5
confOfMonthId=41
optionForWaterYearDateString=
thisEnvironment=SpiresV202501
optionForEndYear="-f 2000"
scriptId=spiInver
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears=
```

**Step `spiTimeI`**. This step is different from the previous ones, because for SPIReS v2025.0.1, we divide each tile forming the big region into 36 cells to carry out temporal interpolation over a waterYear. In all, for `westernUS`, this step submits a minimum of 1+36x5=181 jobs simultaneously (automatically). Slurm will handle all these jobs following its workload balancing functionalities, and not all jobs start at the same time but rather start over a certain period of time.

*For the Northern Hemisphere*, the commands are:
```bash
bigRegionId=5
confOfMonthId=0
optionForWaterYearDateString="-D 2024-09-30-12"
thisEnvironment=SpiresV202501
optionForEndYear=""
scriptId=spiTimeI
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

*For the Southern Hemisphere*, the commands are:
```bash
bigRegionId=7
confOfMonthId=0
optionForWaterYearDateString="-D 2024-03-31-12"
thisEnvironment=SpiresV202501
optionForEndYear=""
scriptId=spiTimeI
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

The rest of the steps will similarly cover a full waterYear, but will handle a full tile per job, rather than the division of tiles into cells that is carried out here.

**Step `moSpires`**

*For the Northern Hemisphere*:
```bash
bigRegionId=5
confOfMonthId=0
optionForWaterYearDateString="-D 2024-09-30-12"
thisEnvironment=SpiresV202501
optionForEndYear=""
scriptId=moSpires
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

*For the Southern Hemisphere*:
```bash
bigRegionId=7
confOfMonthId=0
optionForWaterYearDateString="-D 2024-03-31-12"
thisEnvironment=SpiresV202501
optionForEndYear=""
scriptId=moSpires
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

**Step `daNetCDF`**

*For the Northern Hemisphere*:
```bash
bigRegionId=5
confOfMonthId=0
optionForWaterYearDateString="-D 2024-09-30-12"
thisEnvironment=SpiresV202501
optionForEndYear=""
scriptId=daNetCDF
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

*For the Southern Hemisphere*:
```bash
bigRegionId=7
confOfMonthId=0
optionForWaterYearDateString="-D 2024-03-31-12"
thisEnvironment=SpiresV202501
optionForEndYear=""
scriptId=daNetCDF
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

**Step `daStatis`**
*For the Northern Hemisphere*:
```bash
bigRegionId=5
confOfMonthId=0
optionForWaterYearDateString="-D 2024-09-30-12"
thisEnvironment=SpiresV202501
optionForEndYear=""
scriptId=daStatis
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

*For the Southern Hemisphere*:
```bash
bigRegionId=7
confOfMonthId=0
optionForWaterYearDateString="-D 2024-03-31-12"
thisEnvironment=SpiresV202501
optionForEndYear=""
scriptId=daStatis
optionForLagTimeBetweenSubmissionOfYears=
bash/submitHistoric.sh -B $bigRegionId -C $confOfMonthId $optionForWaterYearDateString -E $thisEnvironment $optionForEndYear -s $scriptId $optionForLagTimeBetweenSubmissionOfYears
```

We advise that the intermediary and output files of this production chain be synchronized back [from scratch to archive](run_nrt_pipeline.md#runrsync) only after a final check on the output files, which are for SPIReS v2025.0.1 the files produced at the `daNetCDF, daStatis` steps. [Locations of the files](run_nrt_pipeline.md#data-file-location).

As said in [Data spaces](run_nrt_pipeline.md#data-spaces), which includes a procedure, it's a good practice for users generating historical data to regularly check their available space and inodes and act accordingly if quotas are close being reached.

Specifically, SPIReS v2025.0.1 was designed to solve the recurrent issue of corrupted .mat files occurring when a job is killed, whether by the user (command `scancel` [in Slurm](install.md#slurm-knowledge)) or by Slurm (out of memory or wall-time errors). This was done by replacing the format .mat (used in the version SPIReS v2024.1.0) by .tif, and saving each variable generated by the algorithm in an individual .tif file per tile per day.

There are 43 raster variables for SPIReS v2025.0.1, per tile, per day. Therefore, this implementation generates a high number of files for the dataLabel `modspiresdailytifsinu`(paths [here](run_nrt_pipeline.md#data-file-location)), which, if not monitored, can saturate the available inodes on the user's scratch (at CU Boulder, this issue does not exist for archive spaces). This is, of course, not a real issue as long as the user does their check regularly, following [this procedure for CU Boulder](run_nrt_pipeline.md#data-spaces).


## More advanced uses

Occasionally, notably in the case of job failures, it might be useful to parameterize these options to the `submitHistoric.sh`:
- `-I $objectId`, which restricts the run for one tile, e.g. 292 for h08v04, listed in `conf/configuration_of_regions.csv` (not possible for step `daMosBig`)
- `-U $slurmExecutionOptions`, to exclude specific, deficient nodes (e.g. `--exclude=toto,titi`, the two nodes **must** be part of the Slurm cluster).

## More advanced remarks

In some problematic cases, `specific/sh/submitStcForHistorics.sh` should be edited, as explained for the example below.

Some jobs associated with specific steps can occasionally be killed because their necessary execution time is longer than the expected time (wall-time) or they can run into an out of memory error. It's possible to edit the wall-time of a step by locally editing `conf/configurationForHistoricsSpiresV202501.sh` the variable `sbatchTimes` (time in hours) and `sbatchMems`, respectively. **Important**: increasing memory often requires increasing the number of CPUs. The jobs can continue to run into out-of-memory issues if the number of parallel workers is kept by default the number of tasks. The protection techniques that we used against that issue are not uniform among scripts.



<br><br><br>
