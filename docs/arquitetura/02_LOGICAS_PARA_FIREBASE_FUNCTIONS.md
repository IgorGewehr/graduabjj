# 02 — Lógicas que devem migrar para Firebase Functions

## 1. Objetivo

Tornar server-authoritative os domínios em que o cliente atual coordena
segredos, identidade, estoque, presença, graduação ou cascatas. A migração é
incremental e preserva nomes/contratos existentes quando houver app antigo vivo.

## 2. Controle de acesso e dispositivos — P0

### Commands

| Function | Permissão | Responsabilidade |
|---|---|---|
| `createAccessDevice` | admin | valida vendor/config, gera id e segredo, guarda hash/versão |
| `rotateAccessDeviceSecret` | admin | invalida versão anterior e retorna segredo uma vez |
| `updateAccessDeviceConfig` | admin | allowlist de campos não secretos |
| `disableAccessDevice` | admin | desabilita sem apagar auditoria/eventos |
| `deleteAccessDevice` | owner/admin reforçado | somente após confirmação e política de retenção |
| `enrollAccessDeviceUser` | staff autorizado | associa externalUserId a studentId com auditoria |

### Modelo-alvo

```yaml
devices/{deviceId}:
  name: string
  vendor: controlid|zkteco|intelbras
  enabled: bool
  secretHash: string
  secretVersion: int
  secretRotatedAt: timestamp
  createdAt: timestamp
  createdBy: uid
  updatedAt: timestamp
  updatedBy: uid
```

O segredo em claro só aparece na resposta de create/rotate e na tela de
provisionamento. Não entra em URL persistida, analytics, Crashlytics ou logs.
Durante rollout, ingest aceita hash atual e, por janela curta, versão anterior.

## 3. Loja, pedidos e estoque — P0

### Commands

| Function | Permissão | Invariantes |
|---|---|---|
| `createStoreOrder` | aluno/responsável/staff | relê produtos, preço, política, status e estoque |
| `markStoreOrderPaidManual` | staff autorizado | transição + estoque + auditoria + invalidação de tentativa |
| `transitionStoreOrder` | staff | máquina de estados forward-only |
| `cancelStoreOrder` | owner/staff autorizado | restaura estoque uma única vez |
| `updateStoreStock` | staff | ajuste com motivo e ledger |

### Regras

- request envia `productId`, quantidade, tamanho e cor; nunca preço/total.
- total e política de método são derivados no servidor.
- estoque é reservado/decrementado em transação.
- `stockSettled` ou ledger impede decremento/restauração duplicados.
- request idempotente usa `requestId` ou doc-id determinístico.
- pagamento por webhook e manual convergem no mesmo application service.
- status válidos: `pending_payment -> paid -> preparing -> ready -> delivered`;
  cancel/refund possuem branches explícitos.

`storeOrders` vira client-read-only após corte; produto pode continuar CRUD
staff-direct numa primeira fase, desde que preço/estoque do pedido sejam sempre
revalidados no backend.

## 4. Identidade, membership e academia — P0

### Consolidar os caminhos existentes

`functions/index.js` já contém join, requests, transfer, leave, roles e códigos.
Extrair sem mudar exports:

```text
identity/
  authorization.js
  membership_repository.js
  student_link_resolver.js       # preserva as 3 eras de vínculo
  join_service.js
  leave_service.js
  role_service.js
  academy_bootstrap.js
  link_codes.js
```

### Commands

- `bootstrapAcademy`: chamado após Firebase Auth; cria global user, academy,
  academy user e mapping de forma idempotente. Se retry, retorna a mesma academia.
- `leaveAcademy`: desfaz linkedUserId, academy user e mapping de forma atômica
  ou com estado de saga explícito.
- `setPrimaryAcademy`: valida que o destino pertence ao mapping vivo.
- `redeemStudentLinkCode`: manter/absorver `joinAcademy` atual.
- `createStudentLinkCode`: gera, aplica TTL, hash e limite de ativos.
- `revokeStudentLinkCode`: server-side.
- role/promotion/demotion continuam no backend atual, mas saem de `index.js`.

FCM topic é efeito local best-effort. Falha em subscribe não desfaz membership;
um login posterior reconcilia subscriptions.

## 5. Presença e check-in — P1

### Commands

| Function | Uso |
|---|---|
| `takeAttendance` | uma ou várias presenças staff, mesma regra e ids |
| `removeAttendance` | apaga presença + ajusta contador na mesma transação |
| `confirmPendingCheckins` | converte pendências em presença de forma idempotente |
| `recordManualAttendance` | origem/motivo explícitos; política para múltiplas no dia |
| `recordSchedulelessAttendance` | core compartilhado com `selfCheckin` |

### Invariantes

- doc-id: `{studentId}_{classId}_{YYYYMMDD}` quando só uma presença/dia é válida;
- presença manual múltipla usa `requestId` determinístico, não auto-id sem dedup;
- data canônica usa relógio server + timezone America/Sao_Paulo; backdate exige
  permissão e motivo;
