#!/usr/bin/bash 

if (( $# > 0 ))
then
	reference=${2##*/}
	reference=${reference%%.*}
	# Run the relocaTE pipeline
	if [ ! -f $reference"annotation" ]; then
		awk -F'[\t]' '{print $3"\t"$1":"$4".."$5}' $5 > $reference"annotation"
	fi
	perl scripts/relocaTE.pl -t $1 -d $3 -g $2 -1 _1 -2 _2 -o $4 -r $reference"annotation"
	
	# Extract the relevant information from the output files for each TE and collate them.
	# Name and description for use with the UCSC genome browser are added to output here.
	for file in $4/*/results/*.gff 
	do
		awk -F'[\t=;]' -v sample=$4 '$14~/Shared/{print $1"\t"$4"\t"$5"\t"$12"_old_"sample"_relocate_sr\t0\t."}' $file >> $4/$4_relocate_presort.bed
		awk -F'[\t=;.]' -v sample=$4 '$18~/Non-reference/{print $1"\t"$5"\t"$6"\t"$13"_new_"sample"_relocate_sr\t0\t"$9}' $file >> $4/$4_relocate_presort.bed
	done

    echo -e "track name=\"$4"_RelocaTE"\" description=\"$4"_RelocaTE"\"" > $4/$4_relocate.bed
    sort -k1,3 -k4rn $f/$f"_relocate_presort.bed" | sort -u -k1,3 | cut -f1-3,5- > $4/tmp
    bedtools sort -i $4/tmp >> $4/$4_relocate.bed

	echo -e "track name=\"$4"_RelocaTE"\" description=\"$4"_RelocaTE"\"" > $4/$4_relocate_duplicated.bed
	bedtools sort -i $4/$4_relocate_presort.bed >> $4/$4_relocate_duplicated.bed
	rm $4/$4_relocate_presort.bed $4/tmp
	
else
	echo "Supply TE sequence with TSD information in description (format 'TSD=....') as option 1"
	echo "Supply fasta reference file as option 2"
	echo "Supply a directory containing fastq files as option 3"
	echo "Supply an output directory name as option 4"
	echo "Supply reference insertion locations in gff format as option 5"
fi
