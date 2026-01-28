# ===================================================================
# GERADORES DE GRÁFICOS (VERSÃO COMPLETA)
# -------------------------------------------------------------------
# Este script contém todas as funções que criam os objetos de gráfico
# ggplot para cada visualização do dashboard.
# ===================================================================

library(ggplot2)
library(dplyr)
library(tidyr)
library(reshape2)

# Carrega as configurações (nomes de colunas) e funções de cálculo
source("R/1_config.R")
source("R/3_utils.R")

# ===================================================================
# Seção 1: Funções Genéricas de Plotagem
# ===================================================================

graficoContagem <- function(df, dimensao_x, fill_conceito, valores_y, titulo){
  grafico <- ggplot(df, aes(x={{dimensao_x}}, y={{valores_y}}, fill={{fill_conceito}}))+
    geom_bar(stat="identity", position = position_dodge(width=1))+ 
    scale_fill_manual(values = c ("#1D556F", "#288FB4", "#F0B775", "#FA360A"), drop = FALSE) +
    geom_text(aes(label = round({{valores_y}}, 2)), vjust = -0.8, position = position_dodge(width = 0.9), size = 4, family = "sans", colour = "#494953") + 
    theme_minimal() +
    labs(x = NULL, y ="Percentual", title=titulo) + 
    scale_y_continuous(limits = c(0,100)) + 
    theme(panel.grid.major.x = element_blank(), 
          legend.position = "right", legend.title = element_blank(), 
          legend.text = element_text(size=10), axis.text.x = element_text(size=10.8),
          axis.text.y = element_text(size=9.6), axis.title.y = element_text(size=11.3),
          plot.title = element_text(size=12.2, hjust = 0.5, margin = margin(0,0,15,0)))
  return(grafico)
}

graficoMedia <- function(df, dimensoes_x, medias_y, titulo) {
  grafico <- ggplot(df, aes(x= {{dimensoes_x}}, y={{medias_y}}, width=0.6)) +
    geom_bar(stat = "identity", fill = "#288FB4") +
    geom_text(aes(label = round({{medias_y}}, 2)), vjust = -0.5, size=4.3) +
    labs(x=NULL, y=NULL, title=titulo) +
    scale_y_continuous(limits = c(0, 4)) +
    theme_minimal() +
    theme(panel.grid.major.x = element_blank(),
          axis.text.x = element_text(size=12.3), axis.text.y = element_text(size=11),
          plot.title = element_text(size=12.5, hjust = 0.5, margin = margin(0,0,20,0)))
  return(grafico)
}

graficoBoxplot <- function(df, dimensao_x, media_y, titulo, labels_x){
  grafico <- ggplot(df, aes(x = {{dimensao_x}}, y = {{media_y}})) +
    scale_x_discrete(labels = labels_x) +
    stat_boxplot(geom = "errorbar", width = 0.6) +
    geom_boxplot(outlier.color = "#B4B4B8", fill = "#288FB4") +
    theme_minimal() +
    scale_y_continuous(limits = c(1,4)) +
    theme(axis.text.x = element_text(size = 10.3),
          plot.title = element_text(size=10.5, hjust = 0.5)) +
    labs(x = NULL, y = "Média", title=titulo)
  return(grafico)
}


# ===================================================================
# Seção 2: Funções Geradoras Específicas
# ===================================================================

# --- Funções para "Dimensões Gerais" (DISCENTE) ---

generate_dimensoes_proporcao_discente <- function(data) {
  contagensDisc <- lapply(data[, colsAutoAvDisc], table)
  contagensDoc <- lapply(data[, colsAcaoDocente], table)
  contagensInfra <- lapply(data[, colsInfra], table)
  
  df <- data.frame(
    dimensao = rep(c("Autoavaliação Discente", "Ação Docente", "Instalações Físicas"), each = length(alternativas)),
    conceito = rep(conceitos, times = 3),
    valores = c(calculoPercent(alternativas, contagensDisc), 
                calculoPercent(alternativas, contagensDoc), 
                calculoPercent(alternativas, contagensInfra)))

  df$dimensao <- factor(df$dimensao, levels = c("Autoavaliação Discente","Ação Docente","Instalações Físicas"))
  df$conceito <- factor(df$conceito, levels = conceitos_ordem_grafico)
  df <- df[order(df$dimensao, df$conceito), ]

  return(graficoContagem(df, dimensao, conceito, valores, "Proporções de respostas por Dimensão (Discente)"))
}

