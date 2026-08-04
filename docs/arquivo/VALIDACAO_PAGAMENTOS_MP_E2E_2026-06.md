> **Arquivado (2026-07):** validação E2E pontual de 2026-06-28 contra um commit
> específico. Registro histórico; para o estado vivo ver `docs/PAGAMENTOS_MP.md`.

All findings are verified against the live code. The `markAsPaid` (lines 640-688) is exactly the model the high-sev `cancel` fix should mirror. Now I have everything to write the report.

# Validacao End-to-End — Pagamentos Mercado Pago (GraduaBJJ)

Branch: `firebase-production` (prod, projeto `arpjj-76350`). Data: 2026-06-28. Todos os achados abaixo foram reconfirmados contra o codigo atual antes deste relatorio.

---

## 1) Resumo

Estado geral: **saudavel no nucleo, com lacunas de UX/visibilidade nas bordas.** Nenhum beco sem saida de dinheiro foi encontrado no caminho feliz; os estados terminais continuam consistentes no backend. Os fixes das auditorias anteriores (criticos/altos) **se mantem sem regressao** — confirmei no working tree os guards-chave:

- `markAsPaid` (`lib/services/payment_service.dart:640-688`) ainda faz pre-read de `gatewayPaymentId/paymentGateway`, apaga `gatewayPaymentId` + campos `pix*` e dispara `cancelMpPix` best-effort. A protecao contra double-charge silencioso (webhook nao acha o doc 'paid' com o mesmo charge id → cai na conciliacao em vez de creditar 2x) esta intacta.
- Webhook fail-closed: `mpMktWebhook` recusa sem `MP_MKT_WEBHOOK_SECRET` (`functions/server_functions.js:5632-5634`).
- Modelo marketplace 0% taxa: `application_fee` omitido de proposito (`server_functions.js:3818, 4464`) — MP rejeita `0`.
- 3DS/`in_process` no cartao tratados como pendente (nao recusa), travando re-submit (`payment_sheets.dart:1618-1646`).

O que **nao** se sustenta na ponta-a-ponta sao tres classes de problema:
1. **Feedback de conclusao** que falta no cartao 3DS/pending (aluno fica sem realtime).
2. **Caminho de Cancelar do admin** que e flip local e nao cancela o PIX vivo nem o preapproval (risco real de cobranca fantasma) + ausencia de UI para encerrar assinatura.
3. **Visibilidade de orfaos** (preapprovals orfaos escritos no backend, zero leitores em `lib/`).

Severidade agregada: 2 high, 4 medium, 4 low, 4 info.

---

## 2) Jornada do aluno

### PIX (mensalidade/avulsa) — OK
`PixPaymentSheet` tem listener realtime (`payment_sheets.dart:165-202`): observa `academies/{acad}/{storeOrders|financials}/{id}`, detecta `status=='paid'` (ou `paymentDate!=null` p/ financial), dispara haptic + dialog de sucesso + `onPaymentConfirmed`. Cancela no `dispose` (`:207`). Este e o padrao de referencia.

### Cartao 3DS / in_process — LACUNA (medium)
`CardPaymentSheet._handlePayment` trata corretamente 3DS (`:1618-1631`) e `in_process/pending` (`:1637-1646`) como pendente e trava re-submit — **mas nao monta nenhum listener.** O aluno fica numa tela "aguardando" estatica que nunca muda mesmo apos a aprovacao chegar via webhook segundos depois. Estado fica consistente no backend, porem sem feedback de conclusao no caminho mais sensivel.
- Loc: `lib/widgets/payment_sheets.dart:1618-1646`. Contraste: `:165-202`.

### Assinatura recorrente `pending` exibida como verde — LACUNA (low)
`createSubscription` ja **retorna o `status`** real do preapproval (`mercado_pago_service.dart:184-191`, campo `status` no record), e a mensagem textual ja diferencia `authorized` de `pending`. Porem o call site **descarta o status**: `result = CardPaymentResult(success: sub.success, message: sub.message)` (`payment_sheets.dart:1537`) — nao seta `status`/`isPending`. Resultado: `pending` cai no branch `result.success` (`:1648`) e mostra snackbar **verde + check** de "sucesso" para uma assinatura ainda nao autorizada pelo emissor. A semantica contradiz o estilo visual.

