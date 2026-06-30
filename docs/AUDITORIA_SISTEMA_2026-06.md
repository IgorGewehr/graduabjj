# Relatório de Auditoria — GraduaBJJ

**Data:** 2026-06-22  
**Branch auditado:** firebase-production (produção, Firestore `arpjj-76350`)  
**Escopo:** Pagamentos (Mercado Pago), cobrança/notificações, graduação, gestão de equipe, login/onboarding, retenção/inadimplência  
**Objetivo de negócio:** reduzir inadimplência e aumentar retenção · **Gateway em produção:** somente Mercado Pago

---

## Resumo executivo

- **1 vulnerabilidade crítica de tomada de conta.** Qualquer usuário autenticado pode se auto-vincular como aluno a **qualquer** academia com **qualquer** `studentId`, sem código, pela regra de escrita do `userAcademyMapping` (`firestore.rules:273-290`, `:305-329`). Isso concede leitura de PII e financeiro do aluno-alvo e permite sobrescrever `linkedUserId/email/cpf/phone`, sequestrando o registro. O Cloud Function `joinAcademy` foi endurecido, mas o caminho client-side ignora totalmente esse guard.

- **A mesma classe de sequestro reaparece em 2 caminhos "oficiais" de cadastro** (alto): `createAccountWithLinkCode` grava o vínculo 100% client-side, sem o orphan-claim guard do CF. Um monitor (que pode cunhar `linkCodes`) ou um código vazado leva ao roubo do registro de outro aluno.

- **Risco de perda de dinheiro recorrente (alto):** falha de criação de assinatura que deixa um preapproval vivo no MP marca o doc como `error` — invisível à guarda de duplicidade — permitindo **double-charge mensal silencioso** que nenhuma das três redes de proteção (dup guard, reconcile, overcharge detector) detecta.

- **Double-charge na aula particular (alto):** marcar uma aula como "pago em dinheiro" **não cancela** o PIX MP em aberto; se a família paga o PIX, é cobrada duas vezes **sem registro de reconciliação e sem alerta** ao admin.

- **Webhook de paywall SaaS falha aberto (alto):** `caktoWebhook` pula a verificação de assinatura quando `CAKTO_WEBHOOK_SECRET` é vazio, ao contrário dos webhooks MP que falham fechados. Um caller não autenticado pode conceder Pro grátis ou revogar academias pagantes.

- **O coração do funil anti-inadimplência está furado (alto):** o cron de cobrança vencida só consulta `status=='pending'` e vira o doc para `overdue` na mesma execução — logo os reminders D+3/D+7/D+15/D+30 **nunca disparam**. Some-se a isso: geração de mensalidades 100% manual e **zero consequência** para o aluno inadimplente.

- **Isolamento Mercado Pago confirmado** na camada de aplicação: o resolver impõe precedência do MP e recusa cobrança em gateway desligado. Abacate/Asaas estão inertes; os achados nessas áreas são código latente (low/info).

- **Áreas sólidas verificadas:** unidade reais×centavos (sem regressão do bug 100x), idempotência de PIX/assinaturas/settle, cancelamento não-best-effort (estado terminal só após confirmação MP), e o grant idempotente da aula particular (1 presença por pagamento).

---

## Achados por área

### Pagamentos (Mercado Pago)

- **Falha de criação que deixa preapproval vivo permite assinatura duplicada (double-charge)** — `[high/money-loss]` · `functions/server_functions.js:4286-4298` (catch), `:4164-4190` (dup guard), `:4061` (heal). **Impacto:** o cartão pode ser cobrado em dois preapprovals todo mês até detecção manual. O doc vira `status:'error'` sem `mpPreapprovalId` e a guarda de duplicidade só cobre `['pending','authorized','paused']`. **Correção:** incluir `'error'` (com `createdAt` recente) na varredura da guarda OU, no catch, fazer `GET /preapproval/search` por `external_reference` para detectar/cancelar/adotar o órfão; ampliar o heal para promover docs `'error'`.

