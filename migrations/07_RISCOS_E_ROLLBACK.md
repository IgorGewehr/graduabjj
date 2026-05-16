# 07 — Risk register & rollback playbook

> O que dá errado em migrações desse tipo, **classificado por probabilidade × impacto**, com mitigação preventiva e procedimento de rollback. Use este doc como referência durante incidentes — está organizado para leitura rápida sob estresse.

---

## 1. Como ler

Cada risco tem o cabeçalho:

```
R-NN — Nome curto
Categoria | Probabilidade | Impacto | Detecção | Mitigação | Rollback
```

- **Categoria**: dados / código / infra / produto / processo / segurança / regulatório
- **Probabilidade**: baixa (< 10%), média (10–40%), alta (> 40%)
- **Impacto**: baixo (afeta um usuário, reversível em min), médio (afeta um cliente, reversível em horas), alto (afeta todos os usuários, requer reconciliação), crítico (perda de dados ou financeiro)

Riscos críticos (impacto = crítico OR probabilidade × impacto = alto) **DEVEM** ter rollback ensaiado em staging antes da fase ir para produção.

---

## 2. Risk register

### R-01 — Belt em português não normalizado durante ETL

- **Categoria**: dados
- **Probabilidade**: alta
- **Impacto**: médio
- **Detecção**: query `SELECT current_belt, count(*) FROM students GROUP BY 1` em produção mostra `'white'` com volume muito superior ao esperado, ou `'unknown'` aparecendo (se você for cuidadoso e fizer fallback explícito).
- **Mitigação preventiva**:
  - Antes do ETL: rodar `SELECT DISTINCT highest_belt FROM users` no BigQuery export. Lista todas as variações reais.
  - Estender `BELT_NORMALIZE` no script ETL (doc 05 §3.1) até cobrir 100% dos valores.
  - Ao invés de usar `'white'` como fallback silencioso, usar `'unknown'` que viola o enum no Postgres → forçando erro no ETL e revisão manual.
- **Rollback**: re-rodar o ETL após estender a mapping table. Postgres permite `UPDATE students SET current_belt = ... WHERE current_belt = 'unknown'`.

### R-02 — Photo URLs do Firebase Storage quebrando

- **Categoria**: dados
- **Probabilidade**: média
- **Impacto**: baixo (foto vira ícone padrão)
- **Detecção**: cliente reporta "foto sumiu". Métricas no Sentry de `network_error` na URL `firebasestorage.googleapis.com`.
- **Mitigação preventiva**:
  - Manter `legacy_photo_url` separado do `photo_path` (doc 05 §11).
  - Widget `StudentAvatar` faz `COALESCE` no front.
  - Não apagar arquivos do Firebase Storage durante a migração.
- **Rollback**: nenhum necessário — basta limpar `photo_path` se a foto migrada estiver corrompida; cliente cai no legado.

### R-03 — Dual-write Cloud Function trava / fica atrás

- **Categoria**: infra
- **Probabilidade**: média
- **Impacto**: médio
- **Detecção**: diff job (doc 05 §9) reporta divergência > 1% por collection. Métrica `cloud_functions_execution_count` cai bruscamente.
- **Mitigação preventiva**:
  - Pub/Sub backed → CF não perde mensagens; só atrasa.
  - Configurar **dead-letter topic** com retries (5 attempts, exp backoff).
  - Alertar em `pubsub_undelivered_messages > 100`.
- **Rollback**: parar trafego de leitura para Tatami via feature flag → cliente volta a usar Firestore (que continua canonical até Fase E).

### R-04 — Webhook Asaas/AbacatePay perdido durante cutover

- **Categoria**: regulatório (dinheiro!)
- **Probabilidade**: média
- **Impacto**: crítico
- **Detecção**:
  - Cliente reclama "paguei e o sistema não reconheceu".
  - Diff `wallet_transactions` Postgres vs Firestore > 0 para uma academia.
  - Painel Asaas mostra "Webhook entregue" mas Tatami não tem registro.
