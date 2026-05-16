# 06 — Plano faseado detalhado

> O doc 02 §13 esboçou 8 fases. Este doc **detalha cada uma**: pré-requisitos, mudanças backend + frontend + dados, plano de teste, **exit criteria** (o que prova que terminou), procedimento de rollback, e estimativa de esforço.
>
> Cada fase é projetada para **fechar com release de loja** — ou seja, é entregável e reversível por release reverse. Big-bang não é uma opção.

---

## Visão geral em uma página

```
T0     Fase 0     Setup do TatamiClient + parser problem+json
       ↓
T+1w   Fase 1     /v1/me + AuthSwitcher academia ativa
       ↓
T+3w   Fase 2     Leituras pesadas (lista alunos, dashboards, search)
       ↓
T+5w   Fase 3     Escritas de baixo risco (CRUD aluno, config, plano)
       ↓
T+7w   Fase 4     Financeiro + webhooks Asaas/AbacatePay
       ↓
T+9w   Fase 5     Attendance + QR + auto-graduação
       ↓
T+11w  Fase 6     Notificações + FCM
       ↓
T+13w  Fase 7     Store + Competições + Storage de fotos
       ↓
T+15w  Fase 8     Encerramento Firestore como ativo (vira arquivo)
```

15 semanas é o **happy-path** com 1 dev backend + 1 frontend dedicados part-time + suporte de SRE. Bugs encontrados podem deslocar fases — o sequenciamento é o que NÃO muda.

---

## Fase 0 — Setup do contrato (semana 1)

### Objetivo

Construir a infra de cliente HTTP no graduabjj **sem mexer em nenhuma tela ainda**. Quando esta fase terminar, o app está exatamente igual ao usuário, mas internamente já fala "tatami language" — só não usou pra nada ainda.

### Pré-requisitos

- Tatami staging acessível (`https://api.staging.tatami.dev`) com `/healthz` retornando 200.
- Service account Firebase pode emitir ID tokens válidos contra o Tatami.

### Backend

Nada. Tatami já deve estar deployado em staging.

### Frontend

Arquivos novos:
- `lib/api/tatami_client.dart` — `Dio` configurado com base URL + interceptor para anexar `Authorization: Bearer <firebase_id_token>`.
- `lib/api/tatami_exception.dart` — exceção tipada que parseia `application/problem+json`.
- `lib/api/problem_interceptor.dart` — converte respostas 4xx/5xx do Tatami em `TatamiException`.
- `lib/api/idempotency.dart` — gerador de `Idempotency-Key` + retry helper.
- `lib/providers/api_provider.dart` — `Provider<TatamiClient>` lendo `TATAMI_BASE_URL` de `--dart-define`.
- `test/api/tatami_client_test.dart` — testa o interceptor de auth e o parser de problem+json com fixtures.

### Dados

Nada. Postgres já populado pela Fase A do doc 05 (se ainda não foi, este é o momento — sem dual-write).

### Plano de teste

- Unit tests do `TatamiException.fromJson` para todos os tipos de erro (validation, unauthorized, forbidden, not-found, conflict).
- Test E2E: chamar `/healthz` do staging e validar 200 + corpo.
- Test E2E: chamar `/v1/me` **sem token** → esperar 401 + problem+json com `type=unauthorized`.

### Exit criteria

- [ ] `flutter test` passa.
- [ ] `TatamiClient.get('/healthz')` retorna 200 em staging.
- [ ] `TatamiException` instanciada manualmente serializa/deserializa corretamente.
- [ ] PR aprovado e mergado em main.
- [ ] Nenhuma tela do app foi tocada.

### Rollback

Trivial. Se algo der errado, o código novo não está sendo chamado por ninguém. Revert do PR.

### Esforço

**~3 dias** de um dev frontend.

---

## Fase 1 — Identity (`/v1/me` + AcademySwitcher) (semanas 2–3)

### Objetivo