generate_dimensoes_media_discente <- function(data) {
  df <- data.frame(
      media = c(mean(unlist(data[, colsAutoAvDisc]), na.rm=TRUE), 
                mean(unlist(data[, colsAcaoDocente]), na.rm=TRUE), 
                mean(unlist(data[, colsInfra]), na.rm=TRUE)),
      dimensoes = c("Autoavaliação Discente", "Ação Docente", "Instalações Físicas"))
  
  df$dimensoes <- factor(df$dimensoes, levels = c("Autoavaliação Discente", "Ação Docente", "Instalações Físicas"))
  
  return(graficoMedia(df, df$dimensoes, df$media, "Médias por dimensão (Discente)"))
}

generate_dimensoes_boxplot_discente <- function(data) {
    # ATENÇÃO: Os nomes de colunas com médias (ex: mediap111) não estão no config.
    # O ideal seria criá-los lá, mas por enquanto vamos manter como no script original.
    long_disc <- valoresUnicos(data, mediap111:mediap117) %>% pivot_longer(cols = -ID, names_to = "item", values_to = "media") %>% mutate(dimensao = "Autoavaliação Discente")
    long_doc <- valoresUnicos(data, mediap211:mediap234) %>% pivot_longer(cols = -ID, names_to = "item", values_to = "media") %>% mutate(dimensao = "Ação Docente")
    long_infra <- valoresUnicos(data, mediap311:mediap314) %>% pivot_longer(cols = -ID, names_to = "item", values_to = "media") %>% mutate(dimensao = "Instalações Físicas")

    df_dimensoes <- bind_rows(long_disc, long_doc, long_infra)
    df_dimensoes$dimensao <- factor(df_dimensoes$dimensao, levels = c("Autoavaliação Discente", "Ação Docente", "Instalações Físicas"))
    
    return(graficoBoxplot(df_dimensoes, dimensao, media, "Distribuição das Médias por Dimensão", c("Autoavaliação Discente","Ação Docente","Instalações Físicas")))
}

# --- Funções para "Autoavaliação Discente" ---

generate_autoav_proporcao_discente <- function(data) {
    contagem <- lapply(data[, colsAutoAvDisc], table)
    dfLong <- percentPorItem(contagem, alternativas)
    
    df <- data.frame(
        questoes = rep(c("1.1.1", "1.1.2", "1.1.3", "1.1.4", "1.1.5", "1.1.6", "1.1.7"), each = 4),
        conceito = factor(dfLong$conceito, levels = conceitos_ordem_grafico),
        valores = dfLong$valores
    )
    df <- df[order(df$questoes, df$conceito), ]
    
    return(graficoContagem(df, questoes, conceito, valores, "Proporções: Autoavaliação Discente"))
}

generate_autoav_media_discente <- function(data) {
    medias <- colMeans(data[, colsAutoAvDisc], na.rm = TRUE)
    df <- data.frame(
        medias = medias,
        questoes = c("1.1.1", "1.1.2", "1.1.3", "1.1.4", "1.1.5", "1.1.6", "1.1.7")
    )
    return(graficoMedia(df, questoes, medias, "Médias: Autoavaliação Discente"))
}

generate_autoav_boxplot_discente <- function(data) {
    data_long <- valoresUnicos(data, mediap111:mediap117) %>%
      pivot_longer(cols = starts_with("mediap"), names_to = "dimensao", values_to = "media")
    
    labels <- c("mediap111" = "1.1.1", "mediap112" = "1.1.2", "mediap113" = "1.1.3", "mediap114" = "1.1.4",
                "mediap115" = "1.1.5", "mediap116" = "1.1.6", "mediap117" = "1.1.7")

    return(graficoBoxplot(data_long, dimensao, media, "Distribuição das Médias: Autoavaliação Discente", labels))
}

# --- Funções para "Avaliação Ação Docente" ---

