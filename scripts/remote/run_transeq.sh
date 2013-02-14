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

echo "************* ALSO IT APPARENTLY SOURCES TOM'S BASHRC!!"


#echo "Here are the relevant lines from Tom's bashrc:"
# export PATH=$PATH:$HOME/bin
# export PERL5LIB=/netapp/home/sharpton/lib/:/netapp/home/sharpton/src/bioperl-live:/netapp/home/sharpton/lib:$PERL5LIB:/netapp/home/sharpton/projects/dev/bioperl/bioperl-hmmer3:/netapp/home/sharpton/bin/x86_64-redhat-linux-gnu:/netapp/home/sharp
# export R_LIBS=/netapp/home/sharpton/R/x86_64-redhat-linux-gnu-library/2.10
# unset USERNAME

INPUT=$1
RAWOUT=$2
SPLITOUT=$3

qstat -f -j ${JOB_ID}                              > $LOGS/transeq/${JOB_ID}.all 2>&1
echo "****************************"               >> $LOGS/transeq/${JOB_ID}.all 2>&1
echo "RUNNING TRANSEQ WITH $*"                    >> $LOGS/transeq/${JOB_ID}.all 2>&1

echo "Alex commented out the 'source' line below"
#source /netapp/home/sharpton/.bash_profile        >> $LOGS/transeq/${JOB_ID}.all 2>&1


date                                              >> $LOGS/transeq/${JOB_ID}.all 2>&1
#transeq -frame=6 input.fa output.fa
transeq -frame=6 $INPUT $OUTPUT                   >> $LOGS/transeq/${JOB_ID}.all 2>&1
date                                              >> $LOGS/transeq/${JOB_ID}.all 2>&1
if[ -z "${SPLITOUT}" ]{
	date                                              >> $LOGS/transeq/${JOB_ID}.all 2>&1
	echo "RUN FINISHED"                               >> $LOGS/transeq/${JOB_ID}.all 2>&1

} else {
	perl split_orf_on_stops.pl -i $OUTPUT -o $RAWOUT  >> $LOGS/transeq/${JOB_ID}.all 2>&1
	date                                              >> $LOGS/transeq/${JOB_ID}.all 2>&1
	echo "RUN FINISHED"                               >> $LOGS/transeq/${JOB_ID}.all 2>&1
} fi
