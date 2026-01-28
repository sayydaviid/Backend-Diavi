# nolint start

# ===================================================================
# PONTO DE ENTRADA DA API (Versão Otimizada p/ Filtragem no Servidor)
# ===================================================================

# --- 0. Opções globais ---
options(stringsAsFactors = FALSE)

# --- 1. Carga de Pacotes e Módulos (sem spam de attach messages) ---
suppressPackageStartupMessages({
  library(plumber)
  library(dplyr)
  library(jsonlite)
  library(tidyr)
})

# Porta/host para PaaS
# Hugging Face Spaces normalmente usa PORT=7860.
PORT <- as.integer(Sys.getenv("PORT", "7860"))
HOST <- Sys.getenv("HOST", "0.0.0.0")

# -------------------------------------------------------------------
# FIX DEFINITIVO DOS WARNINGS DO readxl:
# Força leitura como TEXTO quando main.R/load_data() usar readxl.
# Isso evita: "Expecting logical ... got 'texto...'"
# -------------------------------------------------------------------
read_excel <- function(path, sheet = NULL, ..., col_types = "text", guess_max = 10000) {
  readxl::read_excel(path = path, sheet = sheet, col_types = col_types, guess_max = guess_max, ...)
}
read_xlsx <- function(path, sheet = NULL, ..., col_types = "text", guess_max = 10000) {
  readxl::read_xlsx(path = path, sheet = sheet, col_types = col_types, guess_max = guess_max, ...)
}
read_xls <- function(path, sheet = NULL, ..., col_types = "text", guess_max = 10000) {
  readxl::read_xls(path = path, sheet = sheet, col_types = col_types, guess_max = guess_max, ...)
}

# (opcional) garantir working dir para o source("R/main.R")
suppressWarnings({
  f <- tryCatch(normalizePath(sys.frames()[[1]]$ofile), error = function(e) NULL)
  if (!is.null(f)) setwd(dirname(f))
})

# Carrega configs e utilitários (deve definir load_data, filter_data, etc.)
source("R/main.R")

# Padroniza alternativas (evita tipo inesperado após múltiplos sources)
alternativas <- suppressWarnings(as.numeric(alternativas))

# --- 1.1 Helpers -----------------------------------------------------

normalize_param <- function(x) {
  if (is.null(x)) return("all")

  x_chr <- trimws(as.character(x))
  if (tolower(x_chr) %in% c("", "all", "todos", "todas", "todo", "qualquer", "none", "null", "undefined")) {
    return("all")
  }
  x_chr
}

.assert_subdim_map_doc <- function() {
  if (!exists("subdim_map_doc")) {
    stop("subdim_map_doc não encontrado. Defina em R/1_config.R como uma lista nomeada: nomes = subdimensões; valores = vetores de colunas.")
  }
  if (!is.list(subdim_map_doc) || is.null(names(subdim_map_doc))) {
    stop("subdim_map_doc deve ser uma lista nomeada. Ex: list('Planejamento' = c('D201','D202'), ...)")
  }
}

.label_itens_auto  <- function(cols) gsub("^P(\\d)(\\d)(\\d)$", "\\1.\\2.\\3", cols)
.label_itens_media <- function(cols) gsub("^mediap(\\d)(\\d)(\\d)$", "\\1.\\2.\\3", cols)

.label_itens_any <- function(cols) {
  cols <- as.character(cols)
  cols <- gsub("^mediap(\\d)(\\d)(\\d)$", "\\1.\\2.\\3", cols)
  cols <- gsub("^[PD](\\d)(\\d)(\\d)$", "\\1.\\2.\\3", cols)
  cols
}

.to_num <- function(x) {
  x <- trimws(as.character(x))
  x <- gsub(",", ".", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

.to_num_mediap <- function(x) {
  v <- .to_num(x)
  v[!is.finite(v)] <- NA_real_
  v[v <= 0] <- NA_real_
  v
}

.sample_out <- function(x, max_out = 50) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (!length(x)) return(numeric(0))
  if (length(x) > max_out) sample(x, max_out) else x
}

.calc_stats6_pdf <- function(v) {
  v <- .to_num_mediap(v)
  v <- v[is.finite(v)]
  if (!length(v)) return(rep(NA_real_, 6))

  qs <- as.numeric(quantile(v, probs = c(0, .25, .5, .75, 1), na.rm = TRUE, type = 7))
  c(qs[1], qs[2], qs[3], mean(v, na.rm = TRUE), qs[4], qs[5])
}

.normalize_box_stats <- function(stats_vec) {
  s <- as.numeric(stats_vec)
  if (length(s) < 5 || any(!is.finite(s))) return(s)

  wmin <- s[1]; q1 <- s[2]; med <- s[3]; q3 <- s[4]; wmax <- s[5]

  if (wmin > wmax) { tmp <- wmin; wmin <- wmax; wmax <- tmp }
  if (q1 > q3)     { tmp <- q1;  q1  <- q3;  q3  <- tmp }

  if (med < q1) med <- q1
  if (med > q3) med <- q3

  if (wmin > q1) wmin <- q1
  if (wmax < q3) wmax <- q3

  clamp <- function(v) max(1.0, min(4.0, v))
  wmin <- clamp(wmin); q1 <- clamp(q1); med <- clamp(med); q3 <- clamp(q3); wmax <- clamp(wmax)

  q1   <- max(q1, wmin)
  med  <- max(med, q1)
  q3   <- max(q3, med)
  wmax <- max(wmax, q3)

  c(wmin, q1, med, q3, wmax)
}

.calc_box_safe <- function(v) {
  v <- .to_num_mediap(v)
  v <- v[is.finite(v)]
  if (!length(v)) return(list(stats = rep(NA_real_, 5), out = numeric(0)))

  bs <- boxplot.stats(v)
  bs$stats <- .normalize_box_stats(bs$stats)
  bs
}

# -------------------------------------------------------------------
# COERÇÃO CONTROLADA DE COLUNAS NUMÉRICAS IMPORTANTES
# (porque o XLSX foi lido como texto para evitar warnings do readxl)
# -------------------------------------------------------------------
.coerce_numeric_cols <- function(df, cols) {
  cols <- intersect(as.character(cols), names(df))
  if (!length(cols)) return(df)

  for (cl in cols) {
    v <- df[[cl]]
    if (is.factor(v)) v <- as.character(v)
    v <- trimws(as.character(v))
    v <- gsub(",", ".", v, fixed = TRUE)
    df[[cl]] <- suppressWarnings(as.numeric(v))
  }
  df
}

# --- 2. Carga Inicial dos Dados --------------------------------------
all_data <- load_data()
base_discente_global <- all_data$discente
base_docente_global  <- all_data$docente

# Converte colunas de respostas (1..4), médias (mediap*) e atividades (0/1) para numérico
disc_numeric_cols <- unique(c(
  colsAutoAvDisc, colsAcaoDocente, colsInfra,
  colsAtProfissional, colsGestaoDidatica, colsProcAvaliativo,
  colsAtividadesDisc,
  paste0("mediap", 111:117), paste0("mediap", 211:234), paste0("mediap", 311:314)
))
doc_numeric_cols <- unique(c(
  colsAvTurmaDoc, colsAcaoDocenteDoc, colsInfraDoc,
  colsAtProfissionalDoc, colsGestaoDidaticaDoc, colsProcAvaliativoDoc,
  colsAtividadesDoc
))

base_discente_global <- .coerce_numeric_cols(base_discente_global, disc_numeric_cols)
base_docente_global  <- .coerce_numeric_cols(base_docente_global,  doc_numeric_cols)

cat(">> Dados carregados. API pronta para iniciar.\n")


# --- 3. Definição da API ---------------------------------------------
pr <- pr()

# --- 4. Filtro de CORS -----------------------------------------------
pr <- pr_filter(pr, "cors", function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  res$setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
  if (req$REQUEST_METHOD == "OPTIONS") { res$status <- 200; return(list()) }
  plumber::forward()
})

