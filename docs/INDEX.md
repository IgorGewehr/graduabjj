# Índice da documentação — GraduaBJJ

Mapa de toda a documentação do repo: o que existe, onde vive e quando ler.
Atualizado em 2026-07-21 numa faxina de limpeza — docs obsoletos foram
arquivados (nunca deletados) e docs defasados tiveram o status corrigido no
topo do próprio arquivo. Esta faxina não tocou em código, só em `.md`.

> **Regra geral:** se um doc tem um header "**Status de execução**"/"**Status
> (2026-07)**"/"**Arquivado**" no topo, confie nele mais do que no corpo do
> texto — o corpo pode ter sido escrito antes da feature existir.

---

## 1. Convenções do repo (comece aqui)

| Arquivo | O que traz |
|---|---|
| [`docs/arquitetura/README.md`](arquitetura/README.md) | Auditoria e plano geral de modernização: fronteiras Flutter/Functions, decomposição dos maiores arquivos, dados/Rules, performance, testes, CI, roadmap e Definition of Done. |
| [`docs/arquitetura-pagamentos/README.md`](arquitetura-pagamentos/README.md) | Plano completo para links de pagamento sem login, modularização do Flutter/Firebase Functions, segurança, rollout, testes e Definition of Done. |
| [`/CLAUDE.md`](../CLAUDE.md) | Guia de convenções para qualquer dev/agente no repo — branches, estrutura de pastas, padrões vivos. Extraído do código real. |
| [`docs/guias/BUILD_WINDOWS.md`](guias/BUILD_WINDOWS.md) | Pipeline de build do app Windows de balcão (GitHub Actions) + camada de compatibilidade mobile/desktop. |
| [`docs/guias/CATRACAS.md`](guias/CATRACAS.md) | Integração com catracas por fabricante (Control iD/ZKTeco/Intelbras). |
| [`docs/guias/CATRACA_GATEWAY.md`](guias/CATRACA_GATEWAY.md) | Ponte Windows (`catraca-gateway`, projeto irmão fora deste repo) entre a catraca local e a Cloud Function na nuvem. |

> **⚠️ Achado desta faxina, não corrigido (fora do meu escopo tocar nesses 3 arquivos):**
> `docs/guias/CATRACAS.md` (linha 3-8) afirma que `ingestAccessEvent`
> "**não foi deployada** e **não está apontada por nenhuma catraca real em
> produção**", enquanto `docs/guias/CATRACA_GATEWAY.md` (linha 8) diz, na
> mesma frase, que é "a Cloud Function `ingestAccessEvent` **já deployada em
> produção**". Os dois docs se contradizem. O fato verificado nesta faxina
> (ver `functions/access_control/README.md` abaixo) é que a função **está
> deployada e em piloto real** (Control iD Face, modo Online) — `CATRACAS.md`
> parece ter ficado com uma frase antiga. Vale um ajuste de quem mantém
> `docs/guias/`.

---

## 2. Referências técnicas vivas (mantidas atualizadas nesta faxina)

| Arquivo | O que traz |
|---|---|
| [`functions/access_control/README.md`](../functions/access_control/README.md) | Arquitetura da ingestão de catracas (push-cloud), modelo de dados `devices/{id}`, segurança/idempotência, check-in por turma real + bloqueio por inadimplência. **Status: deployada em produção**, piloto Control iD; ZKTeco/Intelbras prontos aguardando field-confirm. |
| [`docs/WINDOWS.md`](WINDOWS.md) | Como rodar/compilar o app GraduaBJJ no Windows (balcão de recepção); o que muda vs. mobile. |
| [`docs/PAGAMENTOS_MP.md`](PAGAMENTOS_MP.md) | Como o fluxo de pagamentos Mercado Pago funciona hoje, ponta a ponta. |
| [`docs/recorrencia-mp-contract.md`](recorrencia-mp-contract.md) | Contrato de dados da assinatura recorrente MP (campos, crons de reconciliação/dunning). |

---

## 3. Specs de feature (a maioria já implementada — headers dizem o status)

Docs de planejamento de features que hoje descrevem, na prática, o que **já
foi construído** — mantidos como especificação de referência do
comportamento real. Cada um ganhou um header "Status (2026-07)" apontando os
arquivos de código correspondentes.

