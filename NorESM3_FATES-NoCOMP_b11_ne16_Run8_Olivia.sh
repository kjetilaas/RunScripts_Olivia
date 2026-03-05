#!/bin/bash 

dosetup1=1 #do first part of setup
dosetup2=1 #do second part of setup (after first manual modifications)
dosetup3=1 #do second part of setup (after namelist manual modifications)
dosubmit=1 #do the submission stage! Before this step, set up to run on dedicated nodes!!
forcenewcase=1 #scurb all the old cases and start again
doanalysis=0 #analyze output (not yet coded up)
numCPUs=0 #Specify number of cpus. 0: use default

module load NRIS/CPU
module load Python/3.12.3-GCCcore-13.3.0 

echo "setup1, setup2, setup3, submit, forcenewcase, analysis:", $dosetup1, $dosetup2, $dosetup3, $dosubmit, $forcenewcase, $doanalysis 

USER="kjetisaa"
project='nn9560k' #nn8057k: EMERALD, nn2806k: METOS, nn9188k: CICERO, nn9560k: NorESM (INES2), nn9039k: NorESM (UiB: Climate predition unit?), nn2345k: NorESM (EU projects)
machine='olivia'

#NorESM dir
noresmrepo="NorESM_3_0_beta11"
noresmversion="noresm3_0_beta11"

resolution="ne16pg3_tn14" #f19_g17, ne30pg3_tn14, f45_f45_mg37
casename="n1850.$resolution.$noresmversion.Run8.Olivia.`date +"%Y-%m-%d"`"
compset="1850_CAM70%LT%NORESM%CAMoslo_CLM60%FATES-NOCOMP_CICE_BLOM%HYB%ECO_MOSART_DGLC%NOEVOLVE_SWAV_SESP"
refcase="n1850.ne16pg3_tn14.noresm3_0_beta11.Run8.2026-02-07" #Update here
refyear="0811" #Update here
# aka where do you want the code and scripts to live?
workpath="/cluster/projects/nn9560k/$USER/" 

# some more derived path names to simplify scripts
scriptsdir=$workpath$noresmrepo/cime/scripts/

#case dir
casedir=$workpath$casename

#where are we now?
startdr=$(pwd)

#Download code and checkout externals
if [ $dosetup1 -eq 1 ] 
then
    echo $workpath
    cd $workpath

    pwd
    #go to repo, or checkout code
    if [[ -d "$noresmrepo" ]] 
    then
        cd $noresmrepo
        echo "Already have NorESM repo"
    else
        echo "Cloning NorESM"
        
        git clone https://github.com/NorESMhub/NorESM/ $noresmrepo
        cd $noresmrepo
        git checkout $noresmversion      
        #sed -i 's/ctsm5.3.045_noresm_v14/ppe-scramble-tag-for-ctsm-on-norems3-beta04/g' .gitmodules
        #echo "Updated .gitmodules to use ppe-scramble-tag-for-ctsm-on-norems3-beta04 of CLM:"
        #grep -i -n 'ppe-scramble-tag-for-ctsm-on-norems3-beta04' .gitmodules        
        ./bin/git-fleximod update 

        #Update ccs_config for Olivia
        cp /cluster/work/projects/nn9560k/agu002_old/NorESM11/ccs_config/machines/olivia/config_batch.xml ccs_config/machines/olivia/ 
    fi
fi

#Make case
if [[ $dosetup2 -eq 1 ]] 
then
    echo $scriptsdir
    cd $scriptsdir

    if [[ $forcenewcase -eq 1 ]]
    then 
        if [[ -d "$workpath$casename" ]] 
        then    
        echo "$workpath$casename exists on your filesystem. Removing it!"
        rm -rf $workpath$casename
        rm -r /cluster/work/projects/nn9560k/kjetisaa/noresm/$casename
        rm -r /cluster/work/projects/nn9560k/kjetisaa/archive/$casename
        rm -r $casename
        fi
    fi
    if [[ -d "$workpath$casename" ]] 
    then    
        echo "$workpath$casename exists on your filesystem."
    else
        
        echo "making case:" $workpath$casename        
        ./create_newcase --case $workpath$casename --compset $compset --res $resolution --project $project --machine $machine --compiler intel --run-unsupported --user-mods-dir $workpath$noresmrepo/cime_config/usermods_dirs/reduced_out_devsim/                
        cd $workpath$casename

        #XML changes
        echo 'updating settings'  

        ./xmlchange NTASKS=1536,NTASKS_OCN=500,NTASKS_ICE=768,NTASKS_LND=768,ROOTPE_OCN=1536,ROOTPE_LND=768
        ./xmlchange RUN_TYPE=hybrid
        ./xmlchange RUN_STARTDATE=$refyear-01-01  
        ./xmlchange RUN_REFCASE=$refcase
        ./xmlchange RUN_REFDATE=$refyear-01-01 
        ./xmlchange GET_REFCASE=FALSE
        ./xmlchange STOP_OPTION=nyears
        ./xmlchange STOP_N=5
        ./xmlchange REST_N=5
        ./xmlchange RESUBMIT=10       
        ./xmlchange REST_OPTION=nyears
        ./xmlchange HAMOCC_SEDSPINUP=FALSE
        ./xmlchange BLOM_OUTPUT_SIZE=spinup
        ./xmlchange HAMOCC_OUTPUT_SIZE=spinup
        ./xmlchange --subgroup case.run JOB_WALLCLOCK_TIME=48:00:00
        ./xmlchange --subgroup case.st_archive JOB_WALLCLOCK_TIME=2:00:00
        ./xmlchange --subgroup case.compress JOB_WALLCLOCK_TIME=12:00:00   
        echo 'done with xmlchanges'        
        
        ./case.setup
        echo ' '       
        echo "Done with Setup. Updateing namelists in $workpath$casename/user_nl_*"    
