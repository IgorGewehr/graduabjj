# 01 — Arquitetura-alvo e limites

## 1. Fronteira de responsabilidade

```text
Flutter presentation
  -> controller / use case
    -> repository ou backend command

Backend handler
  -> autenticação + parse
    -> application service
      -> domínio puro
      -> repositories/adapters
```

### Flutter

- renderiza estado e coleta intenção;
- mantém estado efêmero do formulário;
- valida formato para UX;
- consulta repositories paginados;
- chama command e interpreta error code estável;
- observa job/projeção e apresenta progresso.

### Firebase Functions

- valida Auth, tenant, papel e permissão;
- relê estado autoritativo;
- aplica invariantes e transições;
- usa transação, idempotência, lock ou job;
- guarda secrets e chama APIs externas;
- grava auditoria e projeções server-owned;
- expõe erro seguro, sem PII ou detalhes internos.

### Firestore Rules

- garantem isolamento de tenant e ownership de campo;
- bloqueiam escrita cliente em documentos server-owned;
- permitem self-service somente por whitelist estreita;
- não tentam reproduzir domínio complexo.

## 2. Teste de decisão: cliente ou backend?

Mover para backend se qualquer resposta for “sim”:

- movimenta/reconhece dinheiro ou estoque?
- usa segredo ou API privilegiada?
- altera dois ou mais documentos/serviços?
- muda vínculo, papel, permissão ou identidade?
- precisa ser igual entre versões diferentes do app?
- depende de relógio, ordem, limite ou capacidade autoritativos?
- recebe retry, concorrência ou entrega duplicada?
- produz histórico legal/auditável?
- será chamado por app, cron, webhook ou dispositivo?

Permanecer no cliente quando for apenas apresentação, preferência própria sob
whitelist, validação de formato, estado temporário ou transformação visual de
dados já autorizados.

## 3. Estrutura Flutter incremental

```text
lib/
  app/
    app.dart
    router/
      app_router.dart
      auth_routes.dart
      portal_routes.dart
      admin_routes.dart
      kiosk_routes.dart
      route_guards.dart
      transitions.dart

  core/
    auth/
    errors/
    logging/
    money/
    time/
    tenant/
    widgets/

  features/
    students/
      domain/
      application/
      data/
      presentation/
    attendance/
    graduation/
    classes/
    identity/
    commerce/
    settings/
    reports/
    social/
    journal/
    competitions/
    access_control/
```

Não é necessário mover o repositório inteiro antes de iniciar. Cada feature
nova entra na estrutura-alvo; arquivos em `screens/`, `services/` e `providers/`
viram façades temporárias e desaparecem após zero call sites.

## 4. Estrutura Functions

```text
functions/
  index.js                         # initializeApp + exports
  shared/
    auth.js
    permissions.js
    validation.js
    tenant.js
    idempotency.js
    time.js
    structured_log.js
    errors.js

  identity/
    handlers.js
    membership_service.js
    academy_bootstrap.js
    link_codes.js
    deletion_jobs.js

  attendance/
    handlers.js
    attendance_service.js
    attendance_repository.js
    ids.js

  graduation/
    handlers.js
    progression_service.js
    ladders.js
    eligibility.js

  classes/
    handlers.js
    membership_service.js
    sport_enrollment.js

  commerce/
    products/
    orders/
    stock/

  access_control/                 # estrutura atual preservada
  retention/                      # extração do arquivo atual
  reports/
  notifications/
  security/totp/
  jobs/import_students/
```

`index.js` não contém domínio. Ele inicializa Admin uma vez e preserva nomes
externos de exports. Nenhum módulo importa `index.js`.

## 5. Limites de tamanho

| Tipo | Alvo | Teto normal |
|---|---:|---:|
| Screen/shell | 150–350 | 400 |
| Section/widget coeso | 80–220 | 250 |
| Controller/use case | 100–300 | 350 |
| Repository/adapter Flutter | 100–300 | 350 |
| Entidade + comportamento puro | 80–300 | 400 |
| Backend domain/adapter | 150–450 | 500 |
| Handler/composition root | 50–250 | 300 |
| Qualquer arquivo de produção | — | 600 |

Exceções: código gerado, catálogo estático ou Rules podem ultrapassar o teto,
com justificativa no arquivo e item de decomposição quando aplicável. Dividir
um arquivo com `part` sem reduzir acoplamento não satisfaz o limite.

O CI deve falhar para novo arquivo acima de 600 e impedir crescimento de um
arquivo legado acima do baseline. A remoção do legado ocorre por orçamento
decrescente, não por um PR gigantesco.

## 6. Command e query separados

Uma interface Flutter não recebe um service de 1.000 linhas com tudo:

```dart
abstract interface class AttendanceQueries {
  Future<AttendancePage> listByStudent(...);
  Stream<AttendanceDay> watchClassDay(...);
}

abstract interface class AttendanceCommands {
  Future<TakeAttendanceResult> take(TakeAttendanceCommand command);
  Future<void> remove(RemoveAttendanceCommand command);
}
```

Queries podem ler Firestore diretamente quando Rules e custo permitem. Commands
sensíveis chamam Functions. Isso evita transformar Functions em proxy de leitura
e mantém cache/offline onde ele agrega valor.

## 7. Contrato de command

Todo command deve declarar:

```yaml
requestId: UUID/ULID gerado por ação do usuário
academyId: tenant explícito
payload: somente intenção, nunca campos server-owned
```

Resposta:

```yaml
ok: true
resultId: string
version: number
warnings: [code]
```

Erro conhecido:

```yaml
code: attendance/already-exists
message: texto seguro opcional
details: allowlist sem PII
retryable: false
```

O backend mapeia `code`; a apresentação decide a copy pt-BR. Não depender de
comparação de texto de Exception.

## 8. Dependências permitidas

- presentation importa application/domain, nunca Firebase concreto;
- application importa domain e interfaces;
- domain não importa Flutter, Firebase, HTTP ou Riverpod;
- data implementa interfaces e pode importar Firebase;
- handler importa application/shared, não contém regra de negócio;
- adapter externo não conhece widget/modelo Firestore cru;
- shared contém contratos estáveis, não um depósito de helpers variados;
- `academyId` é argumento/dependência explícita, nunca global escondido em
  código de domínio.

## 9. Estado e concorrência na UI

- controller expõe `idle/loading/success/error` ou `AsyncValue`;
- mutação nunca ocorre dentro de `build`;
- um submit desabilita repetição visual, mas idempotência continua no backend;
- refresh invalida providers específicos, não toda a árvore;
- dialogs recebem dados e callbacks, não constroem repositories;
- listeners/timers ficam em controllers testáveis e são descartados de forma
  explícita.

## 10. Estratégia de extração

1. listar responsabilidades e call sites;
2. escrever teste de caracterização do comportamento vivo;
3. criar destino com interface pequena;
4. mover uma unidade sem mudar copy/rota/regra;
5. manter façade/reexport temporário;
6. rodar analyzer/testes e comparar call sites;
7. remover façade somente após telemetria/zero imports;
8. então, em PR separado, melhorar comportamento.
