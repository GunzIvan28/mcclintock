#! /bin/bash -l

usage () 
{
	echo "McClintock Usage"
	echo "This script takes the following inputs and will run 5 different transposable element (TE) detection methods:"
	echo "-r : A reference genome sequence in fasta format. [Required]"
	echo "-c : The consensus sequences of the TEs for the species in fasta format. [Required]"
	echo "-g : The locations of known TEs in the reference genome in GFF 3 format. This must include a unique ID"
	echo "     attribute for every entry. [Optional]"
	echo "-t : A tab delimited file with one entry per ID in the GFF file and two columns: the first containing"
	echo "     the ID and the second containing the TE family it belongs to. The family should correspond to the"
	echo "     names of the sequences in the consensus fasta file. [Optional - required if GFF (option -g) is supplied]"
	echo "-1 : The absolute path of the first fastq file from a paired end read, this should be named ending _1.fastq. [Required]"
	echo "-2 : The absolute path of the second fastq file from a paired end read, this should be named ending _2.fastq. [Required]"
	echo "-o : An output folder for the run. If not supplied then the reference genome name will be used. [Optional]"
	echo "-b : Retain the sorted and indexed BAM file of the paired end data aligned to the reference genome."
	echo "-i : If this option is specified then all sample specific intermediate files will be removed, leaving only"
	echo "     the overall results. The default is to leave sample specific intermediate files (may require large amounts"
	echo "     of disk space)"
	echo "-C : This option will include the consensus TE sequences as extra chromosomes in the reference file (useful if the "
	echo "     organism is known to have TEs that are not present in the reference strain). [Optional: default will not include"
	echo "     this]"
	echo "-R : This option will include the reference TE sequences as extra chromosomes in the reference file [Optional: default"
	echo "     will not include this]"
	echo "-m : A string containing the list of software you want the pipeline to use for analysis e.g. \"-m relocate TEMP "
	echo "     ngs_te_mapper\" will launch only those three methods [Optional: default is to run all methods]"
	echo "-p : The number of processors to use for parallel stages of the pipeline. [Optional: default = 1]"
	echo "-h : Prints this help guide."
}

# Set default value for processors in case it is not supplied
processors=1
# Default behaviour is to run all methods if no option is supplied
methods="ngs_te_mapper RelocaTE TEMP RetroSeq PoPoolationTE TE-locate"
# If an output folder is not specified then default to adding no extra folder layer
outputfolder=.

# Get the options supplied to the program
while getopts ":r:c:g:t:1:2:o:p:m:hibCR" opt;
do
	case $opt in
		r)
			inputr=$OPTARG
			;;
		c)
			inputc=$OPTARG
			;;
		g)
			inputg=$OPTARG
			;;
		t)
			inputt=$OPTARG
			;;
		1)	
			input1=$OPTARG
			;;
		2)
			input2=$OPTARG
			;;
		o)
			outputfolder=$OPTARG
			;;
		p)
			processors=$OPTARG
			;;
		m)
			methods=$OPTARG
			;;
		C)
			addconsensus=on
			;;
		R)
			addrefcopies=on
			;;
		i)
			remove_intermediates=on
			;;
		b)
			save_bam=on
			;;
		h)
			usage
			exit 1
			;;
		\?)
			echo "Unknown option: -$OPTARG"
			usage
			exit 1
			;;
		:)
			echo "Missing option argument for -$OPTARG"
			usage
			exit 1
			;;
	esac
done

# Test for presence of required arguments
if [[ -z "$inputr" || -z "$inputc" || -z "$input1" || -z "$input2" ]]
then
	echo "A required parameter is missing"
	usage
	exit 1
fi

# If a GFF file is supplied then a TE family file that links it to the fasta consensus is also needed
if [[ "$inputg" ]]
then
	if [[ -z "$inputt" ]]
	then
		echo "If a GFF file is supplied then a TE family file that links it to the fasta consensus is also needed"
		usage
		exit 1
	fi
fi

# Set up folder structure
printf "\nCreating directory structure...\n\n" | tee -a /dev/stderr