generate_acaodoc_subdim_proporcao_discente <- function(data) {
  contagem21 <- lapply(data[, colsAtProfissional], table)
  contagem22 <- lapply(data[, colsGestaoDidatica], table)
  contagem23 <- lapply(data[, colsProcAvaliativo], table)
  
  dfDoc <- data.frame(
    subdimensoes = rep(c("Atitude Profissional", "Gestão Didática", "Processo Avaliativo"), each = 4),
    conceito = rep(conceitos, times = 3),
    valores = c(calculoPercent(alternativas, contagem21), calculoPercent(alternativas, contagem22), calculoPercent(alternativas, contagem23))
  )
  
  dfDoc$conceito <- factor(dfDoc$conceito, levels = conceitos_ordem_grafico)
  dfDoc <- dfDoc[order(dfDoc$subdimensoes, dfDoc$conceito), ]
  
  return(graficoContagem(dfDoc, subdimensoes, conceito, valores, "Proporções por Subdimensão da Ação Docente"))
}

generate_acaodoc_subdim_media_discente <- function(data) {
  df <- data.frame(
    medias = c(mean(unlist(data[, colsAtProfissional]), na.rm=TRUE), 
               mean(unlist(data[, colsGestaoDidatica]), na.rm=TRUE), 
               mean(unlist(data[, colsProcAvaliativo]), na.rm=TRUE)),
    subdimensoes = c("Atitude Profissional", "Gestão Didática", "Processo Avaliativo")
  )
  return(graficoMedia(df, subdimensoes, medias, "Médias por Subdimensão da Ação Docente"))
}

generate_acaodoc_subdim_boxplot_discente <- function(data) {
    long_21 <- valoresUnicos(data, mediap211:mediap214) %>% pivot_longer(cols = -ID, names_to = "item", values_to = "media") %>% mutate(dimensao = "Atitude Profissional")
    long_22 <- valoresUnicos(data, mediap221:mediap228) %>% pivot_longer(cols = -ID, names_to = "item", values_to = "media") %>% mutate(dimensao = "Gestão Didática")
    long_23 <- valoresUnicos(data, mediap231:mediap234) %>% pivot_longer(cols = -ID, names_to = "item", values_to = "media") %>% mutate(dimensao = "Processo Avaliativo")

    df_mesclado <- bind_rows(long_21, long_22, long_23)
    
    return(graficoBoxplot(df_mesclado, dimensao, media, "Distribuição das Médias por Subdimensão", c("Atitude Profissional", "Gestão Didática", "Processo Avaliativo")))
}

# --- Funções para "Percentual Atividades Academicas" ---

generate_atividades_perc_discente <- function(data) {
  intervalo_colunas <- data %>% select(all_of(colsAtividadesDisc))
  intervalo_colunas[is.na(intervalo_colunas)] <- 0
  intervalo_colunas[intervalo_colunas == ""] <- 0
  if ("4.1.1.P" %in% names(intervalo_colunas)) {
      intervalo_colunas$"4.1.1.P"[intervalo_colunas$"4.1.1.P" != "0" & intervalo_colunas$"4.1.1.P" != "1"] <- "1"
  }
  intervalo_colunas <- mutate_all(intervalo_colunas, function(x) as.numeric(as.character(x)))
  contagem_colunas <- colSums(intervalo_colunas == 1, na.rm = TRUE)
  percentuais <- if (nrow(data) > 0) (contagem_colunas / nrow(data)) * 100 else 0

  df <- data.frame(percentual = percentuais, alternativas = LETTERS[1:18])
  
  return(ggplot(df, aes(x= alternativas, y=percentual, width=0.9)) +
    geom_bar(stat = "identity", fill = "#288FB4") +
    geom_text(aes(label = round(percentuais, 2)), vjust = -0.5, size=4.3) +
    scale_y_continuous(limits = c(0, 100)) +
    labs(x=NULL, y="Percentual", title="Participação em Atividades Acadêmicas (Discente)") +
    theme_minimal() + theme(panel.grid.major.x = element_blank(), axis.text.x = element_text(size=12.3), axis.text.y = element_text(size=11), plot.title = element_text(size=13.5, hjust = 0.5)))
}

