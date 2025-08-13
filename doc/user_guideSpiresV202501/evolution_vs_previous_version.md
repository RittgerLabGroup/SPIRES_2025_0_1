# Evolution of SPIReS v2025.0.1 compared to SPIReS v2024.1.0.

This page presents the main evolutions implemented on the [SPIReS code v2024.1.0](https://github.com/RittgerLabGroup/SPIRES_2024_1_0) (Rittger et al., 2025) to obtain this version. They follow the evolutions previously implemented on the [original SPIReS code](https://github.com/RittgerLabGroup/SPIRES_2024_1_0/blob/master/doc/user_guideSpiresV202410/evolution_vs_previous_version.md).


## Context.

SPIReS v2025.0.1 generates near real-time and historical gap-filled snow properties and albedo, at any elevation and location, using either MODIS or VIIRS sensors. It was designed, developed, and tested from August 2024 to February 2025.

We carried out a study (1) to extend the SPIReS v2024.1.0 code to regions other than western US, including in the South Hemisphere, and (2) to add a complementary sensor, VIIRS, in complement of MODIS. Despite our efforts, we were not able to carry out these evolutions directly on SPIReS v2024.1.0, designed in a brief time and with substantial external dependencies. We therefore decided to design and develop SPIReS v2025.0.1. Similar to SPIReS v2024.1.0, SPIReS v2025.0.1 provide a geotiff and csv plots output used by the web-app running the [snow-today viewer](https://nsidc.org/snow-today/snow-viewer), as well as NETCdF files that can be used by water resource forecast in their models or for other purposes by researchers.

We used SPIReS v2025.0.1 to ingest MOD09GA v6.1 reflectance data files, as well as VNP09GA v2.0.

The development of SPIReS v2025.0.1 was iterative, with 3 distinct milestones:
- the generation of an early MODIS dataset covering Alaska for 2019-2024
- the generation of a prototype VIIRS dataset covering tile h08v05 (California) for 2023
- the generation of a MODIS dataset covering Alaska for 2000-2024, and New Zealand for 2000-2025, with adaptations specific to cloud detection and background reflectance.


## List of evolutions compared to SPIReS v2024.1.0.

### Evolutions of the production chain.

1. Implementation of an additional sensor, VIIRS (using VNP09GA data).
2. Implementation of parallel nrt pipelines for different regions.
3. Implementation of parallel historical production chains.

The production chain was tested over all mountain ranges of America, European Alps, New Zealand, and High Mountain Asia.
<br><br>

### Algorithmic evolutions.

Some important implementations of SPIReS v1 have been kept:
1. The complex and time-consuming spectral unmixing calculations are not carried out during the run and we rather use a lookup table that help to find optimal solutions to the spectral unmixing problem.
2. We also use the clustering of pixels for calculations.
3. All pixels having a snow fraction below 10% are considered snow-free.
4. We stil use the cloud detection neural network (for MODIS only).
<br><br>
For adaptation to new regions and VIIRS sensor, we carried out these evolutions:
1. We produced ancillary data for all new regions, including western US. The code is provided in another repository.
2. We generated updated MODIS and VIIRS SPIReS lookup tables, using https://github.com/RittgerLabGroup/SPIRES_LOOKUP_2025_0_1
3. We refactored the generation of the gap files into one code file only, designing a class named `SpiresInversor`. There is no dependency to the external package SPIReS (or RasterReprojection. The only remaining dependency is for external package Parbal).
4. To avoid file corruption, all intermediary files are now .tif files per tile per day per variable (unless specified)
5. To facilitate validation and bug investigation, and rerun of jobs after interruption, each intermediary variable, including masks, is saved at each step of the pipeline. In particular, input data are saved in a lower precision format (as for STC algorithm)
6. We produced background reflectance data (=snow-free data) for each water year, using the class `SpiresInversor`
7. We removed the elevation threshold of 500 m.a.s.l, spectral unmixing is run on any elevation above 0
8. `SpiresInversor` accepts MOD09GA and VNP09GA as input data
9. All the code is compatible northern hemisphere and southern hemisphere, with water year starting April 1st N-1 for southern hemisphere, for water year N.
10. For MODIS-VIIRS continuity, `SpiresInversor` takes into account bands of similar wavelength for both sensors. Equivalence MODIS/VIIRS: 1: I1, 2: I2, 3: M2, 4: M4, 5: M8, 6: I3, 7: M11.
11. For MODIS-VIIRS continuity, `SpiresInversor` also takes into account similar quality flags for both sensors in the weighing temporal scheme, when possible (VNP09GA does not have all the flags present in MOD09GA)
12. To improve false positive detection, `SpiresInversor` uses both for MODIS and VIIRS:
  - additional cloud detection based on reflectance value thresholds (similar to STC algorithm)
  - inclusion of the edges of clouds in the cloud mask (elevation-dependent)
  - detection of bright objects on-the-ground (elevation-dependent)
13. We changed the pseudo-spatial weighing scheme to calculate grain size and dust concentrations for the pixels having insufficient snow and favored an inverse-distance, elevation-dependent, window-size iterating weighing scheme.
14. We refactored gap-filling into one code file only, designing a class named `SpiresTimeInterpolator`
15. To reduce overdetection of false positive, in particular in polar regions and in early / late season, we changed the persistence filter. Calculation is now done pixel/day by pixel/day of the number of days with snow observation it is and the number of days without snow observation it is. If there are less than 3 days with snow observation (or snow-free observation) in a row, between 2 periods of snow-free observations (or snow observation, respectively), these days are set to no observation (Days without observations can be used as a filter in the ready-to-use output data)
16. `SpiresTimeInterpolator` also determines values for snow cover days
17. Intermediary files for `SpiresTimeInterpolator` are .mat files per tile per water year per cell (a tile = 36 cells)
18. We refactored the code for albedo calculation and generation of daily intermediary files into a new class `SpiresMosaicAlbedo`. This class still uses the Palbal code, with associated lookup table.
19. To avoid issues with the RasterReprojection external package, we refactored the generation of geotiffs for the web-app using standard python and gdal libraries.
