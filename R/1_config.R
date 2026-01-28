# ===================================================================
# ARQUIVO DE CONFIGURAÇÃO GLOBAL
# -------------------------------------------------------------------
# Este arquivo centraliza todas as variáveis que podem mudar,
# como nomes de arquivos, nomes de colunas e parâmetros fixos.
# Isso torna a manutenção do código muito mais fácil.
# ===================================================================


# --- 1. Caminhos de Arquivos e Planilhas ---

dataSource      <- "databases/avalia_2024.xlsx"
sheetDiscente   <- "D_DISC_2024-2"
sheetDocente    <- "D_DOC_2024-2"


# --- 2. Parâmetros Gerais da Avaliação ---

# Alternativas de resposta possíveis nos dados
alternativas <- c(1, 2, 3, 4)

# Legenda correspondente às alternativas
conceitos <- c("Insuficiente", "Regular", "Bom", "Excelente")

# Ordem dos conceitos para exibição nos gráficos de contagem
conceitos_ordem_grafico <- c("Excelente", "Bom", "Regular", "Insuficiente")


# --- 3. Mapeamento de Colunas (Base DISCENTE) ---
# Nomes das colunas na planilha Excel para cada dimensão discente

# Dimensão: Autoavaliação Discente
colsAutoAvDisc <- c("P111", "P112", "P113", "P114", "P115", "P116", "P117")

# Dimensão: Ação Docente (todas as subdimensões juntas)
colsAcaoDocente <- c("P211","P212","P213","P214","P221","P222","P223","P224","P225","P226","P227","P228","P231","P232","P233","P234")

# Dimensão: Instalações Físicas
colsInfra <- c("P311",  "P312", "P313", "P314")

# Subdimensão: Atitude Profissional (parte da Ação Docente)
colsAtProfissional <- c("P211","P212","P213","P214")

# Subdimensão: Gestão Didático-Pedagógica (parte da Ação Docente)
colsGestaoDidatica <- c("P221","P222","P223","P224","P225","P226","P227","P228")

# Subdimensão: Processo Avaliativo (parte da Ação Docente)
colsProcAvaliativo <- c("P231","P232","P233","P234")

# Colunas de Atividades Acadêmicas
# Gera automaticamente "4.1.1.A", "4.1.1.B", ..., "4.1.1.R"
colsAtividadesDisc <- paste0("4.1.1.", LETTERS[1:18])


# --- 4. Mapeamento de Colunas (Base DOCENTE) ---
# Nomes das colunas na planilha Excel para cada dimensão docente

# Dimensão: Avaliação da Turma
colsAvTurmaDoc <- as.character(111:117)

# Dimensão: Autoavaliação da Ação Docente (todas as subdimensões)
colsAcaoDocenteDoc <- as.character(c(211:214, 221:228, 231:234))

# Dimensão: Instalações Físicas
colsInfraDoc <- as.character(311:314)

# Subdimensão: Atitude Profissional (parte da Autoavaliação Docente)
colsAtProfissionalDoc <- as.character(211:214)

# Subdimensão: Gestão Didático-Pedagógica (parte da Autoavaliação Docente)
colsGestaoDidaticaDoc <- as.character(221:228)

# Subdimensão: Processo Avaliativo (parte da Autoavaliação Docente)
colsProcAvaliativoDoc <- as.character(231:234)

# Colunas de Atividades Acadêmicas
# Gera automaticamente "4.1.1.A", "4.1.1.B", ..., "4.1.1.P"
colsAtividadesDoc <- paste0("4.1.1.", LETTERS[1:16])

# -------------------------------------------------------------------
# Subdimensões da Autoavaliação Docente (usadas pelos endpoints /docente/autoavaliacao/subdimensoes/*)
# Mapeie cada subdimensão para o vetor de colunas correspondentes.
# Aqui reaproveitamos os vetores já definidos acima.
# -------------------------------------------------------------------
# PARA:
subdim_map_doc <- list(
  "Atitude Profissional"          = colsAtProfissionalDoc,
  "Gestão Didática"               = colsGestaoDidaticaDoc, # <- Mudei aqui
  "Processo Avaliativo"           = colsProcAvaliativoDoc
)