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
echo "		- oredexp 1.1.0\n"
echo "		- getzones 0.1.1\n"
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
    if [ ! -f "$p2/libgfortran.so.4" ]; then
        # If the file does not exist, copy it from the current working directory to p2
        cp "$p1/libf2c.so.0" $p2
        cp "$p1/libgfortran.so.4" $p2
        echo " > Files 'libf2c.so.0 and libgfortran.so.4' have been copied to $p2"
    else
        echo " > C++ libraries already exist in $p2. Moving on..."
    fi
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
	TIMEOUT=15
	START_TIME=$(date +%s)

	# Loop to check for the file
	while true; do
		# Check if the file exists
		if [ -e "fifo_p8" ]; then
			echo "REDLoss fifo found."
			return
		fi

		# Calculate the elapsed time
		CURRENT_TIME=$(date +%s)
		ELAPSED_TIME=$(( CURRENT_TIME - START_TIME ))

		# Check if the timeout has been reached
		if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
			echo "Error: fifo not found within $TIMEOUT seconds."
			exit 1
		fi

		# Wait for 1 second before the next check
		sleep 1
	done
}

# --- Setup run dirs ---

find output -type f -not -name '*summary-info*' -not -name '*.json' -exec rm -R -f {} +

# ------------------------------------------------------------ 29/06/2023
# NOTE (OO):    Refactoring line below to prevent erasing the contents of work/ 
#               since it also contains REDCat outputs. REmoving only kat/
# ------------------------------------------------------------ 29/06/2023
rm -R -f work/kat/

mkdir -p work/kat/

# Generate the occurrence file...
occurrencetobin -D -P 30000 < ./input/occurrence.csv > ./input/occurrence.bin

#fmpy -a2 --create-financial-structure-files
rm -R -f /tmp/i02QFjyaNF/
mkdir -p /tmp/i02QFjyaNF/fifo/
mkdir -p work/gul_S1_summaryleccalc
mkdir -p work/gul_S1_summaryaalcalc
mkdir -p work/il_S1_summaryleccalc
mkdir -p work/il_S1_summaryaalcalc

mkfifo /tmp/i02QFjyaNF/fifo/gul_P1
mkfifo /tmp/i02QFjyaNF/fifo/gul_P2
mkfifo /tmp/i02QFjyaNF/fifo/gul_P3
mkfifo /tmp/i02QFjyaNF/fifo/gul_P4
mkfifo /tmp/i02QFjyaNF/fifo/gul_P5
mkfifo /tmp/i02QFjyaNF/fifo/gul_P6
mkfifo /tmp/i02QFjyaNF/fifo/gul_P7
mkfifo /tmp/i02QFjyaNF/fifo/gul_P8

# #

mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P1
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P1.idx
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P1

mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P2
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P2.idx
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P2

mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P3
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P3.idx
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P3

mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P4
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P4.idx
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P4

mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P5
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P5.idx
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P5

mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P6
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P6.idx
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P6

mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P7
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P7.idx
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P7

mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P8
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_summary_P8.idx
mkfifo /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P8

# #

mkfifo /tmp/i02QFjyaNF/fifo/il_P1
mkfifo /tmp/i02QFjyaNF/fifo/il_P2
mkfifo /tmp/i02QFjyaNF/fifo/il_P3
mkfifo /tmp/i02QFjyaNF/fifo/il_P4
mkfifo /tmp/i02QFjyaNF/fifo/il_P5
mkfifo /tmp/i02QFjyaNF/fifo/il_P6
mkfifo /tmp/i02QFjyaNF/fifo/il_P7
mkfifo /tmp/i02QFjyaNF/fifo/il_P8

# #

mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P1
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P1.idx
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P1

mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P2
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P2.idx
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P2

mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P3
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P3.idx
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P3

mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P4
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P4.idx
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P4

mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P5
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P5.idx
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P5

mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P6
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P6.idx
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P6

mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P7
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P7.idx
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P7

mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P8
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_summary_P8.idx
mkfifo /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P8

# --- Do insured loss computes ---

( eltcalc < /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P1 > work/kat/il_S1_eltcalc_P1 ) 2>> $LOG_DIR/stderror.err & pid1=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P2 > work/kat/il_S1_eltcalc_P2 ) 2>> $LOG_DIR/stderror.err & pid2=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P3 > work/kat/il_S1_eltcalc_P3 ) 2>> $LOG_DIR/stderror.err & pid3=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P4 > work/kat/il_S1_eltcalc_P4 ) 2>> $LOG_DIR/stderror.err & pid4=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P5 > work/kat/il_S1_eltcalc_P5 ) 2>> $LOG_DIR/stderror.err & pid5=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P6 > work/kat/il_S1_eltcalc_P6 ) 2>> $LOG_DIR/stderror.err & pid6=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P7 > work/kat/il_S1_eltcalc_P7 ) 2>> $LOG_DIR/stderror.err & pid7=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P8 > work/kat/il_S1_eltcalc_P8 ) 2>> $LOG_DIR/stderror.err & pid8=$!

tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P1 /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P1 work/il_S1_summaryaalcalc/P1.bin work/il_S1_summaryleccalc/P1.bin > /dev/null & pid9=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P1.idx work/il_S1_summaryaalcalc/P1.idx work/il_S1_summaryleccalc/P1.idx > /dev/null & pid10=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P2 /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P2 work/il_S1_summaryaalcalc/P2.bin work/il_S1_summaryleccalc/P2.bin > /dev/null & pid11=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P2.idx work/il_S1_summaryaalcalc/P2.idx work/il_S1_summaryleccalc/P2.idx > /dev/null & pid12=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P3 /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P3 work/il_S1_summaryaalcalc/P3.bin work/il_S1_summaryleccalc/P3.bin > /dev/null & pid13=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P3.idx work/il_S1_summaryaalcalc/P3.idx work/il_S1_summaryleccalc/P3.idx > /dev/null & pid14=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P4 /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P4 work/il_S1_summaryaalcalc/P4.bin work/il_S1_summaryleccalc/P4.bin > /dev/null & pid15=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P4.idx work/il_S1_summaryaalcalc/P4.idx work/il_S1_summaryleccalc/P4.idx > /dev/null & pid16=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P5 /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P5 work/il_S1_summaryaalcalc/P5.bin work/il_S1_summaryleccalc/P5.bin > /dev/null & pid17=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P5.idx work/il_S1_summaryaalcalc/P5.idx work/il_S1_summaryleccalc/P5.idx > /dev/null & pid18=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P6 /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P6 work/il_S1_summaryaalcalc/P6.bin work/il_S1_summaryleccalc/P6.bin > /dev/null & pid19=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P6.idx work/il_S1_summaryaalcalc/P6.idx work/il_S1_summaryleccalc/P6.idx > /dev/null & pid20=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P7 /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P7 work/il_S1_summaryaalcalc/P7.bin work/il_S1_summaryleccalc/P7.bin > /dev/null & pid21=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P7.idx work/il_S1_summaryaalcalc/P7.idx work/il_S1_summaryleccalc/P7.idx > /dev/null & pid22=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P8 /tmp/i02QFjyaNF/fifo/il_S1_eltcalc_P8 work/il_S1_summaryaalcalc/P8.bin work/il_S1_summaryleccalc/P8.bin > /dev/null & pid23=$!
tee < /tmp/i02QFjyaNF/fifo/il_S1_summary_P8.idx work/il_S1_summaryaalcalc/P8.idx work/il_S1_summaryleccalc/P8.idx > /dev/null & pid24=$!

# #

