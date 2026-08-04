> **Arquivado (2026-07):** auditoria pontual de 2026-06-11. Os achados críticos
> (`pausedBy` indistinguível de pausa por recusa de cartão, cancelamento
> best-effort que seguia cobrando após falha no PUT do MP) foram corrigidos no
> código atual (`server_functions.js` — guarda `pausedBy:'user'` e
> `cancelMpSubscription` com propagação não-best-effort). Para o estado vivo da
> integração MP, ver `docs/PAGAMENTOS_MP.md` e `docs/recorrencia-mp-contract.md`.
> Mantido aqui só como registro histórico.

# Auditoria da Integração Mercado Pago — GraduaBJJ

**Data:** 2026-06-11 · **Branch:** `firebase-production` · **Método:** workflow multi-agente (6 auditores por dimensão + verificação adversarial por achado; 46 agentes). Todo achado abaixo foi confirmado por um verificador independente lendo o código real; 4 achados foram refutados e descartados.

## Avaliação geral por dimensão

### Assinaturas recorrentes
O núcleo da liquidação de ciclos é bem projetado: id financeiro determinístico (sub_{subId}_{paymentId}) dentro de transação torna o settle idempotente, a conclusão do termo é primariamente por contagem (chargesPaid>=months) e o dunning não consome tentativa em falha transitória de API. Porém, a máquina de estados não registra INTENÇÃO: pausa do aluno é indistinguível de pausa por cartão recusado, e o reconcile+dunning reativam deterministicamente uma assinatura pausada pelo usuário — cobrança sem consentimento. Além disso, cancelamentos "best-effort" no MP finalizam o estado local mesmo quando o PUT falhou (aluno segue sendo cobrado após cancelar/completar o termo), e createMpSubscription não tem guarda contra assinatura ativa duplicada do mesmo aluno/plano.

### Webhooks & liquidação
O caminho marketplace está bem mais maduro que o esperado: HMAC fail-closed com timingSafeEqual, settle transacional com guarda de status + validação de valor (reais, tolerância de 1 centavo), id determinístico para ciclos de assinatura e três crons de backstop. O que sobrou é estrutural: (1) mpSubSettleCycle reabre assinaturas 'completed' e registra como mensalidade normal uma cobrança ALÉM do termo contratado quando o cancel no MP falha; (2) o webhook legado do paywall (mercadoPagoWebhook) não tem guarda contra external_reference do marketplace e concede dias de paywall por valor pago — cross-talk possível se o app MP estiver configurado para receber eventos das contas vendedoras OAuth; (3) vários caminhos respondem 200 quando o doc ainda não existe/não foi achado, queimando os retries do MP; (4) refund/chargeback não é tratado no marketplace (financial/pedido fica 'paid' para sempre).

### Crons de resiliência
O desenho geral é sólido: try/catch por academia (token MP revogado de uma academia não derruba o lote), idempotência de liquidação por id determinístico (sub_{id}_{paymentId}), dunning que não consome tentativa em falha transitória de API, e gates de notificação dedicados (dunningExhaustedNotifiedAt, expiryNotifiedAt mensal). Timezone está correto na prática (crons às 6h15-6h45 SP = 9h UTC, mesma data civil). O que preocupa é estrutural: o term guard marca 'completed' mesmo quando o cancel do preapproval no MP falha — tirando a assinatura de todas as queries dos crons enquanto o MP continua cobrando o aluno; as 4 crons fazem full-scan sequencial de 'academies' sem timeoutSeconds (default 60s em v2), o que com crescimento causa starvation silenciosa e determinística das mesmas academias; e a drenagem de authorized_payments não pagina, podendo perder financials de ciclos antes de completar por data.

### OAuth & segurança
A base do OAuth marketplace está sólida: o `state` é `academyId:nonce` com nonce aleatório de 64 bits validado server-side e anti-replay de 10 min, então academia A não consegue plantar token na academia B; os tokens MP ficam em `academies/{id}/private/*` com regra `read:false/write:false` e catch-all deny — clientes não leem credenciais; o callback exige nonce válido; o refresh de token usa lock distribuído com reclaim de lock órfão; e os pagamentos derivam valor/ownership server-side (amount em REAIS, conferido contra o registro). Os problemas que sobram são estruturais e de estados inconsistentes: (1) o disconnect deixa assinaturas recorrentes órfãs cobrando os alunos sem que ninguém consiga gerenciá-las; (2) o resolvedor de identidade só enxerga a academia primária, bloqueando pagamentos/conexão em academias secundárias; (3) o caminho de refresh deixa flag de reauth espúria e derruba pagamentos concorrentes; (4) a assinatura do webhook não cobre o parâmetro `acad`.

### Pagamentos avulsos (Pix/cartão)
O caminho de mensalidade está bem defendido: valor derivado server-side de financials.amount (REAIS, canônico), cross-check em centavos com tolerância de 1 centavo, guard de CPF/email antes do MP, webhook com HMAC fail-closed e settle transacional idempotente. O que preocupa é estrutural na LOJA: o pedido é criado direto pelo cliente no Firestore e o servidor "deriva" o total dos preços escritos pelo próprio cliente — a defesa é circular e permite pagar centavos por um produto caro. Além disso, a idempotency key fixa do cartão bloqueia retentativas legítimas após uma recusa, e o settle recusa silenciosamente pagamentos com valor divergente (dinheiro debitado do aluno sem reflexo no Firestore, com resposta 200 ao MP).

### Flutter (frontend)
A camada de pagamento está bem estruturada nos pontos centrais: tokenização MP é PCI-safe (cartão vai direto à API do MP com a public key da academia conectada, sem logs de dados sensíveis), valores são consistentemente enviados em centavos com derivação server-side do valor real, double-tap é guardado por flags de loading, e o PixPaymentSheet tem bons estados (CPF, erro+retry, expirado+regenerar, listener em tempo real). O que preocupa: (1) janela real de assinatura duplicada — o CTA "Assinar" aparece enquanto o stream carrega e o retry pós-timeout recria o preapproval sem dedup no cliente nem no backend; (2) o CardPaymentSheet ignora o PaymentGatewayResolver e, numa falha transitória de leitura do Firestore, despeja número+CVV crus no fluxo Asaas/AbacatePay; (3) o listener de confirmação Pix aceita qualquer `paymentDate != null` como pago, o que mostra "Pagamento Confirmado!" sem dinheiro recebido em cobranças reativadas.

## Achados confirmados (36)

---

## Severidade: CRÍTICO

### 1. Pausa feita pelo aluno é reativada automaticamente pelo dunning/reconcile — cobrança sem consentimento
`functions/server_functions.js:4333` · dimensão: Assinaturas recorrentes · confiança do verificador: high

**Problema:** pauseMpSubscription (linhas 3715-3729) pausa o preapproval no MP e grava status:'paused', mas NÃO registra que a pausa foi iniciada pelo usuário. O webhook mpSubSyncPreapproval (linha 3513) e o scheduledSubscriptionReconcile (linhas 4220-4226, que reconcilia TODA assinatura 'paused' a cada 6h) tratam qualquer preapproval 'paused' como falha de cobrança: setam needsReauth=true e agendam nextRetryAt (+1 dia). O scheduledSubscriptionDunning então faz PUT /preapproval {status:'authorized'} e REATIVA a assinatura que o aluno pausou de propósito — o MP volta a cobrar o cartão em 1-2 dias, contrariando a UI que promete 'As próximas cobranças ficam suspensas até você retomar' (subscription_detail_sheet.dart:561). O caminho via reconcile é determinístico (não depende de webhook), então TODA pausa de usuário vira cobrança indevida.

**Evidência:**
```
// pauseMpSubscription: só grava status, sem origem da pausa
await subRef.update({ status: 'paused', updatedAt: FV.serverTimestamp() });
// reconcile (4220-4226): qualquer 'paused' entra em dunning
if (pa.status === 'paused') {
  syncUpdate.needsReauth = true;
  syncUpdate.lastFailureAt = FV.serverTimestamp();
  if (sub.nextRetryAt == null) {
    syncUpdate.nextRetryAt = admin.firestore.Timestamp.fromMillis(
      Date.now() + DUNNING_BACKOFF_DAYS[0] * 24 * 60 * 60 * 1000);
// dunning (4333-4334): reativa no MP
await mpRequest('PUT', `/preapproval/${sub.mpPreapprovalId}`,
  { token, body: { status: 'authorized' } });
```
**Recomendação:** Em pauseMpSubscription, gravar pausedBy:'user' (e needsReauth:false). Em mpSubSyncPreapproval, no reconcile e no dunning, pular o fluxo de needsReauth/nextRetryAt/reativação quando pausedBy==='user'; limpar o flag apenas quando o próprio usuário retomar (callable de resume) ou trocar o cartão.

### 2. Loja: total da cobrança derivado de preços escritos pelo próprio cliente — permite pagar R$0,01 num pedido de R$200
`functions/server_functions.js:2844` · dimensão: Pagamentos avulsos (Pix/cartão) · confiança do verificador: high