- **Cash-marking de aula particular não cancela o PIX MP em aberto → double-charge silencioso** — `[high/money-loss]` · `functions/server_functions.js:5052-5068` vs `lib/services/payment_service.dart:650-679`. **Impacto:** família cobrada duas vezes (dinheiro + PIX); o `mpMktSettle` não flagra duplicidade (o webhook chega com o mesmo `chargeId` do PIX cunhado), caindo em idempotente silencioso, **sem registro nem alerta**. **Correção:** no branch `markPaidCash`, espelhar `PaymentService.markAsPaid` — deletar campos `pix*` e chamar `cancelMpPix` quando `paymentGateway==='mercadopago'`; tratar `status===paid` sem `gatewayPaymentId` como duplicidade no `mpMktSettle`.

- **Double-charge cross-method (PIX vivo + cartão pago) é detectado, não prevenido** — `[medium/money-loss]` · `functions/server_functions.js:3355-3383` vs `3636-3671` e `4793-4808`/`4918-4933`. **Impacto:** PIX e cartão não compartilham lock; cobrança dupla real, recuperada só por reembolso manual após notificação. **Correção:** em `createMpCardPayment`, recusar/cancelar quando houver PIX vivo não pago (`fin.gatewayPaymentId && fin.pixCode && pixExpiresAt>now`); ou reusar o lock estilo `mpAcquirePixMint`.

- **PIX persiste `gatewayPaymentId` + QR vazio em resposta anormal do MP (sem `transaction_data`)** — `[low/ux]` · `functions/server_functions.js:3176-3184`, `3373-3383`. **Impacto:** raro; aluno vê sheet "ok" com QR em branco e timer de 24h, sem poder pagar. Sem double-charge (retry re-minta). **Correção:** se `!tx || !tx.qr_code`, lançar `mapMpPixError` em vez de persistir QR vazio.

- **`createMpCardPayment` mapeia toda recusa MP para um `internal` opaco** — `[low/ux]` · `functions/server_functions.js:3634-3666`. **Impacto:** recusas de cartão que caem em 4xx mostram "Falha ao processar o cartao" sem orientação. **Correção:** espelhar `mapMpPixError`, inspecionar `status_detail`/`e.data.cause` e retornar mensagens pt-BR acionáveis.

- **Validação de CPF gateia PIX mas é opcional no cartão; só checa comprimento, não checksum** — `[low/correctness]` · `functions/server_functions.js:3335-3339`, `3613/3659`, `3139/3169`. **Impacto:** baixo; CPF 11-dígitos inválido vai ao MP e pode ser recusado com erro genérico de cartão. **Correção:** rodar `validateCPF()` cedo nos caminhos MP.

- **`resumeMpSubscription` não revalida o termo (reativa assinatura que já cumpriu N meses)** — `[low/correctness]` · `functions/server_functions.js:4432-4459`, `3915-3945`. **Impacto:** cobrança além do termo contratado; mitigado pelo `termGuard` diário (janela ~1 dia). **Correção:** rejeitar quando `months>0 && chargesPaid>=months` (ou `now>=termEndsAt`); idem `updateSubscriptionCard`.

- **`updateSubscriptionCard` re-autoriza preapproval além do termo sem checagem** — `[low/money-loss]` · `functions/server_functions.js:4461-4499`. **Impacto:** bounded — overcharge guard do `mpSubSettleCycle` flagra como `needsRefund` e o `termGuard` re-cancela (no máximo ~1 ciclo auto-detectado). **Correção:** centralizar `assertSubscriptionStillBillable()` para resume/updateCard/pause.

- **`requestWithdrawal` chama payout externo ANTES do débito atômico de saldo** — `[low/race-condition]` · `functions/server_functions.js:2428-2507`. **Impacto:** latente — fluxo AbacatePay desligado em prod; double/over-payout possível só quando saque for habilitado. **Correção:** reservar fundos em transação antes do payout; idempotency key; compensação no erro.

- **`requestWithdrawal` não gateia gateway habilitado nem valida a resposta da AbacatePay** — `[low/correctness]` · `functions/server_functions.js:2446-2525`. **Impacto:** latente/defesa-em-profundidade. **Correção:** precondição `abacatePayEnabled===true`; reconciliar valor/status reais.

- **`requestWithdrawal` (callable) e método Flutter sem caller no app — endpoint de dinheiro órfão** — `[low/product-gap]` · `functions/server_functions.js:2370`; `lib/services/abacate_pay_service.dart:287-310`. **Impacto:** sem UI de saque; o método Flutter aponta para o backend Tatami/migration. **Correção:** ou enviar UI com salvaguardas, ou remover o callable/método mortos.