- **Mitigação preventiva** (extremamente importante — Fase 4 §):
  1. **Shadow mode** por 7 dias: Tatami recebe webhook mas só loga, não escreve.
  2. Comparar payloads bit a bit com Cloud Function antiga.
  3. **Idempotency**: Tatami usa `external_id` (asaas payment ID) como unique constraint. Reentrega = no-op.
  4. **Storage retry**: Tatami persiste raw webhook em tabela `webhook_received` antes de processar. Se processamento falhar, retry via worker River.
- **Rollback**:
  1. Reverter URL do webhook no painel Asaas/AbacatePay para a Cloud Function antiga.
  2. Re-enviar webhooks dos últimos N minutos via "resend" do painel.
  3. Reconciliação: query `SELECT * FROM webhook_received WHERE processed = false`. Para cada, marcar manualmente no Firestore.

### R-05 — Auto-graduação dispara em massa após habilitar o worker

- **Categoria**: produto
- **Probabilidade**: alta
- **Impacto**: médio
- **Detecção**: ao ligar o worker pela primeira vez, alunos que já passaram do threshold há meses (mas nunca foram graduados manualmente) viram elegíveis simultaneamente. Push notifications em rajada. WhatsApp/Email enviando milhares de mensagens.
- **Mitigação preventiva**:
  - Antes de ligar o worker, rodar **dry-run**: `SELECT * FROM eligibility_view WHERE eligible = true`. Esperar uma rajada se houver backlog.
  - **Quiet launch**: primeira semana, worker apenas registra `belt_progressions` com flag `pending_review = true` e **não dispara notificação**.
  - Admin revisa em massa → bulk approve.
  - Depois desliga `pending_review` e o flow normal continua.
- **Rollback**:
  - Desativar worker (`river job pause notification.belt_eligibility`).
  - Deletar `belt_progressions` com `pending_review = true` se necessário.

### R-06 — UUID v5 colisão (extremamente improvável, mas catastrófico)

- **Categoria**: dados
- **Probabilidade**: baixíssima (< 1 em 2^60 com namespace bem definido)
- **Impacto**: crítico
- **Detecção**: INSERT durante ETL falha com `duplicate key value violates unique constraint`.
- **Mitigação preventiva**:
  - Usar namespace dedicado: `NAMESPACE_TATAMI = uuid_v5(NS_DNS, 'tatami.dev')` e derivar tudo dele.
  - Adicionar o tipo de entidade ao input: `uuid_v5(NS_TATAMI, "academies/" + doc_id)`.
- **Rollback**: investigar manualmente; provavelmente é bug na função geradora (Python `uuid.uuid5` vs Postgres `uuid_generate_v5` resultam diferentes? não — RFC 4122 garante o mesmo).

### R-07 — Migração de attendance trava por trigger lenta

- **Categoria**: infra
- **Probabilidade**: alta
- **Impacto**: baixo (ETL demora horas)
- **Detecção**: bulk INSERT de attendance leva minutos por 10k rows. Postgres CPU em 100%.
- **Mitigação preventiva**:
  - `ALTER TABLE attendance DISABLE TRIGGER update_attendance_count` antes do bulk (doc 05 §3.5).
  - Recalcular `students.attendance_count` em uma única query depois.
  - Usar `COPY` (não `INSERT`) — 10-100× mais rápido.
  - Particionamento já criado **antes** do bulk (senão a tabela ainda é monolítica).
- **Rollback**: não há rollback de "lentidão"; replanejar fora de horário de pico.

### R-08 — RLS bloqueando o ETL ou bloqueando queries legítimas

- **Categoria**: segurança
- **Probabilidade**: média
- **Impacto**: médio
- **Detecção**:
  - Durante ETL: INSERTs falham porque o role `tatami_app` (que tem RLS) está sendo usado em vez de `tatami_migrate` (BYPASSRLS).
  - Em runtime: queries retornam vazio porque o middleware `WithTenantTx` esqueceu de setar `app.academy_id`.