**Problema:** orderExpectedTotalReais soma it.price * it.quantity dos items do pedido, e o comentário afirma que 'each item carries the server-validated price'. Isso é FALSO: pedidos de loja são criados direto pelo cliente no Firestore (sem CF de criação — o próprio comentário de orderEffectivePolicy em :2864 admite isso), e a rule de storeOrders (firestore.rules:670-674) só exige status=='pending_payment' e isPositiveAmount(total) — NÃO valida items[].price contra storeProducts. Um cliente malicioso (SDK Firestore com auth de aluno) cria um pedido com items:[{productId:'gi-caro', price:0.01, quantity:1}], total:0.01 e chama createMpOrderPixPayment/createMpCardPayment: o 'cross-check' (:3099-3104) e o guard do settle (:3919-3925) comparam contra os MESMOS preços forjados — defesa circular. O pedido vira 'paid', o admin é notificado 'Pedido #X pago' e entrega o produto. O StoreService legítimo (store_service.dart:714) usa o preço do banco, mas isso é só o caminho honesto. Bônus: itens sem productId caem em policy 'both' (:2881), então a política pix_only/card_only também é contornável no mesmo ataque.

**Evidência:**
```
// server_functions.js:2849-2855
for (const it of items) {
  const price = Number((it && (it.price ?? it.unitPrice)));
  const qty = Number(it && it.quantity);
  ...
  sum += price * qty;
}
// firestore.rules:670-674 — cliente cria o pedido com qualquer items[].price
allow create: if belongsToAcademy(academyId)
  && isOwnStudentRecord(academyId, request.resource.data.studentId)
  && ... && isPositiveAmount(request.resource.data.total);
```
**Recomendação:** Recomputar o total server-side a partir de storeProducts (a CF já busca cada produto em orderEffectivePolicy — retornar também o price de lá e ignorar it.price do pedido), ou mover a criação do pedido para uma Cloud Function e bloquear create client-side nas rules. Aplicar o mesmo preço autoritativo no guard de mpMktSettle.

---

## Severidade: ALTO

### 3. cancelMpSubscription engole falha do MP e marca 'cancelled' localmente — aluno continua sendo cobrado após cancelar
`functions/server_functions.js:3707` · dimensão: Assinaturas recorrentes · confiança do verificador: high

**Problema:** Se o PUT /preapproval {status:'cancelled'} falhar (timeout, 5xx do MP, refresh de token), o catch apenas loga e a função segue marcando o doc Firestore como 'cancelled' e retornando success:true ao aluno. O preapproval permanece 'authorized' no MP e continua cobrando o cartão todo mês. Não há retry em lugar nenhum: as crons (termGuard/reconcile/dunning) consultam apenas status in ['authorized','paused'], então um doc 'cancelled' nunca é re-verificado contra o MP. Quando a próxima cobrança chegar, mpSubSettleCycle ainda ressuscita o doc para 'authorized' (linha 3415), mas o dinheiro já saiu do cartão do aluno que recebeu confirmação de cancelamento. Note o contraste: pauseMpSubscription NÃO tem try/catch e propaga a falha corretamente.

**Evidência:**
```
if (sub.mpPreapprovalId) {
  try {
    const token = await getMpAccessToken(academyId);
    await mpRequest('PUT', `/preapproval/${sub.mpPreapprovalId}`,
      { token, body: { status: 'cancelled' } });
  } catch (e) {
    console.error('[cancelMpSubscription] erro', e.message);
  }
}
await subRef.update({ status: 'cancelled', updatedAt: FV.serverTimestamp() });
```
**Recomendação:** Propagar a falha do MP (como em pauseMpSubscription) em vez de engolir — só marcar 'cancelled' se o PUT teve sucesso; ou gravar um flag cancelPendingAtMp e ter uma cron que re-tenta o cancelamento no MP enquanto o flag existir.

### 4. createMpSubscription sem guarda de duplicidade — retry/duplo-toque cria dois preapprovals cobrando o mesmo aluno
`functions/server_functions.js:3594` · dimensão: Assinaturas recorrentes · confiança do verificador: high

**Problema:** Não há verificação de assinatura ativa existente (studentId+planId em status pending/authorized/paused) antes de criar. A idempotencyKey enviada ao MP é `sub:${subId}` com subId de um doc NOVO a cada chamada, então duas invocações da callable geram dois preapprovals distintos, ambos 'authorized', ambos cobrando o cartão mensalmente. Cenário real: o POST /preapproval do MP demora, a callable estoura deadline no cliente (FirebaseFunctionsException mapeada para 'Tente novamente' em payment_sheets.dart:1448-1449), o aluno re-tenta e assina duas vezes. O cliente (payment_sheets.dart:1494) também não checa assinatura existente antes de chamar.

**Evidência:**
```
const subRef = db.collection(`academies/${academyId}/subscriptions`).doc();
const subId = subRef.id;
...
pa = await mpRequest('POST', '/preapproval', {
  token,
  idempotencyKey: `sub:${subId}`,  // novo a cada chamada — não protege retry do cliente
```
**Recomendação:** No início da callable, consultar subscriptions por studentId+planId com status in ['pending','authorized','paused'] e rejeitar com failed-precondition ('Já existe uma assinatura ativa deste plano') — ou retornar a existente. Opcionalmente derivar a idempotencyKey de academyId+studentId+planId para blindar corrida entre duas chamadas simultâneas.

### 5. Cobrança além do termo contratado é liquidada como mensalidade normal e reabre assinatura 'completed'
`functions/server_functions.js:3412` · dimensão: Webhooks & liquidação · confiança do verificador: high

**Problema:** mpSubSettleCycle não checa se a assinatura já está 'completed' (ou chargesPaid >= months) antes de liquidar: a transação só barra finDoc duplicado. O cancel do preapproval ao atingir o termo é best-effort (catch em :3450) e o código marca 'completed' localmente MESMO quando o PUT cancelled falhou — e nesse estado a assinatura fica invisível para o termGuard e o reconcile (ambos filtram status in ['authorized','paused'], :4060 e :4187). O MP então cobra o mês N+1 do aluno; o webhook chega, mpSubSettleCycle liquida o ciclo extra, grava um financial 'paid' de mensalidade normal e seta status:'authorized' de volta (rebaixando 'completed'). O aluno paga um mês a mais sem nenhum alerta ou refund — o dinheiro errado fica registrado como receita legítima.

**Evidência:**
```
const subUpdate = {
  chargesPaid: cycle,
  lastPaymentId: paymentId,
  status: 'authorized',   // sem guarda: reabre sub 'completed'
  ...
};
// e no pós-tx:
} catch (e) {
  console.error('[mpSubSettleCycle] term cancel failed', e.message);
}
await subRef.update({ status: 'completed', ... }); // completed mesmo com cancel falho
```
**Recomendação:** Dentro da transação: se sub.status === 'completed' ou chargesPaid >= months, NÃO liquidar como ciclo normal — gravar um financial sinalizado (ex.: type 'overcharge'/flag needsRefund) e notificar admin para reembolso. Quando o PUT cancelled falhar, não marcar 'completed': gravar flag (ex.: termCancelPending=true) mantendo status 'authorized' para o termGuard re-tentar o cancel no dia seguinte.

### 6. Term guard marca 'completed' mesmo quando o cancelamento do preapproval no MP falha — MP continua cobrando o aluno e a assinatura sai de todas as queries dos crons
`functions/server_functions.js:4142` · dimensão: Crons de resiliência · confiança do verificador: high

**Problema:** No bloco final do scheduledSubscriptionTermGuard, o PUT /preapproval {status:'cancelled'} é best-effort (catch só loga) e o update para status:'completed' acontece INCONDICIONALMENTE depois. Se o cancel falhar (token MP revogado — getMpAccessToken lança HttpsError 'failed-precondition' dentro do mesmo try —, 5xx do MP, timeout), o Firestore fica 'completed' mas o preapproval segue 'authorized' no MP, que continua debitando o cartão do aluno todo mês ALÉM do termo contratado. Pior: 'completed' não está em ['authorized','paused'], então a assinatura é excluída para sempre das queries do termGuard e do reconcile — nenhum cron volta a tentar cancelar. O único auto-reparo seria o webhook de authorized_payment (mpSubSettleCycle re-tenta o cancel ao atingir o termo), mas se a causa foi token revogado o webhook também falha em getMpAccessToken, e o aluno é cobrado indefinidamente sem registro local. O mesmo padrão existe em mpSubSettleCycle (linhas 3446-3453). Nota: a banner do bloco diz 'cancela o preapproval + marca completed... Idempotente', mas a idempotência aqui só protege o doc local, não a cobrança real.

**Evidência:**
```
try {
  if (!token) token = await getMpAccessToken(academyId);
  await mpRequest('PUT', `/preapproval/${freshPreapprovalId}`,
    { token, body: { status: 'cancelled' } });
} catch (e) {
  console.error('[termGuard] cancel preapproval falhou', ...);
}
}
await subDoc.ref.update({
  status: 'completed',
  lastEvent: 'term_completed_guard', ... });
```
**Recomendação:** Só marcar 'completed' se o PUT de cancelamento retornou OK (ou se um GET confirmar pa.status === 'cancelled'). Em falha, gravar um estado intermediário (ex.: lastEvent:'term_cancel_failed', termCancelPending:true) mantendo status em 'authorized'/'paused' para que o próximo run do termGuard re-tente o cancel. Aplicar a mesma regra no caminho de término do mpSubSettleCycle.

### 7. disconnectMercadoPago deixa assinaturas recorrentes órfãs cobrando o aluno (sem cancelar preapproval, sem como gerenciar)
`functions/server_functions.js:2781` · dimensão: OAuth & segurança · confiança do verificador: high