- **`mercadoPagoMarketplaceWebhook` sem anti-replay (freshness de `ts`)** — `[low/idempotency]` · `functions/server_functions.js:4562-4579`. **Impacto:** divergência do contrato do webhook de paywall; replay é no-op (re-fetch live + settle idempotente). **Correção:** espelhar a janela de 5 min do `mercadoPagoWebhook`.

- **Webhook de paywall infere período pelo valor pago quando `external_reference`/metadata ausentes** — `[info/product-gap]` · `functions/index.js:1160-1166`, `1266-1270`. **Nota do verificador:** não realizável hoje (checkout sempre envia `external_reference`+`period`; sem cupom/desconto). Tratar como nota de robustez.

- **Tokens OAuth MP em cleartext (mitigado por rules + acesso só-CF)** — `[info/security]` · `functions/server_functions.js:2835-2845`; `firestore.rules:700-703`. **Correção opcional:** envelope-encrypt com Cloud KMS para backups/exports.

**Áreas verificadas como corretas (info):** unidade reais×centavos sem regressão 100x (`server_functions.js:3311-3315`, `mpMktSettle:4937-4958`); idempotência PIX + mint lock + X-Idempotency-Key único (`:3141-3147`, `mpAcquirePixMint:3212-3265`); valor recorrente em REAIS no preapproval (`:4203/:4279`); cancelamento não-best-effort, estado terminal só após confirmação MP (`:4358-4383`); idempotência dos jobs agendados/settle (`:3770-3788`); `termGuard` não conclui assinatura nunca-paga por tempo (`:5446-5455`); reconcile a cada 6h reconcilia `paused` mesmo de pausa intencional do aluno (info/correctness — otimização, `:5543-5560`).

### Cobranças e Notificações (proxy WhatsApp/email)

- **Escada de cobrança WhatsApp nunca dispara além do 1º dia** — `[high/product-gap]` · `functions/server_functions.js:891-916`. **Impacto:** cadência de dunning é de UM disparo (D+0/D+1); D+3/D+7/D+15/D+30 nunca chegam. O mesmo defeito afeta push + notificação interna no mesmo loop. **Correção:** consultar `status in ['pending','overdue']`, mantendo dedup por estágio via `lastReminderStage`. **Nota:** canal WhatsApp inerte até `WHATSAPP_API_KEY` ser setado; impacto live hoje é a push in-app.

- **Sem opt-out/consentimento por aluno para cobrança WhatsApp (risco LGPD)** — `[medium/product-gap]` · `functions/server_functions.js:387`, `:403`. **Impacto:** único gate é por academia; nenhuma flag por aluno; risco LGPD + bloqueio do número no provedor quando habilitado. **Correção:** flag per-student (`whatsappOptOut`), rodapé de opt-out, log de consentimento.

- **Envio em massa no Flutter não lê/grava `lastReminderStage` — duplica com o cron** — `[medium/idempotency]` · `lib/services/billing_reminder_service.dart:992-1053`, `:838-909`. **Impacto:** mesmo aluno pode receber pelo cron e pelo "cobrar todos" no mesmo dia; reenvio manual ilimitado. **Correção:** unificar dedup (gravar `lastReminderStage` também no envio manual, idealmente via CF compartilhada).

- **`sendWhatsAppServer` marca 'sent' só por `res.ok`, sem inspecionar o body** — `[low/idempotency]` · `functions/server_functions.js:197`, `:441-446`. **Impacto:** 200-com-erro grava dedup e queima o estágio para sempre. **Correção:** parsear o corpo; `sent:true` só com confirmação do provedor (`body.success===true`).

- **Crons chamam `financial.dueDate.toDate()` sem null-guard nem try/catch por doc** — `[low/correctness]` · `functions/server_functions.js:907`, `:1019`. **Impacto:** um financial sem `dueDate` (legado/importado) aborta o run inteiro de todas as academias. **Correção:** guardar `dueDate` como no helper `:412` e envolver loops por-doc/por-academia em try/catch.

