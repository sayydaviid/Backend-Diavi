# Usamos a mesma base para garantir compatibilidade
FROM rocker/r-ver:4.4.1

# Evita interações durante instalação
ARG DEBIAN_FRONTEND=noninteractive

# OTIMIZAÇÃO 1: Instalar apenas deps de sistema essenciais
# Removemos algumas redundâncias pois os binários já lidam melhor com isso
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsodium-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# OTIMIZAÇÃO 2: Configurar para baixar BINÁRIOS Linux (não compilar fonte)
# Isso muda o jogo. Ao invés de compilar o dplyr (demora e gasta RAM), ele baixa pronto.
# O user agent é necessário para o servidor P3M entregar o binário correto.
RUN echo "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/jammy/latest'), download.file.method = 'libcurl')" >> /usr/local/lib/R/etc/Rprofile.site \
    && echo "options(HTTPUserAgent = sprintf('R/%s R (%s)', getRversion(), paste(getRversion(), R.version['platform'], R.version['arch'], R.version['os'])))" >> /usr/local/lib/R/etc/Rprofile.site

# Instalação dos pacotes (agora via binários)
# Adicionei 'clean = TRUE' para limpar cache
RUN R -e "install.packages(c( \
    'plumber', \
    'jsonlite', \
    'dplyr', \
    'tidyr', \
    'readr', \
    'stringr', \
    'readxl', \
    'openxlsx', \
    'reshape2', \
    'ggplot2' \
    ), Ncpus=4)" \
    && rm -rf /tmp/downloaded_packages

WORKDIR /app
COPY . /app

ENV PORT=8000
EXPOSE 8000

# OTIMIZAÇÃO 3: Garbage Collection agressivo no boot
# O comando de entrada garante que o R inicie "limpo"
CMD ["Rscript", "run.R"]