| Arquivo | Feature | Status |
|---|---|---|
| [`plano-avaliacao-fisica.md`](plano-avaliacao-fisica.md) | Avaliação física / antropometria | Implementado |
| [`plano-musculacao.md`](plano-musculacao.md) | Modalidade musculação (sem graduação, check-in flexível) | Implementado |
| [`plano-musculacao-e1e2.md`](plano-musculacao-e1e2.md) | Periodização de mesociclo + calculadora de 1RM | Implementado |
| [`plano-treino-execucao.md`](plano-treino-execucao.md) | Registro de execução de treino + biblioteca de exercícios | Implementado |
| [`plano-graduacao-pedagogica.md`](plano-graduacao-pedagogica.md) | Currículo por faixa + progresso de skill | Implementado |
| [`plano-reserva-aula.md`](plano-reserva-aula.md) | Reserva de aula + lista de espera | Implementado |
| [`plano-trocacao.md`](plano-trocacao.md) | Módulo de trocação (timer, combos, cartel) | Implementado |
| [`plano-gamificacao-a4.md`](plano-gamificacao-a4.md) | Meta mensal de presença + surfacing na home | Implementado |
| [`roadmap-modalidades.md`](roadmap-modalidades.md) | Checklist mestre de todos os itens acima (A1-F3) | Todos os itens `[x]` já mergeados/deployados em `firebase-production` |
| [`roadmap-paywall.md`](roadmap-paywall.md) | Paywall/assinatura (migração Cakto→Mercado Pago) | Implementado — o próprio doc já documenta a migração |
| [`aula-particular-turmas.md`](aula-particular-turmas.md) | (A) Aula particular 1:1 com presença automática · (B) "Adicionar Todos" + filtros nas turmas | **A: implementado.** **B: ainda NÃO implementado** — este doc continua sendo o blueprint válido para B. |
| [`competicoes-reformulacao.md`](competicoes-reformulacao.md) | Redesign "Liga & Arena" de Competições (temporadas/XP, cards) | **NÃO implementado** — o módulo de Competições atual é o básico que este doc critica. Blueprint ainda válido/não iniciado. |

### Runbooks de teste manual (QA)

Ainda válidos — as features e telas que descrevem continuam existindo no app:
[`ROTEIRO_TESTES_POS_MERGE_UX_COBRANCAS.md`](ROTEIRO_TESTES_POS_MERGE_UX_COBRANCAS.md) ·
[`ROTEIRO_TESTES_COBRANCAS_META_PIX.md`](ROTEIRO_TESTES_COBRANCAS_META_PIX.md) ·
[`roteiro-teste-completo.md`](roteiro-teste-completo.md) ·
[`roteiro-teste-avaliacao-fisica.md`](roteiro-teste-avaliacao-fisica.md) ·
[`roteiro-teste-graduacao-pedagogica.md`](roteiro-teste-graduacao-pedagogica.md) ·
[`roteiro-teste-musculacao.md`](roteiro-teste-musculacao.md) ·
[`roteiro-teste-treino-execucao.md`](roteiro-teste-treino-execucao.md)

---

## 4. Trabalho ativo nesta branch (`ux-ativacao`) — não mexer

Escritos/editados hoje (2026-07-21) ou nos últimos dias como parte do
trabalho corrente. Não são histórico, são a frente de trabalho viva:

| Arquivo | O que traz |
|---|---|
| [`ANTI_HIDRA_2026-07.md`](ANTI_HIDRA_2026-07.md) | Auditoria de dívida estrutural (god-files, hardcode de esporte, zero CI de teste) + roadmap de refatoração faseado. |
| [`ux/SPEC_ONBOARDING_2026-07.md`](ux/SPEC_ONBOARDING_2026-07.md) | Spec fechando gaps de onboarding (wizard, aha de ativação de cobrança, perfil fitness-aware). |
| [`ux/ARQUITETURA_CHECKIN_DIARIO_2026-07.md`](ux/ARQUITETURA_CHECKIN_DIARIO_2026-07.md) | Generalização do check-in diário (hoje só musculação) para perfis luta/fitness/híbrido. |
| [`ux/NOTAS_FINANCEIRO_2026-07.md`](ux/NOTAS_FINANCEIRO_2026-07.md) | Feedback de UX do dono sobre telas de Financeiro/Cobrança/Dashboard. |
| [`b2c/ATIVACAO_PROFESSOR_2026-07.md`](b2c/ATIVACAO_PROFESSOR_2026-07.md) | Ativação do professor (chamada vazia, turmas, CSV, cobrança por WhatsApp). |
| [`b2c/DIAGNOSTICO_RETENCAO_2026-07.md`](b2c/DIAGNOSTICO_RETENCAO_2026-07.md) | Diagnóstico de causas-raiz de retenção fraca (push, self-log, grafo social). |

---

## 5. `docs/b2c/` — estratégia do app do lutador (B2C)