- **Telefone enviado ao proxy sem normalização/validação no servidor** — `[low/correctness]` · `functions/server_functions.js:398/403/191`. **Impacto:** inconsistência de entrega entre cron (servidor) e app (cliente normaliza). **Correção:** portar `_normalizePhone` (dígitos + prefixo 55) para o servidor.

### Graduação

- **Sheet de promoção manual calcula a próxima faixa pela escada BJJ para TODOS os esportes (`sportId` perdido)** — `[high/correctness]` · `lib/screens/admin/graduation_screen.dart:647`, `:853-866`. **Impacto:** promoção multi-esporte (Muay Thai/karate/judô/luta livre) vira no-op ou faixa errada — feature core quebrada na UI admin. `_getBeltLabel` (`:571`, `:707-708`) sofre o mesmo. **Correção:** passar `sportId` para `_getNextBelt` e `_getBeltLabel`; resolver categoria (kids/adult); validar `newBelt != currentBelt` antes de `promote()`.

- **Sheet hardcoda teto de graus em `<4`, ignorando `maxStripes` por esporte/grade** — `[medium/data-integrity]` · `lib/screens/admin/graduation_screen.dart:595-601`. **Impacto:** faixas-pretas limitadas a 4 (deveria 6/10); Muay Thai (armbands com `maxStripes:0`) ganha graus-fantasma. `promote()` também não clampa. **Correção:** derivar `maxStripes` de `getGradeDefinition(sportId, currentBelt)`; esconder graus para esportes sem stripe.

- **Auto-promoção roda client-side fire-and-forget sem idempotência/lock — presenças concorrentes podem dupla-promover** — `[medium/race-condition]` · `lib/services/attendance_service.dart:417-423/490-496/505-550`; `lib/services/belt_progression_service.dart:481-593/826-932`. **Impacto:** docs duplicados de `beltProgressions`, conquistas públicas duplicadas. Só em academias com `graduationMode=='auto'`; requer concorrência real (2 dispositivos/operadores). **Correção:** mover `promote()` para CF on-attendance-create OU transação com id determinístico (`studentId_sport_targetGrade`).

- **Auto-promoção falha silenciosamente (e nunca retenta) quando a chamada é feita por monitor** — `[low/product-gap]` · `firestore.rules:505-507` vs `:939-945`; `lib/services/attendance_service.dart:505-547`. **Impacto:** em academias monitor-only com auto-graduação, alunos elegíveis nunca são promovidos. Recuperável por qualquer check-in de staff (elegibilidade não decai). **Correção:** rodar auto-promoção server-side OU surfacing de "promoção pendente".

- **Self check-in do aluno infla `attendanceCount` que alimenta a auto-graduação (QR não validado criptograficamente)** — `[low/data-integrity]` · `firestore.rules:445-457`, `508+`; `lib/services/attendance_service.dart:521-526`. **Impacto:** não há graduação automática indevida (writes de `promote()` são staff-gated e falham silenciosamente); o efeito real é inflar o flag de elegibilidade mostrado ao staff. **Correção:** gatear elegibilidade em presenças verificadas por staff/monitor; ou validar QR server-side com token assinado.

**Áreas verificadas como corretas (info):** regra de `beltProgressions` não valida `studentId`/sequência (info — padrão "trust-the-staff" de todo o arquivo de rules; remediar em CF/audit-log, `firestore.rules:939-945`); auto-promoção bloqueia ranks acima de preta e zera graus na troca de faixa (`belt_progression_service.dart:251-275/853-858`).

### Gestão de Equipe (membros, instrutores, códigos)

- **Qualquer autenticado pode se auto-vincular como aluno a QUALQUER academia com QUALQUER `studentId` (sem código)** — `[critical/security]` · `firestore.rules:273-290` (create Pattern 3), `:305-329` (update Path C); helpers `isOwnStudent :79-91`, `isOwnStudentRecord :94-106`. **Impacto:** tomada de conta / vazamento de PII e financeiro em massa; sobrescrita de `linkedUserId/email/cpf/phone` do aluno-alvo; cross-academy sem convite. **Correção:** rotear 100% do join de aluno pelo CF `joinAcademy`; remover create Pattern 3 / update Path C; se mantido client-side, exigir prova de consentimento (linkCode não-usado correspondente OU `students/{id}.linkedUserId` nulo/igual ao caller).

