#!/bin/bash

# Note for lines below: these weird "#" and "$" lines here are SUPER IMPORTANT and are used by the queue somehow. DO NOT REMOVE THEM!
# THESE LINES BELOW ARE NOT COMMENTS, EVEN THOUGH THEY LOOK LIKE COMMENTS!!!!!!!!!!!!!!

#
#$ -S /bin/bash
#$ -l arch=lx24-amd64
#$ -l h_rt=00:30:0
#$ -l scratch=0.5G
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

#for big memory, add this
# #$ -l xe5520=true
#$ -l mem_free=0.5G

LOGS=/dev/stdout #/netapp/home/sharpton/projects/MRC/scripts/logs

echo "************* NOTE THERE IS A HARD-CODED PATH IN run_transeq.sh"
echo "************* ALSO IT APPARENTLY SOURCES TOM'S bash profile!!"

# Arguments to the script: three command-line arguments
INPUT=$1
RAWOUT=$2
SPLITOUT=$3

# where does JOB_ID get set?? I can't figure it out.

## JOB_ID and TASK_ID are both *magic* environment variables that are set automatically by the job scheduler! This is some kind of cluster magic.

ALL_OUT_FILE=$LOGS/transeq/${JOB_ID}.all

qstat -f -j ${JOB_ID}                              > ${ALL_OUT_FILE} 2>&1
# Note that the '>' above is just ONE caret, to CREATE the file, and all the subequent ones APPEND to the file ('>>')

echo "****************************"               >> ${ALL_OUT_FILE} 2>&1
echo "RUNNING TRANSEQ WITH $*"                    >> ${ALL_OUT_FILE} 2>&1

#echo "Alex commented out the 'source' line below"
#source /netapp/home/sharpton/.bash_profile        >> ${ALL_OUT_FILE} 2>&1
date                                              >> ${ALL_OUT_FILE} 2>&1
transeq -frame=6 $INPUT $OUTPUT                   >> ${ALL_OUT_FILE} 2>&1
date                                              >> ${ALL_OUT_FILE} 2>&1
if[ -z "${SPLITOUT}" ]{
	date                                      >> ${ALL_OUT_FILE} 2>&1
	echo "RUN FINISHED"                       >> ${ALL_OUT_FILE} 2>&1
} else {
	perl ${SCRIPTS}/split_orf_on_stops.pl -i $OUTPUT -o $RAWOUT  >> ${ALL_OUT_FILE} 2>&1
	date                                                         >> ${ALL_OUT_FILE} 2>&1
	echo "RUN FINISHED"                                          >> ${ALL_OUT_FILE} 2>&1
} fi

echo "****************************"            >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
