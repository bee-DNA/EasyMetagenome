FROM mambaorg/micromamba:1.5.8

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends bash coreutils findutils grep sed gawk \
    && rm -rf /var/lib/apt/lists/*

USER $MAMBA_USER
ENV MAMBA_DOCKERFILE_ACTIVATE=1
ENV PATH=/opt/conda/bin:$PATH

RUN micromamba install -y -n base -c conda-forge -c bioconda \
    python=3.8 \
    checkm2 \
    && micromamba clean --all --yes

WORKDIR /workspace/app