# --- 5. Endpoints básicos --------------------------------------------
pr <- pr_get(pr, "/", function() list(api_status = "Online", message = "Bem-vindo à API do Dashboard AVALIA."))
pr <- pr_get(pr, "/health", function() list(status = "OK", time = as.character(Sys.time())))
pr <- pr_get(pr, "/filters", function() {
  list(
    campus = sort(unique(c(base_discente_global$CAMPUS, base_docente_global$CAMPUS))),
    cursos = sort(unique(c(base_discente_global$CURSO,  base_docente_global$CURSO)))
  )
})

# ==============================================================================
# PRÉ-CÁLCULO DE RANKINGS (Executa apenas uma vez na inicialização)
# ==============================================================================
todas_colunas_questoes <- c(colsAutoAvDisc, colsAcaoDocente, colsInfra)

rankings_cache <- base_discente_global %>%
  dplyr::select(CAMPUS, dplyr::all_of(todas_colunas_questoes)) %>%
  tidyr::pivot_longer(cols = -CAMPUS, names_to = "questao", values_to = "nota") %>%
  dplyr::filter(!is.na(nota) & !is.na(CAMPUS)) %>%
  dplyr::mutate(nota = suppressWarnings(as.numeric(nota))) %>%
  dplyr::group_by(CAMPUS) %>%
  dplyr::summarise(media_geral = mean(nota, na.rm = TRUE), .groups = "drop")

melhor_campus_global <- rankings_cache %>%
  dplyr::filter(media_geral == max(media_geral, na.rm = TRUE)) %>%
  dplyr::slice(1)

pior_campus_global <- rankings_cache %>%
  dplyr::filter(media_geral == min(media_geral, na.rm = TRUE)) %>%
  dplyr::slice(1)

# ==========================================================
# >>>>>>>>>>>> CARDS (DISCENTE) <<<<<<<<<<<<
# ==========================================================
pr <- pr_get(
  pr, "/discente/geral/summary",
  function(campus = "all", curso = "all") {

    campus_norm <- normalize_param(campus)
    curso_norm  <- normalize_param(curso)

    dados_filtrados <- filter_data(
      base_discente_global,
      base_docente_global,
      campus_norm,
      curso_norm
    )

    disc <- dados_filtrados$disc
    doc  <- dados_filtrados$doc

    names(disc) <- trimws(as.character(names(disc)))
    names(doc)  <- trimws(as.character(names(doc)))

    n_unique_safe <- function(x) {
      x <- trimws(as.character(x))
      x <- x[!is.na(x) & x != ""]
      length(unique(x))
    }

    n_docente  <- if ("DOCENTE"    %in% names(disc)) n_unique_safe(disc$DOCENTE)    else NA_integer_
    n_discente <- if ("MATRICULA"  %in% names(disc)) n_unique_safe(disc$MATRICULA)  else NA_integer_
    n_turmas   <- if ("DISCIPLINA" %in% names(disc)) n_unique_safe(disc$DISCIPLINA) else NA_integer_

    list(
      n_discente = n_discente,
      n_docente  = n_docente,
      n_turmas   = n_turmas,

      nDiscente = n_discente,
      nDocente  = n_docente,
      nTurmas   = n_turmas,

      total_respondentes = n_discente
    )
  }
)

# -------------------------------
# DISCENTES (Agregados)
# -------------------------------
pr <- pr_get(
  pr, "/discente/dimensoes/medias",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    data.frame(
      dimensao = c("Autoavaliação Discente", "Ação Docente", "Instalações Físicas"),
      media = c(
        mean(unlist(dados[, colsAutoAvDisc]), na.rm = TRUE),
        mean(unlist(dados[, colsAcaoDocente]), na.rm = TRUE),
        mean(unlist(dados[, colsInfra]),       na.rm = TRUE)
      )
    )
  }
)

pr <- pr_get(
  pr, "/discente/dimensoes/proporcoes",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    cont_disc  <- lapply(dados[, colsAutoAvDisc], table)
    cont_doc   <- lapply(dados[, colsAcaoDocente], table)
    cont_infra <- lapply(dados[, colsInfra],       table)

    data.frame(
      dimensao = rep(c("Autoavaliação Discente","Ação Docente","Instalações Físicas"), each = length(alternativas)),
      conceito = rep(conceitos, times = 3),
      valor = c(
        calculoPercent(alternativas, cont_disc),
        calculoPercent(alternativas, cont_doc),
        calculoPercent(alternativas, cont_infra)
      )
    )
  }
)

# ==============================================================================
# /discente/dimensoes/boxplot (alinhado ao PDF)
# - stats6 para tabela (Min,Q1,Med,Mean,Q3,Max)
# - boxplot_data envia SOMENTE 5 números [min,q1,med,q3,max] (compatível com Apex)
# ==============================================================================
pr <- pr_get(
  pr, "/discente/dimensoes/boxplot",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus)
    curso  <- normalize_param(curso)
    dados  <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    auto_num  <- dados[, intersect(names(dados), paste0("mediap", 111:117)), drop = FALSE]
    doc_num   <- dados[, intersect(names(dados), paste0("mediap", 211:234)), drop = FALSE]
    infra_num <- dados[, intersect(names(dados), paste0("mediap", 311:314)), drop = FALSE]

    v_auto  <- .to_num_mediap(unlist(auto_num,  use.names = FALSE))
    v_doc   <- .to_num_mediap(unlist(doc_num,   use.names = FALSE))
    v_infra <- .to_num_mediap(unlist(infra_num, use.names = FALSE))

    s6_auto  <- .calc_stats6_pdf(v_auto)
    s6_doc   <- .calc_stats6_pdf(v_doc)
    s6_infra <- .calc_stats6_pdf(v_infra)

    tabela2 <- data.frame(
      Estatística = c("Min", "1º Q.", "Mediana", "Média", "3º Q.", "Max"),
      `Autoavaliação Discente` = round(s6_auto,  2),
      `Ação Docente`           = round(s6_doc,   2),
      `Instalações Físicas`    = round(s6_infra, 2),
      check.names = FALSE
    )

    y5_auto  <- .normalize_box_stats(c(s6_auto[1],  s6_auto[2],  s6_auto[3],  s6_auto[5],  s6_auto[6]))
    y5_doc   <- .normalize_box_stats(c(s6_doc[1],   s6_doc[2],   s6_doc[3],   s6_doc[5],   s6_doc[6]))
    y5_infra <- .normalize_box_stats(c(s6_infra[1], s6_infra[2], s6_infra[3], s6_infra[5], s6_infra[6]))

    boxplot_data <- data.frame(
      x = c("Autoavaliação Discente", "Ação Docente", "Instalações Físicas"),
      y = I(list(
        round(y5_auto,  2),
        round(y5_doc,   2),
        round(y5_infra, 2)
      ))
    )

    stA <- .calc_box_safe(v_auto)
    stD <- .calc_box_safe(v_doc)
    stI <- .calc_box_safe(v_infra)

    outliers_data <- rbind(
      data.frame(x = "Autoavaliação Discente", y = round(.sample_out(stA$out, 200), 2)),
      data.frame(x = "Ação Docente",           y = round(.sample_out(stD$out, 200), 2)),
      data.frame(x = "Instalações Físicas",    y = round(.sample_out(stI$out, 200), 2))
    )
    outliers_data <- outliers_data[is.finite(outliers_data$y), , drop = FALSE]

    list(
      tabela2       = tabela2,
      boxplot_data  = boxplot_data,
      outliers_data = outliers_data
    )
  }
)