generate_atividades_perc_docente <- function(data) {
  intervalo_colunas <- data %>% select(all_of(colsAtividadesDoc))
  intervalo_colunas[is.na(intervalo_colunas)] <- 0
  intervalo_colunas[intervalo_colunas == ""] <- 0
  if ("4.1.1.P" %in% names(intervalo_colunas)) {
    intervalo_colunas$"4.1.1.P"[intervalo_colunas$"4.1.1.P" != "0" & intervalo_colunas$"4.1.1.P" != "1"] <- "1"
  }
  intervalo_colunas <- mutate_all(intervalo_colunas, function(x) as.numeric(as.character(x)))
  contagem_colunas <- colSums(intervalo_colunas == 1, na.rm = TRUE)
  percentuais <- if (nrow(data) > 0) (contagem_colunas / nrow(data)) * 100 else 0
  
  df <- data.frame(percentual = percentuais, alternativas = LETTERS[1:16])
  
  return(ggplot(df, aes(x= alternativas, y=percentual, width=0.9)) +
    geom_bar(stat = "identity", fill = "#288FB4") +
    geom_text(aes(label = round(percentuais, 2)), vjust = -0.5, size=4.3) +
    scale_y_continuous(limits = c(0, 100)) +
    labs(x=NULL, y="Percentual", title="Participação em Atividades Acadêmicas (Docente)") +
    theme_minimal() + theme(panel.grid.major.x = element_blank(), axis.text.x = element_text(size=12.3), axis.text.y = element_text(size=11), plot.title = element_text(size=13.5, hjust = 0.5)))
}

# --- Funções Gerais para "Base Docente" ---

generate_dimensoes_media_docente <- function(data) {
  df <- data.frame(
    medias = c(mean(unlist(data[, colsAvTurmaDoc]), na.rm=TRUE), 
               mean(unlist(data[, colsAcaoDocenteDoc]), na.rm=TRUE), 
               mean(unlist(data[, colsInfraDoc]), na.rm=TRUE)),
    dimensoes = c("Avaliação da Turma", "Autoavaliação da Ação Docente", "Instalações Físicas")
  )
  df$dimensoes <- factor(df$dimensoes, levels = c("Avaliação da Turma", "Autoavaliação da Ação Docente", "Instalações Físicas"))
  return(graficoMedia(df, df$dimensoes, df$medias, "Médias por dimensão (Docente)"))
}

generate_dimensoes_proporcao_docente <- function(data) {
  contagemTurma <- lapply(data[, colsAvTurmaDoc], table)
  contagemAcao <- lapply(data[, colsAcaoDocenteDoc], table)
  contagemInfra <- lapply(data[, colsInfraDoc], table)
  
  df <- data.frame(
    subdimensoes = rep(c("Avaliação da Turma", "Autoavaliação da Ação Docente", "Instalações Físicas"), each = 4),
    conceito = rep(conceitos, times = 3),
    valores = c(calculoPercent(alternativas, contagemTurma), calculoPercent(alternativas, contagemAcao), calculoPercent(alternativas, contagemInfra))
  )
  df$subdimensoes <- factor(df$subdimensoes, levels = c("Avaliação da Turma", "Autoavaliação da Ação Docente", "Instalações Físicas"))
  df$conceito <- factor(df$conceito, levels = conceitos_ordem_grafico)
  df <- df[order(df$subdimensoes, df$conceito), ]
  
  return(graficoContagem(df, df$subdimensoes, df$conceito, df$valores, "Proporções de respostas por Dimensão (Docente)"))
}

generate_avturma_media_docente <- function(data){
    medias <- colMeans(data[, colsAvTurmaDoc], na.rm=TRUE)
    df <- data.frame(medias = medias, questoes = c("1.1.1", "1.1.2", "1.1.3", "1.1.4", "1.1.5", "1.1.6", "1.1.7"))
    return(graficoMedia(df, df$questoes, df$medias, "Médias dos itens: Avaliação da Turma"))
}

generate_avturma_proporcao_docente <- function(data){
    contagem <- lapply(data[, colsAvTurmaDoc], table)
    dfLong <- percentPorItem(contagem, alternativas)
    df <- data.frame(
        questoes = rep(c("1.1.1", "1.1.2", "1.1.3", "1.1.4", "1.1.5", "1.1.6", "1.1.7"), each = 4),
        conceito = factor(dfLong$conceito, levels = conceitos_ordem_grafico),
        valores = dfLong$valores
    )
    df <- df[order(df$questoes, df$conceito), ]
    return(graficoContagem(df, df$questoes, df$conceito, df$valores, "Proporções: Avaliação da Turma"))
}