genome=${inputr##*/}
genome=${genome%%.*}
sample=${input1##*/}
sample=${sample%%_1.f*}

test_dir=`pwd`
if [[ ! -d $test_dir/$outputfolder/$genome ]]
then
	mkdir -p $test_dir/$outputfolder/
	mkdir $test_dir/$outputfolder/$genome/
	mkdir $test_dir/$outputfolder/$genome/reference
fi
mkdir $test_dir/$outputfolder/$genome/$sample
mkdir $test_dir/$outputfolder/$genome/$sample/reads
mkdir $test_dir/$outputfolder/$genome/$sample/bam
mkdir $test_dir/$outputfolder/$genome/$sample/sam
mkdir $test_dir/$outputfolder/$genome/$sample/results
mkdir $test_dir/$outputfolder/$genome/$sample/results/qualitycontrol
mkdir $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults

# Copy input files in to sample directory
# Copy the reference fasta file to the run folder
reference_genome_file=${inputr##*/}
if [[ ! -f $test_dir/$outputfolder/$genome/reference/$reference_genome_file ]]
then
	# Use script to fix the line length of reference input to 80 characters (needed for samtools index)
	perl scripts/fixfastalinelength.pl $inputr 80 $test_dir/$outputfolder/$genome/reference/$reference_genome_file
fi
reference_genome=$test_dir/$outputfolder/$genome/reference/$reference_genome_file

# Copy the TE consesnus fasta file to the run folder
consensus_te_seqs_file=${inputc##*/}
if [[ ! -f $test_dir/$outputfolder/$genome/reference/$consensus_te_seqs_file ]]
then
	# Use script to fix the line length of reference input to 80 characters (needed for samtools index)
	perl scripts/fixfastalinelength.pl $inputc 80 $test_dir/$outputfolder/$genome/reference/$consensus_te_seqs_file
fi
consensus_te_seqs=$test_dir/$outputfolder/$genome/reference/$consensus_te_seqs_file

# Create symbolic links for fastq files to save time and space
fastq1_file=${input1##*/}
cp -s $input1 $test_dir/$outputfolder/$genome/$sample/reads/$fastq1_file
fastq1=$test_dir/$outputfolder/$genome/$sample/reads/$fastq1_file
fastq2_file=${input2##*/}
cp -s $input2 $test_dir/$outputfolder/$genome/$sample/reads/$fastq2_file
fastq2=$test_dir/$outputfolder/$genome/$sample/reads/$fastq2_file

# If a GFF is supplied then run the analysis using the GFF and TE hierarchy as input
if [[ $inputg ]]
then
	# Copy the te locations file to the run folder
	te_locations_file=${inputg##*/}
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/$te_locations_file ]]
	then
		# Copy the gff input via a processing step that creates standard columns and layout for rest of pipeline
		grep -v '^#' $inputg | awk -F'[\t=;]' 'BEGIN {OFS = "\t"}; {printf $1"\t"$2"\t"; for(x=1;x<=NF;x++) if ($x~"ID") printf $(x+1); print "\t"$4,$5,$6,$7,$8,"ID="}' | awk -F'\t' '{print $0$3";Name="$3";Alias="$3}' > $test_dir/$outputfolder/$genome/reference/$te_locations_file
	fi
	te_locations=$test_dir/$outputfolder/$genome/reference/$te_locations_file

	# Copy the te family file to the run folder
	te_families_file=${inputt##*/}
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/$te_families_file ]]
	then
		cp -n $inputt $test_dir/$outputfolder/$genome/reference/$te_families_file
	fi
	te_families=$test_dir/$outputfolder/$genome/reference/$te_families_file

	# Use the GFF to create input for the rest of the pipeline
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/"popoolationte_"$genome".fasta" ]]
	then
		bedtools maskfasta -fi $reference_genome -fo $test_dir/$outputfolder/$genome/reference/"popoolationte_"$genome".fasta" -bed $te_locations
	fi
	popoolationte_reference_genome=$test_dir/$outputfolder/$genome/reference/"popoolationte_"$genome".fasta"

	# Extract sequence of all reference TE copies if this has not already been done
	# Cut first line if it begins with #
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/popool_all_te_seqs.fasta ]]
	then
		if [[ "$addrefcopies" = "on" ]]
		then
			bedtools getfasta -name -fi $reference_genome -bed $te_locations -fo $test_dir/$outputfolder/$genome/reference/ref_te_seqs.fasta
			te_seqs=$test_dir/$outputfolder/$genome/reference/ref_te_seqs.fasta
		fi
		if [[ "$addconsensus" = "on" ]]
		then
			cat $consensus_te_seqs $test_dir/$outputfolder/$genome/reference/ref_te_seqs.fasta > $test_dir/$outputfolder/$genome/reference/all_te_seqs2.fasta
			te_seqs=$test_dir/$outputfolder/$genome/reference/all_te_seqs2.fasta
		fi
		# Use script to fix the line length of reference input to 80 characters (needed for samtools index)
		perl scripts/fixfastalinelength.pl $te_seqs 80 $test_dir/$outputfolder/$genome/reference/all_te_seqs.fasta

		# PoPoolationTE always needs the full TE sequences
		bedtools getfasta -name -fi $reference_genome -bed $te_locations -fo $test_dir/$outputfolder/$genome/reference/popool_ref_te_seqs.fasta
		cat $consensus_te_seqs $test_dir/$outputfolder/$genome/reference/popool_ref_te_seqs.fasta > $test_dir/$outputfolder/$genome/reference/popool_all_te_seqs_tmp.fasta
		perl scripts/fixfastalinelength.pl $test_dir/$outputfolder/$genome/reference/popool_all_te_seqs_tmp.fasta 80 $test_dir/$outputfolder/$genome/reference/popool_all_te_seqs.fasta
		rm $test_dir/$outputfolder/$genome/reference/popool_all_te_seqs_tmp.fasta $test_dir/$outputfolder/$genome/reference/popool_ref_te_seqs.fasta $reference_genome".fai"
	fi
	all_te_seqs=$test_dir/$outputfolder/$genome/reference/all_te_seqs.fasta
	popool_te_seqs=$test_dir/$outputfolder/$genome/reference/popool_all_te_seqs.fasta

	# The pipeline functions most comprehensively (i.e. dealing with insertions with no copies in the reference genome) if
	# the sequences of TEs are added to the end of the genome and reflected in the annotation
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/full_reference.fasta ]]
	then
		if [[ "$addconsensus" = "on" ||  "$addrefcopies" = "on" ]]
		then
			cat $reference_genome $all_te_seqs > $test_dir/$outputfolder/$genome/reference/full_reference.fasta
			cp $test_dir/$outputfolder/$genome/reference/full_reference.fasta $test_dir/$outputfolder/$genome/reference/$genome".fasta"
		fi
	fi
	reference_genome=$test_dir/$outputfolder/$genome/reference/$genome".fasta"

	# PoPoolationTE always needs the full combination reference
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/"popoolationte_full_"$genome".fasta" ]]
	then
			cat $popoolationte_reference_genome $popool_te_seqs > $test_dir/$outputfolder/$genome/reference/"popoolationte_full_"$genome".fasta"
	fi
	popoolationte_reference_genome=$test_dir/$outputfolder/$genome/reference/"popoolationte_full_"$genome".fasta"

	# Add the locations of the sequences of the consensus TEs to the genome annotation
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/TE-lengths ]]
	then
		awk -F">" '/^>/ {print $2"\t"$2}' $consensus_te_seqs > $test_dir/$outputfolder/$genome/reference/tmp
		cat $te_families >> $test_dir/$outputfolder/$genome/reference/tmp
		cp $te_families $test_dir/$outputfolder/$genome/reference/"popool_"$te_families_file
		cp $te_locations $test_dir/$outputfolder/$genome/reference/"popool_"$te_locations_file
		if [[ "$addconsensus" = "on" ||  "$addrefcopies" = "on" ]]
		then
			awk -F">" '/^>/ {if (seqlen){print seqlen}; printf $2"\t" ;seqlen=0;next; } { seqlen = seqlen +length($0)}END{print seqlen}' $all_te_seqs > $test_dir/$outputfolder/$genome/reference/TE-lengths
			while read TE length
			do
				echo -e "$TE\treannotate\ttransposable_element\t1\t$length\t.\t+\t.\tID=instance$TE;Name=instance$TE;Alias=instance$TE" >> $te_locations
				awk -vTE=$TE '{ if(TE==$1) print "instance"TE"\t"$2; }' $test_dir/$outputfolder/$genome/reference/tmp >> $te_families
			done < $test_dir/$outputfolder/$genome/reference/TE-lengths
		fi
		# PoPoolationTE always needs the full family file and annotation
		awk -F">" '/^>/ {if (seqlen){print seqlen}; printf $2"\t" ;seqlen=0;next; } { seqlen = seqlen +length($0)}END{print seqlen}' $popool_te_seqs > $test_dir/$outputfolder/$genome/reference/TE-lengths
		while read TE length
		do
			echo -e "$TE\treannotate\ttransposable_element\t1\t$length\t.\t+\t.\tID=instance$TE;Name=instance$TE;Alias=instance$TE" >> $test_dir/$outputfolder/$genome/reference/"popool_"$te_locations_file
			awk -vTE=$TE '{ if(TE==$1) print "instance"TE"\t"$2; }' $test_dir/$outputfolder/$genome/reference/tmp >> $test_dir/$outputfolder/$genome/reference/"popool_"$te_families_file
		done < $test_dir/$outputfolder/$genome/reference/TE-lengths
		rm $test_dir/$outputfolder/$genome/reference/tmp
	fi
	popool_te_locations=$test_dir/$outputfolder/$genome/reference/"popool_"$te_locations_file
	popool_te_families=$test_dir/$outputfolder/$genome/reference/"popool_"$te_families_file