### Loja (PIX/cartao) — OK com inconsistencia (info)
Cartao da loja roteia corretamente (`payment_sheets.dart:1538-1574`), com `PaymentGateway.none` retornando erro retryable (sem fallback silencioso). PIX da loja tem o mesmo listener. **Inconsistencia:** quando nenhum gateway esta conectado, a mensalidade oferece chave PIX manual da academia (`financial_screen.dart:1487-1535 _PaymentCard`), mas a loja nao (`store_checkout_screen.dart:768-790`) — friccao maior, sem risco de dinheiro.

### Aula particular — OK
Concede 1 presenca ao pagar (MP ou manual), grant idempotente server-side. Sem achados de regressao.

---

## 3) Jornada do professor/admin

### Conectar/Receber — OK
Modelo OAuth marketplace, recebimento direto no `access_token` do admin, `application_fee` omitido (0% taxa). Dual-webhook fail-closed. Sem achados.

### Cancelar cobranca — flip local que NAO cancela o PIX vivo nem o preapproval (HIGH)
`PaymentService.cancel(id)` (`lib/services/payment_service.dart:694-698`) e **apenas** `update(id, {status: cancelled})`. Nenhum pre-read, nenhum `cancelMpPix`, nenhum `cancelMpSubscription`, e o call site `_cancelPayment` (`financial_screen.dart:1603-1616`) **nao tem dialogo de confirmacao**. Consequencias:
- Aluno pode pagar um PIX que o admin deu por cancelado (cobranca fantasma).
- Mensalidade subscription-backed: o cartao **continua sendo debitado** apos o admin "cancelar".
Exatamente o risco que `markAsPaid` e `disconnect` ja mitigam, deixado aberto neste caminho.

### Cancelar/pausar assinatura de um aluno — sem UI no admin (MEDIUM)
`SubscriptionService.cancel/pause/resume` (`subscription_service.dart:195-218`) existe e o backend ja autoriza admin (`assertCanPayFor`), mas a **unica chamada de UI** esta na tela do aluno (`portal/financial_screen.dart`). Zero referencia em `lib/screens/admin/`. Aluno que sai sem cancelar → professor so para a cobranca desconectando o MP inteiro (derruba todos) ou indo ao painel do MP.

### Preapprovals orfaos — escritos no backend, zero leitores na UI (HIGH)
`mpHasOrphanPreapprovals`/`mpOrphanPreapprovalIds` sao escritos em `server_functions.js:3337-3338` (account switch) e `:3552-3553` (disconnect c/ token revogado). **Grep em `lib/` = 0 hits.** Se a notificacao por proxy/push falhar, o admin nunca sabe que ha assinaturas orfas cobrando cartoes de alunos numa conta que o app nao gerencia mais.

### Confirmacao de desconectar nao avisa do cancelamento de assinaturas (MEDIUM)
O `AlertDialog` (`settings_screen.dart:1338-1340`) so diz "Os alunos nao poderao mais pagar... ate reconectar". **Nao avisa** que TODAS as assinaturas recorrentes ativas serao canceladas e nao voltam sozinhas ao reconectar — perda de receita recorrente silenciosa.

### Falha de disconnect vira mensagem generica (LOW)
`disconnect()` engole a excecao e retorna `false` (`mercado_pago_service.dart:308-316`); o handler mostra "Falha ao desconectar." fixo (`settings_screen.dart:1364`). A instrucao acionavel do backend (ex.: "ha assinaturas ativas, tente em alguns minutos") se perde.

### Marcar pago / gerar — OK
`markAsPaid` solido (vide Resumo). Geracao de mensalidades sem achados.

### Saque — latente, corretamente desligado (info)
`requestWithdrawal` (`server_functions.js:2778-2967`) atrelado ao AbacatePay/wallet → inalcancavel no modelo MP direto (retorna `failed-precondition`). Sem risco em prod; codigo latente.

---

## 4) Documentacao

