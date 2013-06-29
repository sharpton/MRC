OVERVIEW


MRC is a metagenomic and metatranscriptomic data and analysis management workflow. In brief, it interfaces with a database of protein families and classifies translated metagenomic/metatrnascriptomic sequence reads into families. Classified reads are considered homologs of the family and the family's functional annotation is transferred to the read. The raw sequence read data, translated peptides, and classification results are all stored in a relational MySQL database, which is queried to calculate functional diversity, such as protein family richness and relative abundance.

MRC handles the communication between three different servers throughout the workflow: 
(1) LOCAL, which is the local machine that manages the workflow, data management, and file parsing;  
(2) DBSERVER, which is a MySQL server that stores the relational database; and 
(3) REMOTE, which is a distributed grid computing cluster (e.g., SGE) that handles parallel computing including read translation and the comparison of translated reads into protein families. 

Note that the DBSERVER and LOCAL can be the same physical machine. If you do not have access to a distributed computing cluster, you can optionally run the entire MRC workflow on a single machine, but this is not recommended for large data sets. Importantly, LOCAL must be able to communicate with both DBSERVER (via mysql ports) and REMOTE (via ssh ports), but DBSERVER and REMOTE do not need to be able to directly communicate with one another.

PASTE TEXT TO GUILLAUME HERE

Distributed versus Local Computing

Because metagenomic/metatranscriptomic data tends to be large, it is highly recommended that you take advantage of the distributed grid computing management software infrastructure that is integrated in MRC. This requires that you have access to a distributed grid computing cluster. Currently, MRC is configured for SGE configured clusters, though I believe very slight modification will enable the software's extension to a PBS configured system. Please contact me if you have access to a PBS configured cluster and would like to help extend MRC to that platform.

If you do not have access to such a cluster, you can run MRC on a single machine, but it will take longer to process all of the data. In such a case, I recommend using --pre-rare-reads to reduce the volume of data you analyze.

INSTALLATION

Admittedly, MRC is not trivial to install. This is largely because of the number of steps in the workflow, the complexity associated with persistently managing communication between multiple servers, and the need to adopt efficient tools to handle the large volume of data generated in metagenomic/metatranscriptomic projects. 

Hopefully, these instructions will get you on your way. If you find that additional details would be helpful, please contact me to indicate where the instructions are ambiguous. 

These Installation instructions are divided into three parts:
1. Software Dependencies ADD GITHUB CLONE TO THIS!
2. Infrastructural Dependencies
3. Workflow Execution

Infrastructural Dependencies

1. The machine on which you have the MRC github repo installed must be able to (a) communicate with your MySQL DB server (localhost is fine) and (b) communicate with your grid computing cluster via password-less SSH keys (currently, only works with SGE configured clusters). We will call the machine that contains the MRC repo the "local" machine (note that this might also be the "database server") and the grid computing cluster the "remote" machine.

2. You must have the SFams MySQL database installed on the database server. You will need select and insert permissions.

3. You must have the SFams flatfile repository installed on the local machine (note - you may need to make some changes to mirror the structure that I'm currently working with, which is similar, though not exact to what you've recently generated in terms of the repo structure; we should discuss this point in more detail. If you would like a copy of my repo, I can ship it over).

4. You must have the search algorithms that you're interested in using to annotate your metagenomic reads installed on the remote machine. MRC is currently configured to use hmmsearch, hmmscan, blastp, last, and rapsearch. I recommend rapsearch. The binaries for these algorithms must be in your $PATH environmental variable. For testing, you do not need to install them all.

5. You must have transeq, which is part of the EMBOSS software suite, installed on the remote server.

6. You must have a location on the local machine that you can write files to. Specifically, we will create a flat file MRC database (MRC_ffdb) that will contain the raw reads, translated reads, and search results. 

7. You must have a location on the remote machine that you can write files to. We will create a copy of the MRC_ffdb on the remote machine.

Software Dependencies

8. You must have the perl dependencies in the MRC source code installed on the local machine. Add them to your PERL5LIB variable on your local machine. These include:

Getopt::Long
Data::Dumper
Bio::SeqIO
Bio::SearchIO
File::Basename
File::Spec
File::Copy
File::Path
File::Cat
IPC::System::Simple
Benchmark
Carp
DBIx::Class::ResultClass::HashRefInflator
DBI
DBD::mysql
DBIx::BulkLoader::Mysql
IO::Uncompress::Gunzip
IO::Compress::Gzip
List::Util

WHERE ARE THE DBI LIBRARIES???

9. You must have the following perl dependencies in the MRC source code installed on the remote machine. Add them to the PERL5LIB variable on your remote machine. These include:

File::Path
File::Spec
IPC::System::Simple

10. From the lib subdirectory in the MRC github repo, add lib/SFams/Schema.pm to your local machine's PERL5LIB variable.

11. At this point, you should have everything you need to run the software.


TEST RUN AND TROUBLESHOOTING