- **Mitigação preventiva**:
  - Documentar claramente em scripts ETL que se conecta como `tatami_migrate`.
  - Integration test que verifica RLS está ativa: `SET ROLE tatami_app; SELECT count(*) FROM students` deve retornar 0.
  - Coverage no backend Go: cada handler tenant-scoped chama `WithTenantTx` ou `SetAcademyIDOnConn`.
- **Rollback**: temporário — `ALTER TABLE x DISABLE ROW LEVEL SECURITY` (não em produção sem aprovação!), corrigir bug, religar.

### R-09 — Vazamento cross-tenant (RLS falhou + bug aplicacional)

- **Categoria**: segurança
- **Probabilidade**: baixa (defesa em profundidade ajuda)
- **Impacto**: crítico (regulatório, reputacional)
- **Detecção**:
  - Idealmente: usuário não reporta porque RLS bloqueia silenciosamente. Mas:
  - Audit log: query inesperada em tabela cruzando academies.
  - Cliente reporta "vejo dados de outra academia". **Tratar como incident P0.**
- **Mitigação preventiva**:
  - **Defense in depth**: RLS no DB + RBAC na aplicação + Tenant resolver no middleware. Nenhum dos 3 sozinho é suficiente; os 3 juntos são.
  - **Penetration test** antes do cutover: tentar acessar `/v1/academies/{outroId}/students` autenticado em outra academy. Esperar 403.
  - **Audit log** em todo POST/PATCH/DELETE com `tenant_id` registrado.
- **Rollback**: incident P0. Desligar feature flag global. Investigar via audit log. Disclosure LGPD se confirmado vazamento.

### R-10 — Idempotency key colidindo

- **Categoria**: produto
- **Probabilidade**: média
- **Impacto**: baixo
- **Detecção**: cliente reclama "criei pedido X mas o sistema retornou o pedido Y" (pedido antigo).
- **Mitigação preventiva**:
  - Cliente gera nova UUID por **operação lógica**, não por dispositivo/sessão.
  - Backend stora `(idempotency_key, request_hash)` — se a chave colide mas o hash difere, retorna 422 com `problem.type=idempotency-conflict`.
  - TTL 24h na tabela `idempotency_keys`.
- **Rollback**: limpar tabela manualmente; cliente recria com nova key.

### R-11 — Migração de timezone perdendo offsets

- **Categoria**: dados
- **Probabilidade**: média
- **Impacto**: médio (datas erradas em relatórios)
- **Detecção**: query `SELECT created_at AT TIME ZONE 'America/Sao_Paulo' FROM ...` mostra horários inesperados (ex.: turma marcada 19h aparece como 22h).
- **Mitigação preventiva**:
  - Firestore Timestamps são sempre UTC. Postgres `timestamptz` armazena UTC + exibe na TZ do client.
  - ETL: garantir que **toda** conversão preserva UTC.
  - Locale do `postgres.conf`: `timezone = 'UTC'` no servidor; cliente seta `SET TIME ZONE 'America/Sao_Paulo'` se necessário (mas para queries diretas, melhor manter UTC e converter no frontend).
- **Rollback**: re-rodar parcelas do ETL após corrigir a conversão.

### R-12 — Imagem do cliente quebra após atualização forçada

- **Categoria**: processo
- **Probabilidade**: alta
- **Impacto**: alto (usuário fica sem app)
- **Detecção**: pico de crashes no Crashlytics imediatamente após release.
- **Mitigação preventiva**:
  - **Staged rollout** nas lojas: 1% → 5% → 25% → 50% → 100% ao longo de 1 semana.
  - **Force update banner** opcional: app verifica `min_required_version` na primeira call ao Tatami; se abaixo, mostra banner pedindo update.
  - **Backwards compatibility** do backend: a versão N do Tatami suporta clients da versão N-1 do app.
- **Rollback**: halt rollout na loja. Hotfix se necessário.

### R-13 — Custos Postgres explodindo

- **Categoria**: infra
- **Probabilidade**: média
- **Impacto**: médio
- **Detecção**:
  - Bill mensal Cloud SQL > esperado.
  - Métrica `cpu_utilization > 70%` sustentado.
  - `pgxpool_acquired_conns / pgxpool_max_conns ≈ 1`.
