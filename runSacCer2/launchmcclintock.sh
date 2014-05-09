#!/bin/bash

url=${1%%_1.f*}
sample_name=${url##*/}

test_dir=`pwd`

# If the sample folder exists this sample must have at least been launched
if [ -d ../sacCer2/$sample_name/ ]; then
	# If the results files exist then nothing needs to be done
	if [[ -f ../sacCer2/$sample_name/results/$sample_name"_relocate.bed" && -f ../sacCer2/$sample_name/results/$sample_name"_ngs_te_mapper.bed" && -f ../sacCer2/$sample_name/results/$sample_name"_retroseq.bed" && -f ../sacCer2/$sample_name/results/$sample_name"_telocate.bed" && -f ../sacCer2/$sample_name/results/$sample_name"_popoolationte.bed" ]]; then
		echo "$sample_name has already been analysed"
	# If they don't then the run must have been interrupted so files are cleaned up and the run is attempted again
	else
		echo "$sample_name has already been started but must have failed to complete. Cleaning up and retrying"
		rm -r ../sacCer2/$sample_name
		rm -r ../RelocaTE/$sample_name
		rm -r ../ngs_te_mapper/$sample_name
		rm -r ../RetroSeq/$sample_name
		rm -r ../TE-locate/$sample_name
		rm -r ../popoolationte/$sample_name
		# Either wget the fastq files, or change commenting to copy them if on kadmon
		wget -q $url"_1.fastq.gz"
		wget -q $url"_2.fastq.gz"
		#cp /mnt/fls01-home01/mqbsscbf/scratch/yeastNGS/SRA/$sample_name"_1.fastq.gz" .
		#cp /mnt/fls01-home01/mqbsscbf/scratch/yeastNGS/SRA/$sample_name"_2.fastq.gz" .
		gunzip $sample_name"_1.fastq.gz"
		gunzip $sample_name"_2.fastq.gz"
		
		cd ..
		
		echo "About to launch mcclintock for $sample_name"
		./mcclintock.sh -r $test_dir/sacCer2.fa -c $test_dir/sac_cer_TE_seqs.fa -g $test_dir/reference_TE_locations.gff -t $test_dir/sac_cer_te_families.tsv -1 $test_dir/$sample_name"_1.fastq" -2 $test_dir/$sample_name"_2.fastq" -i -p 4
		# Remove the fastq files when analysis is complete.
		rm $test_dir/$sample_name"_1.fastq" $test_dir/$sample_name"_2.fastq"
	fi
else
	# Either wget the fastq files, or change commenting to copy them if on kadmon
	wget -q $url"_1.fastq.gz"
	wget -q $url"_2.fastq.gz"
	#cp /mnt/fls01-home01/mqbsscbf/scratch/yeastNGS/SRA/$sample_name"_1.fastq.gz" .
	#cp /mnt/fls01-home01/mqbsscbf/scratch/yeastNGS/SRA/$sample_name"_2.fastq.gz" .
	gunzip $sample_name"_1.fastq.gz"
	gunzip $sample_name"_2.fastq.gz"
	
	cd ..
		
	echo "About to launch mcclintock for $sample_name"
	./mcclintock.sh -r $test_dir/sacCer2.fa -c $test_dir/sac_cer_TE_seqs.fa -g $test_dir/reference_TE_locations.gff -t $test_dir/sac_cer_te_families.tsv -1 $test_dir/$sample_name"_1.fastq" -2 $test_dir/$sample_name"_2.fastq" -i -p 4
	# Remove the fastq files when analysis is complete.
	rm $test_dir/$sample_name"_1.fastq" $test_dir/$sample_name"_2.fastq"
fi