**Problema:** O disconnect apaga o doc de tokens (private/mpAuth) e marca mpConnected:false, mas NÃO cancela/pausa os preapprovals ativos no Mercado Pago nem mexe nos docs de subscriptions com status 'authorized'. O preapproval vive no lado do MP, independente do nosso token OAuth, então o MP continua cobrando o cartão do aluno todo mês mesmo após a academia desconectar. Pior: depois do disconnect, getMpAccessToken passa a lançar 'failed-precondition' (Academia não conectou o Mercado Pago), o que quebra cancelMpSubscription/pauseMpSubscription (o aluno não consegue mais cancelar pelo app) e faz os crons de resiliência (scheduledSubscriptionTermGuard, reconcile, dunning) caírem no catch por-academia e pularem essa academia. Resultado: o term guard nunca cancela ao atingir os N meses → o aluno é cobrado ALÉM do prazo contratado, sem nenhuma forma de parar pelo app.

**Evidência:**
```
exports.disconnectMercadoPago = onCall(async (request) => {
  ...
  await db.doc(`academies/${academyId}/private/mpAuth`).delete().catch(() => {});
  await db.doc(`academies/${academyId}`).update({ mpConnected: false, ... });
  return { success: true };
}); // nenhuma iteração em subscriptions ativas / nenhum PUT preapproval status:cancelled
```
**Recomendação:** Antes de apagar os tokens, iterar academies/{id}/subscriptions com status em ['authorized','pending','paused'] e dar PUT /preapproval/{id} status:cancelled (usando o token ainda válido) + marcar o doc como 'cancelled'. Alternativamente, bloquear o disconnect enquanto houver assinaturas ativas e exigir cancelá-las primeiro. Garantir também que cancelMpSubscription consiga marcar o doc local como cancelled mesmo quando o token já não existir (fallback sem chamada ao MP).

### 8. Cartão: idempotency key fixa por cobrança — uma recusa (CVV errado/sem saldo) bloqueia todas as retentativas
`functions/server_functions.js:3250` · dimensão: Pagamentos avulsos (Pix/cartão) · confiança do verificador: high

**Problema:** createMpCardPayment envia X-Idempotency-Key = `${externalReference}:card`, fixa para sempre por financial/order. No MP, reutilizar a key faz a API devolver a resposta do pagamento ORIGINAL em vez de processar o novo. Cenário comum em produção: aluno digita CVV errado → payment status 'rejected' → corrige o cartão e tenta de novo → a CF envia a MESMA key com o token novo → MP devolve o mesmo pagamento recusado → o aluno fica impossibilitado de pagar a mensalidade/pedido com cartão enquanto a key estiver viva no MP. O caminho PIX já resolveu exatamente isso (comentário em :2907-2912 explica por que a key precisa ser única por mint), mas o cartão não recebeu o mesmo fix.

**Evidência:**
```
payment = await mpRequest('POST', '/v1/payments', {
  token,
  idempotencyKey: `${externalReference}:card`,  // estável para sempre
  body: { ... token: cardToken, ... }
```
**Recomendação:** Incluir o cardToken na key (ex.: `${externalReference}:card:${cardToken}`): o token é estável num retry de transporte (protege contra duplo-clique/timeout) mas único por nova tentativa do usuário (cada tokenização gera token novo), liberando retentativas após recusa.

### 9. Pagamento aprovado com valor divergente: settle recusa silenciosamente, responde 200 ao MP e o dinheiro do aluno some do radar
`functions/server_functions.js:3974` · dimensão: Pagamentos avulsos (Pix/cartão) · confiança do verificador: high

**Problema:** mpMktSettle, ao detectar mismatch entre payment.transaction_amount e o amount atual do doc, retorna {didSettle:false} com apenas um console.error, e o webhook responde 200 'success' — o MP não retenta, nenhum admin é notificado, nenhum flag é gravado. Gatilho realista sem atacante: o aluno gera um PIX de R$200 (válido 24h, valor congelado no MP); o professor edita fin.amount para R$220 antes do pagamento; o aluno paga o PIX de R$200 → dinheiro cai na conta MP da academia, mas o financial fica 'pending' para sempre e o aluno aparece como inadimplente. Agrava: o reuso de PIX existente em createMpPixPayment (:2999) não confere se o PIX vivo ainda corresponde ao fin.amount atual, então continua servindo o QR com valor velho. O mesmo padrão silencioso existe no branch de order (:3921) e quando o doc foi deletado (:3967, !snap.exists).

**Evidência:**
```
if (Math.abs(expectedFinReais - paidFinReais) > 0.01) {
  console.error('[mpMktSettle] amount mismatch fin', docId, ...);
  return { didSettle: false }; // do NOT settle
}
// webhook (:3890-3891): await mpMktSettle(parsed, payment);
// return res.status(200).json({ success: true });  ← MP nunca retenta
```
**Recomendação:** No mismatch, gravar no doc um flag (ex.: settleMismatch: {paymentId, paidAmount, expectedAmount}) e disparar notifyAdminCF para reconciliação manual. Adicionalmente, ao editar amount de um financial com PIX vivo, invalidar/cancelar o PIX (limpar pixCode/pixExpiresAt e cancelar o payment no MP), e no reuso (:2999) verificar se o PIX armazenado corresponde ao amount atual antes de devolvê-lo.

### 10. Assinatura duplicada: CTA 'Assinar' visível durante loading do stream e retry sem dedup recria o preapproval
`lib/screens/portal/financial_screen.dart:59` · dimensão: Flutter (frontend) · confiança do verificador: high

**Problema:** O _SubscriptionSection decide mostrar o CTA 'Assinar' com `valueOrNull ?? const []`: enquanto o stream de subscriptions ainda está carregando, `active` é vazio e o botão de assinar renderiza mesmo que já exista assinatura authorized. Além disso, se createMpSubscription estourar timeout no cliente (deadline-exceeded) após o CF já ter criado o preapproval, o CardPaymentSheet mostra 'Tentar novamente' e o reenvio cria um SEGUNDO preapproval: o backend (server_functions.js:3594-3636) gera um subRef.doc() novo a cada chamada e a idempotencyKey é `sub:${subId}` (novo a cada call), sem checar assinatura ativa existente para (studentId, planId). Resultado: aluno cobrado 2x todo mês no cartão.

**Evidência:**
```
final subs = ref.watch(studentSubscriptionsProvider(student.id)).valueOrNull ?? const <Subscription>[];  // loading => [] => CTA 'Assinar' aparece
// backend (server_functions.js:3594): const subRef = db.collection(`academies/${academyId}/subscriptions`).doc(); // doc NOVO a cada chamada, sem dedup por aluno+plano
```
**Recomendação:** No Flutter: não renderizar o CTA enquanto o provider está em loading (usar .when), e antes de chamar createSubscription reconsultar se já há sub ativa para o aluno+plano. No backend (defesa real): em createMpSubscription, rejeitar/retornar a sub existente quando houver doc com status em {pending, authorized, paused} para o mesmo studentId+planId, e usar idempotencyKey derivada de (academyId, studentId, planId) na janela de retry.

---

## Severidade: MÉDIO

### 11. Atingido o termo, falha no cancel do preapproval ainda marca 'completed' — MP cobra mês extra além do contratado
`functions/server_functions.js:3453` · dimensão: Assinaturas recorrentes · confiança do verificador: high

**Problema:** Em mpSubSettleCycle, quando chargesPaid atinge months, o cancel do preapproval é best-effort: se o PUT falhar, o código mesmo assim grava status:'completed'. O preapproval segue 'authorized' no MP e cobra o ciclo N+1. mpSubSyncPreapproval retorna cedo para 'completed' (linha 3499) e as crons excluem 'completed' das queries, então nada re-tenta o cancelamento até a cobrança extra acontecer (o settle do ciclo N+1 ressuscita o doc para 'authorized' e só então o termGuard cancela de novo no dia seguinte — mas o aluno já pagou um mês a mais, sem reembolso). O scheduledSubscriptionTermGuard tem exatamente o mesmo padrão (cancel best-effort nas linhas 4145-4150 seguido de update incondicional para 'completed' na 4152).

**Evidência:**
```
if (result.months > 0 && result.cycle >= result.months && result.preapprovalId) {
  try {
    await mpRequest('PUT', `/preapproval/${result.preapprovalId}`,
      { token, body: { status: 'cancelled' } });
  } catch (e) {
    console.error('[mpSubSettleCycle] term cancel failed', e.message);
  }
  await subRef.update({ status: 'completed', updatedAt: FV.serverTimestamp() });
```
**Recomendação:** Só marcar 'completed' quando o cancel no MP confirmar; em falha, gravar termCancelPending:true mantendo status anterior, e fazer o termGuard (que já roda diário) re-tentar o cancelamento de subs com esse flag até suceder.

### 12. Crash entre POST /preapproval e o update do doc deixa assinatura 'pending' órfã — MP cobra sem nenhum financial ser gerado
`functions/server_functions.js:3677` · dimensão: Assinaturas recorrentes · confiança do verificador: high

**Problema:** O doc é criado como 'pending' antes do POST ao MP, e mpPreapprovalId só é gravado no update final (linha 3677). Se a function morrer entre o POST bem-sucedido e esse update (timeout/OOM/deploy), o preapproval fica ativo no MP cobrando o cartão, mas: (1) mpSubSyncPreapproval e mpSubHandleAuthorizedPayment localizam a assinatura SOMENTE por where('mpPreapprovalId'==...) e retornam silenciosamente quando não acham (linhas 3470 e 3495); (2) as crons filtram status in ['authorized','paused'], excluindo 'pending'. Resultado: aluno cobrado todo mês, professor sem financials/'paid', zero alertas. O external_reference do preapproval já carrega `${academyId}:sub:${subId}` e permitiria recuperação, mas nunca é usado nos lookups.