- **Mitigação preventiva**:
  - Capacity planning antes do go-live: instância dimensionada para 3× o pico de tráfego.
  - Index audit mensal (doc 03 §4).
  - Partitioning desde o dia 1 nas tabelas hot (já feito).
  - Materialized views para reports pesados (já feito).
- **Rollback**: scale-up vertical (sem downtime no Cloud SQL).

### R-14 — Lentidão na geração mensal de financials

- **Categoria**: produto
- **Probabilidade**: média
- **Impacto**: médio (admins reclamando no dia 1)
- **Detecção**: cron job `generate_monthly_financials` demora > 5 min para uma academia.
- **Mitigação preventiva**:
  - Implementação como **uma única transação SQL** (não loop em Go).
  - `INSERT INTO financials SELECT ... FROM students WHERE ...`.
  - Particionamento de `financials` pode ser adicionado se volume crescer.
- **Rollback**: rodar manualmente fora do horário de pico.

### R-15 — Push notification não chega ao usuário

- **Categoria**: produto
- **Probabilidade**: alta (sempre acontece em algum %)
- **Impacto**: baixo (UX)
- **Detecção**: usuário reporta. Métrica `fcm_send_failure_rate > 5%`.
- **Mitigação preventiva**:
  - Worker River tem retry exp backoff.
  - Token rotation: deregistrar token após N falhas consecutivas (likely uninstalled).
  - Inbox **sempre** persistido (mesmo se push falha, usuário vê quando abrir o app).
- **Rollback**: nenhum necessário — inbox é a fonte de verdade.

### R-16 — Reset de senha quebra durante a transição

- **Categoria**: produto
- **Probabilidade**: baixa
- **Impacto**: médio
- **Detecção**: usuário relata. Métrica `firebase_auth_reset_failure`.
- **Mitigação preventiva**:
  - Firebase Auth fluxo continua intocado. **Nada muda aqui.**
  - Se Tatami algum dia precisar mediar reset de senha, é um endpoint dedicado.
- **Rollback**: confiar no Firebase Auth como sempre.

### R-17 — DNS / WAF / Cloudflare bloqueando o Tatami

- **Categoria**: infra
- **Probabilidade**: baixa
- **Impacto**: crítico (app não fala com backend)
- **Detecção**: app reporta timeouts ou 5xx genéricos.
- **Mitigação preventiva**:
  - Health checks externos (Pingdom / UptimeRobot) no `/healthz` antes do release.
  - WAF rules adicionadas em staging primeiro, replicadas em prod.
  - `terraform plan` reviewed para mudanças de DNS.
- **Rollback**: reverter mudança de DNS. TTL baixo (60s) ajuda.

### R-18 — App rejeitado pela loja (App Store / Play Store)

- **Categoria**: processo
- **Probabilidade**: baixa
- **Impacto**: alto (atrasa release)
- **Detecção**: notificação da loja.
- **Mitigação preventiva**:
  - Privacy Policy atualizada incluindo coleta + processamento via Tatami.
  - LGPD endpoint de "deletar minha conta" funcional (Tatami exposto via `DELETE /v1/me`).
  - Firebase Crashlytics + Sentry declarados em "data collection".
- **Rollback**: corrigir e resubmeter.

### R-19 — Conflict-of-write em mappings durante migração concorrente

- **Categoria**: dados
- **Probabilidade**: média
- **Impacto**: médio
- **Detecção**: erro de PK durante ETL em `user_academy_mappings`.
- **Mitigação preventiva**:
  - `ON CONFLICT (uid, academy_id) DO UPDATE SET ...` em todo INSERT.
  - ETL faz "snapshot at T" e não tenta sincronizar live até a Fase B (dual-write).
- **Rollback**: re-rodar (idempotente).

### R-20 — Ataque DDoS aproveitando a nova superfície

- **Categoria**: segurança
- **Probabilidade**: baixa-média
- **Impacto**: alto
- **Detecção**: pico de tráfego anômalo no Tatami. Latência sobe.
- **Mitigação preventiva**:
  - Rate limiting `httprate.LimitByIP(100/min)` já no chi (Sprint 0).
  - Cloud Run autoscale tem teto.
  - Cloudflare ou Cloud Armor na frente.