# =========================================================================
# SUBDIMENSÕES AÇÃO DOCENTE (DISCENTE) — PROPORÇÕES
# =========================================================================
pr <- pr_get(
  pr, "/discente/acaodocente/subdimensoes/proporcoes",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    cols_atp <- intersect(colsAtProfissional, names(dados))
    cols_ges <- intersect(colsGestaoDidatica, names(dados))
    cols_pro <- intersect(colsProcAvaliativo, names(dados))

    cont_atp <- if (length(cols_atp)) lapply(dados[, cols_atp, drop = FALSE], table) else list()
    cont_ges <- if (length(cols_ges)) lapply(dados[, cols_ges, drop = FALSE], table) else list()
    cont_pro <- if (length(cols_pro)) lapply(dados[, cols_pro, drop = FALSE], table) else list()

    df <- data.frame(
      subdimensao = rep(c("Atitude Profissional", "Gestão Didática", "Processo Avaliativo"), each = length(alternativas)),
      conceito = rep(conceitos, times = 3),
      valor = c(
        calculoPercent(alternativas, cont_atp),
        calculoPercent(alternativas, cont_ges),
        calculoPercent(alternativas, cont_pro)
      )
    )
    df$valor[is.nan(df$valor)] <- 0
    df
  }
)

# -------------------------------
# ATIVIDADES (DISCENTE)
# -------------------------------
pr <- pr_get(
  pr, "/discente/atividades/percentual",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc
    if (nrow(dados) == 0) return(data.frame(atividade = character(), percentual = numeric()))

    intervalo <- dados %>% select(all_of(colsAtividadesDisc)) %>% mutate(across(everything(), as.character))
    intervalo[is.na(intervalo)] <- "0"; intervalo[intervalo == ""] <- "0"

    if ("4.1.1.P" %in% names(intervalo)) {
      intervalo$"4.1.1.P"[ intervalo$"4.1.1.P" != "0" & intervalo$"4.1.1.P" != "1" ] <- "1"
    }

    intervalo <- intervalo %>% mutate(across(everything(), as.numeric))
    contagem <- colSums(intervalo == 1, na.rm = TRUE)
    percentuais <- (contagem / nrow(dados)) * 100

    data.frame(atividade = LETTERS[seq_along(percentuais)], percentual = percentuais)
  }
)

# ====== Detalhes por item (Discente) — PROPORÇÕES/MÉDIAS ======
pr <- pr_get(
  pr, "/discente/autoavaliacao/itens/proporcoes",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc
    itens <- dados[, colsAutoAvDisc, drop = FALSE]

    dados_longos <- itens %>%
      pivot_longer(everything(), names_to = "item", values_to = "valor") %>%
      filter(!is.na(valor)) %>%
      count(item, valor) %>%
      group_by(item) %>%
      mutate(total_item = sum(n), percentual = (n/total_item)*100) %>%
      ungroup()

    dados_longos %>%
      complete(item, valor = alternativas, fill = list(n = 0, total_item = 0, percentual = 0)) %>%
      mutate(item = .label_itens_auto(item), conceito = conceitos[as.numeric(valor)]) %>%
      select(item, conceito, valor = percentual)
  }
)

pr <- pr_get(
  pr, "/discente/autoavaliacao/itens/medias",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc
    itens <- dados[, colsAutoAvDisc, drop = FALSE]
    itens[] <- lapply(itens, function(v) suppressWarnings(as.numeric(v)))
    medias <- sapply(itens, function(col) mean(col, na.rm = TRUE))
    data.frame(item = .label_itens_auto(names(medias)), media = as.numeric(medias), stringsAsFactors = FALSE)
  }
)

# ==============================================================================
# /discente/autoavaliacao/itens/boxplot
# - retorna tabela6 (stats6) e boxplot_data (y5) + outliers
# ==============================================================================
pr <- pr_get(
  pr, "/discente/autoavaliacao/itens/boxplot",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus)
    curso  <- normalize_param(curso)
    dados  <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    cols <- intersect(paste0("mediap", 111:117), names(dados))

    box_df_list  <- list()
    out_df_list  <- list()
    tab_df_list  <- list()

    for (nm in cols) {
      v <- .to_num_mediap(dados[[nm]])
      v <- v[is.finite(v)]
      if (!length(v)) next

      s6 <- .calc_stats6_pdf(v)
      y5 <- .normalize_box_stats(c(s6[1], s6[2], s6[3], s6[5], s6[6]))

      lbl <- .label_itens_media(nm)

      tab_df_list[[length(tab_df_list)+1]] <- data.frame(
        item = lbl,
        Min = round(s6[1],2),
        Q1  = round(s6[2],2),
        Mediana = round(s6[3],2),
        Media   = round(s6[4],2),
        Q3  = round(s6[5],2),
        Max = round(s6[6],2),
        stringsAsFactors = FALSE
      )

      box_df_list[[length(box_df_list)+1]] <- data.frame(
        x = lbl,
        y = I(list(round(y5, 2)))
      )

      st <- .calc_box_safe(v)
      outs <- round(.sample_out(st$out, max_out = 1500), 2)
      if (length(outs)) out_df_list[[length(out_df_list)+1]] <- data.frame(x = lbl, y = as.numeric(outs))
    }

    boxplot_data  <- if (length(box_df_list)) do.call(rbind, box_df_list) else data.frame(x = character(), y = I(list()))
    outliers_data <- if (length(out_df_list)) do.call(rbind, out_df_list) else data.frame(x = character(), y = numeric())
    tabela_items  <- if (length(tab_df_list)) do.call(rbind, tab_df_list) else data.frame()

    list(
      tabela_items = tabela_items,
      boxplot_data = boxplot_data,
      outliers_data = outliers_data
    )
  }
)

# -------------------------------
# ATITUDE PROFISSIONAL (DISCENTE) — PROPORÇÕES/MÉDIAS
# -------------------------------
pr <- pr_get(
  pr, "/discente/atitudeprofissional/itens/proporcoes",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    cols <- intersect(colsAtProfissional, names(dados))
    if (!length(cols)) return(data.frame(item = character(), conceito = character(), valor = numeric()))

    itens <- dados[, cols, drop = FALSE]
    dados_longos <- itens %>%
      pivot_longer(everything(), names_to = "item", values_to = "valor") %>%
      filter(!is.na(valor)) %>%
      count(item, valor) %>%
      group_by(item) %>%
      mutate(total_item = sum(n), percentual = (n/total_item)*100) %>%
      ungroup()

    dados_longos %>%
      complete(item, valor = alternativas, fill = list(n = 0, total_item = 0, percentual = 0)) %>%
      mutate(item = .label_itens_auto(item), conceito = conceitos[as.numeric(valor)]) %>%
      select(item, conceito, valor = percentual)
  }
)