Substituir o ponto de partida da sessão: hoje o cliente lê `users/{uid}` + `userAcademyMapping/{uid}` + N reads de academias. Trocar por uma chamada única `GET /v1/me`.

### Pré-requisitos

- Fase 0 concluída.
- Tatami `/v1/me` testado em staging com pelo menos um usuário real exportado do Firebase.

### Backend

- Verificar que `GET /v1/me` retorna todos os campos que o `AppUser` Dart consome (display_name, photo_url, memberships com role e student_id, primary_academy_id).
- Adicionar header `Cache-Control: private, max-age=60` para `/v1/me` (já estamos atrás de auth, e o cliente decide quando invalidar).

### Frontend

Arquivos modificados:
- `lib/providers/auth_provider.dart` — **mudança principal**. `currentUserProvider` deixa de ler Firestore e passa a chamar `api.get<CurrentUser>('/v1/me')`. Cache via `Provider` com `keepAlive`.
- `lib/providers/selected_academy_provider.dart` — `SelectedAcademyNotifier._initialize()` agora lê de `CurrentUser.memberships` em vez de `userAcademyMapping`. Filtra `m.status == 'active'`.
- `lib/screens/portal/portal_shell.dart` — `AcademySwitcher` lê do mesmo provider; nada muda visualmente.
- `lib/models/user.dart` — `AppUser.fromCurrentUserResponse(json)` adicionado; o factory antigo `fromGlobalAndAcademy` é deprecated mas mantido até a Fase 8.

Arquivos novos:
- `lib/api/identity_repo.dart` — `IdentityRemoteRepo` com `getMe`, `updateMe`, `getMemberships`.

### Dados

Esta fase **assume** Postgres já populado e RLS funcionando. Sem novos ETLs.

Dual-write ainda **não** está ativo para escritas — Fase 3 entra nisso. As escritas de perfil que aconteçam aqui (`updateMe`) **vão simultaneamente para Postgres E Firestore** durante 1 semana. Implementação: backend exporta para Cloud Function que reflete a mudança para Firestore (`mirror_user_to_firestore`).

### Plano de teste

Unit:
- `IdentityRemoteRepo` com mocks → mapeamento de campos.

Integration (real device, staging):
- Login com 3 contas: 1 academia, múltiplas academias, conta sem academy (recém-criada).
- Switcher trocando entre academias muda os providers downstream.

Regression manual:
- Tela de perfil exibe os mesmos campos que antes.
- Header continua mostrando nome correto.
- Logout funciona.

### Exit criteria

- [ ] `/v1/me` é chamado **em todos os pontos** que antes liam Firestore para identidade.
- [ ] Sem nenhuma leitura direta de `userAcademyMapping/{uid}` no código.
- [ ] Diff job confirma paridade entre Firestore.users e Postgres.global_users.
- [ ] 0 crashes em 48h de canary (10% dos usuários).

### Rollback

Feature flag remota `useTatamiIdentity` (Firebase Remote Config ou um endpoint do próprio Tatami). Se virar `false`, o `currentUserProvider` cai no fluxo antigo Firestore.

Manter o código Firestore por mais 2 fases para que esse rollback funcione.

### Esforço

**~1 semana** de um dev frontend + ~2 dias de QA manual.

---

## Fase 2 — Leituras pesadas (semanas 4–5)

### Objetivo

Substituir as listagens grandes e dashboards, que são as fontes de **80% dos reads Firestore** no app.

### Escopo

- Lista de alunos (admin + monitor)
- Dashboard de academia (KPIs)
- Search de alunos por nome
- Histórico de pagamentos por aluno (read-only ainda)
- Histórico de attendance por aluno
- Belt progressions histórico
- Achievements timeline

### Pré-requisitos

- Fase 1 concluída.
- `mv_academy_kpis` populada e refrescando a cada 10min.

### Backend

