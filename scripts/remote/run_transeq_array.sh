#!/bin/bash
#
#$ -S /bin/bash
##$ -l arch=lx24-amd64
#$ -l arch=linux-x64
#$ -l h_rt=00:30:0
#$ -l scratch=0.5G
#$ -cwd
#$ -o /dev/null
#$ -e /dev/null

#for big memory, add this
# #$ -l xe5520=true
#$ -l mem_free=0.5G

#rather than set -t here, set it at the command line so that the range can vary across samples (different samples will have different number of splits)

INPATH=$1
INBASENAME=$2
OUTPATH=$3
OUTBASENAME=$4
SCRIPTS=$5
LOGS=$6
SPLITOUTPATH=$7

INPUT=${INPATH}/${INBASENAME}${SGE_TASK_ID}.fa
OUTPUT=${OUTPATH}/${OUTBASENAME}${SGE_TASK_ID}.fa


#let's see if the results already exist....
if [ -e ${OUTPATH}/${OUTPUT} ]
then
    exit
fi

qstat -f -j ${JOB_ID}                           > $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
uname -a                                       >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
echo "****************************"            >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
echo "RUNNING TRANSEQ WITH $*"                 >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
source /netapp/home/sharpton/.bash_profile     >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
date                                           >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
#transeq -frame=6 input.fa output.fa
echo "transeq -frame=6 $INPUT $OUTPUT"         >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
transeq -frame=6 $INPUT $OUTPUT                >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
if[ -d $SPLITOUTPATH ]{
	SPLITOUTPUT=${SPLITOUTPATH}/${OUTBASENAME}${SGE_TASK_ID}.fa   >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
	echo "perl ${SCRIPTS}split_orf_on_stops.pl -i $OUTPUT -o $SPLITOUTPUT"  >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
	perl ${SCRIPTS}split_orf_on_stops.pl -i $OUTPUT -o $SPLITOUTPUT         >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
	date                                                          >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
	echo "RUN FINISHED"                                           >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
} else {
	date                                              >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
	echo "RUN FINISHED"                               >> $LOGS/transeq/${JOB_ID}.${SGE_TASK_ID}.all 2>&1
} fi