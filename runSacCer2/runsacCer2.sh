#!/bin/bash

test_dir=`pwd`

# Download the reference genome from UCSC (allows easy browsing of results)

printf "Downloading reference genome...\n\n"

wget -nc http://hgdownload.soe.ucsc.edu/goldenPath/sacCer2/bigZips/chromFa.tar.gz
tar xvzf chromFa.tar.gz
rm chromFa.tar.gz
cat chr*fa 2micron.fa > sacCer2.fa
rm chr*fa 2micron.fa

# Download gff locations of reference TE copies
wget -nc http://files.figshare.com/287395/File_S2.txt
awk '{print $3"\treannotate\ttransposable_element\t"$4"\t"$5"\t.\t"$6"\t.\tID="$1;}' File_S2.txt > tmp
sed '1d;$d' tmp > reference_TE_locations.gff
rm File_S2.txt
rm tmp

# The TE families file and consensus TE fasta file are included in this folder

# Download list of file locations from EBI
projects=('SRA072302')
for project in "${projects[@]}"
do
	wget -O $project "http://www.ebi.ac.uk/ena/data/warehouse/filereport?accession=$project&result=read_run&fields=study_accession,secondary_study_accession,sample_accession,secondary_sample_accession,experiment_accession,run_accession,scientific_name,instrument_model,library_layout,fastq_ftp,fastq_galaxy,submitted_ftp,col_tax_id,submitted_galaxy,col_scientific_name&download=text"
	sed 1d $project >> sample_list
done

# Run the pipeline

awk -F'[\t;]' '{print $10}' sample_list > sample_1_urls.txt

# Only allow a maximum of 4 jobs to be submitted to the queue at one time.
sample_no=1

while read line
do 
	if [ $sample_no -eq 1 ]; then
		qsub -l long -l cores=4 -V -cwd -N mcclintock$sample_no launchMcClintock.sh $line
		echo -e "$line\tmcclintock$sample_no" > job_key
	else
        qsub -l long -l cores=4 -V -cwd -N mcclintock$sample_no -hold_jid mcclintock"1" launchMcClintock.sh $line
        echo -e "$line\tmcclintock$sample_no" >> job_key
    fi
    sample_no=$((sample_no+1))
done < sample_1_urls.txt