- Endpoints `GET /v1/academies/{id}/students` com paginação por cursor + filtros (status, belt, category, q) — já existe.
- Endpoint `GET /v1/academies/{id}/kpis` lendo da MV — já existe (parcial).
- Endpoint `GET /v1/academies/{id}/financials` paginado — já existe.
- Endpoint `GET /v1/academies/{id}/students/{sid}/belt-progressions` — já existe.
- Endpoint `GET /v1/academies/{id}/students/{sid}/achievements` — já existe.
- **Novo:** endpoint agregado `GET /v1/academies/{id}/students/{sid}/profile` que retorna header + N "últimos X" de cada subcoleção (vide doc 03 §5).

### Frontend

Modificações grandes:
- `lib/services/student_service.dart` — deprecate `getAll()`. Adicionar `listPaginated(StudentFilter)` que chama Tatami.
- `lib/providers/student_provider.dart` — `studentsPaginatedProvider` baseado em `AsyncNotifier.family`. `studentDashboardProvider` lê `/kpis`.
- `lib/screens/admin/student_list_screen.dart` — usar `PaginatedList<Student>` (componente novo — doc 03 §2). Filtros e busca enviados como query params.
- `lib/screens/admin/student_detail_screen.dart` — usar `/profile` agregado. Cada tab carrega lazy via provider próprio (`belt_progressions_provider(studentId)` etc).
- `lib/services/financial_report_service.dart` — descontinuar; tudo passa pelos endpoints Tatami.
- `lib/services/retention_service.dart` — descontinuar; cliente lê `/risk-scores` do backend.

### Dados

Dual-write para `students.photoUrl` (quando admin troca foto): backend espelha Firestore.

### Plano de teste

- Test contract: validar `GET /v1/academies/{id}/students?limit=50` retorna até 50 itens com next_cursor preenchido.
- Test paginação: scrollar até o fim em uma academia de teste com 500+ alunos seed → não deve travar.
- Test search com query inválida → mostra ErrorView.
- A/B: comparar tempo de abertura da `student_list_screen` Firestore vs Tatami (esperado: Tatami 3-5x mais rápido).

### Exit criteria

- [ ] Nenhuma chamada a `firestore.collection('students')` no código de tela ou provider.
- [ ] Tempo de abertura da tela de alunos < 500ms (p95) em uma academia de 200+ alunos.
- [ ] Tempo de search < 200ms (p95).
- [ ] Custo de leituras Firestore caiu ≥ 60% (Firebase console → Usage).
- [ ] Sem crashes em 1 semana de canary.

### Rollback

Feature flag `useTatamiReads`. Por tela ou global. Mantemos os métodos antigos do `StudentService` por mais 1 fase como fallback.

### Esforço

**~2 semanas** de um dev frontend + 3 dias de QA.

---

## Fase 3 — Escritas de baixo risco (semanas 6–7)

### Objetivo

Migrar escritas que **não envolvem dinheiro** e **não envolvem concorrência crítica**: cadastro/edição de aluno, plano, classe, configurações de academia, link codes.

### Escopo

- Criar/editar/desativar aluno
- Criar/editar plano
- Atribuir alunos a planos
- Criar/editar turma
- Adicionar/remover aluno em turma
- Editar configurações da academia
- Gerar link-codes (aluno + instrutor)
- Resgatar link-code (o passo crítico — uma transação completa)

### Pré-requisitos

- Fase 2 concluída.
- Dual-write para Firestore configurado para essas tabelas (Cloud Function que ouve POST/PATCH no Tatami e reflete no Firestore).

### Backend

- Endpoints já existentes (Sprints 2+3 do Tatami).
- **Adicionar:** trigger Cloud Function `mirror_to_firestore` para students, plans, classes, settings, link_codes.
- Garantir que `POST /v1/link-codes/{code}/redeem` está atômico (transação Postgres com SELECT FOR UPDATE).

### Frontend

