# ===================================================================
# CARREGADOR DE DADOS
# -------------------------------------------------------------------
# A única função deste script é ler os dados brutos da planilha
# e retorná-los em uma lista para serem usados por outros scripts.
# ===================================================================

# Importa a biblioteca necessária para ler arquivos Excel
library(readxl)

# Carrega as configurações (caminho do arquivo e nomes das planilhas)
# O RStudio pode mostrar um aviso aqui, mas é o comportamento esperado.
source("R/1_config.R")

load_data <- function() {
  #   Esta função carrega as bases de dados discente e docente do
  #   arquivo Excel especificado no config.
  #
  #   Return:
  #     list: Uma lista contendo os dataframes 'discente' e 'docente'.
  
  baseDiscente <- read_excel(dataSource, sheet = sheetDiscente) 
  baseDocente <- read_excel(dataSource, sheet = sheetDocente)
  
  # Retorna os dois dataframes dentro de uma única lista nomeada
  return(list(discente = baseDiscente, docente = baseDocente))
}