( summarycalc -m -f  -1 /tmp/i02QFjyaNF/fifo/il_S1_summary_P1 < /tmp/i02QFjyaNF/fifo/il_P1 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -f  -1 /tmp/i02QFjyaNF/fifo/il_S1_summary_P2 < /tmp/i02QFjyaNF/fifo/il_P2 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -f  -1 /tmp/i02QFjyaNF/fifo/il_S1_summary_P3 < /tmp/i02QFjyaNF/fifo/il_P3 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -f  -1 /tmp/i02QFjyaNF/fifo/il_S1_summary_P4 < /tmp/i02QFjyaNF/fifo/il_P4 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -f  -1 /tmp/i02QFjyaNF/fifo/il_S1_summary_P5 < /tmp/i02QFjyaNF/fifo/il_P5 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -f  -1 /tmp/i02QFjyaNF/fifo/il_S1_summary_P6 < /tmp/i02QFjyaNF/fifo/il_P6 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -f  -1 /tmp/i02QFjyaNF/fifo/il_S1_summary_P7 < /tmp/i02QFjyaNF/fifo/il_P7 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -f  -1 /tmp/i02QFjyaNF/fifo/il_S1_summary_P8 < /tmp/i02QFjyaNF/fifo/il_P8 ) 2>> $LOG_DIR/stderror.err  &

# --- Do ground up loss computes ---

( eltcalc < /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P1 > work/kat/gul_S1_eltcalc_P1 ) 2>> $LOG_DIR/stderror.err & pid25=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P2 > work/kat/gul_S1_eltcalc_P2 ) 2>> $LOG_DIR/stderror.err & pid26=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P3 > work/kat/gul_S1_eltcalc_P3 ) 2>> $LOG_DIR/stderror.err & pid27=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P4 > work/kat/gul_S1_eltcalc_P4 ) 2>> $LOG_DIR/stderror.err & pid28=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P5 > work/kat/gul_S1_eltcalc_P5 ) 2>> $LOG_DIR/stderror.err & pid29=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P6 > work/kat/gul_S1_eltcalc_P6 ) 2>> $LOG_DIR/stderror.err & pid30=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P7 > work/kat/gul_S1_eltcalc_P7 ) 2>> $LOG_DIR/stderror.err & pid31=$!
( eltcalc -s < /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P8 > work/kat/gul_S1_eltcalc_P8 ) 2>> $LOG_DIR/stderror.err & pid32=$!


tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P1 /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P1 work/gul_S1_summaryaalcalc/P1.bin work/gul_S1_summaryleccalc/P1.bin > /dev/null & pid33=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P1.idx work/gul_S1_summaryaalcalc/P1.idx work/gul_S1_summaryleccalc/P1.idx > /dev/null & pid34=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P2 /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P2 work/gul_S1_summaryaalcalc/P2.bin work/gul_S1_summaryleccalc/P2.bin > /dev/null & pid35=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P2.idx work/gul_S1_summaryaalcalc/P2.idx work/gul_S1_summaryleccalc/P2.idx > /dev/null & pid36=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P3 /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P3 work/gul_S1_summaryaalcalc/P3.bin work/gul_S1_summaryleccalc/P3.bin > /dev/null & pid37=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P3.idx work/gul_S1_summaryaalcalc/P3.idx work/gul_S1_summaryleccalc/P3.idx > /dev/null & pid38=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P4 /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P4 work/gul_S1_summaryaalcalc/P4.bin work/gul_S1_summaryleccalc/P4.bin > /dev/null & pid39=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P4.idx work/gul_S1_summaryaalcalc/P4.idx work/gul_S1_summaryleccalc/P4.idx > /dev/null & pid40=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P5 /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P5 work/gul_S1_summaryaalcalc/P5.bin work/gul_S1_summaryleccalc/P5.bin > /dev/null & pid41=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P5.idx work/gul_S1_summaryaalcalc/P5.idx work/gul_S1_summaryleccalc/P5.idx > /dev/null & pid42=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P6 /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P6 work/gul_S1_summaryaalcalc/P6.bin work/gul_S1_summaryleccalc/P6.bin > /dev/null & pid43=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P6.idx work/gul_S1_summaryaalcalc/P6.idx work/gul_S1_summaryleccalc/P6.idx > /dev/null & pid44=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P7 /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P7 work/gul_S1_summaryaalcalc/P7.bin work/gul_S1_summaryleccalc/P7.bin > /dev/null & pid45=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P7.idx work/gul_S1_summaryaalcalc/P7.idx work/gul_S1_summaryleccalc/P7.idx > /dev/null & pid46=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P8 /tmp/i02QFjyaNF/fifo/gul_S1_eltcalc_P8 work/gul_S1_summaryaalcalc/P8.bin work/gul_S1_summaryleccalc/P8.bin > /dev/null & pid47=$!
tee < /tmp/i02QFjyaNF/fifo/gul_S1_summary_P8.idx work/gul_S1_summaryaalcalc/P8.idx work/gul_S1_summaryleccalc/P8.idx > /dev/null & pid48=$!