- `lib/services/student_service.dart` — `create/update/delete` chamam Tatami. Cloud Function refletirá no Firestore por compatibilidade.
- `lib/services/plan_service.dart` — idem.
- `lib/services/class_service.dart` — idem.
- `lib/services/settings_service.dart` — `set(key, value)` chama PUT do Tatami.
- `lib/services/link_code_service.dart` — `redeem` chama o endpoint Tatami; método antigo descontinuado.

### Dados

Dual-write **ativo** para todas as tabelas do escopo. Diff job hourly continua rodando.

### Plano de teste

- **Idempotency tests:** chamar `POST /v1/academies/{id}/students` duas vezes com a mesma Idempotency-Key → segundo retorna a mesma resposta.
- **Concurrency test:** dois admins editando o mesmo aluno simultaneamente → último write vence, mas backend retorna 200 (não 409, pois não temos versionamento opt — vide doc 07 §6).
- **Link-code race:** dois dispositivos resgatando o mesmo código → um sucesso, outro 409 com `problem.type=link-code-already-used`.
- **Dual-write integrity:** após criar aluno via Tatami, verificar que aparece no Firestore em < 30s.

### Exit criteria

- [ ] Sem chamadas diretas a `firestore.collection(...).add(...)` ou `.update(...)` para as collections do escopo.
- [ ] Diff Firestore↔Postgres < 0.1% por 7 dias consecutivos.
- [ ] Zero ocorrências de "link code parcialmente resgatado" (estado inconsistente).

### Rollback

Feature flag `useTatamiWrites`. Se desligada, escritas voltam para Firestore direto e Cloud Functions de mirror invertem o sentido (Firestore → Postgres) usando o mesmo diff job.

### Esforço

**~2 semanas** + 3 dias QA.

---

## Fase 4 — Financeiro + webhooks (semanas 8–9)

### Objetivo

A fase mais sensível. Dinheiro está envolvido — qualquer bug aqui custa caro.

### Escopo

- Listar / criar / editar financials
- Marcar como pago (transação que credita wallet)
- Geração mensal automática (cron)
- Listar wallet + transactions
- Webhooks Asaas + AbacatePay apontando para o Tatami
- Sub-account API key criptografada
- Billing contact log

### Pré-requisitos

- Fases 1-3 concluídas.
- Tatami está recebendo webhooks de teste em staging dos sandboxes Asaas e AbacatePay.
- KEK (`TATAMI_SUBACCOUNT_ENCRYPTION_KEY`) configurada e backupada em Secret Manager.

### Backend

- Webhook endpoints já existem (`/v1/webhooks/asaas`, `/v1/webhooks/abacatepay`).
- River cron `generate_monthly_financials` agendado para dia 1 às 6h.
- River cron `mark_overdue` agendado diariamente às 0:30.
- Migrar API keys Asaas do Firestore para `asaas_sub_accounts.encrypted_api_key` (ETL specíficico).

### Frontend

- `lib/services/payment_service.dart` — todas as operações para Tatami. `streamByStudent` vira polling com ETag (doc 03 §8).
- `lib/services/wallet_service.dart` — chamadas para Tatami.
- `lib/screens/admin/financials_*` — usar paginação.
- **Crítico:** botão "Marcar como pago" chama Tatami → backend faz a transação. Cliente **não toca** mais em `wallet_transactions`.

### Asaas / AbacatePay

Mudança operacional crítica: o **URL do webhook configurado** nos painéis Asaas/AbacatePay precisa apontar para o Tatami, não para a Cloud Function antiga.

Procedimento:
1. Dia D-7: ambos webhooks (Cloud Function antiga + Tatami) ativos. Tatami é "shadow" — recebe mas não escreve no banco (`SHADOW_MODE=true`).
2. Comparar payloads recebidos por 7 dias. Confirmar paridade.
3. Dia D: trocar o webhook no painel para o Tatami. Desligar shadow. Cloud Function antiga vira shadow por mais 7 dias.
4. Dia D+7: desligar Cloud Function antiga.

### Plano de teste