# The GFF input is optional, if it is not supplied then RepeatMasker is run to generate the necessary inputs
else
	if [[ ! -f $reference_genome".masked" || ! -f $reference_genome".out.gff" ]]
	then
		# Run RepeatMasker on the genome using the TE database to generate gff annotation
		RepeatMasker -pa $processors -lib $consensus_te_seqs -s -gff -nolow -no_is $reference_genome
		# RepeatMasker appears to override the custom database names during the ProcessRepeats step so this changes them back for
		# Drosophila, more rules like this may be needed for other reference genomes
		sed "s/McClintock-int/McClintock/g" $reference_genome".out.gff" > $test_dir/$outputfolder/$genome/reference/tmp
		sed "s/POGON1/pogo/g" $test_dir/$outputfolder/$genome/reference/tmp > $reference_genome".out.gff"
        perl scripts/fixfastalinelength.pl $reference_genome".masked" 80 $reference_genome".masked2"
        mv $reference_genome".masked2" $reference_genome".masked"
	fi
	popoolationte_reference_genome=$reference_genome".masked"
	te_locations=$reference_genome".out.gff"

	# Run the perl script to create a hierarchy file that corresponds to the RepeatMasker GFF file.
	# (The RepeatMasker file is edited and renamed ..._ID in the process)
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/hierarchy.tsv ]]
	then
		perl scripts/hierarchyfromrepeatmasked.pl $te_locations $consensus_te_seqs $test_dir/$outputfolder/$genome/reference/hierarchy.tsv
	fi
	te_families=$test_dir/$outputfolder/$genome/reference/hierarchy.tsv
	mv $te_locations"_ID" $te_locations
	consensus_te_seqs=$consensus_te_seqs"_ID"

	# Extract sequence of all reference TE copies if this has not already been done
	# Cut first line if it begins with #
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/reference_te_seqs.fasta ]]
	then
		grep -v '^#' $te_locations | awk -F'[\t=;]' 'BEGIN {OFS = "\t"}; {printf $1"\t"$2"\t"; for(x=1;x<=NF;x++) if ($x~"ID") printf $(x+1); print "\t"$4,$5,$6,$7,$8,"ID="}' | awk -F'\t' '{print $0$3";Name="$3";Alias="$3}' > edited.gff
		mv edited.gff $te_locations
		bedtools getfasta -name -fi $reference_genome -bed $te_locations -fo $test_dir/$outputfolder/$genome/reference/reference_te_seqs.fasta
		# Use script to fix the line length of reference input to 80 characters (needed for samtools index)
		perl scripts/fixfastalinelength.pl $test_dir/$outputfolder/$genome/reference/reference_te_seqs.fasta 80 $test_dir/$outputfolder/$genome/reference/reference_te_seqs2.fasta
		mv $test_dir/$outputfolder/$genome/reference/reference_te_seqs2.fasta $test_dir/$outputfolder/$genome/reference/reference_te_seqs.fasta
		rm $reference_genome".fai"
	fi
	reference_te_seqs=$test_dir/$outputfolder/$genome/reference/reference_te_seqs.fasta

	if [[ ! -f $test_dir/$outputfolder/$genome/reference/popool_te_seqs.fasta ]]
	then
		if [[ "$addconsensus" = "on" ]]
		then
			cat $consensus_te_seqs > $test_dir/$outputfolder/$genome/reference/all_te_seqs.fasta
		fi
		if [[ "$addrefcopies" = "on" ]]
		then
			cat $reference_te_seqs >> $test_dir/$outputfolder/$genome/reference/all_te_seqs.fasta
		fi
		cat $consensus_te_seqs $reference_te_seqs > $test_dir/$outputfolder/$genome/reference/popool_te_seqs.fasta
	fi
	all_te_seqs=$test_dir/$outputfolder/$genome/reference/all_te_seqs.fasta
	popool_te_seqs=$test_dir/$outputfolder/$genome/reference/popool_te_seqs.fasta

	# Add the locations of the sequences of the consensus TEs to the genome annotation
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/TE-lengths ]]
	then
        awk -F">" '/^>/ {print $2"\t"$2}' $consensus_te_seqs > $test_dir/$outputfolder/$genome/reference/tmp
        cat $te_families >> $test_dir/$outputfolder/$genome/reference/tmp
        cp $te_families $test_dir/$outputfolder/$genome/reference/"popool_hierarchy.tsv"
        cp $te_locations $test_dir/$outputfolder/$genome/reference/"popool_te_locations.gff"
        if [[ "$addconsensus" = "on" ||  "$addrefcopies" = "on" ]]
        then
            awk -F">" '/^>/ {if (seqlen){print seqlen}; printf $2"\t" ;seqlen=0;next; } { seqlen = seqlen +length($0)}END{print seqlen}' $all_te_seqs > $test_dir/$outputfolder/$genome/reference/TE-lengths
            while read TE length
            do
                echo -e "$TE\treannotate\ttransposable_element\t1\t$length\t.\t+\t.\tID=instance$TE;Name=instance$TE;Alias=instance$TE" >> $te_locations
                awk -vTE=$TE '{ if(TE==$1) print "instance"TE"\t"$2; }' $test_dir/$outputfolder/$genome/reference/tmp >> $te_families
            done < $test_dir/$outputfolder/$genome/reference/TE-lengths
        fi
		# PoPoolationTE always needs the full family file and annotation
		awk -F">" '/^>/ {if (seqlen){print seqlen}; printf $2"\t" ;seqlen=0;next; } { seqlen = seqlen +length($0)}END{print seqlen}' $popool_te_seqs > $test_dir/$outputfolder/$genome/reference/TE-lengths
		while read TE length
		do
			echo -e "$TE\treannotate\ttransposable_element\t1\t$length\t.\t+\t.\tID=instance$TE;Name=instance$TE;Alias=instance$TE" >> $test_dir/$outputfolder/$genome/reference/"popool_te_locations.gff"
			awk -vTE=$TE '{ if(TE==$1) print "instance"TE"\t"$2; }' $test_dir/$outputfolder/$genome/reference/tmp >> $test_dir/$outputfolder/$genome/reference/"popool_hierarchy.tsv"
		done < $test_dir/$outputfolder/$genome/reference/TE-lengths
		rm $test_dir/$outputfolder/$genome/reference/tmp
	fi
	popool_te_locations=$test_dir/$outputfolder/$genome/reference/"popool_te_locations.gff"
	popool_te_families=$test_dir/$outputfolder/$genome/reference/"popool_hierarchy.tsv"

	# The pipeline functions most comprehensively (i.e. dealing with insertions with no copies in the reference genome) if
	# the sequences of TEs are added to the end of the genome and reflected in the annotation
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/full_reference.fasta ]]
	then
        if [[ "$addconsensus" = "on" ||  "$addrefcopies" = "on" ]]
        then
            cat $reference_genome $all_te_seqs > $test_dir/$outputfolder/$genome/reference/full_reference.fasta
            cp $test_dir/$outputfolder/$genome/reference/full_reference.fasta $test_dir/$outputfolder/$genome/reference/$genome".fasta"
        fi
	fi
	reference_genome=$test_dir/$outputfolder/$genome/reference/$genome".fasta"

	# PoPoolationTE always needs the full combination reference
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/"popoolationte_full_"$genome".fasta" ]]
	then
            cat $popoolationte_reference_genome $popool_te_seqs > $test_dir/$outputfolder/$genome/reference/"popoolationte_full_"$genome".fasta"
	fi
	popoolationte_reference_genome=$test_dir/$outputfolder/$genome/reference/"popoolationte_full_"$genome".fasta"