Inventario de `docs/` confirma: existem **auditorias de bug** (`AUDITORIA_MERCADO_PAGO_2026-06.md`, `AUDITORIA_MP_RECURSIVA_2026-06.md`), o **contrato de implementacao** (`recorrencia-mp-contract.md`, `financeiro-recorrencia.md`) e a spec de aula particular (`aula-particular-turmas.md`). **Nao existe** doc de jornada (aluno/professor) nem `docs/PAGAMENTOS_MP.md` end-to-end.

Risco concreto: conhecimento critico (OAuth marketplace 0% taxa, dual-webhook fail-closed, unidade reais/centavos, papeis das ~25 CFs, secrets como `MP_MKT_WEBHOOK_SECRET`) vive so no codigo + na cabeca do autor. Esquecer de setar o secret = webhook fail-closed silencioso = dinheiro entra no MP e nunca liquida no app.

### Esboco proposto — `docs/PAGAMENTOS_MP.md`
1. **Modelo de integracao** — marketplace OAuth, recebimento direto no token do admin, `application_fee` omitido (0% taxa). Cite `server_functions.js:3818, 4464`.
2. **Unidade monetaria (reais x centavos)** — regra unica: `financials.amount` = REAIS (canonico); fronteira app→CF = CENTAVOS; fronteira CF→MP = REAIS (`transaction_amount`). Tabela por callable. Referencia de validacao: `server_functions.js:3984-3991, 4065`; `mercado_pago_service.dart:67,100,130,236`.
3. **Webhook dual + fail-closed** — `mpMktWebhook` recusa sem `MP_MKT_WEBHOOK_SECRET` (`server_functions.js:5619-5634`).
4. **Catalogo de callables MP** (~25) — papel de cada uma (createCardPayment, createSubscription, cancelMpPix, cancelMpSubscription, disconnectMercadoPago, mpMktSettle/handleReversal...).
5. **Defesas em profundidade** — linkar cada guard ao file:line (markAsPaid pre-read+cancelMpPix `payment_service.dart:640-688`; guarda de duplicacao de assinatura `payment_sheets.dart:1517-1530`; 3DS/in_process `:1618-1646`) para que futuras edicoes nao removam guards sem entender o porque.
6. **Orfaos & disconnect** — semantica de `mpHasOrphanPreapprovals`/`mpOrphanPreapprovalIds` e o efeito do disconnect sobre assinaturas.
7. **Saque** — latente (AbacatePay/wallet), inalcancavel no MP direto.

Doc de jornada (opcional, complementar): `docs/jornada-aluno-pagamentos.md` e `docs/jornada-professor-pagamentos.md` mapeando estados visiveis, transicoes de status do doc e pontos de feedback. Adicionar link curto no `README.md`.

---

## 5) Plano priorizado

### P0 — HIGH (risco de dinheiro / cobranca fantasma)

**5.1 `cancel` deve espelhar `markAsPaid`** — `lib/services/payment_service.dart:694-698`
Reescrever para: pre-ler `gatewayPaymentId/paymentGateway` e os campos de subscription; apagar `pix*` + `gatewayPaymentId`; best-effort `cancelMpPix`; se subscription-backed (`mpSubscriptionId`/`mpPreapprovalId`), encaminhar para `cancelMpSubscription`. Usar `markAsPaid` (`:640-688`) como template literal — ele ja tem todo o padrao de pre-read + best-effort.
```dart
Future<Payment> cancel(String id) async {
  String? gatewayPaymentId, paymentGateway, subscriptionId;
  try {
    final snap = await _paymentsRef.doc(id).get();
    final data = snap.data() as Map<String, dynamic>?;
    gatewayPaymentId = data?['gatewayPaymentId'] as String?;
    paymentGateway   = data?['paymentGateway'] as String?;
    subscriptionId   = (data?['mpSubscriptionId'] ?? data?['mpPreapprovalId']) as String?;
  } catch (_) {}

  final payment = await update(id, {
    'status': PaymentStatus.cancelled.value,
    'gatewayPaymentId': FieldValue.delete(),
    'pixCode': FieldValue.delete(),
    'pixQrCode': FieldValue.delete(),
    'pixTicketUrl': FieldValue.delete(),
    'pixExpiresAt': FieldValue.delete(),
  });

  if (gatewayPaymentId != null && gatewayPaymentId.isNotEmpty &&
      paymentGateway == 'mercadopago') {
    try { await FirebaseFunctions.instance.httpsCallable('cancelMpPix')
        .call({'academyId': academyId, 'paymentId': gatewayPaymentId}); }
    catch (e) { print('[PaymentService] cancel: cancelMpPix failed (non-fatal): $e'); }
  }
  if (subscriptionId != null && subscriptionId.isNotEmpty) {
    try { await SubscriptionService(academyId).cancel(subscriptionId); }
    catch (e) { print('[PaymentService] cancel: cancelMpSubscription failed (non-fatal): $e'); }
  }
  return payment;
}
```
+ Adicionar `AlertDialog` de confirmacao em `_cancelPayment` (`financial_screen.dart:1603`) antes do flip (hoje cancela direto, sem confirmar).