- **Webhook signature test:** chamar `/v1/webhooks/asaas` com signature inválida → 401 + problem.
- **Idempotency:** mesmo webhook chegando duas vezes (Asaas reenvia) → segundo é no-op (já processed).
- **Concurrency:** webhook + cliente chamando "marcar pago" simultaneamente → exatamente 1 wallet_transaction criada.
- **End-to-end sandbox:** criar charge no sandbox Asaas, simular pagamento, verificar wallet creditado.
- **Failure inject:** matar conexão DB no meio do processamento de webhook → ao restart, mensagem é reprocessada (River retry).

### Exit criteria

- [ ] Webhook do Asaas/AbacatePay aponta 100% para Tatami por 7 dias consecutivos.
- [ ] Diff de saldo Firestore vs Postgres = 0 por academy.
- [ ] Geração mensal automática rodou pelo menos 1 vez com sucesso (próximo dia 1 do mês).
- [ ] Zero reconciliações manuais necessárias no fechamento mensal.

### Rollback

**Mais difícil**, pois envolve provedor externo. Procedimento:
1. Reverter o webhook URL no painel Asaas/AbacatePay para a Cloud Function antiga.
2. Reverter feature flag `useTatamiFinancials` no app.
3. **Reconciliação manual:** comparar `wallet_transactions` do Postgres com `walletTransactions` do Firestore desde o cutover. Aplicar diff no Firestore.

Por isso a Fase 4 é a primeira que **exige uma janela de manutenção** de ~1h.

### Esforço

**~2 semanas** + 1 semana de shadow/canary + 1 semana de monitoramento intenso.

---

## Fase 5 — Attendance + QR + auto-graduação (semanas 10–11)

### Objetivo

Migrar o sistema de presença, incluindo o flow QR e a auto-graduação.

### Escopo

- Bulk staff check-in
- QR self check-in (com QR assinado pelo backend)
- Confirmação de check-ins pré-aprovados
- Avaliação de elegibilidade de graduação
- Promoção (criação de belt_progression)
- Milestones de presença (via outbox → worker)

### Pré-requisitos

- Fase 4 concluída.
- Endpoint `POST /v1/academies/{id}/classes/{cid}/qr-tokens` implementado (mencionado no doc 02 §4 como "ainda não está no spec").
- Worker `outbox_relay` + `attendance_milestone_worker` rodando em staging.

### Backend

- Endpoints já existentes (Sprint 4).
- **Adicionar:** `POST /v1/academies/{id}/classes/{cid}/qr-tokens` que gera PASETO com TTL 60s assinado por chave da academia.
- Worker que consome outbox `attendance_recorded` e avalia auto-graduação.

### Frontend

- `lib/services/attendance_service.dart` — todas as ops para Tatami.
- `lib/services/checkin_service.dart` — `create/confirm` para Tatami.
- `lib/services/qr_attendance_service.dart` — refatorar completamente:
  - `issueQrForClass(classId)` chama backend que devolve token.
  - Tela do QR só renderiza o token recebido.
  - Scanner envia o token ao backend; backend valida.
- `lib/services/belt_progression_service.dart` — `checkEligibility` chama Tatami; `promote` cria via Tatami.

### Plano de teste

- **QR forge test:** scanner enviar token corrompido → 401.
- **QR replay:** scanner enviar mesmo token 2x → 409 (já usado).
- **QR expired:** scanner enviar token > 60s → 401.
- **Self check-in wrong class:** student da turma A escaneando QR da turma B → 403.
- **Bulk check-in race:** 2 instrutores marcando o mesmo aluno simultaneamente → exatamente 1 attendance criado, segundo recebe 409.
- **Auto-graduation pipeline:** marcar attendance até o threshold → worker dispara notification em < 30s.

### Exit criteria

- [ ] Cliente não toca mais em `firestore.collection('attendance')`.
- [ ] QR é gerado backend-side em 100% dos casos.
- [ ] 0 duplicatas de presença (UNIQUE constraint funcionando).
- [ ] Auto-graduação notifica admin dentro do SLA (< 60s pós-attendance).