**Evidência:**
```
const subSnap = await db.collection(`academies/${academyId}/subscriptions`)
  .where('mpPreapprovalId', '==', String(preapprovalId)).limit(1).get();
if (subSnap.empty) return;  // órfã 'pending' sem mpPreapprovalId: descarte silencioso
```
**Recomendação:** Em mpSubSyncPreapproval/mpSubHandleAuthorizedPayment, quando o lookup por mpPreapprovalId falhar, parsear pa.external_reference (`acad:sub:subId`), localizar o doc pelo id e gravar o mpPreapprovalId ausente antes de processar (self-healing). Adicionalmente, uma cron pode alertar sobre subs 'pending' com mais de 1h.

### 13. mpSubSettleCycle seta status 'authorized' incondicionalmente — ressuscita assinaturas 'cancelled' no Firestore
`functions/server_functions.js:3415` · dimensão: Assinaturas recorrentes · confiança do verificador: high

**Problema:** O update da transação de settle força status:'authorized' sem checar o status atual. Se um authorized_payment aprovado chega DEPOIS de o aluno cancelar (webhook atrasado de uma cobrança em voo, ou drenagem do reconcile/termGuard), o doc 'cancelled' volta a exibir 'Ativa' no app, embora o preapproval esteja cancelado no MP. O doc indevidamente 'authorized' só se corrige quando o reconcile o pegar com nextBillingDate vencida há >48h — como a cobrança acabou de ocorrer, isso leva ~1 mês de estado errado, durante o qual aluno/professor veem uma assinatura ativa que nunca mais cobrará. O guard de 'completed' existe no sync (linha 3499) mas não no settle.

**Evidência:**
```
const subUpdate = {
  chargesPaid: cycle,
  lastPaymentId: paymentId,
  status: 'authorized',   // incondicional — sobrescreve 'cancelled'/'completed'
  needsReauth: false,
```
**Recomendação:** No settle, preservar status terminal: só setar 'authorized' quando sub.status não for 'cancelled' nem 'completed' (o financial deve ser mintado mesmo assim — o dinheiro entrou — mas sem ressuscitar o estado).

### 14. referenceMonth/dueDate do ciclo usam a data do settle, não da cobrança — liquidação atrasada contabiliza no mês errado
`functions/server_functions.js:3389` · dimensão: Assinaturas recorrentes · confiança do verificador: high

**Problema:** mpSubSettleCycle deriva referenceMonth e dueDate de `new Date()` (momento da execução). O reconcile só age >48h após a cobrança e a drenagem do termGuard pode rodar semanas depois — uma cobrança de 30/jan liquidada em 02/fev gera financial com referenceMonth '2026-02'. Quando a cobrança legítima de fevereiro chegar, o professor verá duas mensalidades em fevereiro e nenhuma em janeiro: relatórios mensais e o histórico de ciclos do aluno ficam errados, e telas que verificam 'mensalidade do mês paga' por referenceMonth podem dar resultado incorreto. O payload do MP (ap.payment.date_created / ap.debit_date) está disponível nos três call sites mas não é usado.

**Evidência:**
```
const now = new Date();
const referenceMonth =
  `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
...
dueDate: admin.firestore.Timestamp.fromDate(now),
```
**Recomendação:** Passar a data da cobrança (mpPayload.debit_date || mpPayload.payment.date_created || payment.date_approved) para mpSubSettleCycle e derivar referenceMonth/dueDate dela, caindo para now apenas se ausente.

### 15. Webhook de assinatura responde 200 quando o doc ainda não tem mpPreapprovalId — evento perdido sem retry do MP
`functions/server_functions.js:3470` · dimensão: Webhooks & liquidação · confiança do verificador: medium

**Problema:** createMpSubscription cria o preapproval com status:'authorized' (cobra na hora) e só grava mpPreapprovalId no doc DEPOIS que o POST retorna (:3653/3677). O webhook subscription_authorized_payment do 1º ciclo pode chegar antes desse update; mpSubHandleAuthorizedPayment busca por mpPreapprovalId, acha vazio e retorna silenciosamente — o handler externo responde 200 success, então o MP NUNCA re-entrega. A recuperação fica por conta do reconcile, mas para subs 'authorized' ele só age quando nextBillingDate está vencida há >48h — ou seja, o financial 'paid' do 1º ciclo só aparece ~1 mês depois e até lá o professor vê o aluno como não-pago. O mesmo padrão de 200-em-doc-ausente existe em mpMktSettle (snap.exists false → didSettle:false → 200): um financial/pedido apagado ou ainda não visível faz o pagamento PIX aprovado sumir para sempre do app.

**Evidência:**
```
const subSnap = await db.collection(`academies/${academyId}/subscriptions`)
  .where('mpPreapprovalId', '==', String(preapprovalId)).limit(1).get();