We use mrc_handler.pl to interface with the workflow. There are a lot of options, which can be set using run time variables, but I recommend that we keep it simple to start. From the scripts directory in the MRC github repo, try the following:
perl mrc_handler.pl --dbuser=<your_mysql_username> --dbpass=<your_mysql_password> --dbhost=<database_hostname(e.g., localhost)> --rhost=<remote_hostname(e.g.,chef.compbio.ucsf.edu)> --ruser=<remote_username> --rdir=<location_of_remote_ffdb(e.g., /home/sharpton/MRC_ffdb_chef/)> --dbname=<name_of_mysql_SFams_DB> --ffdb=<location_of_local_ffdb(e.g., /home/sharpton/MRC_ffdb/) --refdb=<location_to_local_sfams_repo(e.g.,/home/sharpton/sifting_families/)> --dbprefix=<custom_prefix_for_your_searchdb(see below)> --projdir=<location_to_metagenome_file_on_local_machine(eg, ../data/randsamp_subset_perfect_2)> --sub=<location_to_sfam_subset_list (eg,../data/randsamp_subset_perfect_2_famids.txt)> --bdb --stage --use_rapsearch
The --bdb option tells mrc to build a blast database (composed of family members), the --stage option tells mrc to push that database to the remote server, the --use_rapsearch tells mrc to search your reads against the blast database that you will build with rapsearch, and the --force I think a brief explanation of what the workflow will do would be useful at this point. The --sub option tells mrc to only include a subset of the SFams in the blast database. By pointing --sub to ../data/randsamp_subset_perfect_2_famids.txt  you will have a relatively small search database, which will keep troubleshooting simple since the workflow will move quickly. If you also point --projdir to ../data/randsamp_subset_perfect_2, you will have a small set of reads that should ultimately produce meaningful hits to a database built from the andsamp_subset_perfect_2_famids.txt subset of families.

WORKFLOW DETAILS

At this point, a brief description of the workflow would be useful. First, we identify the location of the metagenomes that we want to process and create a new project. We are actually pointing mrc_handler.pl to a directory of FASTA files, where each file corresponds to a sample. We assume that all of the files in the directory come from the same analysis project. We then insert a new project and, for each fasta file in the directory, a new sample in to the MySQL database. This returns a project id and sample ids, which are used to create a flatfile database for the project on the local machine:

/home/sharpton/MRC_ffdb/projects/<project_id>/<sample_id>/......

Note that to prevent data from being analyzed multiple times, we require that the name of the samples, which are obtained from the FASTA file names, are unique in the database. This is annoying for troubleshooting because you have to wipe the sample from the database before rerunning the software, but it'll save a lot of time in the future. There are two ways to do this. For now, I'll recommend that you have a MySQL tab open and simply do the following:

delete from projects where project_id = <project_id>

There is a cascade delete on sample_id, so this should be sufficient for clearing the project from the database.


We then insert reads into the database (unless --is-slim is set, but this is only recommended for VERY LARGE metagenomes) and push the local flatfile database to the remote machine. Note that the local and remote databases for a project mirror one another.

From the local machine, we then launch transeq, which create 6 frame translations for each read. We also split the translated peptides on stop codons on the remote machine. The results of this process are called orfs, which are subsequently pulled back to the local machine and inserted into the MySQL database.

If --bdb (build blast database) or --hdb (build hmm database) are set, then we build a search database, which will act as the reference information for read annotation. Here, we open the SFams repo and cat family data (either sequences if a blast database is needed or HMMs if an HMM database is needed) into a split database of predetermined size (see mrc_handler.pl for information on how to tune this; for now, use the default size). If you only want to search against a subset of the families, point --sub to a file that lists family ids to search against, one per line. The result of this process is a compressed search database that is ready for massively parallel computing, located in the following directory:

/home/sharpton/MRC_ffdb/BLASTdbs/

where the database is named by the runtime option --dbprefix. We then transfer this database to the remote machine since --stage is set. If we need to format the database (e.g., formatdb, lastdb, prerapsearch), then we launch the appropriate process from the local machine on the remote cluster (this is automatically conducted if --stage is set). 

Note that you do not need to rebuild or restage a database every time you run as these directories are common to all MRC projects. Once you’ve built and staged a database, it is good for as many runs as you would like. But, you can always rebuild or restage using the --0force option, if you like.

Now we are ready to annotate reads by classifing orfs into protein families. Here, mrc_handler.pl launches a series of array jobs to massively parallelize the pairwise comparison of reads to families. It will only run the algorithms that you tell it to at runtime (e.g., --use_rapsearch). The handler will process the reads for each sample iteratively, so you should not flood your queue with jobs, though this depends on how many times you split your original sequence sample file.

Two important items of note. First, you may have to tweak the SGE submission script for your specific cluster by editing scripts/build_remote_rapsearch_script.pl. Ultimately, I’d like to incorporate a more flexible way of dealing with this. Also, you might need to make similar changes to run_remote_transeq.pl and run_remote_prerapsearch.pl (and the similar files for the other algorithms).

Second, the handler will check for jobs that did not run to completion and will restart them. Reasons for failure may be that the walltime on a node was hit because of CPU limitations or other types of cryptic, node-specific limitations. In my experience, 2 restarts is enough to ensure that all jobs run to completion. But, you may find that this is insufficient for your purposes.


Once all of the jobs have been successfully executed, mrc pulls the results to the local flat file database and parses the output files. It uses user specified (default options are set in mrc_handler.pl) thresholds to determine if a read is a member of a family. Search results passing these thresholds result in a new row being created in familymembers, with the orf_id being entered as the subsequent member. Note that the default is to allow only the top scoring orf to be classified to a family for each read (e.g., a read is only represented a single time in familymembers).

For now, the program will stop. I’m sorting through some final output routines, which will produce diversity metrics and plots (I’m hoping to have this by early next week).


RUN-TIME OPTIONS



FAQ