**5.2 Banner de preapprovals orfaos** — `lib/screens/admin/settings_screen.dart` (cartao MP) e/ou `financial_screen.dart`
Ler `mpHasOrphanPreapprovals`/`mpOrphanPreapprovalIds` da academia; exibir banner persistente com os IDs + instrucao de cancelar no painel do MP. Backend ja escreve (`server_functions.js:3337,3552`); falta so o leitor (0 hits hoje).

### P1 — MEDIUM

**5.3 UI admin para encerrar assinatura** — novo botao "Encerrar assinatura" no detalhe da cobranca/aluno admin → `SubscriptionService(academyId).cancel(subscriptionId)` (`subscription_service.dart:195`). Backend pronto e autorizado p/ admin.

**5.4 Aviso no dialogo de desconectar** — `settings_screen.dart:1338`, acrescentar ao `content`: "Todas as assinaturas recorrentes ativas serao canceladas e os cartoes deixarao de ser cobrados. Isso nao pode ser desfeito automaticamente."

**5.5 Listener realtime no cartao 3DS/pending** — `payment_sheets.dart:1618-1646`. Quando `_paymentPending` vira true, montar `StreamSubscription` no doc (espelhar `PixPaymentSheet._setupPaymentListener` `:165-202`): ao detectar `paid`/`paymentDate`, fechar sheet + `onPaymentSuccess` + dialog. Cancelar no `dispose`.

### P2 — LOW

**5.6 Subscription pending ≠ verde** — propagar `status` ate o `CardPaymentResult`: em `payment_sheets.dart:1537` trocar por `result = CardPaymentResult(success: sub.success, message: sub.message, isPending: sub.status != 'authorized')` (o record ja expoe `sub.status`, `mercado_pago_service.dart:190`). Assim `pending` cai no branch `result.isPending` (`:1637`, estilo neutro) em vez do snackbar verde.

**5.7 Propagar erro de disconnect** — `mercado_pago_service.dart:308` capturar `FirebaseFunctionsException` e propagar `e.message`; `settings_screen.dart:1364` exibir essa mensagem em vez de "Falha ao desconectar." fixo.

**5.8 Docs** — criar `docs/PAGAMENTOS_MP.md` (esboco secao 4) + link no `README.md`.

### P3 — INFO (sem acao / opcional)
- PIX manual na loja sem gateway (`store_checkout_screen.dart:162-186`) — espelhar `_PaymentCard` da mensalidade ou documentar como presencial.
- `requestWithdrawal` latente — manter desligado, documentar; considerar remover se descontinuar AbacatePay.
- Docs de jornada (aluno/professor) complementares ao `PAGAMENTOS_MP.md`.

---

Arquivos relevantes (todos confirmados):
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/payment_service.dart` (`cancel` :694; `markAsPaid` :640-688)
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/widgets/payment_sheets.dart` (PIX listener :165-202; cartao :1500-1674)
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/mercado_pago_service.dart` (`createSubscription` :180-191; `disconnect` :308-318)
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/subscription_service.dart` (`cancel/pause/resume` :195-218)
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/admin/financial_screen.dart` (`_cancelPayment` :1603-1616)
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/admin/settings_screen.dart` (`_disconnectMercadoPago` :1333-1369)
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/server_functions.js` (orfaos :3337,3552; application_fee :3818,4464; webhook secret :5619-5634)
- `/Users/igorgewehr/WebstormProjects/graduabjj/docs/PAGAMENTOS_MP.md` (a criar)