- **Rollback**: ativar modo "challenge" no Cloudflare; banir IPs ofensivos.

---

## 3. Decision tree — "o que faço agora?"

```
                  Incidente reportado
                          │
              ┌───────────┼───────────┐
              │           │           │
        Dados              Latência      Erro 5xx
        inconsistentes
              │           │           │
              ▼           ▼           ▼
    Diff job já       Postgres CPU?  Logs Tatami
    detectou?         ↓               ↓
    ↓                 OK ── Cloud Run? ↓
    Sim → R-03/-04   ↓                Stack trace
    Não → criar      Não OK          conhecido?
    incident manual   ↓                ↓
                     R-13 / scale     Sim → playbook
                                     Não → P0
```

---

## 4. Procedimentos de rollback por fase

Cada fase tem **rollback testado em staging** antes de ir para prod.

### Fase 0 — Rollback trivial

```bash
git revert <merge-commit>
git push origin main
# CI deploya automaticamente
```

### Fase 1 — Feature flag

```bash
# Firebase Remote Config (ou Tatami /v1/feature-flags)
curl -X PATCH -H "Authorization: ..." \
  https://api.tatami.dev/admin/feature-flags/useTatamiIdentity \
  -d '{"enabled": false}'
```

Tempo: < 5 min. Cliente cai no fluxo Firestore na próxima abertura.

### Fase 2 — Feature flag por tela

```bash
# Por tela
curl -X PATCH ... /admin/feature-flags/useTatamiReads_students -d '{"enabled": false}'
curl -X PATCH ... /admin/feature-flags/useTatamiReads_dashboard -d '{"enabled": false}'
```

Cliente lê via Firestore na tela específica. Dual-write garante paridade.

### Fase 3 — Reverter direction do dual-write

Cloud Functions de mirror **invertem** o sentido (Postgres → Firestore vira Firestore → Postgres). Requer 30 min de janela + verificação:

```bash
# 1. Pausar Cloud Function "mirror_postgres_to_firestore"
gcloud functions deploy mirror_postgres_to_firestore --no-allow-unauthenticated --max-instances 0

# 2. Habilitar Cloud Function "mirror_firestore_to_postgres" (já existia em standby)
gcloud functions deploy mirror_firestore_to_postgres --max-instances 10

# 3. Feature flag off em todos os writes
for flag in useTatamiWrites_students useTatamiWrites_plans useTatamiWrites_classes useTatamiWrites_settings; do
  curl -X PATCH ... /admin/feature-flags/$flag -d '{"enabled": false}'
done
```

### Fase 4 — Webhook revert (mais sensível)

```bash
# 1. Login no painel Asaas, voltar URL para Cloud Function antiga
#    https://us-central1-arpjj-76350.cloudfunctions.net/asaasWebhookHandler

# 2. Idem AbacatePay.

# 3. Feature flag financials off no app.

# 4. Reconciliação manual:
psql "$DSN" -c "
  SELECT wt.external_id, wt.amount, wt.created_at
  FROM wallet_transactions wt
  WHERE created_at > '2026-05-15T00:00:00Z'  -- inicio do cutover
    AND NOT EXISTS (
      SELECT 1 FROM firestore_walletTransactions fwt
      WHERE fwt.external_id = wt.external_id
    );
" > /tmp/missing_in_firestore.csv

# 5. Importar /tmp/missing_in_firestore.csv para Firestore via script Python.
```

Tempo: 1-3h dependendo do volume divergente. Comunicação com clientes obrigatória.

### Fase 5 — Feature flag attendance

```bash
curl -X PATCH ... /admin/feature-flags/useTatamiAttendance -d '{"enabled": false}'
```

Worker de auto-graduação **continua rodando** no backend mas não dispara notificação enquanto a flag está off (configuração separada).

### Fase 6 — Feature flag notifications

Trivial. Worker FCM no Tatami pode ser pausado:

```bash
# Worker River
SELECT pg_advisory_lock(...); -- ou via API administrativa
```

Inbox continua sendo persistido; só dispatch é interrompido.

### Fase 7 — Feature flag store + competitions

Idem. Storage signed URLs continuam funcionando; bytes legados servem do Firebase.

### Fase 8 — Rollback "real" complicado

Após 30 dias estáveis sem rollback, fechamos a Fase 8. Re-abrir Firestore como sistema vivo seria semanas de trabalho. Por isso o gate de 30 dias.

Em caso extremo: importar Firestore do arquivo Coldline GCS → Firestore vivo, reverter clientes 8 versões. Não recomendado; tratar como desastre, não rollback.

---

## 5. Comunicação em incidente

### Por severidade

- **P0 (crítico, todos os usuários)**: status page atualizada em < 5 min. Mensagem in-app. Slack #incidents broadcast. Manager paged.
- **P1 (alto, um cliente impactado)**: contato direto com o cliente em < 30 min. Slack #incidents.
- **P2 (médio, degradado)**: investigar em horário comercial. Comunicar no próximo report semanal.
- **P3 (baixo, edge case)**: ticket no backlog.

### Template de mensagem in-app (P0)

```
Estamos passando por uma instabilidade na sincronização de dados.
Suas informações estão seguras. Algumas funções podem demorar mais
que o normal nas próximas horas.
Acompanhe o status em status.tatami.dev.
Código: {trace_id}
```

### Template de post-mortem

Após resolver o incidente, dentro de 5 dias úteis:

```
1. Resumo (1 parágrafo)
2. Timeline (UTC)
3. Causa raiz
4. O que funcionou
5. O que não funcionou
6. Action items (com owner + deadline)
7. Atualização deste doc 07 com novo risco se aplicável
```

---

## 6. O que ainda não estamos protegidos contra

Honestidade: nenhum sistema é 100% seguro. Áreas onde reconhecemos vulnerabilidade residual:

- **Optimistic concurrency**: não temos versionamento de rows (`version` column + check on UPDATE). Dois admins editando o mesmo aluno simultaneamente → último vence silenciosamente. Mitigação futura: adicionar `version int` em tabelas críticas e retornar 409 se conflict.
- **Backup do Postgres**: confiamos no managed (Cloud SQL). RPO 5min, RTO 30min em teoria. **Não testamos restore em produção** ainda. **TODO**: drill trimestral.
- **Secret rotation**: KEK do Asaas, ID tokens Firebase, API keys. Procedimento documentado em RUNBOOK.md do Tatami mas não ensaiado.
- **Multi-region**: somos single-region (us-east1). Se a região cair, Tatami fica indisponível. Não é prioridade — academias são regionais — mas vale documentar.

Cada um desses é candidato a ADR + sprint dedicado pós-migração.

---

## 7. Drill trimestral (post-migração)

Após a Fase 8, trimestralmente:

1. **Restore drill**: pegar snapshot Cloud SQL de 24h atrás, restaurar em instância de teste, rodar suite de smoke tests. Medir tempo.
2. **Rollback drill**: pegar uma feature, simular falha, reverter via flag. Medir tempo.
3. **Webhook reentry**: pegar payload Asaas histórico, replay no endpoint. Confirmar idempotency.
4. **RLS pentest**: tentativa cross-tenant com usuário de teste. Esperar 403.
5. **Pubsub backlog**: parar consumidor por 1h. Religar. Medir tempo de drenagem.

Resultados ficam num doc separado em `docs/drills/`.

---

## 8. Checklist por release

Imprimir, colar na parede do dev BE + dev FE:

```
□ Feature flag pronta (default OFF em prod)
□ Smoke test em staging passou
□ Dual-write validado (se aplicável)
□ Rollback procedimento documentado
□ Rollback ensaiado em staging
□ Status page atualizada
□ Comunicação preparada (Slack template + in-app banner)
□ On-call alocado (BE + FE + SRE)
□ Canary 10% por 24h
□ Métricas baseline capturadas
□ Decisão de prosseguir 100% ou abortar tomada com dados
```
