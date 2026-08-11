# 06 — Testes, CI e observabilidade

## 1. Baseline confirmado

- 39 arquivos de teste Flutter;
- 4 arquivos de teste Node;
- nenhum teste de Firestore Rules encontrado;
- `functions/package.json` não possui script `test` ou `check`;
- um único workflow, `windows.yml`;
- `flutter analyze` roda nesse workflow com `continue-on-error: true`;
- execução auditada de `flutter analyze` reportou 265 issues;
- não há gate de tamanho, imports proibidos ou inventário de exports Firebase.

Há bons testes puros em `test/core` e alguns contratos financeiros. O gap é
principalmente behavior de application service, Rules, integração multi-doc e
execução obrigatória no CI.

## 2. Pipeline-alvo

Criar `.github/workflows/quality.yml` com jobs paralelos:

```text
flutter-quality
  -> pub get
  -> format check
  -> architecture checks
  -> analyze (baseline/no-new primeiro; fatal depois)
  -> flutter test

functions-quality
  -> npm ci
  -> lint/check
  -> unit/contract tests
  -> export inventory

firebase-emulator
  -> Rules tests
  -> application integration tests
```

Build Windows depende desses gates ou roda em paralelo, mas não é o único CI.

## 3. Analyzer sem big-bang

Os 265 issues não justificam manter tudo não bloqueante para sempre.

1. salvar baseline por regra/arquivo;
2. CI falha apenas para issue nova;
3. arquivo tocado não pode aumentar seu total;
4. corrigir warnings ao decompor cada feature;
5. tornar errors e warnings fatal quando baseline chegar a zero;
6. infos de deprecation/print entram em budget decrescente.

Não misturar limpeza de centenas de lints no PR mecânico de um domínio crítico.

## 4. Testes por camada

| Camada | Tipo |
|---|---|
| Domain Dart/Node | unitário puro, tables/property tests |
| Controller Flutter | unitário com fake repository/commands |
| Widget/section | jornada e estados idle/loading/error/success |
| Backend application | fake repositories, clock e adapters |
| Firestore repository | Emulator |
| Rules | Emulator com matriz de papéis/tenants/campos |
| API externa | contract fake + sandbox controlado |
| E2E | poucos fluxos críticos, estáveis e com fixtures |

Source-grep test é canário temporário, não prova comportamento.

## 5. Testes necessários antes dos primeiros movimentos

### Catracas

- create/rotate retorna secret uma vez;
- hash atual/anterior e revogação;
- admin de outro tenant negado;
- logs redigidos;
- ingest aceita/rejeita por versão sem regressão dos adapters.

### Loja

- preço/total sempre vêm do banco;
- duas compras disputando último estoque;
- duplicate request não duplica pedido/settle;
- cancel restaura uma vez;
- status terminal não reabre;
- manual paid e webhook convergem.

### Identidade

- bootstrap retry retorna mesma academia;
- falha intermediária recuperável;
- join preserva três eras de vínculo;
- leave remove todos os lados ou marca saga partial;
- cross-tenant/role escalation negados;
- code redeem é single-use sob corrida.

### Presença

- duas chamadas concorrentes geram uma presença;
- bulk reporta already-present sem duplicar contador;
- remove reverte contador atomicamente;
- timezone na virada do dia BR;
- backdate exige permissão;
- selfCheckin e staff scheduleless colidem no mesmo id.

### Graduação

- matriz esporte/categoria/faixa/grau;
- promoção cria student/progression/achievement uma vez;
- target inválido/retrocesso negado;
- correção/undo preservam audit trail;
- BJJ legacy fields e `sportData` ficam coerentes.

### Deletion/import jobs

- dry-run sem write;
- retry do meio não repete itens concluídos;
- financeiro liquidado preservado/anônimo conforme policy;
- coleção nova sem policy faz teste falhar (fail-closed);
- linhas inválidas não abortam itens válidos.

## 6. Characterization tests para god-files

Antes de extrair uma tela:

- rota e deep link;
- tabs/sections visíveis por role/feature flag;
- estados loading/empty/error/data;
- confirmação e copy das ações críticas;
- refresh/invalidation;
- pop/back e retorno de dialogs;
- analytics, quando houver;
- snapshots apenas para componentes estáveis, não para tela inteira mutável.

O teste não precisa cobrir cada pixel. Precisa congelar o comportamento que o
split não está autorizado a mudar.

## 7. Architecture checks

Adicionar script rápido que falha quando:

- novo arquivo de produção passa de 600 linhas;
- arquivo legado acima do teto cresce além do baseline;
- `lib/features/**/presentation` importa Firestore, HTTP ou service concreto;
- `domain` importa Flutter/Firebase/Riverpod;
- `functions/index.js` ganha domínio além de export/composição;
- novo secret-like `dart-define` é adicionado;
- arquivo em `legacy/` ganha novo importador fora de allowlist;
- export Firebase desaparece da lista aprovada.

O check deve aceitar allowlist pequena, comentada e com prazo/fase de remoção.

## 8. Observabilidade backend

Log estruturado comum:

```yaml
severity: INFO|WARNING|ERROR
event: attendance.take.completed
requestId: string
academyId: string
actorUid: string
targetId: string?
durationMs: number
outcome: success|denied|partial|failed
errorCode: string?
```

Redaction ocorre antes de serializar. Não incluir payload cru.

Métricas/alertas:

- error rate e p95 por Function;
- denied por permission/tenant;
- idempotent replay count;
- transação contention/retry;
- job partial/lease expired;
- store stock mismatch;
- attendance counter drift;
- projection lag;
- Function deletada/ausente após deploy.

## 9. Reconcilers

Dados desnormalizados precisam de verificação:

- `student.attendanceCount` vs attendance real;
- grade do student vs última progressão oficial;
- order stock ledger vs produto;
- mapping/user/student link;
- report snapshot watermark;
- public/social projection version.

Reconciler começa em audit-only, gera contagem/amostra sem PII e só depois ganha
modo repair explícito.

## 10. Definition of ready para refatorar um domínio

- [ ] owner e invariantes documentados;
- [ ] contrato atual caracterizado;
- [ ] exports/Rules/call sites inventariados;
- [ ] testes essenciais verdes;
- [ ] rollback definido;
- [ ] mudança cabe em PR revisável;
- [ ] nenhuma migração de runtime/schema misturada sem necessidade.
