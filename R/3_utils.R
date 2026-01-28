# ===================================================================
# FUNÇÕES UTILITÁRIAS
# -------------------------------------------------------------------
# Este script contém as funções "ajudantes" para cálculos,
# transformações e filtragem de dados. Elas serão usadas
# pelos scripts de geração de gráficos.
# ===================================================================

library(dplyr)
library(tidyr)
library(reshape2)

# Carrega as configurações para ter acesso a variáveis como 'conceitos'
source("R/1_config.R")


calculoPercent <- function(alternativas, vetorContagem){
  #   Calcula o percentual total de cada alternativa de resposta
  #   (1 a 4) somando todas as ocorrências em várias colunas.
  #
  #   Parametros:
  #     alternativas (vector): Vetor com as possíveis respostas (ex: c(1,2,3,4)).
  #     vetorContagem (list): Lista de tabelas de contagem (resultado do `lapply(df, table)`).
  #   Return:
  #     vector: Um vetor com os percentuais de cada alternativa.
  
  somaContagem <- sapply(alternativas, function(valor) {
    sum(sapply(vetorContagem, function(tabela){
      if (as.character(valor) %in% names(tabela)){
        return(tabela[as.character(valor)])
      }
      else {
        return(0)
      }
    }), na.rm = TRUE)
  })
  
  # Adiciona verificação para evitar divisão por zero se não houver dados
  if (sum(somaContagem) == 0) return(rep(0, length(somaContagem)))
  
  percentuais <- (somaContagem / sum(somaContagem)) * 100
  return(percentuais)
}


percentPorItem <- function(contagem, alternativas) {
  #   Calcula o percentual de cada alternativa para cada item (coluna)
  #   individualmente e formata o resultado em um dataframe longo.
  #
  #   Parametros:
  #     contagem (list): Lista de tabelas de contagem.
  #     alternativas (vector): Vetor com as possíveis respostas.
  #   Return:
  #     dataframe: Dataframe longo com colunas 'questoes', 'valores' e 'conceito'.
  
  percentQuestoes <- lapply(contagem, function(tabela) {
    # Evita divisão por zero se um item específico não tiver respostas
    if (sum(tabela, na.rm = TRUE) == 0) return(setNames(rep(0, length(alternativas)), alternativas))
    
    percentuais <- (tabela / sum(tabela, na.rm = TRUE)) * 100
    
    sapply(alternativas, function(alt) {
      if (as.character(alt) %in% names(percentuais)) {
        return(percentuais[as.character(alt)])
      } else {
        return(0)
      }
    })
  })
  
  df <- data.frame(percentQuestoes)
  dfLong <- reshape2::melt(df, varnames = "questoes", value.name = "valores")
  dfLong$conceito <- rep(conceitos, times = ncol(df))
  
  return (dfLong)
}


valoresUnicos <- function(df, intervalo){
  #   Seleciona valores únicos de um intervalo de colunas com base no ID do respondente.
  #   Útil para os boxplots, para não contar a mesma média de turma várias vezes.
  #
  #   Parametros:
  #     df (dataframe): O dataframe a ser processado.
  #     intervalo (tidy-select): Um seletor de colunas do dplyr (ex: mediap111:mediap117).
  #   Return:
  #     dataframe: Dataframe com linhas únicas para o ID e as colunas selecionadas.
  
  df <- df %>%
    select(ID, {{intervalo}})
  
  dfUnico <- df %>%
    distinct(ID, across(everything()), .keep_all = TRUE)
  
  return(dfUnico)
}


filter_data <- function(base_discente, base_docente, campus_input, curso_input) {
  #   Filtra as bases de dados discente e docente com base nos inputs
  #   de campus e curso.
  #
  #   Parametros:
  #     base_discente (dataframe): Dataframe completo dos discentes.
  #     base_docente (dataframe): Dataframe completo dos docentes.
  #     campus_input (string): O campus a ser filtrado, ou "all" para todos.
  #     curso_input (string): O curso a ser filtrado, ou "all" para todos.
  #   Return:
  #     list: Uma lista com os dataframes 'disc' e 'doc' já filtrados.
  
  baseDisc <- base_discente
  baseDoc <- base_docente
  
  if (campus_input != "all") {
    baseDisc <- baseDisc %>% filter(CAMPUS == campus_input)
    baseDoc <- baseDoc %>% filter(CAMPUS == campus_input)
    
    # O filtro de curso só é aplicado se um campus específico for selecionado
    if (curso_input != "all") {
      baseDisc <- baseDisc %>% filter(CURSO == curso_input)
      baseDoc <- baseDoc %>% filter(CURSO == curso_input)
    }
  }
  
  return(list(disc = baseDisc, doc = baseDoc))
}