#!/bin/bash 

module load NRIS/CPU
module load Python/3.12.3-GCCcore-13.3.0 

#Scrip to clone, build and run NorESM

dosetup1=1 #do first part of setup
dosetup2=1 #do second part of setup (after first manual modifications)
dosetup3=1 #do second part of setup (after namelist manual modifications)
dosubmit=1 #do the submission stage
forcenewcase=1 #scurb all the old cases and start again

echo "setup1, setup2, setup3, submit, forcenewcase:", $dosetup1, $dosetup2, $dosetup3, $dosubmit, $forcenewcase

USER="kjetisaa"
project='nn9560k' #nn8057k: EMERALD, nn2806k: METOS, nn9188k: CICERO, nn9560k: NorESM (INES2), nn9039k: NorESM (UiB: Climate predition unit?), nn2345k: NorESM (EU projects)
machine='olivia'

#NorESM dir
noresmrepo="ctsm5.4.042_noresm_v1" 
noresmversion="ctsm5.4.042_noresm_v1"

resolution="ne16pg3_tn14" #f19_g17, ne30pg3_tn14, f45_f45_mg37, ne16pg3_tn14 
casename="ihist.$resolution.$noresmversion.CPLHIST_Scenario_VL_olv.`date +"%Y-%m-%d"`"
echo "casename: $casename"
compset="NIHISTClm60NorCplHist"  #NIHISTClm60NorCplHist : HIST_DATM%CPLHIST_CLM60%FATES-NCFB%NORESM_SICE_SOCN_MOSART_SGLC_SWAV

# aka where do you want the code and scripts to live?
workpath="/cluster/work/projects/nn9560k/$USER/" 

# some more derived path names to simplify scripts
scriptsdir=$workpath$noresmrepo/cime/scripts/

#case dir
casedir=$workpath$casename

#where are we now?
startdr=$(pwd)

#Download code and checkout externals
if [ $dosetup1 -eq 1 ] 
then
    cd $workpath

    pwd
    #go to repo, or checkout code
    if [[ -d "$noresmrepo" ]] 
    then
        cd $noresmrepo
        echo "Already have NorESM repo"
    else
        echo "Cloning NorESM"
        
        if [[ $noresmversion == ctsm* ]] ; then
            echo "Using CTSM version $noresmversion"
            git clone https://github.com/NorESMhub/CTSM/ $noresmrepo
        else
            echo "Using NorESM version $noresmversion"
            git clone https://github.com/NorESMhub/NorESM/ $noresmrepo
        fi
        cd $noresmrepo
        git checkout $noresmversion
        ./bin/git-fleximod update
        echo "Built model here: $workpath$noresmrepo"        

    fi
fi

#Make case
if [[ $dosetup2 -eq 1 ]] 
then
    cd $scriptsdir

    if [[ $forcenewcase -eq 1 ]]
    then 
        if [[ -d "$workpath$casename" ]] 
        then    
        echo "$workpath$casename exists on your filesystem. Removing it!"
        rm -rf /cluster/work/projects/nn9560k/kjetisaa/$casename
        rm -rf /cluster/work/projects/nn9560k/kjetisaa/noresm/$casename
        rm -rf /cluster/work/projects/nn9560k/kjetisaa/archive/$casename
        rm -r $casename
	fi
    fi
    if [[ -d "$workpath$casename" ]] 
    then    
        echo "$workpath$casename exists on your filesystem."
    else
        
        echo "making case:" $workpath$casename        
        ./create_newcase --case $workpath$casename --compset $compset --res $resolution --project $project --run-unsupported --mach $machine --compiler intel

        cd $workpath$casename
        #XML changes
        echo 'updating settings'         
	./xmlchange DATM_CPLHIST_CASE=n1850.ne16pg3_tn14.noresm3_0_beta10.Run6.2026-01-23
        ./xmlchange DATM_CPLHIST_DIR=/cluster/work/projects/nn9560k/inputdata/atm/datm7/NorESM_CPLHIST/n1850.ne16pg3_tn14.noresm3_0_beta10.Run6.2026-01-23/cpl/hist/
        ./xmlchange DATM_PRESNDEP=none
        ./xmlchange DATM_YR_START=406
        ./xmlchange DATM_YR_END=425
        ./xmlchange RUN_STARTDATE=2022-01-01
        ./xmlchange STOP_OPTION=nyears
        ./xmlchange STOP_N=20
        ./xmlchange RESUBMIT=3
        ./xmlchange --subgroup case.run JOB_WALLCLOCK_TIME=48:00:00
        ./xmlchange --subgroup case.st_archive JOB_WALLCLOCK_TIME=00:30:00        
        
        echo 'done with xmlchanges'        
        
        ./case.setup
        echo ' '
        echo "Done with Setup. Update namelists in $workpath$casename/user_nl_*"

        #Add following lines to user_nl_clm   
cat <<EOF >> user_nl_clm
 finidat = '/cluster/work/projects/nn9560k/adagj/archive/nhist.ne16pg3_tn14.pr-noresm3_0_beta19.Base_i446F.Olivia.2026-06-07/rest/2022-01-01-00000/nhist.ne16pg3_tn14.pr-noresm3_0_beta19.Base_i446F.Olivia.2026-06-07.clm2.r.2022-01-01-00000.nc'
 flandusepftdat = '/cluster/work/projects/nn9560k/inputdata//lnd/clm2/surfdata_esmf/ctsm5.4.0/fates_LU_data_CMIP7/fates_landuse_pft_surfdata_ne16np4_c260508.nc'
 fluh_timeseries = '/cluster/work/projects/nn9560k/inputdata//lnd/clm2/surfdata_esmf/ctsm5.4.0/fates_LU_data_CMIP7/LUH3_timeseries_2022-2100_VL_surfdata_ne16np4_c260624.nc'
EOF

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
fi

#Submit job
if [[ $dosubmit -eq 1 ]] 
then
    cd $workpath$casename
    ./case.submit
    echo " "
    echo 'done submitting'       
fi

#After it has finised:
# - copy to NIRD: https://noresm-docs.readthedocs.io/en/noresm2/output/archive_output.html
# - run land diag: https://github.com/NorESMhub/xesmf_clm_fates_diagnostic 
    # python run_diagnostic_full_from_terminal.py /nird/datalake/NS9560K/kjetisaa/i1850.FATES-NOCOMP-coldstart.ne30pg3_tn14.alpha08d.20250130/lnd/hist/ pamfile=short_nocomp.json outpath=/datalake/NS9560K/www/diagnostics/noresm/kjetisaa/
#Useful commands: 
# - cdo -fldmean -mergetime -apply,selvar,FATES_GPP,TOTSOMC,TLAI,TWS,TOTECOSYSC [ n1850.FATES-NOCOMP-AD.ne30_tn14.alpha08d.20250127_fixFincl1.clm2.h0.00* ] simple_mean_of_gridcells.nc