fi

# If FastQC is installed then launch FastQC on the input fastqs
location=`which fastqc`
if [[ -z "$location" ]]
then
	printf "\nFastQC not installed, skipping input quality analysis...\n\n" | tee -a /dev/stderr
else
	printf "\nPerforming FastQC analysis...\n\n" | tee -a /dev/stderr
	mkdir $test_dir/$outputfolder/$genome/$sample/results/qualitycontrol/fastqc_analysis
	fastqc -t $processors $fastq1 $fastq2 -o $test_dir/$outputfolder/$genome/$sample/results/qualitycontrol/fastqc_analysis
fi

# Create indexes of reference genome if not already made for this genome
if [[ ! -f $reference_genome".fai" ]]
then
	samtools faidx $reference_genome
	samtools faidx $popoolationte_reference_genome
fi
if [[ ! -f $reference_genome".bwt" ]]
then
	bwa index $reference_genome
	bwa index $popoolationte_reference_genome
fi

# Create bed file of reference TE locations
if [[ ! -f $test_dir/$outputfolder/$genome"/reference/reference_TE_locations.bed" ]]
then
	awk -F["\t"\;=] '{print $1"\t"$4-1"\t"$5"\t"$10"\t.\t"$7}' $te_locations > $test_dir/$outputfolder/$genome/reference/reference_TE_locations.bed