generate_acaodocente_subdim_media_docente <- function(data){
    df <- data.frame(
        medias = c(mean(unlist(data[, colsAtProfissionalDoc]), na.rm=TRUE), 
                   mean(unlist(data[, colsGestaoDidaticaDoc]), na.rm=TRUE), 
                   mean(unlist(data[, colsProcAvaliativoDoc]), na.rm=TRUE)),
        dimensoes = c("Atitude Profissional", "Gestão Didática", "Processo Avaliativo")
    )
    return(graficoMedia(df, df$dimensoes, df$medias, "Médias por Subdimensão da Autoavaliação Docente"))
}

generate_acaodocente_subdim_proporcao_docente <- function(data){
    contagem21 <- lapply(data[, colsAtProfissionalDoc], table)
    contagem22 <- lapply(data[, colsGestaoDidaticaDoc], table)
    contagem23 <- lapply(data[, colsProcAvaliativoDoc], table)

    df <- data.frame(
        subdimensoes = rep(c("Atitude Profissional", "Gestão Didática", "Processo Avaliativo"), each=4),
        conceito = rep(conceitos, times = 3),
        valores = c(calculoPercent(alternativas,contagem21), calculoPercent(alternativas,contagem22), calculoPercent(alternativas,contagem23))
    )
    df$conceito <- factor(df$conceito, levels = conceitos_ordem_grafico)
    df <- df[order(df$subdimensoes, df$conceito), ]
    
    return(graficoContagem(df, df$subdimensoes, df$conceito, df$valores, "Proporções por Subdimensão da Autoavaliação Docente"))
}

# --- Funções para "Atitude Profissional" (Discente e Docente) ---

generate_atitudeprof_media_discente <- function(data) {
    medias <- colMeans(data[, colsAtProfissional], na.rm=TRUE)
    df <- data.frame(medias = medias, questoes = c("2.1.1", "2.1.2", "2.1.3", "2.1.4"))
    return(graficoMedia(df, df$questoes, df$medias, "Médias: Atitude Profissional (Discente)"))
}

generate_atitudeprof_media_docente <- function(data) {
    medias <- colMeans(data[, colsAtProfissionalDoc], na.rm=TRUE)
    df <- data.frame(medias = medias, questoes = c("2.1.1", "2.1.2", "2.1.3", "2.1.4"))
    return(graficoMedia(df, df$questoes, df$medias, "Médias: Atitude Profissional (Docente)"))
}

generate_atitudeprof_proporcao_discente <- function(data) {
    contagem <- lapply(data[, colsAtProfissional], table)
    dfLong <- percentPorItem(contagem, alternativas)
    df <- data.frame(
        questoes = rep(c("2.1.1", "2.1.2", "2.1.3", "2.1.4"), each = 4),
        conceito = factor(dfLong$conceito, levels = conceitos_ordem_grafico),
        valores = dfLong$valores
    )
    df <- df[order(df$questoes, df$conceito), ]
    return(graficoContagem(df, df$questoes, df$conceito, df$valores, "Proporções: Atitude Profissional (Discente)"))
}

generate_atitudeprof_proporcao_docente <- function(data) {
    contagem <- lapply(data[, colsAtProfissionalDoc], table)
    dfLong <- percentPorItem(contagem, alternativas)
    df <- data.frame(
        questoes = rep(c("2.1.1", "2.1.2", "2.1.3", "2.1.4"), each = 4),
        conceito = factor(dfLong$conceito, levels = conceitos_ordem_grafico),
        valores = dfLong$valores
    )
    df <- df[order(df$questoes, df$conceito), ]
    return(graficoContagem(df, df$questoes, df$conceito, df$valores, "Proporções: Atitude Profissional (Docente)"))
}

generate_atitudeprof_boxplot_discente <- function(data) {
    data_long <- valoresUnicos(data, mediap211:mediap214) %>%
      pivot_longer(cols = starts_with("mediap"), names_to = "dimensao", values_to = "media")
    labels <- c("mediap211" = "2.1.1", "mediap212" = "2.1.2", "mediap213" = "2.1.3", "mediap214" = "2.1.4")
    return(graficoBoxplot(data_long, dimensao, media, "Distribuição das Médias: Atitude Profissional", labels))
}

