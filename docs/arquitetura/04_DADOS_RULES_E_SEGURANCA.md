# 04 — Dados, Firestore Rules, segurança e concorrência

## 1. Ownership de coleções e campos

| Dados | Writer atual | Writer-alvo |
|---|---|---|
| `academies.subscription`, OAuth/private | backend | backend |
| configuração visual/básica da academia | admin client | admin client por allowlist/command específico |
| config sensível de acesso/pagamento | admin client misto | backend command |
| `devices.secret` | admin client | backend; hash/versão server-only |
| `accessEvents`, rate limits | backend | backend |
| `students` dados pessoais | staff/self client | client sob whitelist estreita |
| `students` status/vínculo/grade/contadores | client misto | backend commands/triggers |
| `attendance` | staff/aluno client + selfCheckin | backend command; selfCheckin atual preservado |
| `classes` metadados | staff client | pode permanecer client |
| membership de classe + seed de modalidade | client multi-write | backend command |
| `beltProgressions`/achievements oficiais | staff client + backend | backend |
| `selfGraduations`/`selfCompetitions` | dono client + guard | preservar |
| `storeProducts` | staff client | pode permanecer; ajustes críticos auditados |
| `storeOrders`/stock settlement | client + webhook | backend |
| `linkCodes`/`instructorLinkCodes` | legado client + backend | backend após corte |
| `publicProfiles` | trigger backend | preservar server-only |
| `retention.*`/snapshots | backend | preservar server-only |
| `retentionContacts` | staff client + job fecha outcome | preservar com allowlist/auditoria ou command fino |

Não transformar `students` inteiro em server-write-only de uma vez. Separar
campos pessoais self-service de campos autoritativos evita regressão offline e
reduz Functions desnecessárias.

## 2. Sequência obrigatória para fechar Rules

1. documentar contrato e ownership;
2. implementar backend e testes;
3. publicar app que usa o caminho novo;
4. telemetrar uso do caminho antigo;
5. impor versão mínima ou aguardar janela acordada;
6. executar backfill antes de exigir campos novos;
7. fechar Rules e rodar Emulator tests;
8. remover client legacy em release posterior.

Nunca apertar Rules no mesmo deploy que inaugura o único caminho compatível.

## 3. Matriz mínima de Rules tests

Para cada coleção:

- não autenticado;
- aluno próprio, aluno de outro tenant e responsável;
- monitor;
- instrutor sem/com extra permission;
- admin, owner;
- tentativa cross-academy;
- create/update/delete;
- alteração de um campo permitido junto com um server-owned;
- terminal state;
- documento ausente/legado sem campo novo.

Rules devem testar diff de campos e valores, não apenas “role pode update”.

## 4. Segredos

### Catracas

- guardar hash, versão e timestamps;
- comparação timing-safe no backend;
- segredo em claro exibido uma vez;
- rotação com overlap curto e revogação;
- remover segredo de query string quando firmware permitir header/HMAC;
- redigir URL, header e payload nos logs.

### Notificação e pagamentos

O plano de pagamentos já determina remoção de chaves do build/Flutter. Aplicar a
mesma política a todo adapter: Secret Manager/param server-side, nunca
`String.fromEnvironment` para credencial privada.

Firebase Web API key em `firebase_options.dart` é identificador público do
cliente, não deve ser tratada como segredo. A proteção depende de Auth, App
Check, Rules e restrições do projeto.

### TOTP

Seed TOTP é secreto por usuário: cifrado em repouso, jamais Firestore-readable
pelo cliente após setup. Backup code é armazenado como hash e exibido uma vez.

## 5. Autorização multi-tenant

Toda Function recebe `academyId`, mas não confia nele. O handler:

1. exige `request.auth.uid`;
2. valida formato de `academyId` e ids que compõem paths;
3. resolve vínculo pelas três eras documentadas;
4. resolve papel e `extraPermissions` server-side;
5. valida que os documentos lidos pertencem ao tenant;
6. grava ator a partir de Auth.

Centralizar em `shared/auth.js` e `shared/permissions.js`. Hoje existem helpers
semelhantes em `index.js` e `server_functions.js`; duplicação pode produzir
decisões distintas.

## 6. Idempotência e concorrência

| Operação | Chave sugerida |
|---|---|
| Presença única | `studentId:classId:YYYYMMDD` |
| Presença manual múltipla | `requestId` |
| Promoção | `studentId:sport:targetGrade:targetStripes:requestId` |
| Pedido | `uid:cartFingerprint:requestId` |
| Settle de estoque | `orderId:paymentId` |
| Link code consume | hash do código + uid, transação única |
| Import | `jobId:rowNumber` |
| Hard delete | `academyId:studentId:policyVersion` |

Desabilitar botão não é idempotência. Retry de rede, dois dispositivos e webhook
podem repetir a operação mesmo com UI perfeita.

Transação Firestore é suficiente quando tudo cabe nos limites. Para API externa
+ Firestore, usar state machine/outbox/reconciler; não segurar transação aberta
durante HTTP.

## 7. Auditoria

Operações sensíveis gravam evento append-only:

```yaml
action: store_order.mark_paid_manual
academyId: string
targetType: storeOrder
targetId: string
actorUid: string
actorRole: string
requestId: string
occurredAt: timestamp
before: allowlist resumida
after: allowlist resumida
reason: string?
source: app|cron|webhook|device
```

Nunca registrar token, secret, código TOTP, CPF completo, cartão, mensagem livre
sem redaction ou snapshot Firestore integral.

## 8. PII e projeções

`publicProfiles` é o padrão correto: projeção mínima, server-owned, opção de
privacidade e sem PII. Repetir para social/cross-academy/relatórios quando o
cliente hoje precisa ler docs privados amplos.

- allowlist positiva de campos;
- versionar projeção (`projectionVersion`);
- trigger/backfill idempotente;
- teste que falha se campo sensível novo entrar no espelho;
- delete/anonymize propagado;
- risco de retenção nunca aparece em perfil público.

## 9. App Check e abuso

App Check ajuda a reduzir abuso, mas não substitui Auth/Rules. Habilitar
gradualmente em callables e endpoints públicos com métricas antes de enforcement.
Endpoints sem Auth (catraca/link público) precisam rate limit, anti-replay,
idempotência, limite de body e identifiers validados.

## 10. Backfills

Todo script em `functions/scripts/` deve:

- dry-run por padrão;
- exigir projeto/tenant explícito;
- validar path absoluto de destino lógico;
- paginar e limitar concorrência;
- usar chave idempotente/version field;
- produzir contagens before/after/errors;
- não conter secrets;
- ter runbook de rollback quando reversível.