pr <- pr_get(
  pr, "/discente/atitudeprofissional/itens/medias",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc
    itens <- dados[, colsAtProfissional, drop = FALSE]
    itens[] <- lapply(itens, function(v) suppressWarnings(as.numeric(v)))
    medias <- sapply(itens, function(col) mean(col, na.rm = TRUE))
    data.frame(item = .label_itens_auto(names(medias)), media = as.numeric(medias), stringsAsFactors = FALSE)
  }
)

# ==============================================================================
# /discente/atitudeprofissional/itens/boxplot (mediap211..214)
# - tabela_items (stats6) + boxplot_data (y5) + outliers
# ==============================================================================
pr <- pr_get(
  pr, "/discente/atitudeprofissional/itens/boxplot",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus)
    curso  <- normalize_param(curso)

    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc
    cols  <- intersect(paste0("mediap", 211:214), names(dados))

    box_df_list <- list()
    out_df_list <- list()
    tab_df_list <- list()

    for (nm in cols) {
      v <- .to_num_mediap(dados[[nm]])
      v <- v[is.finite(v)]
      if (!length(v)) next

      s6 <- .calc_stats6_pdf(v)
      y5 <- .normalize_box_stats(c(s6[1], s6[2], s6[3], s6[5], s6[6]))

      lbl <- .label_itens_media(nm)

      tab_df_list[[length(tab_df_list)+1]] <- data.frame(
        item = lbl,
        Min = round(s6[1],2),
        Q1  = round(s6[2],2),
        Mediana = round(s6[3],2),
        Media   = round(s6[4],2),
        Q3  = round(s6[5],2),
        Max = round(s6[6],2),
        stringsAsFactors = FALSE
      )

      box_df_list[[length(box_df_list)+1]] <- data.frame(x = lbl, y = I(list(round(y5,2))))

      st <- .calc_box_safe(v)
      outs <- round(.sample_out(st$out, max_out = 1500), 2)
      if (length(outs)) out_df_list[[length(out_df_list)+1]] <- data.frame(x = lbl, y = as.numeric(outs))
    }

    list(
      tabela_items  = if (length(tab_df_list)) do.call(rbind, tab_df_list) else data.frame(),
      boxplot_data  = if (length(box_df_list)) do.call(rbind, box_df_list) else data.frame(x = character(), y = I(list())),
      outliers_data = if (length(out_df_list)) do.call(rbind, out_df_list) else data.frame(x = character(), y = numeric())
    )
  }
)

# ==========================================================
# ---------------------------- DOCENTES (Agregados)
# ==========================================================
pr <- pr_get(
  pr, "/docente/dimensoes/medias",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc

    data.frame(
      dimensao = c("Avaliação da Turma","Autoavaliação da Ação Docente","Instalações Físicas"),
      media = c(
        mean(unlist(dados[, colsAvTurmaDoc]),     na.rm = TRUE),
        mean(unlist(dados[, colsAcaoDocenteDoc]), na.rm = TRUE),
        mean(unlist(dados[, colsInfraDoc]),       na.rm = TRUE)
      )
    )
  }
)

pr <- pr_get(
  pr, "/docente/dimensoes/proporcoes",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc

    cont_turma <- lapply(dados[, colsAvTurmaDoc],     table)
    cont_acao  <- lapply(dados[, colsAcaoDocenteDoc], table)
    cont_infra <- lapply(dados[, colsInfraDoc],       table)

    data.frame(
      dimensao = rep(c("Avaliação da Turma","Autoavaliação da Ação Docente","Instalações Físicas"), each = length(alternativas)),
      conceito = rep(conceitos, times = 3),
      valor = c(
        calculoPercent(alternativas, cont_turma),
        calculoPercent(alternativas, cont_acao),
        calculoPercent(alternativas, cont_infra)
      )
    )
  }
)

# ==============================================================================
# /docente/dimensoes/boxplot (compatível com Apex: y5)
# ==============================================================================
pr <- pr_get(
  pr, "/docente/dimensoes/boxplot",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus)
    curso  <- normalize_param(curso)
    dados  <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc

    cols_turma <- intersect(colsAvTurmaDoc,     names(dados))
    cols_acao  <- intersect(colsAcaoDocenteDoc, names(dados))
    cols_infra <- intersect(colsInfraDoc,       names(dados))

    v_turma <- if (length(cols_turma)) unlist(dados[, cols_turma, drop = FALSE], use.names = FALSE) else numeric(0)
    v_acao  <- if (length(cols_acao))  unlist(dados[, cols_acao,  drop = FALSE], use.names = FALSE) else numeric(0)
    v_infra <- if (length(cols_infra)) unlist(dados[, cols_infra, drop = FALSE], use.names = FALSE) else numeric(0)

    s_turma <- .calc_box_safe(v_turma)
    s_acao  <- .calc_box_safe(v_acao)
    s_infra <- .calc_box_safe(v_infra)

    boxplot_data <- data.frame(
      x = c("Avaliação da Turma", "Autoavaliação da Ação Docente", "Instalações Físicas"),
      y = I(list(
        round(s_turma$stats, 2),
        round(s_acao$stats,  2),
        round(s_infra$stats, 2)
      ))
    )

    outliers_data <- rbind(
      data.frame(x = "Avaliação da Turma",            y = round(.sample_out(s_turma$out, 200), 2)),
      data.frame(x = "Autoavaliação da Ação Docente", y = round(.sample_out(s_acao$out,  200), 2)),
      data.frame(x = "Instalações Físicas",           y = round(.sample_out(s_infra$out, 200), 2))
    )
    outliers_data <- outliers_data[is.finite(outliers_data$y), , drop = FALSE]

    list(boxplot_data  = boxplot_data, outliers_data = outliers_data)
  }
)

# -------------------------------
# ATIVIDADES (DOCENTE)
# -------------------------------
pr <- pr_get(
  pr, "/docente/atividades/percentual",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    if (!nrow(dados)) return(data.frame(atividade = character(), percentual = numeric()))

    intervalo <- dados %>% select(all_of(colsAtividadesDoc)) %>% mutate(across(everything(), as.character))
    intervalo[is.na(intervalo)] <- "0"; intervalo[intervalo == ""] <- "0"

    if ("4.1.1.P" %in% names(intervalo)) {
      intervalo$"4.1.1.P"[ intervalo$"4.1.1.P" != "0" & intervalo$"4.1.1.P" != "1" ] <- "1"
    }

    intervalo <- intervalo %>% mutate(across(everything(), as.numeric))
    cont <- colSums(intervalo == 1, na.rm = TRUE)

    data.frame(atividade = LETTERS[seq_along(cont)], percentual = (cont / nrow(dados))*100)
  }
)

# ==========================================================
# ENDPOINTS DOCENTE (Subdimensões) — compatibilidade dashboard atual
# (base discente)
# ==========================================================
pr <- pr_get(
  pr, "/docente/autoavaliacao/subdimensoes/proporcoes",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    cols_atp <- intersect(colsAtProfissional, names(dados))
    cols_ges <- intersect(colsGestaoDidatica, names(dados))
    cols_pro <- intersect(colsProcAvaliativo, names(dados))

    cont_atp <- if (length(cols_atp)) lapply(dados[, cols_atp, drop = FALSE], table) else list()
    cont_ges <- if (length(cols_ges)) lapply(dados[, cols_ges, drop = FALSE], table) else list()
    cont_pro <- if (length(cols_pro)) lapply(dados[, cols_pro, drop = FALSE], table) else list()

    df <- data.frame(
      subdimensao = rep(c("Atitude Profissional", "Gestão Didática", "Processo Avaliativo"), each = length(alternativas)),
      conceito    = rep(conceitos, times = 3),
      valor       = c(
        calculoPercent(alternativas, cont_atp),
        calculoPercent(alternativas, cont_ges),
        calculoPercent(alternativas, cont_pro)
      )
    )
    df$valor[is.nan(df$valor)] <- 0
    df
  }
)