# --- Funções para "Gestão Didática" (Discente e Docente) ---

generate_gestaodid_media_discente <- function(data) {
    medias <- colMeans(data[, colsGestaoDidatica], na.rm=TRUE)
    df <- data.frame(medias = medias, questoes = c("2.2.1", "2.2.2", "2.2.3", "2.2.4","2.2.5", "2.2.6", "2.2.7", "2.2.8"))
    return(graficoMedia(df, df$questoes, df$medias, "Médias: Gestão Didática (Discente)"))
}

generate_gestaodid_media_docente <- function(data) {
    medias <- colMeans(data[, colsGestaoDidaticaDoc], na.rm=TRUE)
    df <- data.frame(medias = medias, questoes = c("2.2.1", "2.2.2", "2.2.3", "2.2.4","2.2.5", "2.2.6", "2.2.7", "2.2.8"))
    return(graficoMedia(df, df$questoes, df$medias, "Médias: Gestão Didática (Docente)"))
}

generate_gestaodid_proporcao_discente <- function(data) {
    contagem <- lapply(data[, colsGestaoDidatica], table)
    dfLong <- percentPorItem(contagem, alternativas)
    df <- data.frame(
        questoes = rep(c("2.2.1", "2.2.2", "2.2.3", "2.2.4","2.2.5","2.2.6","2.2.7","2.2.8"), each = 4),
        conceito = factor(dfLong$conceito, levels = conceitos_ordem_grafico),
        valores = dfLong$valores
    )
    df <- df[order(df$questoes, df$conceito), ]
    return(graficoContagem(df, df$questoes, df$conceito, df$valores, "Proporções: Gestão Didática (Discente)"))
}

generate_gestaodid_proporcao_docente <- function(data) {
    contagem <- lapply(data[, colsGestaoDidaticaDoc], table)
    dfLong <- percentPorItem(contagem, alternativas)
    df <- data.frame(
        questoes = rep(c("2.2.1", "2.2.2", "2.2.3", "2.2.4","2.2.5","2.2.6","2.2.7","2.2.8"), each = 4),
        conceito = factor(dfLong$conceito, levels = conceitos_ordem_grafico),
        valores = dfLong$valores
    )
    df <- df[order(df$questoes, df$conceito), ]
    return(graficoContagem(df, df$questoes, df$conceito, df$valores, "Proporções: Gestão Didática (Docente)"))
}

generate_gestaodid_boxplot_discente <- function(data) {
    data_long <- valoresUnicos(data, mediap221:mediap228) %>%
      pivot_longer(cols = starts_with("mediap"), names_to = "dimensao", values_to = "media")
    labels <- c("mediap221" = "2.2.1", "mediap222" = "2.2.2", "mediap223" = "2.2.3", "mediap224" = "2.2.4",
                "mediap225" = "2.2.5", "mediap226" = "2.2.6", "mediap227" = "2.2.7", "mediap228" = "2.2.8")
    return(graficoBoxplot(data_long, dimensao, media, "Distribuição das Médias: Gestão Didática", labels))
}

# --- Funções para "Processo Avaliativo" (Discente e Docente) ---

generate_procav_media_discente <- function(data) {
    medias <- colMeans(data[, colsProcAvaliativo], na.rm=TRUE)
    df <- data.frame(medias = medias, questoes = c("2.3.1", "2.3.2", "2.3.3", "2.3.4"))
    return(graficoMedia(df, df$questoes, df$medias, "Médias: Processo Avaliativo (Discente)"))
}

generate_procav_media_docente <- function(data) {
    medias <- colMeans(data[, colsProcAvaliativoDoc], na.rm=TRUE)
    df <- data.frame(medias = medias, questoes = c("2.3.1", "2.3.2", "2.3.3", "2.3.4"))
    return(graficoMedia(df, df$questoes, df$medias, "Médias: Processo Avaliativo (Docente)"))
}

