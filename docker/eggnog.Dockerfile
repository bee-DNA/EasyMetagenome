FROM mambaorg/micromamba:1.5.8

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends bash coreutils findutils grep sed gawk \
    && rm -rf /var/lib/apt/lists/*

USER $MAMBA_USER
ENV MAMBA_DOCKERFILE_ACTIVATE=1
ENV PATH=/opt/conda/bin:$PATH

RUN micromamba install -y -n base -c conda-forge -c bioconda \
    python=3.10 \
    eggnog-mapper=2.1.13=pyhdfd78af_2 \
    diamond \
    && EXPECTED_DIAMOND_PATH="$(python -c "import os,eggnogmapper; print(os.path.join(os.path.dirname(eggnogmapper.__file__), 'bin', 'diamond'))")" \
    && mkdir -p "$(dirname "$EXPECTED_DIAMOND_PATH")" \
    && ln -sf "$(command -v diamond)" "$EXPECTED_DIAMOND_PATH" \
    && micromamba clean --all --yes

WORKDIR /workspace/app