pr <- pr_get(
  pr, "/docente/autoavaliacao/subdimensoes/medias",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    atp <- intersect(colsAtProfissional, names(dados))
    ges <- intersect(colsGestaoDidatica, names(dados))
    pro <- intersect(colsProcAvaliativo, names(dados))

    bloco_media <- function(cols, rotulo) {
      if (!length(cols)) return(NULL)
      b <- dados[, cols, drop = FALSE]
      b[] <- lapply(b, function(v) suppressWarnings(as.numeric(v)))
      tibble(subdimensao = rotulo, media = mean(unlist(b), na.rm = TRUE))
    }

    res <- list(
      bloco_media(atp, "Atitude Profissional"),
      bloco_media(ges, "Gestão Didática"),
      bloco_media(pro, "Processo Avaliativo")
    )
    res <- Filter(Negate(is.null), res)
    if (!length(res)) return(data.frame(subdimensao = character(), media = numeric()))
    bind_rows(res)
  }
)

# ==============================================================================
# /docente/autoavaliacao/subdimensoes/boxplot (base discente, y5 normalizado)
# ==============================================================================
pr <- pr_get(
  pr, "/docente/autoavaliacao/subdimensoes/boxplot",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados  <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    cols_21 <- intersect(paste0("mediap", 211:214), names(dados))
    cols_22 <- intersect(paste0("mediap", 221:228), names(dados))
    cols_23 <- intersect(paste0("mediap", 231:234), names(dados))

    v_21 <- if (length(cols_21)) .to_num_mediap(unlist(dados[, cols_21, drop = FALSE], use.names = FALSE)) else numeric(0)
    v_22 <- if (length(cols_22)) .to_num_mediap(unlist(dados[, cols_22, drop = FALSE], use.names = FALSE)) else numeric(0)
    v_23 <- if (length(cols_23)) .to_num_mediap(unlist(dados[, cols_23, drop = FALSE], use.names = FALSE)) else numeric(0)

    s_21 <- .calc_box_safe(v_21)
    s_22 <- .calc_box_safe(v_22)
    s_23 <- .calc_box_safe(v_23)

    boxplot_data <- data.frame(
      x = c("Atitude Profissional", "Gestão Didática", "Processo Avaliativo"),
      y = I(list(
        round(s_21$stats, 2),
        round(s_22$stats, 2),
        round(s_23$stats, 2)
      ))
    )

    outliers_data <- rbind(
      data.frame(x = "Atitude Profissional", y = round(.sample_out(s_21$out, 200), 2)),
      data.frame(x = "Gestão Didática",      y = round(.sample_out(s_22$out, 200), 2)),
      data.frame(x = "Processo Avaliativo",  y = round(.sample_out(s_23$out, 200), 2))
    )
    outliers_data <- outliers_data[is.finite(outliers_data$y), , drop = FALSE]

    list(boxplot_data = boxplot_data, outliers_data = outliers_data)
  }
)

# ==========================================================
# BASE DOCENTE — ITENS E SUBDIMENSÕES (usando base DOCENTE)
# ==========================================================

# Avaliação da Turma (DOCENTE) — Itens: médias e proporções
pr <- pr_get(
  pr, "/docente/avaliacaoturma/itens/medias",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    itens <- dados[, colsAvTurmaDoc, drop = FALSE]
    itens[] <- lapply(itens, function(v) suppressWarnings(as.numeric(v)))
    medias <- sapply(itens, function(col) mean(col, na.rm = TRUE))
    data.frame(item = .label_itens_auto(names(medias)), media = as.numeric(medias), stringsAsFactors = FALSE)
  }
)

pr <- pr_get(
  pr, "/docente/avaliacaoturma/itens/proporcoes",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    itens <- dados[, colsAvTurmaDoc, drop = FALSE]

    dados_longos <- itens %>%
      pivot_longer(everything(), names_to = "item", values_to = "valor") %>%
      filter(!is.na(valor)) %>%
      count(item, valor) %>%
      group_by(item) %>%
      mutate(total_item = sum(n), percentual = (n/total_item)*100) %>%
      ungroup()

    dados_longos %>%
      complete(item, valor = alternativas, fill = list(n = 0, total_item = 0, percentual = 0)) %>%
      mutate(item = .label_itens_auto(item), conceito = conceitos[as.numeric(valor)]) %>%
      select(item, conceito, valor = percentual)
  }
)

# Autoavaliação da Ação Docente (DOCENTE) — Subdimensões: médias e proporções
pr <- pr_get(
  pr, "/docente_base/autoavaliacao/subdimensoes/medias",
  function(campus = "all", curso = "all") {

    .assert_subdim_map_doc()
    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    names(dados) <- trimws(as.character(names(dados)))

    res <- lapply(names(subdim_map_doc), function(sd) {
      cols <- intersect(subdim_map_doc[[sd]], names(dados))
      if (!length(cols)) return(NULL)
      bloco <- dados[, cols, drop = FALSE]
      bloco[] <- lapply(bloco, function(v) suppressWarnings(as.numeric(v)))
      tibble(subdimensao = sd, media = mean(unlist(bloco), na.rm = TRUE))
    })

    res <- Filter(Negate(is.null), res)
    if (!length(res)) return(data.frame(subdimensao = character(), media = numeric()))
    bind_rows(res)
  }
)

pr <- pr_get(
  pr, "/docente_base/autoavaliacao/subdimensoes/proporcoes",
  function(campus = "all", curso = "all") {

    .assert_subdim_map_doc()
    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    names(dados) <- trimws(as.character(names(dados)))

    out_list <- list()
    for (sd in names(subdim_map_doc)) {
      cols <- intersect(subdim_map_doc[[sd]], names(dados))
      if (!length(cols)) next

      dl <- dados[, cols, drop = FALSE] %>%
        pivot_longer(everything(), names_to = "item", values_to = "valor") %>%
        filter(!is.na(valor))
      if (!nrow(dl)) next

      cont <- dl %>% count(valor) %>% mutate(total = sum(n), percentual = (n/total)*100)

      cont_comp <- tibble(valor = alternativas) %>%
        left_join(cont, by = "valor") %>%
        mutate(
          n = ifelse(is.na(n), 0, n),
          total = ifelse(is.na(total), 0, total),
          percentual = ifelse(is.na(percentual), 0, percentual),
          conceito = conceitos[as.numeric(valor)],
          subdimensao = sd
        ) %>%
        select(subdimensao, conceito, valor = percentual)

      out_list[[length(out_list)+1]] <- cont_comp
    }

    if (!length(out_list)) return(data.frame(subdimensao = character(), conceito = character(), valor = numeric()))
    bind_rows(out_list)
  }
)