- **`createAccountWithLinkCode` grava vínculo 100% client-side, ignorando o orphan-claim guard** — `[high/security]` · `lib/providers/auth_provider.dart:557-655`; `lib/services/global_user_service.dart:186-238`; `lib/services/link_code_service.dart:278-297`. **Impacto:** código vazado/cunhado por monitor permite linkar a conta nova a registro de aluno existente, sequestrando histórico/financeiro; 3 writes não-atômicos. **Correção:** migrar para o CF `joinAcademy` após criar a conta Auth; eliminar `markAsUsed`/`linkUserToAcademy`/escrita direta de `students` no cliente.

- **Caminho de primeiro cadastro por link-code bypassa o orphan check server-side (account takeover)** — `[high/security]` · `lib/providers/auth_provider.dart:557-655`; `lib/services/link_code_service.dart:278-297`; contraste `functions/index.js:203-227`. **Impacto:** monitor cunha código apontando para registro de qualquer aluno e sobrescreve `linkedUserId` da conta recém-criada; o `markAsUsed` e o retry inline (`auth_provider.dart:632-637`) fazem `student.update` sem checar `linkedUserId` prévio. **Correção:** rotear pelo `joinAcademy` OU regra Firestore que só permita escrita de `linkedUserId` quando o prévio for nulo; recusar alunos já linkados em `validateCodeGlobally`/`markAsUsed`.

- **Qualquer autenticado pode QUEIMAR códigos de convite de outra academia — DoS de onboarding** — `[low/security]` · `firestore.rules:584-587`, `:609-612`; leitura cross-academy `:1198-1206`. **Impacto:** enumeração + marcação em massa de códigos como usados, sabotando onboarding; sem escalonamento de privilégio. **Correção:** tornar a marcação server-only (Admin SDK) OU exigir que o caller seja membro/redentor real.

- **Admin não-dono poderia rebaixar/revogar o DONO — sem proteção de `ownerId` em demote/revoke** — `[low/correctness]` · `functions/index.js:566-608`, `:613-662`. **Impacto:** risco latente de tomada de academia se surgir 2º admin. **Nota do verificador (importante):** um 2º admin **já é alcançável hoje** via `firestore.rules:370-375` (qualquer autenticado cria `academies/{id}/users/{seuUid}` com `role=='admin'`, sem checar `ownerId`) — esse é o vetor real de takeover, fora do local citado. **Correção:** bloquear ação quando alvo == `ownerId` **e** corrigir a regra de self-create de admin em `firestore.rules:370-375`.

**Áreas verificadas como corretas (info):** controles de escalonamento no servidor (`extraPermissions` clampadas, promote/demote/revoke exigem admin, código de instrutor só por admin — `functions/index.js:48-74/361-366/502-503`); script de backfill idempotente e bem-escopado (concede permissões por design — `functions/scripts/backfill_instructor_permissions.js:61-65/142-190`).

### Login e Onboarding

- **Caminho de primeiro cadastro bypassa o orphan check (account takeover)** — `[high/security]` — *ver detalhamento idêntico na seção Gestão de Equipe acima.*

- **Conta Firebase Auth órfã em falha parcial no onboarding (dead-end `email-already-in-use`)** — `[medium/product-gap]` · `lib/providers/auth_provider.dart:566-589`, `478-543`; `lib/screens/auth/link_code_screen.dart:284-295`. **Impacto:** usuário com falha mid-flow não completa o cadastro nem re-registra com o mesmo email (Auth criado primeiro, writes Firestore depois). **Correção:** provisioning idempotente/recuperável (detectar usuário autenticado-mas-não-provisionado e completar os docs), ou mover tudo para uma CF retentável; oferecer "entrar para finalizar o vínculo".

- **Validação de email aceita endereços malformados (só checa `@`)** — `[info/ux]` · `lib/screens/auth/login_screen.dart:170-173`, `link_code_screen.dart:773-775`. **Nota do verificador:** o erro `invalid-email` do Firebase já é mapeado para mensagem inline; impacto de fricção descrito não ocorre de fato. **Correção:** regex/validador consistente; opcionalmente confirmar email pós-signup.

**Áreas verificadas como corretas (info):** acesso responsável-adulto (kids→dependente) é read-scoped e o link adulto é staff-only — sem vazamento cross-account (`firestore.rules:121-125/399-401/417-426`).

