# 04 — Dados, segurança e observabilidade

## 1. Propriedade dos campos

| Dado/campo | Escritor autorizado |
|---|---|
| `financials.amount`, `dueDate`, `status` | Cloud Function de ação financeira |
| `method`, `paymentDate`, `paymentGateway` | settle ou ação manual server-side |
| `gatewayPaymentId`, `pix*`, `cardPending*` | adapter/settle Mercado Pago |
| `financialVersion`, `publicPaymentLinkHash` | serviço de cobrança pública |
| `lastReminder*`, `lastDueSoon*` | dispatch backend |
| `subscriptions/*` | backend apenas (já é assim) |
| `private/mpAuth` | backend apenas (já é assim) |
| `publicPaymentLinks/*` | backend apenas |
| `paymentAttempts/*` | backend apenas; staff pode ler projeção segura |
| `billingDispatchJobs/*` | backend; solicitante/staff pode ler |

Objetivo final: cliente não escreve `financials`. Ele chama uma ação com
permissão e recebe o estado resultante.

## 2. Firestore Rules

### 2.1. Novas coleções

```rules
match /publicPaymentLinks/{linkHash} {
  allow read, write: if false;
}

match /academies/{academyId}/paymentAttempts/{attemptId} {
  allow read: if isAcademyAdmin(academyId);
  allow write: if false;
}

match /academies/{academyId}/billingDispatchJobs/{jobId} {
  allow read: if isAcademyStaff(academyId);
  allow write: if false;

  match /items/{itemId} {
    allow read: if isAcademyStaff(academyId);
    allow write: if false;
  }
}
```

### 2.2. Financials

Estado final:

```rules
match /academies/{academyId}/financials/{financialId} {
  allow read: if isAcademyStaff(academyId)
              || isOwnStudentRecord(academyId, resource.data.studentId)
              || isResponsibleForStudent(academyId, resource.data.studentId);
  allow write: if false;
}
```

Isso só entra depois da publicação e adoção da versão que usa callables para
create/update/pay/cancel/reactivate/delete. Até lá, criar uma regra intermediária
que bloqueie explicitamente todos os campos server-owned e telemetrar recusas.

### 2.3. Store orders

Aluno ainda pode criar o pedido com whitelist estrita; fulfillment staff pode
alterar somente `status` dentro da máquina de estados. Campos `gateway*`,
`payment*`, `pix*`, valor, itens e estoque são server-only.

### 2.4. Testes de Rules obrigatórios

- aluno lê somente a própria cobrança;
- responsável lê somente dependente;
- instrutor sem permissão não cria ação financeira;
- admin não escreve campos monetários diretamente após o corte;
- público não lê link/tentativa no Firestore;
- app não planta gateway fields em pedido;
- estado terminal não reabre pelo cliente.

## 3. Token público

- Gerar 32 bytes com CSPRNG.
- Codificar Base64URL sem padding.
- Armazenar `SHA-256(rawToken)` como doc ID.
- Comparação do hash em representação fixa.
- Não colocar academia/financial/aluno no token.
- Não registrar token bruto, URL completa nem body da API pública.
- Permitir revogação e rotação individual.
- A posse do link autoriza **ver o resumo mínimo e iniciar checkout**, não alterar
  a dívida nem ler cadastro.

O link pode ser duradouro; a cobrança continua fechando a autorização quando
fica paga/cancelada. “Duradouro” não significa impossível de revogar.

## 4. Proteção do endpoint público

- HTTPS obrigatório.
- Métodos estritos: POST para API, GET só para shell estático.
- `Content-Type: application/json` e limite de body pequeno.
- Origin allowlist para o site oficial; não usar CORS `*` no start.
- Rate limit por `linkHash` e IP hasheado.
- Lock/idempotência por `requestId` e financialVersion.
- Limite de tentativas novas por link em janela; tentativa viva é reusada.
- Timeout explícito na API MP.
- Respostas genéricas para token inválido/revogado, evitando enumeração.
- CSP sem inline inseguro quando viável.
- `frame-ancestors 'none'`, `X-Frame-Options: DENY`.
- `Referrer-Policy: no-referrer` e `Cache-Control: no-store`.
- `robots: noindex,nofollow`.
- CAPTCHA/Turnstile somente se métricas mostrarem abuso; não adicionar fricção
  preventiva ao pagamento normal.