# -------------------------------
# ATITUDE PROFISSIONAL (DOCENTE) — Itens: médias, proporções, boxplot
# -------------------------------
pr <- pr_get(
  pr, "/docente/atitudeprofissional/itens/medias",
  function(campus = "all", curso = "all") {

    .assert_subdim_map_doc()
    campus <- normalize_param(campus); curso <- normalize_param(curso)

    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    names(dados) <- trimws(as.character(names(dados)))

    cols <- intersect(subdim_map_doc[["Atitude Profissional"]], names(dados))
    if (!length(cols)) return(data.frame(item = character(), media = numeric()))

    itens <- dados[, cols, drop = FALSE]
    itens[] <- lapply(itens, function(v) suppressWarnings(as.numeric(v)))
    medias <- sapply(itens, function(col) mean(col, na.rm = TRUE))

    data.frame(item = .label_itens_any(names(medias)), media = as.numeric(medias), stringsAsFactors = FALSE)
  }
)

pr <- pr_get(
  pr, "/docente/atitudeprofissional/itens/proporcoes",
  function(campus = "all", curso = "all") {

    .assert_subdim_map_doc()
    campus <- normalize_param(campus); curso <- normalize_param(curso)

    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    names(dados) <- trimws(as.character(names(dados)))

    cols <- intersect(subdim_map_doc[["Atitude Profissional"]], names(dados))
    if (!length(cols)) return(data.frame(item = character(), conceito = character(), valor = numeric()))

    itens <- dados[, cols, drop = FALSE]
    dados_longos <- itens %>%
      pivot_longer(everything(), names_to = "item", values_to = "valor") %>%
      filter(!is.na(valor)) %>%
      count(item, valor) %>%
      group_by(item) %>%
      mutate(total_item = sum(n), percentual = (n/total_item)*100) %>%
      ungroup()

    dados_longos %>%
      complete(item, valor = alternativas, fill = list(n = 0, total_item = 0, percentual = 0)) %>%
      mutate(item = .label_itens_any(item), conceito = conceitos[as.numeric(valor)]) %>%
      select(item, conceito, valor = percentual)
  }
)

# /docente/atitudeprofissional/itens/boxplot (y5 normalizado)
pr <- pr_get(
  pr, "/docente/atitudeprofissional/itens/boxplot",
  function(campus = "all", curso = "all") {

    .assert_subdim_map_doc()
    campus <- normalize_param(campus); curso <- normalize_param(curso)

    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    if (!nrow(dados)) {
      return(list(
        boxplot_data  = data.frame(x = character(), y = I(list())),
        outliers_data = data.frame(x = character(), y = numeric())
      ))
    }

    names(dados) <- trimws(as.character(names(dados)))

    cols_sd <- intersect(subdim_map_doc[["Atitude Profissional"]], names(dados))
    if (!length(cols_sd)) cols_sd <- grep("^D21[1-4]$", names(dados), value = TRUE)
    if (!length(cols_sd)) {
      return(list(
        boxplot_data  = data.frame(x = character(), y = I(list())),
        outliers_data = data.frame(x = character(), y = numeric())
      ))
    }

    box_df_list <- list()
    out_df_list <- list()

    for (nm in cols_sd) {
      s <- .calc_box_safe(dados[[nm]])
      lbl <- .label_itens_any(nm)

      box_df_list[[length(box_df_list)+1]] <- data.frame(x = lbl, y = I(list(round(s$stats, 2))))

      outs <- round(.sample_out(s$out, max_out = 1500), 2)
      if (length(outs)) out_df_list[[length(out_df_list)+1]] <- data.frame(x = lbl, y = as.numeric(outs))
    }

    list(
      boxplot_data  = if (length(box_df_list)) do.call(rbind, box_df_list) else data.frame(x = character(), y = I(list())),
      outliers_data = if (length(out_df_list)) do.call(rbind, out_df_list) else data.frame(x = character(), y = numeric())
    )
  }
)

# ================================
# GESTÃO DIDÁTICA (DISCENTE) — médias/proporções
# ================================
pr <- pr_get(
  pr, "/discente/gestaodidatica/itens/medias",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    cols <- intersect(colsGestaoDidatica, names(dados))
    if (!length(cols)) return(data.frame(item = character(), media = numeric()))

    itens <- dados[, cols, drop = FALSE]
    itens[] <- lapply(itens, function(v) suppressWarnings(as.numeric(v)))
    medias <- sapply(itens, function(col) mean(col, na.rm = TRUE))

    data.frame(item = .label_itens_any(names(medias)), media = as.numeric(medias), stringsAsFactors = FALSE)
  }
)

pr <- pr_get(
  pr, "/discente/gestaodidatica/itens/proporcoes",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    cols <- intersect(colsGestaoDidatica, names(dados))
    if (!length(cols)) return(data.frame(item = character(), conceito = character(), valor = numeric()))

    itens <- dados[, cols, drop = FALSE]
    dados_longos <- itens %>%
      tidyr::pivot_longer(everything(), names_to = "item", values_to = "valor") %>%
      dplyr::filter(!is.na(valor)) %>%
      dplyr::count(item, valor) %>%
      dplyr::group_by(item) %>%
      dplyr::mutate(total_item = sum(n), percentual = (n / total_item) * 100) %>%
      dplyr::ungroup()

    dados_longos %>%
      tidyr::complete(item, valor = alternativas, fill = list(n = 0, total_item = 0, percentual = 0)) %>%
      dplyr::mutate(item = .label_itens_any(item), conceito = conceitos[as.numeric(valor)]) %>%
      dplyr::select(item, conceito, valor = percentual)
  }
)

# ================================
# GESTÃO DIDÁTICA (DOCENTE) — médias/proporções/boxplot
# ================================
pr <- pr_get(
  pr, "/docente/gestaodidatica/itens/medias",
  function(campus = "all", curso = "all") {

    .assert_subdim_map_doc()
    campus <- normalize_param(campus); curso <- normalize_param(curso)

    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    names(dados) <- trimws(as.character(names(dados)))

    cols <- intersect(subdim_map_doc[["Gestão Didática"]], names(dados))
    if (!length(cols)) return(data.frame(item = character(), media = numeric()))

    itens <- dados[, cols, drop = FALSE]
    itens[] <- lapply(itens, function(v) suppressWarnings(as.numeric(v)))
    medias <- sapply(itens, function(col) mean(col, na.rm = TRUE))

    data.frame(item = .label_itens_any(names(medias)), media = as.numeric(medias), stringsAsFactors = FALSE)
  }
)

pr <- pr_get(
  pr, "/docente/gestaodidatica/itens/proporcoes",
  function(campus = "all", curso = "all") {

    .assert_subdim_map_doc()
    campus <- normalize_param(campus); curso <- normalize_param(curso)

    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    names(dados) <- trimws(as.character(names(dados)))

    cols <- intersect(subdim_map_doc[["Gestão Didática"]], names(dados))
    if (!length(cols)) return(data.frame(item = character(), conceito = character(), valor = numeric()))

    itens <- dados[, cols, drop = FALSE]
    dados_longos <- itens %>%
      tidyr::pivot_longer(everything(), names_to = "item", values_to = "valor") %>%
      dplyr::filter(!is.na(valor)) %>%
      dplyr::count(item, valor) %>%
      dplyr::group_by(item) %>%
      dplyr::mutate(total_item = sum(n), percentual = (n / total_item) * 100) %>%
      dplyr::ungroup()

    dados_longos %>%
      tidyr::complete(item, valor = alternativas, fill = list(n = 0, total_item = 0, percentual = 0)) %>%
      dplyr::mutate(item = .label_itens_any(item), conceito = conceitos[as.numeric(valor)]) %>%
      dplyr::select(item, conceito, valor = percentual)
  }
)