if (subSnap.empty) return;  // handler responde 200 → MP não re-tenta
```
**Recomendação:** Quando o lookup vier vazio, fazer fallback: GET /preapproval/{id} e parsear external_reference (`acadId:sub:subId`) para achar o doc direto; se ainda assim não existir, responder 404/500 para o MP re-entregar com backoff em vez de 200. Aplicar o mesmo aos casos !snap.exists de mpMktSettle (distinguir 'doc não existe' de 'já pago').

### 16. Refund/chargeback não tratado no marketplace: financial/pedido fica 'paid' e estoque não volta
`functions/server_functions.js:3887` · dimensão: Webhooks & liquidação · confiança do verificador: high

**Problema:** No webhook marketplace, qualquer status != 'approved' é simplesmente ignorado (200). Quando um pagamento já liquidado é estornado (refunded/charged_back/cancelled), o MP notifica de novo o mesmo payment id com o novo status — e o código não faz nada: o financial continua 'paid', o pedido continua 'paid', o estoque continua decrementado e o admin não é avisado. O professor vê receita que foi devolvida ao aluno (livro-caixa errado) e, em disputa de cartão (chargeback), nem fica sabendo. O webhook legado do paywall trata exatamente esse caso (index.js:1219 revoga acesso), mostrando que o requisito é conhecido mas ficou de fora do caminho marketplace.

**Evidência:**
```
if (payment.status !== 'approved') {
  return res.status(200).json({ received: true, status: payment.status });
}
await mpMktSettle(parsed, payment);
```
**Recomendação:** Tratar refunded/charged_back/cancelled em mpMktSettle: se o doc está 'paid' com o mesmo gatewayPaymentId, marcar status 'refunded'/'chargeback', restaurar estoque do pedido e notificar o admin. Para assinaturas, sinalizar o ciclo estornado no financial sub_{id}_{paymentId}.

### 17. Webhook legado valida assinatura fail-open: sem MP_WEBHOOK_SECRET qualquer POST é aceito
`functions/index.js:1331` · dimensão: Webhooks & liquidação · confiança do verificador: high

**Problema:** mercadoPagoWebhook só valida o x-signature SE process.env.MP_WEBHOOK_SECRET estiver presente — se o secret faltar/estiver vazio (rotação, novo ambiente, rename), a validação é pulada inteira e qualquer um pode POSTar. O dano direto é limitado porque o handler re-busca o payment na API do MP com o token da plataforma, mas um atacante com o id de um pagamento real pode forçar re-processamento fora de hora (ex.: replays do path refunded para revogar acesso). O webhook marketplace ao lado faz o certo (fail-closed, :3826), evidenciando a inconsistência. Nenhum dos dois valida frescor do ts (replay ilimitado de uma requisição assinada capturada).

**Evidência:**
```
if (webhookSecret) {
  const xSignature = req.header('x-signature') || '';
  ...
  if (!valid) { return res.status(401)...; }
}
// sem secret → segue processando sem autenticar
```
**Recomendação:** Espelhar o marketplace: if (!webhookSecret) return 401 (fail-closed). Opcionalmente validar janela de ts (ex.: |now - ts| < 5 min) em ambos os webhooks para bloquear replay.

### 18. Idempotência do paywall por campo único e sem transação: entregas concorrentes/duplicadas estendem paidUntil mais de uma vez
`functions/index.js:1239` · dimensão: Webhooks & liquidação · confiança do verificador: high

**Problema:** mpHandlePayment deduplica comparando subscription.externalPaymentId com o chargeId em um read-then-write SEM transação. Duas entregas simultâneas do mesmo payment (retry do MP + entrega original) passam ambas pela checagem e cada uma estende paidUntil a partir do valor já estendido (base = paidUntil atual) — concessão dupla. Pior: como só o ÚLTIMO chargeId fica gravado, uma re-entrega tardia do pagamento A depois de processado o pagamento B (campo agora = B) passa de novo e concede de novo. É dinheiro a menos para a plataforma (acesso grátis), não para o professor, mas é estado de assinatura inconsistente no mesmo padrão que o marketplace já corrigiu com transações.

**Evidência:**
```
if (snap.get('subscription.externalPaymentId') === chargeId) {
  return res.status(200).json({success: true, academyId, action: 'duplicate'});
}
...
await academyRef.update({ 'subscription.paidUntil': Timestamp.fromDate(paidUntil), 'subscription.externalPaymentId': chargeId, ... });
```
**Recomendação:** Mover a concessão para db.runTransaction e deduplicar por doc determinístico (ex.: academies/{id}/paywallPayments/{chargeId} criado na mesma transação), como já é feito no marketplace com o financial sub_{}_{}.

### 19. As 4 crons fazem full-scan sequencial de 'academies' sem timeoutSeconds — starvation silenciosa e determinística das últimas academias conforme a base cresce
`functions/server_functions.js:4052` · dimensão: Crons de resiliência · confiança do verificador: high

**Problema:** scheduledSubscriptionTermGuard (4052), Reconcile (4180), Dunning (4276) e CardExpiryWarning (4389) começam com db.collection('academies').get() — TODAS as academias, inclusive as sem MP conectado e sem nenhuma assinatura — e iteram sequencialmente com awaits para uma query de subcoleção por academia mais chamadas HTTP ao MP por assinatura (GET /preapproval + search de authorized_payments no reconcile). Nenhuma das funções define timeoutSeconds, então valem os 60s default do v2 onSchedule. Quando o tempo estourar, a execução é abortada no meio do loop e — como a ordem do snapshot é determinística — são SEMPRE as mesmas academias do fim que nunca são processadas: dunning nunca re-tenta, reconcile nunca recupera webhook perdido, termGuard nunca completa. Professor dessas academias fica sem a resiliência inteira, silenciosamente (só um log de timeout da plataforma, sem erro de negócio).

**Evidência:**
```
exports.scheduledSubscriptionReconcile = onSchedule(
  { schedule: '0 */6 * * *', timeZone: 'America/Sao_Paulo', secrets: MP_MKT_SECRETS },
  async () => { ...
    const academiesSnapshot = await db.collection('academies').get();
    for (const academyDoc of academiesSnapshot.docs) { ... }
```
**Recomendação:** Trocar o scan de academias por uma collectionGroup('subscriptions').where('status','in',['authorized','paused']) (com o índice collection-group correspondente), que toca só os docs relevantes; agrupar por academyId para reusar o token. Definir timeoutSeconds explícito (ex.: 540) e, idealmente, processar academias com Promise.allSettled em lotes pequenos. No mínimo, logar quantas academias/assinaturas foram processadas vs. total para detectar starvation.

### 20. Backstop por data do termGuard converte assinatura inadimplente parcialmente paga (paused, ex.: 5/12 ciclos) em 'completed' — estado que aparenta quitação total
`functions/server_functions.js:4137` · dimensão: Crons de resiliência · confiança do verificador: high

**Problema:** A proteção contra completar por mera passagem de tempo só cobre freshCharges===0. Uma assinatura que pagou alguns ciclos, depois pausou (cartão recusado) e esgotou o dunning fica 'paused' até termEnd+35d — quando o termGuard a marca 'completed' (lastEvent:'term_completed_guard') e cancela o preapproval, mesmo com freshCharges muito menor que months. 'completed' é o mesmo estado terminal de uma assinatura 100% paga, então o professor perde a distinção entre 'aluno quitou o plano' e 'aluno pagou 5 de 12 e sumiu' — os ciclos em aberto somem da visibilidade de cobrança sem qualquer notificação (nenhum notifyAdminCF nesse caminho).

**Evidência:**
```
const completeByCharges = freshCharges >= months;
if (!completeByCharges && freshCharges === 0) {
  continue; // nunca-paga: não concluir por data, segue o dunning
}
// Atingiu o termo → cancela no MP (best-effort) e marca completed.
```
**Recomendação:** Quando !completeByCharges (data-backstop com 0<freshCharges<months), usar um estado terminal distinto (ex.: 'expired' ou 'completed' + termShortfall: months-freshCharges) e notificar o admin de que o termo encerrou com ciclos não pagos, em vez de marcar o mesmo 'completed' da quitação por contagem.

### 21. referenceMonth do financial é o mês do SETTLE (UTC), não o mês do ciclo — drenagem atrasada pelo reconcile/termGuard empilha ciclos antigos no mês corrente
`functions/server_functions.js:3389` · dimensão: Crons de resiliência · confiança do verificador: high

**Problema:** mpSubSettleCycle calcula referenceMonth a partir de new Date() no momento da liquidação. Os crons de resiliência liquidam por design ciclos ATRASADOS (reconcile só age >48h após nextBillingDate; termGuard drena no fim do termo): um pagamento aprovado em abril, drenado em junho, vira receita de '2026-06'; se dois ciclos perdidos são drenados no mesmo run, ambos recebem o MESMO referenceMonth com recurringCycle consecutivos, e o mês realmente coberto fica sem nenhum financial 'paid'. Relatórios mensais do professor e qualquer lógica que dedupe/agrupe mensalidade por referenceMonth ficam errados. Agravante menor: o cálculo usa o fuso do runtime (UTC) — settle de webhook entre 21h e 23h59 de São Paulo no último dia do mês cai no mês seguinte. Os valores em si estão corretos (transaction_amount em reais → financials.amount em reais, sem confusão de unidade).

**Evidência:**
```
const now = new Date();
const referenceMonth =
  `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
```
**Recomendação:** Derivar referenceMonth do ciclo, não do relógio: usar a data do pagamento do MP (ap.payment.date_approved / debit_date do authorized_payment, convertida para America/Sao_Paulo) ou calcular a partir de createdAt/billingDay + recurringCycle. Passar essa data via parâmetro de mpSubSettleCycle a partir do payload já disponível nos chamadores.

### 22. getUserAcademyInfo só resolve a academia PRIMÁRIA — bloqueia pagar/assinar/conectar em academias secundárias
`functions/server_functions.js:1668` · dimensão: OAuth & segurança · confiança do verificador: high

**Problema:** getUserAcademyInfo deriva academyId = primaryAcademyId || academyIds[0] e retorna sempre UMA academia (a primária). Como assertCanPayFor e requireAdminOf comparam userInfo.academyId !== academyId, qualquer usuário que pertença a mais de uma academia (o modelo de mapping é multi-academia: academyIds é array) fica IMPOSSIBILITADO de pagar mensalidade/loja, criar/cancelar assinatura ou conectar/desconectar o MP em qualquer academia que não seja a primária — todas as funções sensíveis lançam permission-denied. Para um aluno ativo em duas academias, ou um admin/dono de uma segunda academia, isso vira 'professor sem receber' / aluno sem conseguir pagar, de forma silenciosa.

**Evidência:**
```
const academyId = mappingData?.primaryAcademyId || mappingData?.academyIds?.[0];
const academyDetails = academyId && mappingData?.academyDetails?.[academyId];
... return { academyId, role: academyDetails.role, studentId: academyDetails.studentId };
// assertCanPayFor: if (userInfo.academyId !== academyId) throw permission-denied
```
**Recomendação:** Tornar a checagem por-academia: resolver role/studentId a partir de mappingData.academyDetails[academyId do request] (ou do doc academies/{academyId}/users/{uid}) em vez de assumir a primária. assertCanPayFor/requireAdminOf devem validar a membership NA academia passada no request, não na primária.

### 23. Refresh de token: flag mpNeedsReauth espúria nunca é limpa no caminho rápido + pagamentos concorrentes lançam deadline-exceeded durante o refresh
`functions/server_functions.js:2641` · dimensão: OAuth & segurança · confiança do verificador: high

**Problema:** Dois problemas no getMpAccessToken: (a) o early-return de token fresco (linha 2574) retorna sem limpar academyRef.mpNeedsReauth; mpNeedsReauth só é deletado DENTRO do branch de refresh bem-sucedido (linha 2653). Logo, se uma renovação falhar uma vez (marca mpNeedsReauth:true, 2641) mas o token persistido por OUTRA renovação concorrente ainda estiver fresco, a flag de 'reconecte sua conta' fica grudada por todo o ciclo de vida do token (~meses), induzindo o admin a desconectar/reconectar à toa (ver achado do disconnect). (b) Durante um refresh normal que demore >3s, qualquer pagamento concorrente cai no laço de espera (10×300ms), não vê token fresco, falha o re-acquire do lock (não-stale antes de 30s) e lança 'deadline-exceeded' ao usuário — cobranças legítimas falham com 'tente novamente' enquanto o token renova. Se o /oauth/token passar de LOCK_STALE_MS (30s), um segundo caller reivindica o lock e faz um refresh DUPLO com o mesmo refresh_token; como o MP rotaciona o refresh_token a cada uso, o segundo refresh invalida/é rejeitado e marca mpNeedsReauth indevidamente.

**Evidência:**
```
if (isFresh(d)) { return d.accessToken; } // 2574 — retorna sem limpar mpNeedsReauth
...
await academyRef.set({ mpNeedsReauth: true }, { merge: true }).catch(() => {}); // 2641 set
...
throw new HttpsError('deadline-exceeded', 'Não foi possível atualizar o token do Mercado Pago. Tente novamente.'); // 2618
const LOCK_STALE_MS = 30 * 1000;
```
**Recomendação:** Limpar mpNeedsReauth também no early-return de token fresco (ou sempre que um accessToken válido for retornado). No laço de espera, em vez de lançar deadline-exceeded de imediato, reler e reusar o token recém-renovado pelo holder (estender o número/intervalo de tentativas) antes de falhar. Considerar elevar LOCK_STALE_MS acima do timeout realista do /oauth/token para evitar reclaim prematuro e refresh duplo.

### 24. Race na geração de PIX: check-then-act sem transação permite dois PIX pagáveis para a mesma cobrança (pagamento duplo real)
`functions/server_functions.js:2999` · dimensão: Pagamentos avulsos (Pix/cartão) · confiança do verificador: high

**Problema:** createMpPixPayment (e o espelho de order em :3108) faz get() → verifica fin.pixCode/pixExpiresAt → cria PIX no MP → update(), tudo fora de transação. O próprio cenário que o código cita (criança e responsável abrindo a mesma cobrança ao mesmo tempo) quebra o reuso: ambos passam o check antes de qualquer write e cada um minta um PIX distinto (a idempotency key tem epoch-millis, então o MP cria dois pagamentos). Os dois QR codes ficam pagáveis por 24h com o mesmo external_reference. Se ambos pagarem, o primeiro settla (transação idempotente) e o segundo pagamento aprovado é simplesmente ignorado pelo guard status=='paid' — a família paga a mensalidade DUAS vezes e não existe nem registro nem refund. O mesmo vale para o retry após falha do finRef.update (:3040): o PIX antigo continua vivo no MP.

**Evidência:**
```
if (fin.gatewayPaymentId && fin.pixCode && existingExpiry > Date.now()) {
  return { pixCode: fin.pixCode, ... }; // reuse
}
... // janela de corrida: nada impede dois mints concorrentes
const pix = await createMpPix({ ... });
await finRef.update({ pixCode: pix.pixCode || null, ... });
```
**Recomendação:** Serializar o mint por cobrança (lock doc estilo mpTokenLock, ou transação que grava um campo pixMintInProgress antes de chamar o MP), e/ou cancelar o pagamento PIX anterior no MP (PUT /v1/payments/{id} status=cancelled) antes de gravar o novo. No mpMktSettle, detectar um segundo pagamento aprovado para doc já 'paid' e alertar o admin para refund.

### 25. Cartão não valida nem resolve payerEmail (assimetria com PIX) — usuários com email placeholder falham com erro genérico
`functions/server_functions.js:3264` · dimensão: Pagamentos avulsos (Pix/cartão) · confiança do verificador: high

**Problema:** Os dois caminhos PIX rejeitam email vazio e fazem fallback para o email do Firebase Auth quando o informado é vazio/placeholder '@bjjeasy.com.br' (:3018-3029), porque 'Mercado Pago rejects it' (comentário em :2930). createMpCardPayment envia `payer.email: payerEmail || undefined` cru: usuário sem email no Auth, ou com email placeholder do domínio do sistema, manda um payer inválido ao MP. O erro do MP cai no catch (:3271-3273) que descarta status/data e devolve sempre 'Falha ao processar o cartao.' — o aluno não tem como saber o que corrigir e o professor fica sem receber. O client (mercado_pago_service.dart:35) só usa FirebaseAuth.currentUser?.email, que pode ser null ou placeholder.

**Evidência:**
```
payer: {
  email: payerEmail || undefined,   // sem guard, sem fallback, sem filtro de placeholder
  ...
}
} catch (e) {
  console.error('[createMpCardPayment] erro', e.message, e.data);
  throw new HttpsError('internal', 'Falha ao processar o cartao.');
```
**Recomendação:** Replicar no caminho de cartão o bloco de resolução de email da mensalidade PIX (fallback para admin.auth().getUser + rejeição fail-fast com mensagem clara), e mapear os erros 400 do MP (payer/email/token inválido) para mensagens acionáveis em vez do 'internal' genérico.

### 26. CardPaymentSheet ignora o PaymentGatewayResolver e cai em fallback que envia número de cartão + CVV crus para Asaas/AbacatePay
`lib/widgets/payment_sheets.dart:1522` · dimensão: Flutter (frontend) · confiança do verificador: high

**Problema:** O resolver e o PaymentMethodSheet garantem que cartão = somente Mercado Pago (tokenizado, PCI-safe) — há até teste lockando isso. Mas _handlePayment re-resolve o gateway por conta própria via mp.isEnabled(), que retorna false em QUALQUER erro de leitura do Firestore (catch → false). Numa falha transitória de rede no momento do pagamento de uma academia MP, o código cai silenciosamente no branch Asaas/AbacatePay, que envia `...cardData.toJson()` (número completo, CVV, CPF) através do Cloud Function `createCardPayment` (abacate_pay_service.dart:204-211, asaas_payment_service.dart:175) — dados de cartão crus atravessam o backend, num gateway que nem está conectado, e o usuário recebe um erro confuso após já ter exposto o cartão.

**Evidência:**
```
final useMp = await mp.isEnabled();            // isEnabled(): catch (_) { return false; }
final isAsaas = !useMp && await asaasService.isEnabled();
...
} else {
  result = await AbacatePayService(academyId).createStoreOrderCardPayment(   // envia ...cardData.toJson() cru pelo CF
    ...,
    cardData: cardData,
```
**Recomendação:** Passar o PaymentGateway resolvido (do paymentGatewayProvider) como parâmetro do CardPaymentSheet em vez de re-resolver internamente. Se o gateway resolvido for MP e a leitura falhar, mostrar erro com retry — nunca cair em fallback de outro gateway. Avaliar remover os fluxos de cartão cru Asaas/Abacate do app, já que cardSupported=false para eles em toda a UI.

### 27. createSubscription reporta 'Assinatura ativada!' ignorando o status retornado e vaza e.toString() cru para o usuário
`lib/services/mercado_pago_service.dart:180` · dimensão: Flutter (frontend) · confiança do verificador: high

**Problema:** Após o callable retornar, o método devolve `success: true, message: 'Assinatura ativada!'` incondicionalmente, mesmo que o CF retorne status 'pending' ou outro estado não-authorized do preapproval — o aluno vê 'ativada' para uma assinatura que pode nunca cobrar (estado inconsistente entre UI e MP). No catch genérico, `message: e.toString()` chega cru à UI (ex.: 'Exception: Falha ao validar o cartao (400).'), incluindo falhas do MpCardTokenizer que nunca passam pelo mapeamento amigável _friendlyCardError.

**Evidência:**
```
final data = Map<String, dynamic>.from(result.data);
return (
  success: true,
  message: 'Assinatura ativada!',
  ...
  status: data['status'] as String?,
);
...
} catch (e) {
  return (
    success: false,
    message: e.toString(),
```
**Recomendação:** Derivar success/mensagem do `status` retornado (authorized → 'ativada'; pending → 'aguardando autorização do cartão' com instrução). No catch genérico, mapear para copy pt-BR amigável (reutilizar a lógica do _friendlyCardError) em vez de e.toString().

### 28. setState sem guard de mounted nos caminhos de erro de _handlePayment após awaits
`lib/widgets/payment_sheets.dart:1586` · dimensão: Flutter (frontend) · confiança do verificador: high

**Problema:** O bottom sheet de cartão pode ser dismissado por drag enquanto a cobrança está em voo. No retorno, o branch de falha (`else { setState(... _errorMessage ...) }`) e o `catch` chamam setState sem checar mounted (o branch de sucesso checa). Resultado: exceção 'setState() called after dispose' não tratada e, pior, o usuário que fechou o sheet durante uma recusa nunca vê a mensagem de erro — ele pode acreditar que pagou (cartão recusado = professor sem receber) ou re-tentar via outro caminho duplicando a tentativa.

**Evidência:**
```
} else {
  setState(() {
    _errorMessage =
        result.message ?? 'Pagamento nao aprovado. ...';
  });
}
} catch (e) {
  setState(() {
    _errorMessage = _friendlyCardError(e);
  });
```
**Recomendação:** Adicionar `if (!mounted) return;` antes dos setState do branch de falha e do catch. Considerar `isDismissible: false` ou barreira durante _isLoading para que o usuário não perca o resultado de uma cobrança em voo.

---

## Severidade: BAIXO

### 29. Cancelar via sheet com dado stale rebaixa assinatura 'completed' para 'cancelled' e cliente engole o erro real do MP na troca de cartão
`lib/widgets/payment/subscription_detail_sheet.dart:690` · dimensão: Assinaturas recorrentes · confiança do verificador: high

**Problema:** Dois pontos menores no Flutter: (1) cancelMpSubscription/_loadOwnedSubscription não validam o status atual, então um cancel disparado de um sheet com snapshot stale (o sheet recebe `sub` por valor, não stream) sobrescreve 'completed' → 'cancelled', corrompendo a distinção que o backend protege no webhook (linha 3499 do server_functions.js); (2) no UpdateSubscriptionCardSheet, qualquer exceção vira a mensagem genérica 'Verifique os dados', descartando o failed-precondition específico do backend e o status code do tokenizador MP, dificultando o aluno em dunning entender por que o cartão foi recusado.

**Evidência:**
```
} catch (e) {
  if (!mounted) return;
  setState(() {
    _isLoading = false;
    _errorMessage =
        'Não foi possível atualizar o cartão. Verifique os dados e '
        'tente novamente.';
  });
```
**Recomendação:** No backend, fazer cancel/pause rejeitarem (failed-precondition) quando o status atual for 'completed' ou 'cancelled'. No sheet de troca de cartão, exibir e.message quando for FirebaseFunctionsException (como já faz _friendlyCardError em payment_sheets.dart).

### 30. Decremento de estoque e notificação fora da transação de settle: crash deixa estoque superestimado sem retry
`functions/server_functions.js:3943` · dimensão: Webhooks & liquidação · confiança do verificador: high

**Problema:** Em mpMktSettle (pedidos), o flip para 'paid' acontece na transação, mas o decremento de estoque e o notifyAdminCF rodam depois, fora dela. Se a function morrer entre o commit e o loop de estoque (timeout, OOM, deploy), a re-entrega do webhook bate em status==='paid' → didSettle:false → retorna sem decrementar: o estoque fica errado para sempre e o admin não é notificado do pedido pago. O design escolhido evita decrementos duplos, mas perde a garantia de execução do efeito.

**Evidência:**
```
if (!settle.didSettle) return; // another execution already settled it
const items = settle.items;
if (Array.isArray(items)) {
  for (const item of items) { ... FieldValue.increment(-item.quantity) ... }
```
**Recomendação:** Marcar na transação um campo stockSettled:false no pedido e fazer o decremento idempotente guiado por esse flag (re-entrega verifica paid && !stockSettled e completa o efeito), ou mover o decremento para dentro da própria transação (ler os products na tx).

### 31. Drenagem de /authorized_payments/search não pagina — ciclos além da primeira página nunca são liquidados e o termGuard pode 'completar' por data perdendo financials para sempre
`functions/server_functions.js:4100` · dimensão: Crons de resiliência · confiança do verificador: medium

**Problema:** Tanto o termGuard (4093-4110) quanto o reconcile (4237-4253) leem apenas search.results da primeira página do search do MP (APIs de search do MP são paginadas com limit default baixo e paging.total/offset). Para uma assinatura de 12+ meses cujos webhooks se perderam por período prolongado, os authorized_payments aprovados além da primeira página nunca são drenados: os financials 'paid' desses ciclos não são criados e chargesPaid fica subcontado. No termGuard isso interage mal com o backstop por data: após termEnd+35d, ele completa a assinatura com freshCharges<months e cancela o preapproval — e, como 'completed' sai das queries de todos os crons, os ciclos não-drenados ficam perdidos permanentemente (professor 'recebeu' no cartão mas não tem registro de receita).

**Evidência:**
```
const search = await mpRequest('GET',
  `/authorized_payments/search?preapproval_id=${sub.mpPreapprovalId}`,
  { token })...
const results = (search && (search.results || search.elements)) || [];
for (const ap of results) { ... }  // sem loop de offset/paging
```
**Recomendação:** Implementar paginação no search (limit+offset até cobrir paging.total, com teto de segurança de iterações), idealmente num helper compartilhado usado pelo termGuard e pelo reconcile. No termGuard, considerar não completar por dateBackstop quando freshCharges<months e a drenagem retornou resultados na borda do page size.

### 32. Update do dunning após reativação não é transacional — pode sobrescrever o reset de failedAttempts feito por webhook concorrente (settle/sync), encurtando retentativas futuras
`functions/server_functions.js:4358` · dimensão: Crons de resiliência · confiança do verificador: medium

**Problema:** Entre o PUT /preapproval {status:'authorized'} (4333) e o subDoc.ref.update (4358), o MP pode disparar webhooks que chegam em segundos: mpSubSyncPreapproval (authorized → failedAttempts:0, nextRetryAt:null) e até mpSubSettleCycle se a cobrança aprovar rápido (failedAttempts:0, status:'authorized'). O update do cron então grava incondicionalmente failedAttempts:attemptN, lastFailureAt e nextRetryAt sobre o estado já recuperado, usando dados lidos no snapshot da query. Uma assinatura saudável fica com contador de dunning fantasma; numa pausa futura, o sync não re-seta nextRetryAt (só seta se null) e o ciclo começa já em attempt 2-3, dando ao aluno menos retentativas que a política [1,3,7] antes da suspensão. Janela pequena e autocurável no próximo settle, por isso low — mas é o único write de estado de dunning fora de transação no fluxo.

**Evidência:**
```
await mpRequest('PUT', `/preapproval/${sub.mpPreapprovalId}`,
  { token, body: { status: 'authorized' } });
...
await subDoc.ref.update({
  failedAttempts: attemptN,
  lastFailureAt: FV.serverTimestamp(),
  nextRetryAt: nextRetry, ... });
```
**Recomendação:** Fazer o update pós-reativação em db.runTransaction: re-ler o doc e só gravar failedAttempts/nextRetryAt se o status ainda for 'paused' e lastPaymentId não mudou (nenhum settle no intervalo); caso contrário, não tocar nos contadores.

### 33. Teste de regressão documenta bug já corrigido: afirma que a loja não tem guard de CPF/email, mas o guard existe
`functions/test/mp_pix_payer_validation.test.js:93` · dimensão: Pagamentos avulsos (Pix/cartão) · confiança do verificador: high

**Problema:** O teste 'BUG[low] loja PIX has NO CPF/email guard' afirma que createMpOrderPixPayment passa payerCpf cru ao MP sem validação, e promete 'flipar' quando o guard for adicionado. O guard FOI adicionado (server_functions.js:3122-3138, simétrico ao da mensalidade), mas o teste não flipou porque ele testa um espelho local da lógica, não o código de produção — exatamente o drift que o cabeçalho ('Kept byte-for-byte equivalent to production so the test breaks if prod drifts') dizia impedir. Resultado: a suíte documenta ativamente um estado falso do código de pagamento, e os números de linha âncora do cabeçalho (~2902, ~3000, 3044-3050) também estão todos defasados. Risco: um futuro mantenedor 'corrige' a assimetria que não existe mais, ou confia no teste verde como prova de comportamento.

**Evidência:**
```
test('BUG[low] loja PIX has NO CPF/email guard: a missing CPF slips through to MP', () => {
  // Simulating the loja path: createMpOrderPixPayment passes payerCpf raw to
  // createMpPix (server_functions.js:3049) with no prior length check.
// ← FALSO hoje: server_functions.js:3123-3126 tem o mesmo fail-fast da mensalidade
```
**Recomendação:** Atualizar o teste para afirmar a simetria atual (os dois caminhos rejeitam CPF<11 dígitos e email inválido) e remover o teste 'BUG[low]'. Idealmente extrair o guard para uma função exportável e testá-la diretamente, eliminando o espelho que pode divergir.

### 34. Gateway 'none' cai no branch AbacatePay no generate() de PIX e erro transitório do resolver some silenciosamente com o botão de pagar
`lib/screens/portal/financial_screen.dart:513` · dimensão: Flutter (frontend) · confiança do verificador: high

**Problema:** Duas falhas combinadas: (1) no switch do generate(), `case PaymentGateway.none:` compartilha o branch do AbacatePay — se o sheet for aberto com resolução transitória 'none' (race entre abacatePayEnabledProvider cacheado e a nova leitura), o app tenta criar PIX num gateway não conectado, gerando erro confuso em vez do estado 'sem método' desenhado. (2) PaymentGatewayResolver.resolve degrada para `none` em QUALQUER exceção (e isEnabled() engole erros retornando false), então uma falha de rede momentânea faz o botão 'Pagar mensalidade' de uma academia MP conectada desaparecer silenciosamente (showPayButton: abacatePayEnabled), com a mensagem enganosa 'Pagamento online indisponivel. Fale com a recepcao' — professor deixa de receber online sem ninguém perceber.

**Evidência:**
```
case PaymentGateway.abacatePay:
case PaymentGateway.none:
  return AbacatePayService(academyId).createPixPayment(   // 'none' tenta cobrar via AbacatePay
// resolver: } catch (_) { return PaymentGateway.none; }  // erro de rede == 'nada conectado'
```
**Recomendação:** Tratar PaymentGateway.none no generate() retornando null/erro amigável (nunca chamando um gateway). No resolver, distinguir 'falha ao resolver' de 'nada conectado' (ex.: estado resolvedor com erro + retry na UI, ou rethrow para o FutureProvider expor AsyncError com botão de tentar novamente).

### 35. Checkout da loja pula o sheet de pagamento silenciosamente se o gateway ainda não resolveu no momento do Confirmar
`lib/screens/portal/store_checkout_screen.dart:136` · dimensão: Flutter (frontend) · confiança do verificador: high

**Problema:** _gateway é resolvido uma única vez no initState de forma assíncrona. Se o usuário (em conexão lenta) atravessar Revisão → Pagamento → Confirmar antes da resolução terminar, `_openPaymentSheet` cai em `gateway == null → _goToOrders()`: o pedido é criado como pending, mostra confete + 'Pedido criado! Conclua o pagamento.' e o usuário é despejado na lista de pedidos sem nunca ver as opções de PIX/cartão — mesmo com MP conectado. Sem mensagem explicando o que houve, parte dos compradores vai achar que concluiu e o professor fica com pedido pendente sem cobrança gerada.

**Evidência:**
```
if (gateway == null || !gateway.pixEnabled || currentUser == null) {
  _goToOrders();
  return;
}
```
**Recomendação:** Em _confirm/_openPaymentSheet, se _gateway ainda for null, aguardar a resolução (`await ref.read(paymentGatewayProvider(...).future)`) em vez de tratar como 'sem gateway'; só seguir para _goToOrders sem sheet quando a resolução concluída for de fato none — e mesmo nesse caso, mostrar o aviso de 'combine com a academia' antes de navegar.

### 36. MpCardTokenizer descarta a causa do erro do Mercado Pago — usuário não sabe se errou CVV, validade ou número
`lib/services/mp_card_tokenizer.dart:48` · dimensão: Flutter (frontend) · confiança do verificador: high

**Problema:** Em respostas não-2xx do /v1/card_tokens, o tokenizer lança apenas 'Falha ao validar o cartao (status)' sem parsear o body do MP (que traz `cause` com códigos como E301 número inválido, E302 CVV, 325/326 validade). Esse Exception genérico ainda escapa do mapeamento amigável nos fluxos de assinatura (createSubscription catch genérico) e de troca de cartão (UpdateSubscriptionCardSheet mostra mensagem fixa). No fluxo de dunning — onde o aluno PRECISA atualizar o cartão para a academia voltar a receber — um erro de digitação vira um beco sem saída sem orientação, aumentando churn de assinatura.

**Evidência:**
```
if (res.statusCode < 200 || res.statusCode >= 300) {
  throw Exception('Falha ao validar o cartao (${res.statusCode}).');
}
```
**Recomendação:** Parsear `cause`/`message` do body de erro do MP e mapear os códigos comuns para mensagens acionáveis em pt-BR ('CVV inválido', 'Data de validade incorreta', 'Número do cartão inválido'), lançando uma exceção tipada que os sheets exibam diretamente. Nunca logar o body junto com dados do request.

---

## Achados refutados na verificação (descartados)

- **(webhook) Webhook legado do paywall pode conceder/revogar assinatura do app a partir de pagamentos do marketplace (cross-talk)** — A evidência citada EXISTE literalmente (functions/index.js:1168-1172 mpParseExternalRef ingênuo; :1246-1247 fallback mpAmountToDays; :1219-1228 revogação em refunded/cancelled; mpResolveAcademyRef resolve o 1º segmento como academyId). Porém o cenário de grant/revoke cruzado NÃO é alcançável, por três guardas que o auditor não considerou ou descartou sem base:

(1) A premissa central do achado — "os tokens OAuth dos vendedores são emitidos pela MESMA aplicação MP do paywall" — é contradita pelo próprio código. server_functions.js:2506-2513 documenta explicitamente que o marketplace é uma aplicação MP DISTINTA: "DISTINCT from the platform paywall MP integration in index.js ... Do not mix the secrets or webhook names", com secrets próprios (MP_OAUTH_CLIENT_ID/MP_OAUTH_CLIENT_SECRET/MP_MKT_WEBHOOK_SECRET) separados dos do paywall (MERCADOPAGO_ACCESS_TOKEN/MP_WEBHOOK_SECRET). Vendedores conectam via OAuth à aplicação de marketplace; eventos de "linked accounts" iriam para o webhook configurado NESSA aplicação, não no painel da aplicação do paywall.

(2) Roteamento explícito: TODO recurso de marketplace (PIX :2924-2925, cartão :3259-3260, preapproval :3621-3626) é criado com notification_url apontando para mercadoPagoMarketplaceWebhook?acad=..., que valida HMAC com MP_MKT_WEBHOOK_SECRET (fail-closed, :3825-3846) e checa parsed.academyId !== acad (:3873).

(3) Guarda técnica decisiva, válida MESMO sob misconfiguração de painel: mpHandlePayment/mpHandlePreapproval só executam após mpFetch(`/v1/payments/${id}` ou `/preapproval/${id}`) ter SUCESSO com o token da plataforma do paywall (index.js:1362-1376; mpFetch lança em não-2xx, :1175-1181). Pagamentos do marketplace são criados com o access_token OAuth do VENDEDOR (application_fee=0, settle direto na conta dele — :2502-2504); na semântica da API do MP, GET /v1/payments/{id} é escopado à conta collector/credencial — o token da plataforma recebe 404, mpFetch lança, o handler nunca roda e nenhum write em Firestore acontece. Resultado: 500 + retries do MP (ruído), nunca concessão/revogação. O próprio auditor admitiu isso como cenário alternativo ("vira 500 + retries... ruído") mas precificou a severidade pelo cenário de grant/revoke, que é inalcançável.

Residual real: a fragilidade defensiva existe (parsing pega tudo antes do 1º ':', fallback por valor) e a recomendação de rejeitar refs com 2º segmento fin|order|sub e remover mpAmountToDays é hardening válido — mas é defense-in-depth de severidade baixa, não vulnerabilidade high alcançável. Confiança media (não high) porque os valores reais dos secrets e a configuração do painel MP não são verificáveis pelo repo; ainda assim a guarda (3) de escopo de token segura o cenário independentemente do painel.

- **(webhook) Path 'payment' de assinatura no webhook marketplace liquida sem validar valor nem vínculo com o preapproval** — A evidência citada existe (functions/server_functions.js:3878-3885: sem amount-check e sem mpPayload), mas o cenário de falha não é alcançável e há guardas que o auditor não viu. (1) O webhook valida HMAC fail-closed e o data.id está no manifest assinado (3825-3846); o payment é re-buscado com o token da PRÓPRIA academia (3871), logo só pagamentos autênticos daquela conta MP entram no fluxo. (2) external_reference do tipo 'sub' (`${acad}:sub:${subId}`) só nasce server-side no POST /preapproval (3596/3621); todos os caminhos de criação de pagamento avulso hardcodam refs 'fin'/'order' server-side (342, 3035, 3144, 3244) — nenhum cliente controla external_reference, então não existe como um aluno/atacante mintar um payment com ref 'sub'. (3) Os únicos payments que o MP gera com esse ref são as cobranças recorrentes do próprio preapproval, cujo transaction_amount foi fixado server-side a partir do plano (auto_recurring.transaction_amount = monthlyValue = sub.recurringValue, 3562/3630) e não há caminho que altere o valor do preapproval — logo amount == recurringValue por construção; um 'pagamento de valor errado' com ref sub só poderia ser forjado pelo próprio dono da conta MP da academia, que já pode escrever financials pagos direto no Firestore (nenhuma fronteira de confiança cruzada). (4) 'Outro preapproval reaproveitando o ref' é impossível: o ref embute um doc id Firestore fresco por chamada. (5) A ausência de amount-check é uniforme em TODOS os caminhos de settle de sub (3477, 4108, 4251), não uma inconsistência deste branch vs fin/order — fin/order checam porque o documento é mutável entre o mint do PIX e o pagamento; recurringValue não é. (6) O ponto do mpPayload é verdadeiro mas imaterial: o espelho do cartão é alimentado na criação (3673-3676), na troca de cartão (3762-3765), no caminho primário subscription_authorized_payment (3478) e nas duas crons (4109, 4252); o branch 'payment' é fallback defensivo explícito, e o pior caso é apenas a perda do aviso cosmético de cartão expirando se o MP entregar somente topic 'payment' para sempre. Conclusão: o claim central (liquidar valor errado / payment de outro preapproval) está neutralizado por guardas estruturais; o que resta é nit de defense-in-depth, não vulnerabilidade real.

- **(oauth-seguranca) Assinatura do webhook não cobre o parâmetro de query `acad` que seleciona academia/token** — The literal evidence is accurate: at functions/server_functions.js:3839 the HMAC manifest is `id:${dataId.toLowerCase()};request-id:${xRequestId};ts:${ts};`, and `acad` (req.query.acad, line 3816) drives getMpAccessToken(acad) and the subscription handlers without entering the signature. But the failure scenario the auditor posits (replaying a legit webhook with a different acad) is fully neutralized by guards on every path:\n\n1) subscription_preapproval -> mpSubSyncPreapproval(acad,...) (3490): uses getMpAccessToken(acad), i.e. academy A's OWN token, to GET /preapproval/{id} that belongs to academy B -> cross-account 404 -> throws -> caught (3892) -> HTTP 500, no settle. Even if it returned, the lookup is scoped to academies/${acad}/subscriptions filtered by mpPreapprovalId==id -> empty -> early return.\n2) subscription_authorized_payment -> mpSubHandleAuthorizedPayment(acad,...) (3463): same pattern, GET /authorized_payments/{id} with A's token -> 404 -> throws; plus the same scoped .where('mpPreapprovalId'==...) empty-guard.\n3) payment path (3870-3874): explicit parsed.academyId !== acad -> ref_mismatch early return; mpMktSettle additionally re-checks amount and does an idempotent status flip.\n4) Same-academy replay / lack of ts freshness: neutralized by idempotency — deterministic finId sub_${subscriptionId}_${paymentId} (3379) blocks double-settle in a transaction; order settle guards on status==='paid'.\n\nCrucially, the recommendation to add acad to the HMAC manifest is semantically infeasible: Mercado Pago's x-signature scheme signs exactly id;request-id;ts — acad is a query param of our own notification URL and is never part of MP's HMAC, so it cannot be added without breaking validation. The proper mitigation (external_reference / per-academy collection scoping) is already implemented on every path. The finding itself concedes cross-tenant impact is nil. This is a defense-in-depth observation, not a reachable/exploitable defect.