( summarycalc -m -i  -1 /tmp/i02QFjyaNF/fifo/gul_S1_summary_P1 < /tmp/i02QFjyaNF/fifo/gul_P1 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -i  -1 /tmp/i02QFjyaNF/fifo/gul_S1_summary_P2 < /tmp/i02QFjyaNF/fifo/gul_P2 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -i  -1 /tmp/i02QFjyaNF/fifo/gul_S1_summary_P3 < /tmp/i02QFjyaNF/fifo/gul_P3 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -i  -1 /tmp/i02QFjyaNF/fifo/gul_S1_summary_P4 < /tmp/i02QFjyaNF/fifo/gul_P4 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -i  -1 /tmp/i02QFjyaNF/fifo/gul_S1_summary_P5 < /tmp/i02QFjyaNF/fifo/gul_P5 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -i  -1 /tmp/i02QFjyaNF/fifo/gul_S1_summary_P6 < /tmp/i02QFjyaNF/fifo/gul_P6 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -i  -1 /tmp/i02QFjyaNF/fifo/gul_S1_summary_P7 < /tmp/i02QFjyaNF/fifo/gul_P7 ) 2>> $LOG_DIR/stderror.err  &
( summarycalc -m -i  -1 /tmp/i02QFjyaNF/fifo/gul_S1_summary_P8 < /tmp/i02QFjyaNF/fifo/gul_P8 ) 2>> $LOG_DIR/stderror.err  &

# ------------------------------------------------------------------------------ 21/12/2023
# NOTE (OO):    This is the heart of the script. Commenting out the two lines 
#               and replacing them with REDCat-ktools fusion
# 
echo
echo "|---> Opening up REDLoss pipes now..."
touch output/redloss.log
REDLoss -f redloss1.cf 2>> output/redloss.log & 
REDLoss -f redloss2.cf & 
REDLoss -f redloss3.cf & 
REDLoss -f redloss4.cf & 
REDLoss -f redloss5.cf & 
REDLoss -f redloss6.cf & 
REDLoss -f redloss7.cf & 
REDLoss -f redloss8.cf & 

echo "|---> Check REDLoss fifo..."

ls -a

check_fifo_x

( tee < fifo_p1 /tmp/i02QFjyaNF/fifo/gul_P1 | fmcalc -a2 > /tmp/i02QFjyaNF/fifo/il_P1  ) 2>> $LOG_DIR/stderror.err &
( tee < fifo_p2 /tmp/i02QFjyaNF/fifo/gul_P2 | fmcalc -a2 > /tmp/i02QFjyaNF/fifo/il_P2  ) 2>> $LOG_DIR/stderror.err &
( tee < fifo_p3 /tmp/i02QFjyaNF/fifo/gul_P3 | fmcalc -a2 > /tmp/i02QFjyaNF/fifo/il_P3  ) 2>> $LOG_DIR/stderror.err &
( tee < fifo_p4 /tmp/i02QFjyaNF/fifo/gul_P4 | fmcalc -a2 > /tmp/i02QFjyaNF/fifo/il_P4  ) 2>> $LOG_DIR/stderror.err &
( tee < fifo_p5 /tmp/i02QFjyaNF/fifo/gul_P5 | fmcalc -a2 > /tmp/i02QFjyaNF/fifo/il_P5  ) 2>> $LOG_DIR/stderror.err &
( tee < fifo_p6 /tmp/i02QFjyaNF/fifo/gul_P6 | fmcalc -a2 > /tmp/i02QFjyaNF/fifo/il_P6  ) 2>> $LOG_DIR/stderror.err &
( tee < fifo_p7 /tmp/i02QFjyaNF/fifo/gul_P7 | fmcalc -a2 > /tmp/i02QFjyaNF/fifo/il_P7  ) 2>> $LOG_DIR/stderror.err &
( tee < fifo_p8 /tmp/i02QFjyaNF/fifo/gul_P8 | fmcalc -a2 > /tmp/i02QFjyaNF/fifo/il_P8  ) 2>> $LOG_DIR/stderror.err &

