FROM rocker/r-ver:4.4.1

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libsodium-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

ENV CRAN=https://cloud.r-project.org

RUN R -e "options(repos=c(CRAN='${CRAN}')); install.packages(c( \
  'plumber','jsonlite','dplyr','tidyr','tidyselect','readr','stringr', \
  'readxl','openxlsx','reshape2','ggplot2' \
), Ncpus=4); stopifnot(requireNamespace('plumber', quietly=TRUE))"

WORKDIR /app
COPY . /app

# Hugging Face Docker Spaces (padrão)
ENV PORT=8000
EXPOSE 8000

CMD ["Rscript", "run.R"]
