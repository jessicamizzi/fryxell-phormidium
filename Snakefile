# add quast rule (and add to rule all?)

rule all:
    input:
        'output/04_anvio/mat/anvio_contigs.db',
        'output/04_anvio/lab/anvio_contigs.db',
        'output/04_anvio/coassembly/anvio_contigs.db'

rule fastqc_reads:
    input:
        'input/{sample}/{filename}_R{direction}_{lane}.fastq',
    output:
        'output/00_fastqc_reads/{sample}/{filename}_R{direction}_{lane}_fastqc.html',
        'output/00_fastqc_reads/{sample}/{filename}_R{direction}_{lane}_fastqc.zip',
    shell: '''
        module load fastqc/0.11.5
        fastqc -o `dirname {output[0]}` {input} '''

rule download_adapters:
    output:
        adapters='input/TruSeq3-PE-2.fa'
    shell: '''
        wget https://anonscm.debian.org/cgit/debian-med/trimmomatic.git/plain/adapters/TruSeq3-PE-2.fa
        mv TruSeq3-PE-2.fa input/ '''

rule trimmomatic_lab_sample:
    input:
        forward='input/lab_sample/lab_sample_39872_GTGAAA_L002_R1_00{lane}.fastq',
        reverse='input/lab_sample/lab_sample_39872_GTGAAA_L002_R2_00{lane}.fastq',
        adapters='input/TruSeq3-PE-2.fa'
    output:
        forward_paired='output/01_trimmomatic_lab/lab_sample_39872_GTGAAA_L002_R1_00{lane}_paired_trim.fastq',
        forward_unpaired='output/01_trimmomatic_lab/lab_sample_39872_GTGAAA_L002_R1_00{lane}_unpaired_trim.fastq',
        reverse_paired='output/01_trimmomatic_lab/lab_sample_39872_GTGAAA_L002_R2_00{lane}_paired_trim.fastq',
        reverse_unpaired='output/01_trimmomatic_lab/lab_sample_39872_GTGAAA_L002_R2_00{lane}_unpaired_trim.fastq'
    message:
        'Trimming Illumina adapters from {input.forward} and {input.reverse}'
    conda:
        'envs/trimmomatic.yaml'
    shell: '''
        trimmomatic PE {input.forward} {input.reverse} {output.forward_paired} \
        {output.forward_unpaired} {output.reverse_paired} {output.reverse_unpaired} \
        ILLUMINACLIP:{input.adapters}:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:25 '''

rule interleave_lab_sample:
    input:
        forward_paired='output/01_trimmomatic_lab/lab_sample_39872_GTGAAA_L002_R1_00{lane}_paired_trim.fastq',
        reverse_paired='output/01_trimmomatic_lab/lab_sample_39872_GTGAAA_L002_R2_00{lane}_paired_trim.fastq'
    output:
        interleave_out='output/02_interleave_lab/lab_sample_39872_GTGAAA_L002_00{lane}_paired_trim_interleaved.fastq'
    message:
        'Interleaving {input.forward_paired} and {input.reverse_paired}'
    conda:
        'envs/interleave.yaml'
    shell: '''
        interleave-reads.py {input.forward_paired} {input.reverse_paired} -o {output.interleave_out} '''

rule megahit_lab:
    input: 
        expand('output/02_interleave_lab/lab_sample_39872_GTGAAA_L002_00{lane}_paired_trim_interleaved.fastq',
                lane=range(1,7))
    output:
        'output/03_megahit_lab/final.contigs.fa'
    conda:
        'envs/megahit.yaml'
    params:
        input_list=lambda w, input: ','.join(input)
    shell: '''
        rm -rf output/03_megahit_lab
        megahit --12 {params.input_list} -o output/03_megahit_lab '''

rule megahit_mat:
    input:
        'input/mat_sample/mat_sample_104_ABC_L00_R12_0.fastq'
    output:
        'output/03_megahit_mat/final.contigs.fa'
    conda:
        'envs/megahit.yaml'
    shell: '''
        rm -fr output/03_megahit_mat
        megahit --12 {input} -o output/03_megahit_mat '''