fi
bed_te_locations_file=$test_dir/$outputfolder/$genome/reference/reference_TE_locations.bed

# Allow case insensitivity for method names
shopt -s nocasematch
if [[ $methods == *TE-locate* || $methods == *TElocate* || $methods == *RetroSeq* || $methods == *TEMP* ]]
then
	# Create sam files for input
	printf "\nCreating sam alignment...\n\n" | tee -a /dev/stderr

	bwa mem -t $processors -v 0 $reference_genome $fastq1 $fastq2 > $test_dir/$outputfolder/$genome/$sample/sam/$sample.sam

	sam=$test_dir/$outputfolder/$genome/$sample/sam/$sample.sam

	# Calculate the median insert size of the sample
	printf "\nCalculating median insert size...\n\n" | tee -a /dev/stderr
	median_insertsize=`cut -f9 $sam | sort -n | awk '{if ($1 > 0) ins[reads++]=$1; } END { print ins[int(reads/2)]; }'`
	printf "\nMedian insert size = $median_insertsize\n\n" | tee -a /dev/stderr
	echo $median_insertsize > $test_dir/$outputfolder/$genome/$sample/results/qualitycontrol/median_insertsize

	if [[ $methods == *RetroSeq* || $methods == *TEMP* ]]
	then
		# Create bam files for input
		printf "\nCreating bam alignment files...\n\n" | tee -a /dev/stderr
		samtools view -Sb -t $reference_genome".fai" $sam | samtools sort - $test_dir/$outputfolder/$genome/$sample/bam/$sample
		bam=$test_dir/$outputfolder/$genome/$sample/bam/$sample.bam
		samtools index $bam

		# Get stats of bam file from samtools
		samtools flagstat $bam > $test_dir/$outputfolder/$genome/$sample/results/qualitycontrol/bwamem_bamstats.txt
	fi
	shopt -u nocasematch
	# Sort the sam file lexically for TE-locate
	printf "\nSorting sam alignment...\n\n" | tee -a /dev/stderr
	sort --temporary-directory=$test_dir/$outputfolder/$genome/$sample/sam/ $test_dir/$outputfolder/$genome/$sample/sam/$sample.sam > $test_dir/$outputfolder/$genome/$sample/sam/sorted$sample.sam
	rm $test_dir/$outputfolder/$genome/$sample/sam/$sample.sam
	mv $test_dir/$outputfolder/$genome/$sample/sam/sorted$sample.sam $test_dir/$outputfolder/$genome/$sample/sam/$sample.sam
	sam=$test_dir/$outputfolder/$genome/$sample/sam/$sample.sam
	sam_folder=$test_dir/$outputfolder/$genome/$sample/sam