pr <- pr_get(
  pr, "/docente/gestaodidatica/itens/boxplot",
  function(campus = "all", curso = "all") {

    .assert_subdim_map_doc()
    campus <- normalize_param(campus); curso <- normalize_param(curso)

    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    if (!nrow(dados)) {
      return(list(
        boxplot_data  = data.frame(x = character(), y = I(list())),
        outliers_data = data.frame(x = character(), y = numeric())
      ))
    }

    names(dados) <- trimws(as.character(names(dados)))

    cols <- intersect(subdim_map_doc[["Gestão Didática"]], names(dados))
    if (!length(cols)) {
      return(list(
        boxplot_data  = data.frame(x = character(), y = I(list())),
        outliers_data = data.frame(x = character(), y = numeric())
      ))
    }

    box_df_list <- list()
    out_df_list <- list()

    for (nm in cols) {
      s <- .calc_box_safe(dados[[nm]])
      lbl <- .label_itens_any(nm)

      box_df_list[[length(box_df_list)+1]] <- data.frame(x = lbl, y = I(list(round(s$stats, 2))))

      outs <- round(.sample_out(s$out, max_out = 1500), 2)
      if (length(outs)) out_df_list[[length(out_df_list)+1]] <- data.frame(x = lbl, y = as.numeric(outs))
    }

    list(
      boxplot_data  = if (length(box_df_list)) do.call(rbind, box_df_list) else data.frame(x = character(), y = I(list())),
      outliers_data = if (length(out_df_list)) do.call(rbind, out_df_list) else data.frame(x = character(), y = numeric())
    )
  }
)

# ==============================================================================
# /discente/gestaodidatica/itens/boxplot (mediap221..228)
# - tabela_items (stats6) + boxplot_data (y5) + outliers
# ==============================================================================
pr <- pr_get(
  pr, "/discente/gestaodidatica/itens/boxplot",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus)
    curso  <- normalize_param(curso)

    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc
    cols  <- intersect(paste0("mediap", 221:228), names(dados))

    box_df_list <- list()
    out_df_list <- list()
    tab_df_list <- list()

    for (nm in cols) {
      v <- .to_num_mediap(dados[[nm]])
      v <- v[is.finite(v)]
      if (!length(v)) next

      s6 <- .calc_stats6_pdf(v)
      y5 <- .normalize_box_stats(c(s6[1], s6[2], s6[3], s6[5], s6[6]))
      lbl <- .label_itens_media(nm)

      tab_df_list[[length(tab_df_list)+1]] <- data.frame(
        item = lbl,
        Min = round(s6[1],2),
        Q1  = round(s6[2],2),
        Mediana = round(s6[3],2),
        Media   = round(s6[4],2),
        Q3  = round(s6[5],2),
        Max = round(s6[6],2),
        stringsAsFactors = FALSE
      )

      box_df_list[[length(box_df_list)+1]] <- data.frame(x = lbl, y = I(list(round(y5,2))))

      st <- .calc_box_safe(v)
      outs <- round(.sample_out(st$out, max_out = 1500), 2)
      if (length(outs)) out_df_list[[length(out_df_list)+1]] <- data.frame(x = lbl, y = as.numeric(outs))
    }

    list(
      tabela_items  = if (length(tab_df_list)) do.call(rbind, tab_df_list) else data.frame(),
      boxplot_data  = if (length(box_df_list)) do.call(rbind, box_df_list) else data.frame(x = character(), y = I(list())),
      outliers_data = if (length(out_df_list)) do.call(rbind, out_df_list) else data.frame(x = character(), y = numeric())
    )
  }
)

# ================================
# PROCESSO AVALIATIVO (DISCENTE) — médias/proporções
# ================================
pr <- pr_get(
  pr, "/discente/processoavaliativo/itens/medias",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados  <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    cols <- intersect(colsProcAvaliativo, names(dados))
    if (!length(cols)) return(data.frame(item = character(), media = numeric()))

    itens <- dados[, cols, drop = FALSE]
    itens[] <- lapply(itens, function(v) suppressWarnings(as.numeric(v)))
    medias <- sapply(itens, function(col) mean(col, na.rm = TRUE))

    data.frame(item = .label_itens_any(names(medias)), media = as.numeric(medias), stringsAsFactors = FALSE)
  }
)

pr <- pr_get(
  pr, "/discente/processoavaliativo/itens/proporcoes",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados  <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    cols <- intersect(colsProcAvaliativo, names(dados))
    if (!length(cols)) return(data.frame(item = character(), conceito = character(), valor = numeric()))

    itens <- dados[, cols, drop = FALSE]
    dados_longos <- itens %>%
      tidyr::pivot_longer(everything(), names_to = "item", values_to = "valor") %>%
      dplyr::filter(!is.na(valor)) %>%
      dplyr::count(item, valor) %>%
      dplyr::group_by(item) %>%
      dplyr::mutate(total_item = sum(n), percentual = (n / total_item) * 100) %>%
      dplyr::ungroup()

    dados_longos %>%
      tidyr::complete(item, valor = alternativas, fill = list(n = 0, total_item = 0, percentual = 0)) %>%
      dplyr::mutate(item = .label_itens_any(item), conceito = conceitos[as.numeric(valor)]) %>%
      dplyr::select(item, conceito, valor = percentual)
  }
)

# ==============================================================================
# /discente/processoavaliativo/itens/boxplot (mediap231..234)
# ==============================================================================
pr <- pr_get(
  pr, "/discente/processoavaliativo/itens/boxplot",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus)
    curso  <- normalize_param(curso)

    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc
    cols  <- intersect(paste0("mediap", 231:234), names(dados))

    box_df_list <- list()
    out_df_list <- list()
    tab_df_list <- list()

    for (nm in cols) {
      v <- .to_num_mediap(dados[[nm]])
      v <- v[is.finite(v)]
      if (!length(v)) next

      s6 <- .calc_stats6_pdf(v)
      y5 <- .normalize_box_stats(c(s6[1], s6[2], s6[3], s6[5], s6[6]))
      lbl <- .label_itens_media(nm)

      tab_df_list[[length(tab_df_list)+1]] <- data.frame(
        item = lbl,
        Min = round(s6[1],2),
        Q1  = round(s6[2],2),
        Mediana = round(s6[3],2),
        Media   = round(s6[4],2),
        Q3  = round(s6[5],2),
        Max = round(s6[6],2),
        stringsAsFactors = FALSE
      )

      box_df_list[[length(box_df_list)+1]] <- data.frame(x = lbl, y = I(list(round(y5,2))))

      st <- .calc_box_safe(v)
      outs <- round(.sample_out(st$out, max_out = 1500), 2)
      if (length(outs)) out_df_list[[length(out_df_list)+1]] <- data.frame(x = lbl, y = as.numeric(outs))
    }

    list(
      tabela_items  = if (length(tab_df_list)) do.call(rbind, tab_df_list) else data.frame(),
      boxplot_data  = if (length(box_df_list)) do.call(rbind, box_df_list) else data.frame(x = character(), y = I(list())),
      outliers_data = if (length(out_df_list)) do.call(rbind, out_df_list) else data.frame(x = character(), y = numeric())
    )
  }
)

