FROM mambaorg/micromamba:1.5.8

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        coreutils \
        findutils \
        grep \
        sed \
        gawk \
        wget \
        curl \
        ca-certificates \
        tar \
        gzip \
    && rm -rf /var/lib/apt/lists/*

USER $MAMBA_USER
ENV MAMBA_DOCKERFILE_ACTIVATE=1
ENV PATH=/opt/conda/bin:$PATH

RUN micromamba install -y -n base -c conda-forge conda

RUN micromamba create -y -n easymetagenome -c conda-forge -c bioconda \
        python=3.10 \
        fastp \
        megahit \
        prodigal \
        bowtie2 \
        samtools \
        metabat2 \
        metaphlan \
        lefse \
        pandas \
        numpy \
        scipy \
        matplotlib \
        scikit-learn \
        pip \
    && micromamba run -n easymetagenome pip install --no-cache-dir matplotlib-venn

RUN micromamba create -y -n humann4 -c conda-forge -c bioconda \
        python=3.12 \
        humann \
        metaphlan \
        pandas \
        numpy \
        scipy \
        matplotlib \
        scikit-learn

RUN micromamba create -y -n checkm2_env -c conda-forge -c bioconda \
        python=3.8 \
        checkm2

RUN micromamba create -y -n eggnog_env -c conda-forge -c bioconda \
        python=3.10 \
        eggnog-mapper=2.1.13=pyhdfd78af_2 \
        diamond

RUN micromamba clean --all --yes

WORKDIR /workspace/app