echo

#
# ------------------------------------------------------------------------------ 21/12/2023

wait $pid1 $pid2 $pid3 $pid4 $pid5 $pid6 $pid7 $pid8 $pid9 $pid10 $pid11 $pid12 $pid13 $pid14 $pid15 $pid16 $pid17 $pid18 $pid19 $pid20 $pid21 $pid22 $pid23 $pid24 $pid25 $pid26 $pid27 $pid28 $pid29 $pid30 $pid31 $pid32 $pid33 $pid34 $pid35 $pid36 $pid37 $pid38 $pid39 $pid40 $pid41 $pid42 $pid43 $pid44 $pid45 $pid46 $pid47 $pid48

# --- Do insured loss kats ---

kat work/kat/il_S1_eltcalc_P1 work/kat/il_S1_eltcalc_P2 work/kat/il_S1_eltcalc_P3 work/kat/il_S1_eltcalc_P4 work/kat/il_S1_eltcalc_P5 work/kat/il_S1_eltcalc_P6 work/kat/il_S1_eltcalc_P7 work/kat/il_S1_eltcalc_P8 > output/il_S1_eltcalc.csv & kpid1=$!

# --- Do ground up loss kats ---

kat work/kat/gul_S1_eltcalc_P1 work/kat/gul_S1_eltcalc_P2 work/kat/gul_S1_eltcalc_P3 work/kat/gul_S1_eltcalc_P4 work/kat/gul_S1_eltcalc_P5 work/kat/gul_S1_eltcalc_P6 work/kat/gul_S1_eltcalc_P7 work/kat/gul_S1_eltcalc_P8 > output/gul_S1_eltcalc.csv & kpid2=$!
wait $kpid1 $kpid2

( aalcalc -Kil_S1_summaryaalcalc > output/il_S1_aalcalc.csv ) 2>> $LOG_DIR/stderror.err & lpid1=$!
( leccalc -r -Kil_S1_summaryleccalc -F output/il_S1_leccalc_full_uncertainty_aep.csv -f output/il_S1_leccalc_full_uncertainty_oep.csv ) 2>> $LOG_DIR/stderror.err & lpid2=$!
( aalcalc -Kgul_S1_summaryaalcalc > output/gul_S1_aalcalc.csv ) 2>> $LOG_DIR/stderror.err & lpid3=$!
( leccalc -r -Kgul_S1_summaryleccalc -F output/gul_S1_leccalc_full_uncertainty_aep.csv -f output/gul_S1_leccalc_full_uncertainty_oep.csv ) 2>> $LOG_DIR/stderror.err & lpid4=$!

wait $lpid1 $lpid2 $lpid3 $lpid4

# ------------------------------------------------------------ 29/06/2023
# NOTE (OO):    Again, not touching work/ not the tmp named pipe to be able to
#               monitor outputs.
# ------------------------------------------------------------ 29/06/2023

check_complete

echo "INFO > Cleaning up temporary files..."

rm -R -f /tmp/i02QFjyaNF/
rm -rf ./work/maps_int

echo "INFO > Finished running ktools!"
