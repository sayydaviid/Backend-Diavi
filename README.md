---
title: AVALIA Backend (Plumber R)
emoji: 🧪
colorFrom: indigo
colorTo: blue
sdk: docker
app_port: 8000
pinned: false
---

API em R (Plumber) para o dashboard AVALIA.

## Como usar
- Healthcheck: `/health`
- Filtros: `/filters`
- Exemplos:
  - `/discente/geral/summary?campus=all&curso=all`

> Este Space usa **Dockerfile** e sobe o servidor em `0.0.0.0:$PORT`.