- **(frontend) Listener do PIX confirma pagamento por `paymentDate != null` — cobrança reativada mostra 'Pagamento Confirmado!' sem pagamento** — A evidência citada existe (lib/widgets/payment_sheets.dart:190-191 confirma por paymentDate != null; payment_service.dart:641-659 reactivate() não limpa paymentDate), mas o cenário de falha é inalcançável. A guarda está em lib/screens/admin/financial_screen.dart: nas linhas 667-678 e 1982-2020, as ações 'Cancelar' e 'Dar Baixa' só aparecem quando status != paid && status != cancelled, e 'Reativar' só quando status == cancelled — uma cobrança paga mostra 'Sem ações disponíveis'. O fluxo do auditor ('admin marca pago por engano → reativa') não existe: não há como cancelar nem reativar uma cobrança paga, e reactivate() só roda em docs cancelados, que só podem vir de docs não-pagos (cancel gateado por !isPaid), os quais nunca têm paymentDate. Além disso, TODOS os escritores de paymentDate setam status:'paid' na mesma escrita (markAsPaid em payment_service.dart:577-609; mpMktSettle transacional em server_functions.js:3979-3990; settle de cartão AbacatePay ~2233; mpSubSettleCycle ~3395 que cria docs já pagos), o webhook ignora status não-aprovados (3887-3889, sem reversão por refund/chargeback), e não existe 'desfazer baixa' em lugar nenhum (site/ é landing page estática, sem webapp). O aluno só consegue abrir o sheet PIX para cobranças pending/overdue (portal financial_screen.dart:608-609), estado que nunca coexiste com paymentDate via código. Estados residuais exigiriam edição manual no console Firestore ou uma corrida cancel-vs-webhook na qual o dinheiro FOI recebido — em nenhum caso ocorre 'confirmado sem dinheiro'. A recomendação (confirmar só por status=='paid' e limpar paymentDate no reactivate) é hardening válido de baixa prioridade, mas o achado high não é real.
