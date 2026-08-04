# Arquitetura — Check-in diário do aluno (pivô fitness/generalista)

Data: 2026-07-21. Autor: análise Fable (sessão ux-ativacao).
Requisito do dono: aluno de musculação marca a própria presença, POR DIA, sem QR
obrigatório, sem horário específico, sem turma — e isso precisa conviver
elegantemente com academias que usam turmas e com CTs híbridos (turma + livre).
"Tudo precisa conversar muito bem no fim do dia."

## 1. Inventário do que JÁ existe (verificado no código)

| Peça | Onde | Estado |
|---|---|---|
| CF `selfCheckin` | functions/index.js:1371-1453 | **Check-in diário SEM turma já existe**: docId `{studentId}_musculacao_{YYYYMMDD}`, `classId: 'musculacao'` (sintético), `sport: 'musculacao'`, valida horário de funcionamento e se o aluno tem a modalidade. Hardcoded pra musculação. |
| Modos de check-in | settings_service.dart:203,255,495 | `studentCheckinEnabled` (default false) + `musculacaoCheckinMode` `'qr'|'button'|'manual'` — **modo botão já previsto**, ambos passam pela mesma CF. |
| Check-in por turma (QR) | checkin_service.dart | Por (studentId, classId, data), status `pending` até o professor confirmar. É o fluxo de TURMA — não muda. |
| Catraca | access_control/ | Presença s/ turma com `classId` sintético `catraca_{deviceId}`, 1/dia, gate financeiro. |
| Pipeline de presença | retention_functions.js | `onAttendanceWrite` → retenção + feed + push do ato da presença. **Agnóstico de origem** — qualquer presença (chamada/QR/catraca/selfCheckin) alimenta streak/feed/push de graça. |
| Multimodal | core/sports.dart | Modalidades SEM-FAIXA (musculação/boxe/MMA) = presença pura; graduação/faixa é camada condicional. `musculacaoEnabled` default TRUE. |
| Equipe | team_service.dart | Roles `admin|instructor|student`; instructors com `extraPermissions` enforced server-side via callables; nav_catalog gateia entradas por `requiresPermission`. |
| Perfil da academia | (em construção, agente Wave A) | `academy.profile` = fight/fitness/hybrid + `AcademyVocab` + picker no cadastro/settings. |

Conclusão do inventário: **não é feature nova — é generalização + orquestração.**
O modelo de dados, o pipeline e até o modo botão já existem.

## 2. O design

### 2.1 Servidor (generalizar `selfCheckin`)
- Parâmetro `sport` (default 'musculacao' = retrocompat total). Aceita qualquer
  modalidade marcada como schedule-less no catálogo (sem-faixa ≈ sem-turma).
- docId: mantém `{studentId}_musculacao_{YYYYMMDD}` para musculação (compat com
  dados existentes); demais esportes: `{studentId}_checkin_{sport}_{YYYYMMDD}`.
- 1 check-in/dia/modalidade (idempotente por docId — já é assim).
- Presença criada é OFICIAL (source `self_checkin`): conta streak/feed/retention
  via pipeline existente. NÃO conta pra graduação por faixa (graduação já conta
  só presenças verificadas de modalidades com faixa — invariante preservada
  sem código novo).
- Respeita gate financeiro? DECISÃO: não bloquear check-in por inadimplência
  (o bloqueio físico é da catraca; negar o registro do aluno presente só gera
  dado errado). Anotar `overdue` no doc se quisermos sinalizar depois.

### 2.2 Aluno (orquestração por perfil — o coração do pedido)
Regra única: **o que o aluno vê é função das modalidades DELE + perfil da academia.**

| Cenário | O que o aluno vê |
|---|---|
| Academia `fitness` (ou aluno só com modalidades sem-turma) | Botão grande "**CHECK-IN**" no hub/portal (1 tap → presença do dia → celebração/streak). Sem QR, sem turma, sem horário. Zero menção a turmas em toda a UI. |
| Academia `fight` (aluno só com turmas) | **Nada muda.** QR/chamada/catraca como hoje. Botão de check-in diário NÃO aparece. |
| CT `hybrid` (aluno com turma E musculação) | Os dois convivem SEM mistura: check-in diário registra a modalidade livre; presença de turma segue pela chamada/QR. Doc-ids distintos → mesmo dia pode ter ambas (já é o comportamento multimodal). UI: botão CHECK-IN + agenda de turmas, cada um no seu lugar de sempre. |
| Aluno sem a modalidade livre | Botão não aparece (a CF já valida sports do aluno — dupla barreira). |

Anti-"porco": nenhum toggle novo pro aluno, nenhuma tela nova — o botão entra
no lugar que o QR de musculação ocupa hoje (mesma superfície), e o modo
(`button` vs `qr`) é decisão do DONO em settings (já existe o campo). QR
continua disponível pra quem quer o ritual do totem na recepção.

### 2.3 Professor/dono
- Chamada por turma: intocada.
- Visão "quem está aqui hoje": a lista de presenças do dia (todas as origens:
  chamada, QR, catraca, check-in) — já existe consulta equivalente; expor no
  lugar certo por perfil (fitness: vira a "chamada" deles; fight: secundário).
- Confirmação pendente (fluxo QR de turma) NÃO se aplica ao check-in diário —
  sem professor no loop por design (academia não tem "professor da turma").

### 2.4 Equipe/permissões (análise pedida)
- Roles atuais servem: `instructor` em academia fitness = recepção/personal
  (vocabulário via AcademyVocab: "instrutor"/"equipe" já é neutro).
- Permissões granulares (`financial:view` etc.) não dependem de turma — nada a
  mudar no modelo. Entradas de nav turma-cêntricas somem no perfil fitness via
  nav_catalog (mesmo mecanismo de flags existente).
- Chamada manual da equipe continua possível (recepção marca presença de aluno
  sem app) — hoje isso exige turma; com a "chamada rápida sem turma" (Wave A/B)
  a equipe marca direto na lista de alunos.

### 2.5 Settings — defaults por perfil (aplicar na criação da academia)
| Flag | fight (hoje) | fitness | hybrid |
|---|---|---|---|
| studentCheckinEnabled | false | **true (modo button)** | true |
| musculacaoEnabled | true | true | true |
| workoutPlansEnabled | false | **true** (fichas de treino são o pão do gym) | opcional |
| graduationProgress/autoGraduation | flags atuais | **ocultos** (sem faixa) | flags atuais |
| booking/striking/vídeos | false | false | false |
"Ocultos" ≠ removidos: o mecanismo de nav_catalog já esconde entradas; academias
existentes não mudam (defaults só na criação).

## 3. Sequência de implementação
1. (Wave A em curso) fundação `profile` + vocab.
2. Generalizar `selfCheckin` (param sport + docId novo) — pequena, servidor.
3. Botão CHECK-IN no app do aluno gateado por perfil/modalidade + celebração
   (reusa a do QR de musculação).
4. Defaults por perfil na criação + nav_catalog por perfil.
5. Visão "presenças de hoje" do dono (fitness-first).
Cada passo aditivo; academias fight não veem NADA disso sem optar.