Pasta com índice próprio: **[`b2c/README.md`](b2c/README.md)** — leia-o
primeiro, ele explica a ordem de leitura (síntese → pesquisa → planos de
feature) e o status de execução de cada doc (a maioria da Fase 1-2 já está em
produção; ver headers "Status de execução" em cada arquivo). Não duplicado
aqui para não divergir de novo.

---

## 6. `docs/arquivo/` — histórico (nunca deletar)

Relatórios de auditoria/revisão/validação pontuais e planos já superados por
implementação ou por um design diferente do que foi construído. Preservados
por valor histórico — **nunca apague**, mesmo que pareçam redundantes com o
que está vivo hoje.

**Pagamentos / Mercado Pago** — achados críticos confirmados corrigidos no
código atual (ver `docs/PAGAMENTOS_MP.md`/`docs/recorrencia-mp-contract.md`
para o estado vivo):
`AUDITORIA_MERCADO_PAGO_2026-06.md` · `AUDITORIA_MP_RECURSIVA_2026-06.md` ·
`AUDITORIA_FIXES_2026-06.md` · `VALIDACAO_PAGAMENTOS_MP_E2E_2026-06.md` ·
`financeiro-recorrencia.md` (blueprint pré-implementação da recorrência,
já construída)

**Auditoria geral do sistema** — o achado CRÍTICO (account takeover via
`firestore.rules`) foi corrigido (commit `1ddf1e7`, verificado no
`firestore.rules` atual):
`AUDITORIA_SISTEMA_2026-06.md` · `PRODUCTION_READINESS_2026-06.md`

**Revisões/validações de módulo (2026-06)** — achados pontuais, alguns
confirmados corrigidos (perfil do aluno — leak de PII crítico, corrigido),
outros não reverificados nesta faxina:
`REVISAO_CAMPEONATOS_2026-06.md` · `REVISAO_DASHBOARD_MENU_2026-06.md` ·
`REVISAO_PERFIL_ALUNO_2026-06.md` · `REVISAO_REVISAO_GERAL_2026-06.md` ·
`VALIDACAO_COMPETICOES_2026-06.md` · `VALIDACAO_JORNAL_EVENTOS_2026-06.md`

**Catraca / controle de acesso** — relatórios de fase (scaffold → turma real
+ bloqueio por inadimplência), ambos escritos quando a função ainda não
estava deployada; hoje está (ver `functions/access_control/README.md`):
`CATRACAS_INTEGRACAO_2026-06.md` · `CATRACAS_TURMA_BLOQUEIO_2026-06.md` ·
`VALIDACAO_CATRACA_SETTINGS_2026-06.md` (o plano de UI que propôs já foi
construído — `AdminDevicesScreen`/`DeviceEnrollmentScreen`)

**Onboarding / multi-academia** — designs que **não** são o que foi
construído (o sistema real é mais simples/diferente):
`arquitetura-onboarding-self-signup.md` (propôs `academyDirectory`+descoberta
por cidade; o que foi ao ar foi um código único por academia) ·
`ONBOARDING_MAPA_2026-06.md` (design de tour, hoje superado por
`ux/SPEC_ONBOARDING_2026-07.md`) ·
`MULTIACADEMIA_DESIGN_2026-06.md` (implementado; gap residual do client
rastreado em `ANTI_HIDRA_2026-07.md`)

**Stubs quebrados (b2c)** — nunca continham conteúdo real, só o resumo do
agente que os gerou; mantidos só para não perder o rastro de que existiram:
`b2c_MULTIACADEMIA_STATUS_2026-06_STUB_QUEBRADO.md` ·
`b2c_PREP_FASE_LUTADOR_2026-06_STUB_QUEBRADO.md`

---

## 7. Como manter isso vivo

- Ao concluir uma feature descrita por um `plano-*.md`/`*_PLANO.md`, adicione
  um header "Status (data): IMPLEMENTADO" com os arquivos de código — não
  precisa reescrever o corpo do doc, o header já evita a confusão.
  Veja qualquer arquivo da seção 3 como modelo.
- Ao rodar uma auditoria/revisão/validação pontual, o destino natural dela
  **depois que os achados forem corrigidos** é `docs/arquivo/` — não deletar.
- Novo doc de arquitetura para uma feature pontual (`FOO_PLANO.md`) deve ser
  listado em `docs/b2c/README.md` (se for do lutador) ou nesta seção 3/4 (se
  for do core de gestão) assim que nascer — a falha mais comum encontrada
  nesta faxina foi documentos ficarem "invisíveis" (não linkados de lugar
  nenhum) até acumular meses de atraso.
