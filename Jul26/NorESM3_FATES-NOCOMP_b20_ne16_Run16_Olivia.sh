#!/bin/bash 

dosetup1=1 #do first part of setup
dosetup2=1 #do second part of setup (after first manual modifications)
dosetup3=1 #do second part of setup (after namelist manual modifications)
dosubmit=1 #do the submission stage! Before this step, set up to run on dedicated nodes!!
forcenewcase=1 #scurb all the old cases and start again
forcenewcode=0 #scrub old code and start again
doanalysis=0 #analyze output (not yet coded up)
numCPUs=0 #Specify number of cpus. 0: use default

module load NRIS/CPU
module load Python/3.12.3-GCCcore-13.3.0 

echo "setup1, setup2, setup3, submit, forcenewcase, analysis:", $dosetup1, $dosetup2, $dosetup3, $dosubmit, $forcenewcase, $doanalysis 

USER="kjetisaa"
project='nn9560k' #nn8057k: EMERALD, nn2806k: METOS, nn9188k: CICERO, nn9560k: NorESM (INES2), nn9039k: NorESM (UiB: Climate predition unit?), nn2345k: NorESM (EU projects), nn11118k: NorESM4CMIP7
machine='olivia'

#NorESM dir
noresmrepo="NorESM_3_0_beta20"
noresmversion="noresm3_0_beta20"
runTag="Run16"

resolution="ne16pg3_tn14" #f19_g17, ne30pg3_tn14, f45_f45_mg37
casename="n1850.$resolution.$noresmversion.$runTag.Olivia.`date +"%Y-%m-%d"`"
compset="N1850" #N1850                : 1850_CAM70%LT%NORESM%CAMoslo_CLM60%FATES-NCFB%NORESM_CICE_BLOM%HYB%ECO_MOSART_DGLC%NOEVOLVE_SWAV_SESP
refcase="n1850.ne16pg3_tn14.noresm3_0_beta19.Run15-E.Olivia.2026-06-18" #Update here
refyear="1751" #Update here
# aka where do you want the code and scripts to live?
workpath="/cluster/work/projects/nn9560k/$USER/" 
# workpath="/cluster/projects/nn9560k/$USER/" 

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

    if [[ $forcenewcode -eq 1 ]]
    then
        if [[ -d "$noresmrepo" ]] 
        then    
        echo "$workpath$noresmrepo exists on your filesystem. Removing it!"
        rm -rf $workpath$noresmrepo
        fi
    fi

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
#        sed -i 's/ctsm5.4.042_noresm_v0/ctsm5.4.042_noresm_v1/g' .gitmodules
#        echo "Updated .gitmodules to use ctsm5.4.042_noresm_v1:"
#        grep -i -n 'ctsm5.4.042_noresm_v0' .gitmodules            
        ./bin/git-fleximod update 

        #Update ccs_config for Olivia
        #cp /cluster/work/projects/nn9560k/agu002_old/NorESM11/ccs_config/machines/olivia/config_batch.xml ccs_config/machines/olivia/ 
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

        ./xmlchange NTASKS=1536,NTASKS_OCN=500,ROOTPE_OCN=1536
        ./xmlchange RUN_TYPE=hybrid
        ./xmlchange RUN_STARTDATE=$refyear-01-01  
        ./xmlchange RUN_REFCASE=$refcase
        ./xmlchange RUN_REFDATE=$refyear-01-01 
#        ./xmlchange GET_REFCASE=FALSE
        ./xmlchange STOP_OPTION=nyears
        ./xmlchange STOP_N=10
        ./xmlchange REST_N=10
        ./xmlchange RESUBMIT=1       
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
clubb_c8		= 4.85
micro_mg_autocon_lwp_exp		= 2.5D0
EOF

cat <<EOF >> user_nl_cpl
histaux_atm2med_file1_enabled = .true.
histaux_atm2med_file2_enabled = .true.
histaux_atm2med_file3_enabled = .true.
histaux_atm2med_file4_enabled = .true.
histaux_atm2med_file5_enabled = .true.
histaux_rof2med_file1_enabled = .true.
histaux_atm2med_file5_ntperfile = 1
histaux_atm2med_file5_history_n = 1
histaux_atm2med_file5_history_option = 'ndays'
histaux_rof2med_file1_ntperfile = 1
histaux_rof2med_file1_history_n = 1
histaux_rof2med_file1_history_option = 'ndays'
histaux_l2x1yrg = .true.
EOF

cat <<EOF >> user_nl_clm
paramfile = '/cluster/home/kjetisaa/RunScripts_Olivia/Jun26/ctsm60_params.noresm.c260611.nc'
fates_paramfile = '/cluster/home/kjetisaa/RunScripts_Olivia/Jun26/fates_params_noresm_c260615.json'
EOF

cat <<EOF >> user_nl_blom
SWAMTH = 'chlorophyll_ohl03'
CE = 0.09
EOF

cat <<EOF >> user_nl_cice
ksno = 0.25
floediam = 50.0
drsnw_min = 1.5
rsnw_fall=200.
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
    cp /cluster/work/projects/nn9560k/kjetisaa/archive/$refcase/rest/$refyear-01-01-00000/*.r*.nc /cluster/work/projects/nn9560k/kjetisaa/noresm/$casename/run/ 
    cp /cluster/work/projects/nn9560k/kjetisaa/archive/$refcase/rest/$refyear-01-01-00000/rpointer.*$refyear-01-01-00000 /cluster/work/projects/nn9560k/kjetisaa/noresm/$casename/run/ 
    cp /cluster/work/projects/nn9560k/kjetisaa/archive/$refcase/rest/$refyear-01-01-00000/$refcase.cam.i.$refyear-01-01-00000.nc /cluster/work/projects/nn9560k/kjetisaa/noresm/$casename/run/
#    cp /cluster/work/projects/nn9560k/kjetisaa/RESTART/$refcase/$refyear-01-01-00000/*.r*.nc /cluster/work/projects/nn9560k/kjetisaa/noresm/$casename/run/ 
#    cp /cluster/work/projects/nn9560k/kjetisaa/RESTART/$refcase/$refyear-01-01-00000/rpointer.*$refyear-01-01-00000 /cluster/work/projects/nn9560k/kjetisaa/noresm/$casename/run/ 
#    cp /cluster/work/projects/nn9560k/kjetisaa/RESTART/$refcase/$refyear-01-01-00000/$refcase.cam.i.$refyear-01-01-00000.nc /cluster/work/projects/nn9560k/kjetisaa/noresm/$casename/run/ 
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