fi

shopt -s nocasematch
if [[ $methods == *TE-locate* || $methods == *TElocate* ]]
then
	shopt -u nocasematch
	################################## Run TE-locate ##################################

	printf "\nRunning TE-locate pipeline...\n\n" | tee -a /dev/stderr

	# Adjust hierachy levels
	cd TE-locate
	telocate_te_locations=${te_locations%.*}
	telocate_te_locations=$telocate_te_locations"_HL.gff"
	if [[ ! -f $telocate_te_locations ]]
	then
		perl TE_hierarchy.pl $te_locations $te_families Alias
	fi

	bash runtelocate.sh $sam_folder $reference_genome $telocate_te_locations 2 $sample $median_insertsize $outputfolder

	# Save the original result file and the bed files filtered by mcclintock
	mv $outputfolder/$sample/$sample"_telocate"* $test_dir/$outputfolder/$genome/$sample/results/
	mkdir $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults/TE-locate
	cp $outputfolder/$sample/*.info $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults/TE-locate

	# If cleanup intermediate files is specified then delete all intermediate files specific to the sample
	# i.e. leave any reusable species data behind.
	if [[ "$remove_intermediates" = "on" ]]
	then
		printf "\nRemoving TE-locate intermediate files\n\n"
		rm -r $sam_folder
		rm -r $outputfolder/$sample
	fi
	cd ..
fi

shopt -s nocasematch
if [[ $methods == *RetroSeq* ]]
then
	shopt -u nocasematch
	################################## Run RetroSeq ##################################

	printf "\nRunning RetroSeq pipeline...\n\n" | tee -a /dev/stderr

	cd RetroSeq
	bash runretroseq.sh $consensus_te_seqs $bam $reference_genome $bed_te_locations_file $te_families $outputfolder

	# Save the original result file and the bed files filtered by mcclintock
	mv $outputfolder/$sample/$sample"_retroseq"* $test_dir/$outputfolder/$genome/$sample/results/
	mkdir $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults/RetroSeq
	cp $outputfolder/$sample/$sample".calling.PE.vcf" $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults/RetroSeq

	# If cleanup intermediate files is specified then delete all intermediate files specific to the sample
	# i.e. leave any reusable species data behind.
	if [[ "$remove_intermediates" = "on" ]]
	then
		printf "\nRemoving RetroSeq intermediate files\n\n"
		# If the save bam option is specified then override the command to delete the bam files.
		if [[ "$save_bam" != "on" ]]
		then
			rm -r $test_dir/$outputfolder/$genome/$sample/bam
		fi
		rm -r $outputfolder/$sample
	fi
	cd ..
fi

shopt -s nocasematch
if [[ $methods == *TEMP* ]]
then
	shopt -u nocasematch
	################################## Run TEMP ##################################

	printf "\nRunning TEMP pipeline...\n\n" | tee -a /dev/stderr

	cd TEMP

	bash runtemp.sh $bam $sam $consensus_te_seqs $bed_te_locations_file $te_families $median_insertsize $sample $processors $outputfolder

	# Save the original result file and the bed files filtered by mcclintock
	mv $outputfolder/$sample/$sample"_temp"* $test_dir/$outputfolder/$genome/$sample/results/
	mkdir $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults/TEMP
	cp $outputfolder/$sample/$sample".insertion.refined.bp.summary" $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults/TEMP

	# If cleanup intermediate files is specified then delete all intermediate files specific to the sample
	# i.e. leave any reusable species data behind.
	if [[ "$remove_intermediates" = "on" ]]
	then
		printf "\nRemoving TEMP intermediate files\n\n"
		rm -r $outputfolder/$sample
	fi
	cd ..
fi

shopt -s nocasematch
if [[ $methods == *RelocaTE* ]]
then
	shopt -u nocasematch
	################################## Run RelocaTE ##################################

	printf "\nRunning RelocaTE pipeline...\n\n" | tee -a /dev/stderr

	# Add TSD lengths to consensus TE sequences
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/relocate_te_seqs.fasta ]]
	then
		awk '{if (/>/) print $0" TSD=UNK"; else print $0}' $consensus_te_seqs > $test_dir/$outputfolder/$genome/reference/relocate_te_seqs.fasta
	fi
	relocate_te_seqs=$test_dir/$outputfolder/$genome/reference/relocate_te_seqs.fasta

	# Create general gff file to allow reference TE detection in RelocaTE
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/relocate_te_locations.gff ]]
	then
		awk 'FNR==NR{array[$1]=$2;next}{print $1,$2,array[$3],$4,$5,$6,$7,$8,$9}' FS='\t' OFS='\t' $te_families $te_locations > $test_dir/$outputfolder/$genome/reference/relocate_te_locations.gff
	fi
	relocate_te_locations=$test_dir/$outputfolder/$genome/reference/relocate_te_locations.gff

	cd RelocaTE
	bash runrelocate.sh $relocate_te_seqs $reference_genome $test_dir/$outputfolder/$genome/$sample/reads $sample $relocate_te_locations $outputfolder

	# Save the original result file and the bed files filtered by mcclintock
	mv $outputfolder/$sample/$sample"_relocate"* $test_dir/$outputfolder/$genome/$sample/results/
	mkdir $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults/RelocaTE
	cp -r $outputfolder/$sample/*/results $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults/RelocaTE

	# If cleanup intermediate files is specified then delete all intermediate files specific to the sample
	# i.e. leave any reusable species data behind.
	if [[ "$remove_intermediates" = "on" ]]
	then
		printf "\nRemoving RelocaTE intermediate files\n\n"
		rm -r $outputfolder/$sample
	fi
	cd ..