### Retenção e Inadimplência (efetividade)

- **Escalonamento de cobrança vencida nunca dispara após o 1º dia** — `[high/product-gap]` · `functions/server_functions.js:891-916`. *(Detalhado em Cobranças.)* Raiz: query `status=='pending'` + flip terminal para `'overdue'` no mesmo run. **Correção:** `status in ['pending','overdue']`.

- **Geração mensal de cobranças é 100% manual — alunos sem assinatura de cartão podem evadir sem nunca virar inadimplentes** — `[high/product-gap]` · `lib/services/payment_service.dart:770-942`. **Impacto:** se o admin não roda `generateMonthlyTuitions`, não há `financial pending` → nenhum `dueDate` para vencer → o aluno some da detecção; "taxa de cobrança" inflada. **Correção:** cron mensal server-side por academia, dedupe idempotente por `(studentId, referenceMonth)`; alternativamente, alerta proativo ao admin.

- **`scheduledOverdueCheck`/`scheduledDueSoonReminder` sem try/catch por academia — uma academia ruim aborta o job inteiro** — `[high/correctness]` · `functions/server_functions.js:880-983`. **Impacto:** um doc malformado ou erro transitório derruba a cobrança de toda a base naquele dia (job roda 1x/dia). **Correção:** envolver o loop por-academia em try/catch (espelhar o cron de gamificação `:1403-1412`); null-guard em `dueDate`; migrar para `forEachMpAcademy`.

- **`getStudentUserId` varre a coleção `userAcademyMapping` inteira por aluno, a cada cron** — `[medium/correctness]` · `functions/server_functions.js:142-159`. **Impacto:** custo/latência O(alunos×mappings); aluno sem conta no app tem a notificação in-app descartada silenciosamente. **Correção:** leitura direta `userAcademyMapping.doc(uid)` ou índice reverso `studentId→uid`; canal alternativo quando não houver uid.

- **Inadimplência não tem NENHUMA consequência (não bloqueia check-in, reserva nem acesso)** — `[medium/product-gap]` · `lib/services/retention_service.dart:238-267`. **Impacto:** inadimplir é "grátis" para o aluno; remove o incentivo de regularização. **Correção:** consequência configurável por academia (aviso no check-in → restrição de reserva >N dias → soft-paywall no portal), tom "firme mas humano".

- **Marcos de gamificação (streak/ranking) são gravados mas NUNCA notificam o aluno** — `[medium/product-gap]` · `functions/server_functions.js:1185-1219`. **Impacto:** o gatilho de retenção mais potente (streak) não fecha o loop — só aparece passivamente na timeline/ranking. **Correção:** em `upsertAutoAchievement`, no `create()` true, resolver uid e enviar push + notificação interna (idempotente pelo retorno true).

- **Lembrete de expiração de trial da academia (conversão SaaS) DESABILITADO (bloco comentado)** — `[medium/product-gap]` · `functions/index.js:1553-1665`. **Impacto:** academias em trial caem no paywall sem nudge prévio, reduzindo conversão trial→pago. **Correção:** finalizar/reabilitar `trialExpiryReminder` (lógica de janela e dedupe já prontas); reusar o proxy de notificação se o email não estiver maduro.

- **Cobrança de aula avulsa/particular usa wording de "mensalidade atrasada" no cron** — `[low/ux]` · `functions/server_functions.js:905-955`. **Impacto:** mensagem confusa (aula avulsa cobrada como mensalidade, com ameaça de suspensão no template D+30 — este só no WhatsApp inerte). **Correção:** diferenciar copy por `type`; restringir a régua a `type=='monthly_tuition'`.

- **`scheduledDueSoonReminder` cobre janela fixa de 3 dias e some quando vira `overdue`** — `[low/product-gap]` · `functions/server_functions.js:1010-1064`. **Impacto:** cadência preventiva estreita; push diária sem dedupe na janela. **Correção:** antecedência configurável (D-7, D-2); dedupe por estágio no a-vencer.