### Rollback

Feature flag `useTatamiAttendance`. Pode ser por academia se uma academia específica der problema.

### Esforço

**~2 semanas** + 1 semana de soak time.

---

## Fase 6 — Notificações + FCM (semana 12)

### Objetivo

Migrar inbox + dispatch + registro de FCM tokens.

### Escopo

- Listar inbox de notificações
- Marcar como lida (idempotente)
- Registrar/deregistrar FCM token
- Broadcast admin
- Dispatch via FCM (substituindo Cloud Function)

### Pré-requisitos

- Fases 1-5 concluídas (várias dependem de notification).
- Service account do Firebase configurada no Tatami.

### Backend

- Endpoints `/v1/me/notifications*` + `/v1/me/fcm-tokens*` já existem (Sprint 7).
- Worker FCM dispatcher implementado e testado.
- Cloud Function antiga `sendNotification` pode coexistir durante transição (shadow).

### Frontend

- `lib/services/notification_service.dart` — para Tatami.
- `lib/services/push_notification_service.dart` — registro de FCM token via Tatami no `app_init`.
- Stream Firestore de notificações → polling com ETag (doc 03 §8).

### Dados

Histórico de notifications: **apenas últimos 90 dias** copiados para Postgres (vide doc 05 §3.6). Resto fica em arquivo Firestore.

### Plano de teste

- **End-to-end:** marcar attendance que dispara milestone → push chega no dispositivo de teste em < 60s.
- **Token rotation:** desinstalar e reinstalar app → token velho deregistrado, novo registrado.
- **Broadcast:** admin envia broadcast → todos os membros ativos recebem em < 5min.

### Exit criteria

- [ ] Cloud Function antiga desligada.
- [ ] Push notifications fluindo 100% via Tatami por 7 dias.
- [ ] Inbox lê 100% de Postgres.

### Esforço

**~1 semana** + soak.

---

## Fase 7 — Store + Competições + Storage (semana 13–14)

### Objetivo

Migrar features menores e o pipeline de fotos.

### Escopo

- Loja: produtos, pedidos, decremento atômico de estoque.
- Competições: CRUD, inscrições, resultados.
- Fotos de competição: upload 2-step (signed URL + finalize).
- Migração das URLs Firebase Storage existentes (mantidas como `legacy_photo_url`).
- Job paralelo para mover bytes para GCS/S3 (longo prazo, pode levar meses).

### Pré-requisitos

- Endpoint `/v1/uploads/sign` implementado (mencionado em doc 02 §9).
- Bucket GCS criado e IAM configurado.

### Backend

- Endpoints já existentes (Sprint 6).
- **Adicionar:** `POST /v1/uploads/sign` — gera signed URL para PUT direto no GCS.
- Worker `migrate_legacy_photos` (River periodic) — copia bytes do Firebase Storage para GCS em batches; atualiza `photo_path`.

### Frontend

- `lib/services/store_service.dart`, `competition_*_service.dart` — para Tatami.
- `lib/services/photo_upload_service.dart` — refatorar para o flow 2-step.
- `StudentAvatar` widget (doc 03 §3) usado em toda lista — entende `photo_path` (Tatami) ou `legacy_photo_url` (Firebase).

### Plano de teste

- **Out-of-stock race:** 2 clientes comprando o último item → 1 sucesso, outro 409.
- **Photo upload happy path:** PUT direto no GCS, finalize, foto aparece na tela.
- **Legacy photos:** abrir aluno antigo sem migrar bytes → foto renderiza via `legacy_photo_url`.

### Exit criteria

- [ ] Compras via app fluem 100% via Tatami.
- [ ] Upload de fotos vai 100% via signed URL.
- [ ] Job de migração de bytes está rodando em background.

### Esforço

**~2 semanas**.

---

## Fase 8 — Encerramento Firestore (semana 15+)

### Objetivo

Desligar Firestore como sistema vivo. Vira read-only / arquivo.

