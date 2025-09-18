#!/bin/bash
###################################################################
#
# Shell script that launches all REDLoss and ktools modules in parallel and in-memory.
#
###################################################################
#	* Fully parallelized in-memory REDCat/ktools
#	* The script is called model run directory a.k.a., "model_run_dir" after being copied into it
# 		by the tasks.py script (see OASIS platform for its whereabouts)
# 	* Hard coded to launch 8 simultaneous REDCat/ktools pipes.
# 	* Hard coded to produce the occurrence file using 30,000 years of period length
# 	* <CAUTION> Beware that the p1, ORED_EXP_KEYS_DIR, and CF_FILES_DIR variables are hard coded.
# 	
# Authored by Omer Odabasi on May 2023
# Last modified, Jan 2024
###################################################################

echo '====================< W E L C O M E >======================='
echo
echo "INFO: You are running run-ored-fifo.sh, last modified on Jan, 2024."
echo "INFO: Noteworthy features of this version are:"
echo " 	> Updated to run RED's EUM23"
echo " 	> Runs REDCat in fifo mode"
echo " 	> REDCAT Versions: \n
			- REDExp 1.6.0	Nov 13 2023\n
			- REDHazOQ 1.2.3  Oct 26, 2023 \n
			- REDLoss 2.2.1   Dec 19 2023\n
			- REDField 2.1.0  Oct 25 2023\n"
echo "		- oredexp 1.3.1\n"
echo "		- getzones 0.1.0\n"
echo '====================  ° ° ° ° ° ° °  ======================='
echo

###################################################
# FUNCTIONS
###################################################

# DEPRECATED. No longer using this for model run via the UI
set_n_sim_redloss(){
	# Set the name of the text file
	file_name="redloss.cf"
	nS=$1
	# Search for the line containing "OPT_OUTDIR" in the text file
	line=$(grep "OPT_SIMACC" $file_name)

	# Check if the line was found
	if [ -n "$line" ]
	then
	  echo $line
	  # Extract the part of the line after the comma
	  value=$(echo $line | awk -F, '{print $2}')
	  newLine="OPT_SIMACC,$nS" 
      #value=$(echo $value | sed 's+\/+\\\/+g')

	  # Replace the original line with new
	  sed -i "s+${line}+${newLine}+g" redloss.cf
      echo "INFO > Set OPT_SIMACC to $nS."
	fi
}

###################################################
# INPUT VARIABLES
###################################################
username=$(whoami)

p1="/home/worker/model/src/redcat"
p2="/usr/lib/x86_64-linux-gnu"
ORED_EXP_KEYS_DIR=/home/worker/model/model_data/OasisRed/redcat
CF_FILES_DIR=/home/worker/model/

###################################################
# PROGRAM
###################################################

echo 'Checking CWD (run-ored.sh)...'
pwd 
CWD=$(pwd)

echo '==================== STAGE-0: Set up requisite directories  ======================='
echo " > Note that this program expects the latest REDCat executables to reside in ${p1}"
if ! echo "$PATH" | grep -q "$p1"
then
    echo " > Adding to path > ${p1}"
    export PATH=$PATH:${p1}
fi

if ! echo "$PATH" | grep -q "$p2"
then
    echo " > Adding to path >> ${p2}"
    export PATH=$PATH:${p2}
    # Better avoid this operation provided that these dlls should bu consistent with the OS
    #if [ ! -f "$p2/libgfortran.so.4" ]; then
    #    # If the file does not exist, copy it from the current working directory to p2
    #    cp "$p1/libf2c.so.0" $p2
    #    cp "$p1/libgfortran.so.4" $p2
    #    echo " > Files 'libf2c.so.0 and libgfortran.so.4' have been copied to $p2"
    #else
    #    echo " > C++ libraries already exist in $p2. Moving on..."
    #fi
fi

# Step-1: Call oredexp to convert location.csv into portfolio.csv to stream into REDExp.
#  > Define folder containing OED-REDEXP conversion files. In my device its located in the below dir.
###########################################################################################
#echo '==================== STAGE-1: Input portfolio conversion: OED to REDCat ======================='
# DEPRECATED AS OF 22/12. Moved under tasks.py of OasisPlatform

#echo '==================== STAGE-2a: Call REDExp ======================='
#echo ' NOTE that below steps of the program expects three REDCat configuration files (.cf) for REDExp, REDHaz, and REDLoss to be herein present.'
#REDExp -f redexp.cf 2>&1 | tee -a work/REDLog.csv
## Wait for the process to finis
#wait $!
#rm REDExp.out
#echo " INFO> REDEXp execution completed."
# DEPRECATED AS OF 04/01. Moved under tasks.py of OasisPlatform