- **Detecção de vencido usa comparação direta de timestamp sem normalizar fim do dia (BRT)** — `[low/correctness]` · `functions/server_functions.js:907-921`. **Impacto:** "atrasada há 0 dias" no próprio dia do vencimento às 09:00 BRT. **Nota:** o getter `isOverdue` do app usa a MESMA comparação crua — não há divergência app↔servidor (verificador corrigiu o achado nesse ponto). **Correção:** normalizar ambos para fim do dia em `America/Sao_Paulo`.

- **Risco de inadimplência (peso 20) só conta `status=='overdue'`, herdando o furo da detecção** — `[low/product-gap]` · `lib/services/retention_service.dart:238-241`. **Impacto:** aluno vencido ainda em `pending` pontua 0 no fator de pagamento; mitigado pelo cron diário (janela ~1 dia). **Correção:** contar `dueDate` vencido com `status not in {paid, cancelled}` (reusar `isOverdue`).

### Gestão de Equipe / Isolamento de gateway (transversal)

- **`firestore.rules` academy-update permite admin flipar `abacatePayEnabled`/`asaasEnabled`/`mpConnected` diretamente** — `[low/correctness]` · `firestore.rules:345-347`. **Impacto:** invariante "MP-only" só enforçado por dados, não por rules; admin (ou token comprometido) pode forçar o resolver para AbacatePay (`mpConnected:false + abacatePayEnabled:true`) — escopo limitado à própria academia. **Correção:** tornar as flags server-only (adicionar ao `affectedKeys` bloqueado); só CFs OAuth/toggle as alteram.

---

## Veredito: isolamento Mercado Pago

O isolamento **se mantém na camada de aplicação**: o `PaymentGatewayResolver` (`lib/services/payment/payment_gateway_resolver.dart:36-61`) checa `mpConnected` primeiro, retorna `PaymentGateway.none` apenas após leitura bem-sucedida sem flag (re-lança em falha transitória), e todos os call sites de PIX/cartão tratam `none` com mensagem amigável sem nunca alcançar uma cobrança — não há "dead-end charge" possível pelo cliente. Abacate/Asaas estão **inertes em produção** (AbacatePay forçado `false` no connect MP; wallet de saque sem fundos; saque é código órfão/latente apontando para o backend Tatami). O **único risco residual** é defesa-em-profundidade: as flags de gateway são editáveis por admin via `firestore.rules:345-347`, então o invariante "MP-only" é garantido por dados/UI e não por regra — recomenda-se torná-las server-only para transformar a convenção em garantia rígida.

---

## Retenção & Inadimplência — avaliação de efetividade

O funil **não cumpre o objetivo de negócio hoje**. As quatro etapas — detecção de vencido → lembrete → escalonamento → consequência — têm rupturas em cada estágio, e a feature principal (régua de cobrança escalonada) está efetivamente inoperante:

- **Detecção é incompleta e frágil.** A geração de mensalidades para alunos sem assinatura de cartão é 100% manual (`payment_service.dart:770-942`) — quem não gera não detecta. E o cron de detecção não tem try/catch por academia (`server_functions.js:880-983`), então um único doc sujo zera a cobrança de toda a base naquele dia.
- **Escalonamento está quebrado.** O cron consulta só `status=='pending'` e vira o doc para `overdue` no mesmo run (`:891-916`), então D+3/D+7/D+15/D+30 **nunca disparam**. O aluno inadimplente recebe um único toque e some do funil automatizado. (O canal WhatsApp ainda está inerte sem `WHATSAPP_API_KEY`, então o blast hoje é só a push in-app.)
- **Consequência é inexistente.** Estar `overdue` não bloqueia check-in, reserva nem acesso (`retention_service.dart:238-267`) — inadimplir não tem custo para o aluno.
- **O loop de retenção positivo (gamificação) não fecha.** Streaks e ranking são gravados mas nunca notificam (`server_functions.js:1185-1219`), desperdiçando o gatilho de hábito mais potente.

**Recomendações concretas, em ordem de impacto:**
1. Trocar a query do `scheduledOverdueCheck` para `status in ['pending','overdue']`, mantendo dedup por `lastReminderStage` — destrava toda a escada D+3→D+30.
2. Criar cron mensal server-side de geração de mensalidades (dedupe idempotente por `studentId+referenceMonth`) — fecha o buraco de detecção para alunos PIX/dinheiro.
3. Envolver os crons de cobrança em try/catch por academia + null-guard de `dueDate` — impede que um tenant ruim derrube a cobrança global.
4. Notificar marcos de gamificação (push + interna) no `upsertAutoAchievement` — fecha o loop de retenção.
5. Introduzir consequência configurável por academia (aviso no check-in → restrição de reserva → soft-paywall).
6. Habilitar/finalizar o `trialExpiryReminder` para conversão trial→pago no nível SaaS.