### Escopo

- Desligar Cloud Functions de dual-write / mirror.
- Security rules Firestore → `allow read: if true; allow write: if false;` (read-only por 90 dias para fallback).
- Após 90 dias: export final para Coldline GCS; collections apagadas.
- Frontend: nenhuma referência ao Firestore SDK exceto Auth + Storage (até bytes migrados).

### Pré-requisitos

- Fases 1-7 concluídas com >30 dias de estabilidade comprovada.
- 0 rollbacks executados na última 30 dias.

### Frontend

- Remover `cloud_firestore` do pubspec.yaml.
- Remover imports.
- Limpar código deprecated marcado nas fases anteriores.
- Remover feature flags (todos os reads/writes vão para Tatami sem flag).

### Backend

- Desligar Cloud Functions de sync.
- Aplicar security rules Firestore final.

### Exit criteria

- [ ] `cloud_firestore` removido do `pubspec.yaml`.
- [ ] APK / IPA size diminui (sem o SDK).
- [ ] CI passa sem warnings deprecated.
- [ ] Custo Firestore mensal cai para próximo a zero (só Auth + Storage durante migração de bytes).

### Esforço

**~1 semana** de limpeza + monitoramento contínuo.

---

## Tabela de resumo

| Fase | Semana | Esforço dev | Risco | Janela manutenção | Rollback |
|---|---|---|---|---|---|
| 0 | 1 | 3d FE | 🟢 trivial | não | revert PR |
| 1 | 2-3 | 1w FE | 🟢 baixo | não | feature flag |
| 2 | 4-5 | 2w FE | 🟠 médio | não | feature flag por tela |
| 3 | 6-7 | 2w FE + 1w BE | 🟠 médio | não | feature flag + dual-write reverse |
| 4 | 8-9 | 2w FE + 1w BE + 1w SRE | 🔴 alto | sim, ~1h | webhook revert + manual recon |
| 5 | 10-11 | 2w FE + 1w BE | 🟠 médio | não | feature flag |
| 6 | 12 | 1w FE + 0.5w BE | 🟠 médio | não | feature flag |
| 7 | 13-14 | 2w FE + 1w BE | 🟠 médio | não | feature flag |
| 8 | 15+ | 1w FE + 0.5w SRE | 🟢 baixo | não | revert PRs (mas Postgres é canonical) |

**Total de horas de trabalho concentrado**: ~14 semanas-dev backend + 14 semanas-dev frontend + ~3 semanas-SRE. Pode ser comprimido se a equipe tiver paralelismo (até a Fase 4 que serializa).

---

## Convenções operacionais por fase

Cada fase abre com:
1. **Kickoff meeting** (1h) com tech lead, dev BE, dev FE, SRE, PO. Revisar este doc + última coluna de exit criteria.
2. **Branch protegida** `migration/fase-X` em ambos repos.
3. **Canary release** para 10% dos usuários (Firebase A/B) na primeira semana.
4. **Daily diff report** automatizado no Slack.
5. **Stand-up de 15min** dedicado à migração, diário, até closing.

E fecha com:
1. **Closing review** (1h): exit criteria todos checados, lições aprendidas, atualizações ao doc 07 (Risk).
2. **PR de cleanup** removendo código deprecated da fase anterior se aplicável.
3. **Tag git** `migration/fase-X-done` nos dois repos.

---

## O que NÃO é negociável

- **Pular fase é fonte de incidente.** A ordem importa porque dependências reais existem (Fase 3 depende de Fase 2; Fase 5 depende de Fase 3 etc).
- **Big-bang release.** Cada fase tem que ser releaseável sozinha.
- **Sem feature flag = sem deploy.** Toda mudança que rota de Firestore para Tatami passa por flag até a fase de encerramento.
- **Sem rollback testado em staging = sem ir pra prod.** O procedimento de rollback (doc 07 §por fase) precisa ser ensaiado antes do release.

Quem cortar canto numa dessas, paga depois.