fi

shopt -s nocasematch
if [[ $methods == *ngs_te_mapper* || $methods == *ngstemapper* ]]
then
	shopt -u nocasematch
	################################## Run ngs_te_mapper ##################################

	printf "\nRunning ngs_te_mapper pipeline...\n\n" | tee -a /dev/stderr

	cd ngs_te_mapper

	bash runngstemapper.sh $consensus_te_seqs $reference_genome $sample $fastq1 $fastq2 $outputfolder

	# Save the original result file and the bed file filtered by mcclintock
	mv $outputfolder/$sample/$sample"_ngs_te_mapper_nonredundant.bed" $test_dir/$outputfolder/$genome/$sample/results/
	mkdir $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults/ngs_te_mapper
	cp $outputfolder/$sample/bed_tsd/*.bed $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults/ngs_te_mapper

	# If cleanup intermediate files is specified then delete all intermediate files specific to the sample
	# i.e. leave any reusable species data behind.
	if [[ "$remove_intermediates" = "on" ]]
	then
		printf "\nRemoving ngs_te_mapper intermediate files\n\n"
		rm -r $outputfolder/$sample
	fi
	cd ..
fi

shopt -s nocasematch
if [[ $methods == *popoolationte* ]]
then
	shopt -u nocasematch
	################################## Run PoPoolationTE ##################################

	printf "\nRunning PoPoolationTE pipeline...\n\n" | tee -a /dev/stderr

	# Create te_hierachy
	if [[ ! -f $test_dir/$outputfolder/$genome/reference/te_hierarchy ]]
	then
		printf "insert\tid\tfamily\tsuperfamily\tsuborder\torder\tclass\tproblem\n" > $test_dir/$outputfolder/$genome/reference/te_hierarchy
		awk '{printf $0"\t"$2"\t"$2"\tna\tna\tna\t0\n"}' $popool_te_families >> $test_dir/$outputfolder/$genome/reference/te_hierarchy
	fi
	te_hierarchy=$test_dir/$outputfolder/$genome/reference/te_hierarchy

	cd PoPoolationTE
	bash runpopoolationte.sh $popoolationte_reference_genome $te_hierarchy $fastq1 $fastq2 $popool_te_locations $processors $outputfolder

	# Save the original result file and the bed files filtered by mcclintock
	mv $outputfolder/$sample/$sample"_popoolationte"* $test_dir/$outputfolder/$genome/$sample/results/
	mkdir $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults/PoPoolationTE
	cp $outputfolder/$sample/te-poly-filtered.txt $test_dir/$outputfolder/$genome/$sample/results/originalmethodresults/PoPoolationTE

	# If cleanup intermediate files is specified then delete all intermediate files specific to the sample
	# i.e. leave any reusable species data behind.
	if [[ "$remove_intermediates" = "on" ]]
	then
		printf "\nRemoving PoPoolationTE intermediate files\n\n"
		rm -r $outputfolder/$sample
	fi
	cd ..
fi

#########################################################################################

# If cleanup intermediate files is specified then delete all intermediate files specific to the sample
# i.e. leave any reusable species data behind.
if [[ "$remove_intermediates" = "on" ]]
then
	printf "\nRemoving McClintock intermediate files\n\n"
	rm -r $test_dir/$outputfolder/$genome/$sample/reads
fi

printf "\nPipeline Complete\n\n" | tee -a /dev/stderr