generate_procav_proporcao_discente <- function(data) {
    contagem <- lapply(data[, colsProcAvaliativo], table)
    dfLong <- percentPorItem(contagem, alternativas)
    df <- data.frame(
        questoes = rep(c("2.3.1", "2.3.2", "2.3.3", "2.3.4"), each = 4),
        conceito = factor(dfLong$conceito, levels = conceitos_ordem_grafico),
        valores = dfLong$valores
    )
    df <- df[order(df$questoes, df$conceito), ]
    return(graficoContagem(df, df$questoes, df$conceito, df$valores, "Proporções: Processo Avaliativo (Discente)"))
}

generate_procav_proporcao_docente <- function(data) {
    contagem <- lapply(data[, colsProcAvaliativoDoc], table)
    dfLong <- percentPorItem(contagem, alternativas)
    df <- data.frame(
        questoes = rep(c("2.3.1", "2.3.2", "2.3.3", "2.3.4"), each = 4),
        conceito = factor(dfLong$conceito, levels = conceitos_ordem_grafico),
        valores = dfLong$valores
    )
    df <- df[order(df$questoes, df$conceito), ]
    return(graficoContagem(df, df$questoes, df$conceito, df$valores, "Proporções: Processo Avaliativo (Docente)"))
}

generate_procav_boxplot_discente <- function(data) {
    data_long <- valoresUnicos(data, mediap231:mediap234) %>%
      pivot_longer(cols = starts_with("mediap"), names_to = "dimensao", values_to = "media")
    labels <- c("mediap231" = "2.3.1", "mediap232" = "2.3.2", "mediap233" = "2.3.3", "mediap234" = "2.3.4")
    return(graficoBoxplot(data_long, dimensao, media, "Distribuição das Médias: Processo Avaliativo", labels))
}

# --- Funções para "Instalações Físicas" (Discente e Docente) ---

generate_infra_media_discente <- function(data) {
    medias <- colMeans(data[, colsInfra], na.rm=TRUE)
    df <- data.frame(medias = medias, questoes = c("3.1.1", "3.1.2", "3.1.3", "3.1.4"))
    return(graficoMedia(df, df$questoes, df$medias, "Médias: Instalações Físicas (Discente)"))
}

generate_infra_media_docente <- function(data) {
    medias <- colMeans(data[, colsInfraDoc], na.rm=TRUE)
    df <- data.frame(medias = medias, questoes = c("3.1.1", "3.1.2", "3.1.3", "3.1.4"))
    return(graficoMedia(df, df$questoes, df$medias, "Médias: Instalações Físicas (Docente)"))
}

generate_infra_proporcao_discente <- function(data) {
    contagem <- lapply(data[, colsInfra], table)
    dfLong <- percentPorItem(contagem, alternativas)
    df <- data.frame(
        questoes = rep(c("3.1.1", "3.1.2", "3.1.3", "3.1.4"), each = 4),
        conceito = factor(dfLong$conceito, levels = conceitos_ordem_grafico),
        valores = dfLong$valores
    )
    df <- df[order(df$questoes, df$conceito), ]
    return(graficoContagem(df, df$questoes, df$conceito, df$valores, "Proporções: Instalações Físicas (Discente)"))
}

generate_infra_proporcao_docente <- function(data) {
    contagem <- lapply(data[, colsInfraDoc], table)
    dfLong <- percentPorItem(contagem, alternativas)
    df <- data.frame(
        questoes = rep(c("3.1.1", "3.1.2", "3.1.3", "3.1.4"), each = 4),
        conceito = factor(dfLong$conceito, levels = conceitos_ordem_grafico),
        valores = dfLong$valores
    )
    df <- df[order(df$questoes, df$conceito), ]
    return(graficoContagem(df, df$questoes, df$conceito, df$valores, "Proporções: Instalações Físicas (Docente)"))
}

generate_infra_boxplot_discente <- function(data) {
    data_long <- valoresUnicos(data, mediap311:mediap314) %>%
      pivot_longer(cols = starts_with("mediap"), names_to = "dimensao", values_to = "media")
    labels <- c("mediap311" = "3.1.1", "mediap312" = "3.1.2", "mediap313" = "3.1.3", "mediap314" = "3.1.4")
    return(graficoBoxplot(data_long, dimensao, media, "Distribuição das Médias: Instalações Físicas", labels))
}