- student e class pertencem ao mesmo `academyId`;
- ator é `request.auth.uid`, nunca string recebida;
- `attendanceCount` muda junto com a presença;
- milestone/feed/retention são eventos pós-commit idempotentes;
- bulk processa chunks e retorna `created/alreadyPresent/failed` por aluno.

Queries de calendário, por aluno e por turma ficam em `AttendanceQueries` no
Flutter, com paginação.

## 6. Graduação e conquistas — P1

### Commands

- `promoteStudent`;
- `correctStudentGraduation`;
- `undoStudentGraduation`;
- `setAchievementVisibility` em lote quando necessário;
- `recomputeStudentMilestones` já existe e deve delegar ao módulo novo.

Transação de promoção:

1. relê student e configuração da academia;
2. valida modalidade, categoria, escada, grade atual e permissão;
3. decide se é faixa ou grau;
4. cria `beltProgressions/{id}`;
5. atualiza `sportData` e campos BJJ legados;
6. cria achievement/timeline com id determinístico;
7. grava audit event.

Elegibilidade pode ter preview Dart para UX, mas backend Node é a autoridade.
Para reduzir espelhos manuais, persistir `ladderVersion`/config ou gerar as duas
representações a partir de um artefato de catálogo validado no build.

## 7. Turmas e matrícula — P1

### Commands

- `addStudentsToClass`;
- `removeStudentsFromClass`;
- `moveStudentBetweenClasses`, se o produto ganhar essa ação;
- `archiveClass`, quando houver presença/reserva histórica.

Adicionar aluno atualiza roster e seed de `sports/sportData` no mesmo command.
Para listas grandes, chunks idempotentes registram item status. `create/update`
de metadados simples da turma pode permanecer client-direct inicialmente.

## 8. Exclusão e importação de alunos — P1

### Hard delete

`requestStudentDeletionJob` cria:

```text
academies/{academyId}/deletionJobs/{jobId}
  targetStudentId
  requestedBy
  status: planned|running|partial|completed|failed
  policyVersion
  countsByCollection
  errors
```

- dry-run obrigatório antes de confirmar;
- política decide anonimizar, reter ou apagar cada coleção;
- financeiro liquidado e auditoria nunca somem por decisão implícita do app;
- retry continua do checkpoint;
- novos domínios entram num registry testado de retention/deletion.

### Import

Flutter continua parseando CSV para preview. Ao confirmar, envia linhas
normalizadas para `studentImportJobs`; worker processa chave idempotente por
linha (`jobId:rowNumber` ou external key), grava erros estruturados e permite
retry apenas dos itens falhos.

## 9. Códigos de convite — P1

Após a versão mínima:

- coleção não permite list/query público de códigos;
- armazenar `codeHash`, não código em claro como chave de busca enumerável;
- callable aplica rate limit por uid/IP/device e TTL;
- consume é transacional com claim do student;
- logs não registram código;
- código de instrutor valida permissions contra allowlist server-side.

## 10. Competições — P1/P2

Autodeclarações pessoais em `students/{id}/selfCompetitions` permanecem no
cliente. Já competição oficial ganha backend quando houver capacidade,
inscrição, transporte, resultado que alimenta medalha/achievement ou operação
multi-doc:

- `enrollCompetition` valida aluno, prazo, categoria e duplicidade;
- `cancelCompetitionEnrollment` aplica cutoff;
- `recordCompetitionResult` cria resultado + achievement idempotente;
- `deleteCompetitionResult` reverte projeções correspondentes.

## 11. TOTP e endpoints órfãos — P0

Escolher uma das duas opções antes de manter a UI:

1. implementar `security/totp` em HTTPS Functions/callables, com Secret Manager,
   criptografia do seed, backup codes hashed, rate limit e reautenticação; ou
2. esconder/remover o fluxo até existir backend suportado.

O mesmo vale para KYC Asaas legado. Não criar proxy genérico `/api`; cada
capacidade viva deve ter contrato, owner, teste e observabilidade.

## 12. Relatórios, social e projeções — P2

- `exportAcademyReport`: job gera CSV em Storage com URL assinada curta;
- `academyDashboardProjection`: contadores por mês/status;
- `globalFighterHistory`: projeção por uid para evitar N academias sequenciais;
- feed/audiência social: continuar materialização server-side e remover emissão
  duplicada no client conforme cobertura;
- ranking usa projeção/consulta limitada, não download de rosters inteiros.

## 13. Preservação de exports

Antes de mover qualquer Function:

1. gerar lista ordenada de `exports.*` atual;
2. criar teste que carrega `index.js` e compara o contrato;
3. preservar nome externo e runtime durante extração;
4. testar Emulator/cold start;
5. revisar dry-run de deploy contra deletes inesperados.

Extrair módulo não autoriza migrar v1 para v2 no mesmo PR.
