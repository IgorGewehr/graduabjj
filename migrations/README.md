# Migração graduabjj → Tatami

Plano de migração do app Flutter `graduabjj` para o novo backend Go/Postgres (`tatami`).

## Os 9 documentos

### Estratégia (por quê + o quê)
1. **[`01_LOGICA_DELEGADA_AO_FRONTEND.md`](01_LOGICA_DELEGADA_AO_FRONTEND.md)** — 15 peças de lógica de negócio que o cliente executa hoje e que precisam ir para o backend. Classificadas por risco.
2. **[`02_MAPEAMENTO_ENDPOINTS_NOVO_BACKEND.md`](02_MAPEAMENTO_ENDPOINTS_NOVO_BACKEND.md)** — mapa exaustivo `Service.method() → endpoint REST`. Plano faseado de release.
3. **[`03_OTIMIZACOES_GERAIS_APP.md`](03_OTIMIZACOES_GERAIS_APP.md)** — 15 melhorias que o novo backend destrava, matriz esforço × impacto.
4. **[`04_MULTI_ACADEMIA_E_EQUIPE.md`](04_MULTI_ACADEMIA_E_EQUIPE.md)** — audit dos subsistemas multi-academia + equipe; lacunas conceituais que o backend ainda precisa cobrir.

### Execução (como + quando)
5. **[`05_MIGRACAO_DE_DADOS.md`](05_MIGRACAO_DE_DADOS.md)** — **doc mais crítico**. Inventário Firestore, mapeamento campo-a-campo, ETL via BigQuery, validação, cutover, rollback.
6. **[`06_PLANO_FASEADO_DETALHADO.md`](06_PLANO_FASEADO_DETALHADO.md)** — 9 fases (0 a 8) com pré-requisitos, mudanças BE+FE+dados, plano de teste, **exit criteria**, rollback, esforço.
7. **[`07_RISCOS_E_ROLLBACK.md`](07_RISCOS_E_ROLLBACK.md)** — risk register (20 riscos categorizados), decision tree para incidentes, procedimentos de rollback por fase, drill trimestral.

### Daily work (durante o desenvolvimento)
8. **[`08_RECEITUARIO_FRONTEND.md`](08_RECEITUARIO_FRONTEND.md)** — 17 receitas before/after copy-paste: cliente HTTP, erro tipado, idempotency, paginação, optimistic update, upload 2-step, polling com ETag, etc.
9. **[`09_GLOSSARIO_E_CONVENCOES.md`](09_GLOSSARIO_E_CONVENCOES.md)** — vocabulário PT↔EN canônico, naming (SQL/OpenAPI/Go/Dart), convenções de datas/dinheiro/erros/status/commits/logs/testes/feature-flags. Árbitro em PRs.

## Ordem sugerida de leitura

- **Tech lead / arquiteto:** 01 → 04 → 05 → 06 → 07 → 02 → 03 → 09 → 08
- **Desenvolvedor backend:** 09 → 02 → 05 → 06 → 07 → 04 → 01
- **Desenvolvedor frontend:** 09 → 08 → 02 → 06 → 03 → 01
- **SRE / DBA:** 05 → 07 → 09 → 06
- **Product / suporte:** 01 → 04 → 06 (especialmente §"Tabela de resumo") → 07 (§"Comunicação em incidente")

## Quando consultar cada um

- "Como faço X no app?" → **08**
- "Como chamo este endpoint?" → **02**
- "Como nomeio este campo / o que ele significa?" → **09**
- "Em que fase devo entrar nisso?" → **06**
- "Como migro estes dados do Firestore?" → **05**
- "O que pode dar errado e como reverto?" → **07**
- "Por que precisamos migrar?" → **01** + **03**
- "Como tratar usuários multi-academia / guardian com múltiplos filhos?" → **04**

## Premissas

- Backend Tatami vivo em `https://api.tatami.dev` (ou equivalente staging).
- Firebase Auth continua sendo o IdP — não migramos identidade.
- Firebase Storage pode continuar transitório até a Fase 7 da migração (vide §13 do doc 02).
- Cada fase é um release de loja. O Tatami suporta convivência: ler do Tatami + escrever no Firestore funciona durante a transição (só não fica bonito).