rule megahit_coassembly:
    input:
        expand('output/02_interleave_lab/lab_sample_39872_GTGAAA_L002_00{lane}_paired_trim_interleaved.fastq',
                lane=range(1,7)),
        'input/mat_sample/mat_sample_104_ABC_L00_R12_0.fastq'
    output:
        'output/03_megahit_coassembly/final.contigs.fa'
    conda:
        'envs/megahit.yaml'
    params:
        input_list=lambda w, input: ','.join(input)
    shell: '''
        rm -fr output/03_megahit_coassembly
        megahit --12 {params.input_list} -o output/03_megahit_coassembly '''

rule anvio_reform_fasta:
    input:
        'output/03_megahit_{sample}/final.contigs.fa'
    output:
        fixed_contigs='output/04_anvio/{sample}/contigs_fixed.fa',
        report='output/04_anvio/{sample}/name_conversions.txt'
    conda:
        'envs/anvio.yaml'
    shell: '''
        anvi-script-reformat-fasta {input} -o {output.fixed_contigs} --min-len 2000 --simplify-names --report {output.report} '''

rule anvio_bowtie_build:
    input:
        'output/04_anvio/{sample}/contigs_fixed.fa'
    output:
        dynamic('output/04_anvio/{sample}/contigs_fixed/anvio-contigs.db.{version}')
    conda:
        'envs/anvio.yaml'
    shell:
        '''
            bowtie2-build {input} {output} '''

rule bowtie2_samtools_map_mat:
    input:
        raw_reads='input/mat_sample/mat_sample_104_ABC_L00_R12_0.fastq'
    output:
        sam='output/04_anvio/mat/mat.sam',
        bam='output/04_anvio/mat/mat.bam'
    conda:
        'envs/anvio.yaml'
    shell: '''
        bowtie2 --threads 8 -x output/04_anvio/mat/contigs_fixed/anvio-contigs.db.1 -U {input.raw_reads} -S {output.sam}
        samtools view -U 4 -bS {output.sam} > {output.bam} '''

rule bowtie2_samtools_map_lab:
    input:
        forward=expand('input/lab_sample/lab_sample_39872_GTGAAA_L002_R1_00{lane}.fastq',
                        lane=range(1,7)),
        reverse=expand('input/lab_sample/lab_sample_39872_GTGAAA_L002_R2_00{lane}.fastq',
                        lane=range(1,7))
    output:
        sam='output/04_anvio/lab/lab.sam',
        bam='output/04_anvio/lab/lab.bam'
    conda:
        'envs/anvio.yaml'
    params:
        input_list=lambda w, input: ','.join(input)
    shell: ''' 
        bowtie2 --threads 8 -x output/04_anvio/lab/contigs_fixed/anvio-contigs.db.1 -U {params.input_list} -S {output.sam}
        samtools view -U 4 -bS {output.sam} > {output.bam} '''

rule bowtie2_samtools_map_coassembly:
    input:
        forward=expand('input/lab_sample/lab_sample_39872_GTGAAA_L002_R1_00{lane}.fastq',
                        lane=range(1,7)),
        reverse=expand('input/lab_sample/lab_sample_39872_GTGAAA_L002_R2_00{lane}.fastq',
                        lane=range(1,7)),
        mat='input/mat_sample/mat_sample_104_ABC_L00_R12_0.fastq'
    output:
        sam='output/04_anvio/coassembly/coassembly.sam',
        bam='output/04_anvio/coassembly/coassembly.bam'
    conda:
        'envs/anvio.yaml'
    params:
        input_list=lambda w, input: ','.join(input)
    shell: '''
        bowtie2 --threads 8 -x output/04_anvio/coassembly/contigs_fixed/anvio-contigs.db.1 -U {params.input_list} -S {output.sam}
        samtools view -U 4 -bS {output.sam} > {output.bam} '''

rule convert_bam_anvio:
    input:
        'output/04_anvio/{sample}/{sample}.bam'
    output:
        'output/04_anvio/{sample}/{sample}.bam-sorted.bam.bai'
    conda:
        'envs/anvio.yaml'
    shell: '''
        anvi-init-bam {input} '''

rule anvi_gen_contigs_database:
    input:
        'output/04_anvio/{sample}/contigs_fixed.fa'
    output:
        'output/04_anvio/{sample}/anvio_contigs.db'
    conda:
        'envs/anvio.yaml'
    shell: '''
        anvi-gen-contigs-database -f {input} -o {output} '''