#echo '==================== STAGE-2b: Call REDHazOQ ======================='
#echo
#REDHazOQ -f redhazoq.cf 2>&1 | tee -a work/REDLog.csv
#wait $!
#rm REDHaz.out
#echo "INFO> REDHazoq execution completed"
# DEPRECATED AS OF 04/01. Moved under tasks.py of OasisPlatform

echo '==================== STAGE-3: REDLoss & Ktools ======================='
echo

# NOTES °°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°° 
# 29/06/2023: Init
#   >   Script modified by OO, expanding on the original, procedurally generated 
#       (i.e., on the fly),'run_ktools.sh' script.
# 10/07/2023: Expanding to a fixed no. of (6) threads
# °°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°

SCRIPT=$(readlink -f "$0") && cd $(dirname "$SCRIPT")

# --- Script Init ---
set -euET -o pipefail
shopt -s inherit_errexit 2>/dev/null || echo "WARNING: Unable to set inherit_errexit. Possibly unsupported by this shell, Subprocess failures may not be detected."

LOG_DIR=log
mkdir -p $LOG_DIR
rm -R -f $LOG_DIR/*

touch $LOG_DIR/stderror.err
ktools_monitor.sh $$ $LOG_DIR & pid0=$!

exit_handler(){
   exit_code=$?

   # disable handler
   trap - QUIT HUP INT KILL TERM ERR EXIT

   kill -9 $pid0 2> /dev/null
   if [ "$exit_code" -gt 0 ]; then
       # Error - run process clean up
       echo 'Ktools Run Error - exitcode='$exit_code

       set +x
       group_pid=$(ps -p $$ -o pgid --no-headers)
       sess_pid=$(ps -p $$ -o sess --no-headers)
       script_pid=$$
       printf "Script PID:%d, GPID:%s, SPID:%d
" $script_pid $group_pid $sess_pid >> $LOG_DIR/killout.txt

       ps -jf f -g $sess_pid > $LOG_DIR/subprocess_list
       PIDS_KILL=$(pgrep -a --pgroup $group_pid | awk 'BEGIN { FS = "[ \t\n]+" }{ if ($1 >= '$script_pid') print}' | grep -v celery | egrep -v *\\.log$  | egrep -v *\\.sh$ | sort -n -r)
       echo "$PIDS_KILL" >> $LOG_DIR/killout.txt
       kill -9 $(echo "$PIDS_KILL" | awk 'BEGIN { FS = "[ \t\n]+" }{ print $1 }') 2>/dev/null
       exit $exit_code
   else
       # script successful
       exit 0
   fi
}
trap exit_handler QUIT HUP INT KILL TERM ERR EXIT

# NOTE (OO - 10/07/2023): Removed eve, getmodel, and gulcalc from proc_list below.
check_complete(){
    set +e
    proc_list="fmcalc summarycalc eltcalc aalcalc leccalc pltcalc ordleccalc"
    has_error=0
    for p in $proc_list; do
        started=$(find log -name "$p*.log" | wc -l)
        finished=$(find log -name "$p*.log" -exec grep -l "finish" {} + | wc -l)
        if [ "$finished" -lt "$started" ]; then
            echo "[ERROR] $p - $((started-finished)) processes lost"
            has_error=1
        elif [ "$started" -gt 0 ]; then
            echo "[OK] $p"
        fi
    done
    if [ "$has_error" -ne 0 ]; then
        false # raise non-zero exit code
    else
        echo 'Run Completed'
    fi
}

check_fifo_x(){
    # Set the timeout duration
    TIMEOUT=300
    START_TIME=$(date +%s)

    # Loop to check for the files
    while true; do
        # Initialize a flag to track if all files are found
        all_files_found=true

        # Loop from 1 to N to check each file
        for i in $(seq 1 "$1"); do
            file="fifo/fifo_p$i"
            # Check if the file does not exist
            if [ ! -e "$file" ]; then
                all_files_found=false
                echo "$file not found."
                break
            fi
        done

        # If all files are found, print success message and return
        if $all_files_found; then
            echo "All REDLoss fifo files found."
            return
        fi

        # Calculate the elapsed time
        CURRENT_TIME=$(date +%s)
        ELAPSED_TIME=$(( CURRENT_TIME - START_TIME ))

        # Check if the timeout has been reached
        if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
            echo "Error: Not all fifo files found within $TIMEOUT seconds."
            exit 1
        fi

        # Wait for 1 second before the next check
        sleep 1
    done
}

# --- Setup run dirs ---

occurrencetobin -D -P 30000 < ./input/occurrence.csv > ./input/occurrence.bin

find output -type f -not -name '*summary-info*' -not -name '*.json' -exec rm -R -f {} +