# ================================
# PROCESSO AVALIATIVO (DOCENTE) — médias/proporções
# ================================
pr <- pr_get(
  pr, "/docente/processoavaliativo/itens/medias",
  function(campus = "all", curso = "all") {

    .assert_subdim_map_doc()
    campus <- normalize_param(campus); curso <- normalize_param(curso)

    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    names(dados) <- trimws(as.character(names(dados)))

    cols <- intersect(subdim_map_doc[["Processo Avaliativo"]], names(dados))
    if (!length(cols)) return(data.frame(item = character(), media = numeric()))

    itens <- dados[, cols, drop = FALSE]
    itens[] <- lapply(itens, function(v) suppressWarnings(as.numeric(v)))
    medias <- sapply(itens, function(col) mean(col, na.rm = TRUE))

    data.frame(item = .label_itens_any(names(medias)), media = as.numeric(medias), stringsAsFactors = FALSE)
  }
)

pr <- pr_get(
  pr, "/docente/processoavaliativo/itens/proporcoes",
  function(campus = "all", curso = "all") {

    .assert_subdim_map_doc()
    campus <- normalize_param(campus); curso <- normalize_param(curso)

    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc
    names(dados) <- trimws(as.character(names(dados)))

    cols <- intersect(subdim_map_doc[["Processo Avaliativo"]], names(dados))
    if (!length(cols)) return(data.frame(item = character(), conceito = character(), valor = numeric()))

    itens <- dados[, cols, drop = FALSE]
    dados_longos <- itens %>%
      tidyr::pivot_longer(everything(), names_to = "item", values_to = "valor") %>%
      dplyr::filter(!is.na(valor)) %>%
      dplyr::count(item, valor) %>%
      dplyr::group_by(item) %>%
      dplyr::mutate(total_item = sum(n), percentual = (n / total_item) * 100) %>%
      dplyr::ungroup()

    dados_longos %>%
      tidyr::complete(item, valor = alternativas, fill = list(n = 0, total_item = 0, percentual = 0)) %>%
      dplyr::mutate(item = .label_itens_any(item), conceito = conceitos[as.numeric(valor)]) %>%
      dplyr::select(item, conceito, valor = percentual)
  }
)

# ================================
# INSTALAÇÕES FÍSICAS (DISCENTE) — médias/proporções/boxplot
# ================================
pr <- pr_get(
  pr, "/discente/instalacoes/itens/medias",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados  <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    cols <- intersect(colsInfra, names(dados))
    if (!length(cols)) return(data.frame(item = character(), media = numeric()))

    itens <- dados[, cols, drop = FALSE]
    itens[] <- lapply(itens, function(v) suppressWarnings(as.numeric(v)))
    medias <- sapply(itens, function(col) mean(col, na.rm = TRUE))

    data.frame(item = .label_itens_any(names(medias)), media = as.numeric(medias), stringsAsFactors = FALSE)
  }
)

pr <- pr_get(
  pr, "/discente/instalacoes/itens/proporcoes",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados  <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc

    cols <- intersect(colsInfra, names(dados))
    if (!length(cols)) return(data.frame(item = character(), conceito = character(), valor = numeric()))

    itens <- dados[, cols, drop = FALSE]
    dados_longos <- itens %>%
      tidyr::pivot_longer(everything(), names_to = "item", values_to = "valor") %>%
      dplyr::filter(!is.na(valor)) %>%
      dplyr::count(item, valor) %>%
      dplyr::group_by(item) %>%
      dplyr::mutate(total_item = sum(n), percentual = (n / total_item) * 100) %>%
      dplyr::ungroup()

    dados_longos %>%
      tidyr::complete(item, valor = alternativas, fill = list(n = 0, total_item = 0, percentual = 0)) %>%
      dplyr::mutate(item = .label_itens_any(item), conceito = conceitos[as.numeric(valor)]) %>%
      dplyr::select(item, conceito, valor = percentual)
  }
)

pr <- pr_get(
  pr, "/discente/instalacoes/itens/boxplot",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus)
    curso  <- normalize_param(curso)

    dados <- filter_data(base_discente_global, base_docente_global, campus, curso)$disc
    cols  <- intersect(paste0("mediap", 311:314), names(dados))

    box_df_list <- list()
    out_df_list <- list()
    tab_df_list <- list()

    for (nm in cols) {
      v <- .to_num_mediap(dados[[nm]])
      v <- v[is.finite(v)]
      if (!length(v)) next

      s6 <- .calc_stats6_pdf(v)
      y5 <- .normalize_box_stats(c(s6[1], s6[2], s6[3], s6[5], s6[6]))
      lbl <- .label_itens_media(nm)

      tab_df_list[[length(tab_df_list)+1]] <- data.frame(
        item = lbl,
        Min = round(s6[1],2),
        Q1  = round(s6[2],2),
        Mediana = round(s6[3],2),
        Media   = round(s6[4],2),
        Q3  = round(s6[5],2),
        Max = round(s6[6],2),
        stringsAsFactors = FALSE
      )

      box_df_list[[length(box_df_list)+1]] <- data.frame(x = lbl, y = I(list(round(y5,2))))

      st <- .calc_box_safe(v)
      outs <- round(.sample_out(st$out, max_out = 1500), 2)
      if (length(outs)) out_df_list[[length(out_df_list)+1]] <- data.frame(x = lbl, y = as.numeric(outs))
    }

    list(
      tabela_items  = if (length(tab_df_list)) do.call(rbind, tab_df_list) else data.frame(),
      boxplot_data  = if (length(box_df_list)) do.call(rbind, box_df_list) else data.frame(x = character(), y = I(list())),
      outliers_data = if (length(out_df_list)) do.call(rbind, out_df_list) else data.frame(x = character(), y = numeric())
    )
  }
)

# ================================
# INSTALAÇÕES FÍSICAS (DOCENTE) — médias/proporções
# ================================
pr <- pr_get(
  pr, "/docente/instalacoes/itens/medias",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados  <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc

    cols <- intersect(colsInfraDoc, names(dados))
    if (!length(cols)) return(data.frame(item = character(), media = numeric()))

    itens <- dados[, cols, drop = FALSE]
    itens[] <- lapply(itens, function(v) suppressWarnings(as.numeric(v)))
    medias <- sapply(itens, function(col) mean(col, na.rm = TRUE))

    data.frame(item = .label_itens_any(names(medias)), media = as.numeric(medias), stringsAsFactors = FALSE)
  }
)

pr <- pr_get(
  pr, "/docente/instalacoes/itens/proporcoes",
  function(campus = "all", curso = "all") {

    campus <- normalize_param(campus); curso <- normalize_param(curso)
    dados  <- filter_data(base_discente_global, base_docente_global, campus, curso)$doc

    cols <- intersect(colsInfraDoc, names(dados))
    if (!length(cols)) return(data.frame(item = character(), conceito = character(), valor = numeric()))

    itens <- dados[, cols, drop = FALSE]
    dados_longos <- itens %>%
      tidyr::pivot_longer(everything(), names_to = "item", values_to = "valor") %>%
      dplyr::filter(!is.na(valor)) %>%
      dplyr::count(item, valor) %>%
      dplyr::group_by(item) %>%
      dplyr::mutate(total_item = sum(n), percentual = (n / total_item) * 100) %>%
      dplyr::ungroup()

    dados_longos %>%
      tidyr::complete(item, valor = alternativas, fill = list(n = 0, total_item = 0, percentual = 0)) %>%
      dplyr::mutate(item = .label_itens_any(item), conceito = conceitos[as.numeric(valor)]) %>%
      dplyr::select(item, conceito, valor = percentual)
  }
)

# --- 6. Iniciar o Servidor -------------------------------------------
pr$run(host = HOST, port = PORT)

# nolint end
