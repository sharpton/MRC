#!/bin/bash
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

LOGS=/netapp/home/sharpton/projects/MRC/scripts/logs


echo "************* NOTE THERE IS A HARD-CODED PATH IN run_transeq.sh"
echo "************* ALSO IT APPARENTLY SOURCES TOM'S bash profile!!"
echo "Alex also cannot figure out how JOB_ID gets set."

INPUT=$1
RAWOUT=$2
SPLITOUT=$3

# where does JOB_ID get set?? I can't figure it out.

qstat -f -j ${JOB_ID}                              > $LOGS/transeq/${JOB_ID}.all 2>&1
echo "****************************"               >> $LOGS/transeq/${JOB_ID}.all 2>&1
echo "RUNNING TRANSEQ WITH $*"                    >> $LOGS/transeq/${JOB_ID}.all 2>&1

#echo "Alex commented out the 'source' line below"
source /netapp/home/sharpton/.bash_profile        >> $LOGS/transeq/${JOB_ID}.all 2>&1

date                                              >> $LOGS/transeq/${JOB_ID}.all 2>&1
transeq -frame=6 $INPUT $OUTPUT                   >> $LOGS/transeq/${JOB_ID}.all 2>&1
date                                              >> $LOGS/transeq/${JOB_ID}.all 2>&1
if[ -z "${SPLITOUT}" ]{
	date                                              >> $LOGS/transeq/${JOB_ID}.all 2>&1
	echo "RUN FINISHED"                               >> $LOGS/transeq/${JOB_ID}.all 2>&1
} else {
	perl ${SCRIPTS}/split_orf_on_stops.pl -i $OUTPUT -o $RAWOUT  >> $LOGS/transeq/${JOB_ID}.all 2>&1
	date                                              >> $LOGS/transeq/${JOB_ID}.all 2>&1
	echo "RUN FINISHED"                               >> $LOGS/transeq/${JOB_ID}.all 2>&1
} fi

echo "****************************"            >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