---

## Plano de ação priorizado

| # | Prioridade | Área | Ação | Esforço |
|---|-----------|------|------|---------|
| 1 | P0 — Crítico | Gestão de Equipe / Rules | Rotear 100% do join de aluno pelo CF `joinAcademy`; remover/endurecer create Pattern 3 e update Path C (`firestore.rules:273-290/305-329`) exigindo registro órfão ou linkCode válido | Médio |
| 2 | P0 — Crítico | Login/Onboarding | Migrar `createAccountWithLinkCode` para o CF `joinAcademy`; eliminar `markAsUsed`/escrita direta de `students` no cliente (`auth_provider.dart:557-655`, `632-637`) | Médio |
| 3 | P0 — Segurança | Gestão de Equipe / Rules | Corrigir self-create de admin sem checar `ownerId` (`firestore.rules:370-375`) + bloquear demote/revoke contra `ownerId` (`functions/index.js:566-662`) | Baixo |
| 4 | P0 — Money | Cobranças / Aula particular | No `markPaidCash`, deletar campos `pix*` e chamar `cancelMpPix` (`server_functions.js:5052-5068`); tratar settle `paid` sem `gatewayPaymentId` como duplicidade alertável | Baixo |
| 5 | P0 — Money | Pagamentos / Assinaturas | Incluir `'error'` na guarda de duplicidade do `createMpSubscription` e/ou `GET /preapproval/search` no catch para adotar/cancelar órfão (`server_functions.js:4164-4190/4286-4298`) | Médio |
| 6 | P0 — Segurança | Pagamentos / Webhooks | Fazer `caktoWebhook` falhar fechado quando `CAKTO_WEBHOOK_SECRET` ausente/vazio (`functions/index.js:937-948`) | Baixo |
| 7 | P1 — Retenção | Cobranças / Crons | Query do overdue-cron `status in ['pending','overdue']` + dedup por `lastReminderStage` — destrava escada D+3→D+30 (`server_functions.js:891-916`) | Baixo |
| 8 | P1 — Resiliência | Cobranças / Crons | try/catch por academia + null-guard de `dueDate` nos crons de cobrança (`server_functions.js:880-983`, `907`, `1019`) | Baixo |
| 9 | P1 — Retenção | Inadimplência | Cron mensal server-side de geração de mensalidades, dedupe idempotente por `(studentId, referenceMonth)` (substituir botão manual `payment_service.dart:770-942`) | Médio |
| 10 | P1 — Correctness | Graduação | Passar `sportId` para `_getNextBelt`/`_getBeltLabel` e derivar `maxStripes` por grade na sheet de promoção (`graduation_screen.dart:595-601/647/853-866`) | Baixo |
| 11 | P2 — Money | Pagamentos / PIX-cartão | Bloquear cartão quando há PIX vivo não pago, ou compartilhar lock entre métodos (`server_functions.js:3636-3671`) | Médio |
| 12 | P2 — Retenção | Gamificação | Notificar marcos de streak/ranking (push + interna) no `upsertAutoAchievement` (`server_functions.js:1185-1219`) | Baixo |
| 13 | P2 — Hardening | Isolamento de gateway | Tornar `abacatePayEnabled`/`asaasEnabled`/`mpConnected` server-only nas rules (`firestore.rules:345-347`) | Baixo |
| 14 | P2 — LGPD | Cobranças | Flag de opt-out por aluno + dedup unificado cron/manual no WhatsApp (`server_functions.js:387`, `billing_reminder_service.dart:992-1053`) | Médio |

---

**Resumo de severidades:** 1 critical · 8 high · 7 medium · 18 low · 14 info. **Refutados/rebaixados na verificação adversarial:** 14. Os achados info incluem validações positivas importantes (unidade reais×centavos, idempotência MP, cancelamento não-best-effort, isolamento MP na camada de app) que confirmam que correções anteriores se mantêm sem regressão.