App Check não substitui autenticação nesse endpoint, pois o comprador não tem o
app. A defesa é token de alta entropia + validação server-side + rate limit.

## 5. Segredos

### Correção imediata

1. Rotacionar a credencial do notification server atualmente presente em
   `build.sh` e já distribuída em binaries.
2. Revogar a credencial antiga após backend novo estar apto a enviar.
3. Remover todas as chaves de `dart-define`.
4. Armazenar novas chaves no Secret Manager.
5. Considerar limpeza do histórico Git conforme política do repositório, sabendo
   que limpeza não substitui rotação.

### Inventário obrigatório

| Secret | Consumidor permitido |
|---|---|
| `MP_OAUTH_CLIENT_ID/SECRET` | `payments/academy/oauth_*` |
| `MP_MKT_WEBHOOK_SECRET` | webhook academia |
| token MP plataforma | `payments/platform/*` |
| secret webhook plataforma | `payments/platform/webhook` |
| chave notification server | `notifications/client.js` |

Nenhum log imprime token, refresh token, CPF completo, e-mail completo ou chave.

## 6. Webhook e conciliação

Preservar:

- HMAC timing-safe;
- janela anti-replay;
- fetch server-to-server do pagamento;
- confirmação de tenant pela referência;
- validação de valor;
- idempotência;
- unmatched payment;
- estorno integral/parcial e chargeback.

Adicionar:

- `correlationId` estável por evento;
- `attemptId` quando conhecido;
- armazenamento de `payment_method_id` e `payment_type_id` crus para auditoria;
- mapper canônico para `pix`, `credit_card`, `debit_card`, `account_money`,
  `bank_slip` ou `other`;
- métrica de webhook inválido, stale, retry e atraso até settle;
- reconciliação periódica de tentativas `pending` antigas.

Não mapear todo método não-Pix como cartão, como ocorre hoje.

## 7. LGPD e minimização

Página pública pode exibir:

- nome público da academia;
- logo;
- primeiro nome ou nome abreviado do pagador/aluno;
- descrição saneada;
- valor, vencimento e status.

Não pode exibir:

- CPF;
- telefone/e-mail;
- endereço;
- turma, saúde, graduação ou histórico;
- IDs internos;
- lista de outras dívidas;
- nome completo de menor se não for necessário.

Eventos analíticos usam `academyId`/`financialId` apenas em ambiente server-side
com acesso controlado. Ferramenta web/analytics não recebe token nem PII.

## 8. Logging estruturado

Formato mínimo:

```json
{
  "event": "public_checkout_started",
  "severity": "INFO",
  "correlationId": "...",
  "academyId": "...",
  "targetType": "financial",
  "targetId": "...",
  "attemptId": "...",
  "provider": "mercadopago",
  "mode": "checkout_pro",
  "result": "ready",
  "durationMs": 213
}
```

Nunca incluir `rawToken`, `init_point` completo, CPF, PAN, CVV, access token ou
payload inteiro do MP.

## 9. Métricas e alertas

Funil:

```text
reminder_sent
  -> public_link_resolved
  -> checkout_started
  -> payment_created
  -> payment_approved
  -> financial_settled
```

Alertas:

- webhook 5xx ou 401 acima do baseline;
- approved sem settle após 5 minutos;
- `amount_mismatch` > 0;
- `unmatchedPayments` novo;
- duplicidade aprovada;
- refresh OAuth falhando/`mpNeedsReauth`;
- taxa de `checkout_start_failed` elevada por academia;
- fila de billing jobs parada;
- links resolvidos com cobrança inexistente acima do normal.

Indicadores de produto:

- conversão mensagem → abertura;
- abertura → checkout;
- checkout → pagamento;
- tempo até pagamento;
- métodos escolhidos;
- expirações por pagamento, sem apresentá-las como cancelamento da dívida.

## 10. Retenção e limpeza

- `paymentAttempts`: manter conforme necessidade fiscal/suporte; dados técnicos
  sem PII podem ser arquivados/agregados após a janela definida.
- Rate-limit counters: TTL curto.
- Billing job items: TTL após período operacional, preservando resumo do job.
- Links de cobrança pagos podem permanecer para mostrar comprovante mínimo, mas
  devem ser revogáveis e não listar histórico.
- Logs seguem política de retenção e redaction central.