## Changes to user_nl_* files goes here

cat <<EOF >> user_nl_cam
use_aerocom                = .false.
interpolate_nlat           = 96
interpolate_nlon           = 144
interpolate_output         = .true.,.true.
history_aerosol            = .false.
zmconv_c0_lnd              =  0.0075D0
zmconv_c0_ocn              =  0.0050D0
zmconv_ke                  =  5.0E-6
zmconv_ke_lnd              =  1.0E-5
clim_modal_aero_top_press  =  1.D-4
bndtvg                     = '/cluster/work/projects/nn9560k/inputdata/atm/cam/ggas/noaamisc.r8.nc'
dust_emis_method           = 'Leung_2023'
dust_emis_fact             = 6.1D0
rafsip_on                  = .true.
micro_mg_dcs               = 600.D-6
clubb_c8                   = 4.55
zmconv_tiedke_add	   = 0.7
nhtfrq = 0, -24
mfilt  = 1,   30 
ndens  = 2,   2
fincl1 = 'IntHeatTr', 'PotEnerTr', 'LatHeatTr', 'KinEnerTr', 'TotEnerTr'
fincl2 = 'Z500', 'T850', 'U850', 'V850'
EOF

cat <<EOF >> user_nl_clm
glacier_region_behavior = 'single_at_atm_topo','UNSET','virtual','virtual' 
glcmec_downscale_longwave = .false. 
precip_repartition_glc_all_rain_t = 2. 
precip_repartition_glc_all_snow_t = 0. 
snow_thermal_cond_glc_method = 'Jordan1991'
albice = 0.6,0.4
use_fates_nocomp=.true.
use_fates_fixed_biogeog=.true.
fates_stomatal_model='medlyn2011'
fates_spitfire_mode=4
use_fates_luh=.true.
use_fates_lupft=.true.
fates_harvest_mode='luhdata_area'
use_fates_potentialveg=.false.
do_transient_lakes = .false.
do_transient_urban = .false.
fates_paramfile = '/cluster/work/projects/nn9560k/inputdata/lnd/clm2/paramdata/fates_params_sci.1.88.6_api.42.0.0_14pft_nor_sci3_api1_c260123.nc'
fluh_timeseries='/cluster/work/projects/nn9560k/inputdata/LU_data_CMIP7/LUH2_states_transitions_management.timeseries_ne16_hist_steadystate_1850_2025-11-06_cdf5.nc'
flandusepftdat='/cluster/work/projects/nn9560k/inputdata/LU_data_CMIP7/fates_landuse_pft_map_to_surfdata_ne16np4_251106_cdf5.nc'
paramfile = '/cluster/work/projects/nn9560k/inputdata/lnd/clm2/paramdata/ctsm60_params.5.3.045_noresm_v14_c260117.nc'
hist_fincl1 = "FATES_LITTER_IN", "FATES_LITTER_OUT", "FATES_SEEDS_IN_EXTERN_EL", "TOTSOMC", "TOTLITC", "TOT_WOODPRODC", "TOT_WOODPRODC_LOSS", "SOM_C_LEACHED"
EOF

cat <<EOF >> user_nl_cpl
ocean_albedo_scheme = 1
EOF

cat <<EOF >> user_nl_blom
EGC = 2.5
EGIDFQ = 1.25
dmsp3=0.1296
dmsp5=0.0136
dremcalc  = 0.0045
dremopal  = 0.008
rcalc     = 7.0
ropal     = 80.0
rano3denit = 0.00010
disso_poc = 3.9e-7
disso_sil = 1.0e-7
wlin=0.0154762
wmin=5.4
EOF

cat <<EOF >> user_nl_cice
drsnw_min = 1.0
floediam = 50.0
f_aero='m'
f_iage='m'
EOF
        echo "done with user_nl_* modifications"

    fi
fi

#Build case case
if [[ $dosetup3 -eq 1 ]] 
then
    cd $workpath$casename
    echo "Currently in" $(pwd)
    ./case.build
    echo ' '    
    echo "Done with Build"

    # copy restart files and pointers
    cp /cluster/work/projects/nn9560k/kjetisaa/RESTART/$refcase/$refyear-01-01-00000/*.r*.nc /cluster/work/projects/nn9560k/kjetisaa/noresm/$casename/run/ 
    cp /cluster/work/projects/nn9560k/kjetisaa/RESTART/$refcase/$refyear-01-01-00000/rpointer.*$refyear-01-01-00000 /cluster/work/projects/nn9560k/kjetisaa/noresm/$casename/run/ 
    cp /cluster/work/projects/nn9560k/kjetisaa/RESTART/$refcase/$refyear-01-01-00000/$refcase.cam.i.$refyear-01-01-00000.nc /cluster/work/projects/nn9560k/kjetisaa/noresm/$casename/run/ 
    echo "copied restart files and pointers"
fi

#Submit job
if [[ $dosubmit -eq 1 ]] 
then
    cd $workpath$casename
    ./case.submit
    echo " "
    echo 'done submitting'       
fi