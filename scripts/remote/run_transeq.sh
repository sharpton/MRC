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

qstat -f -j ${JOB_ID}                           > $LOGS/transeq/${JOB_ID}.all 2>&1
echo "****************************"            >> $LOGS/transeq/${JOB_ID}.all 2>&1
echo "RUNNING TRANSEQ WITH $*"                 >> $LOGS/transeq/${JOB_ID}.all 2>&1
source /netapp/home/sharpton/.bash_profile     >> $LOGS/transeq/${JOB_ID}.all 2>&1
date                                           >> $LOGS/transeq/${JOB_ID}.all 2>&1
#transeq -frame=6 input.fa output.fa
transeq -frame=6 $*                            >> $LOGS/transeq/${JOB_ID}.all 2>&1
date                                           >> $LOGS/transeq/${JOB_ID}.all 2>&1
echo "RUN FINISHED"                            >> $LOGS/transeq/${JOB_ID}.all 2>&1