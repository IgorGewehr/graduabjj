# 05 — Performance e acesso a dados

## 1. Diagnóstico

O maior custo não vem apenas de widgets grandes. Há telas que carregam coleções
inteiras, services que fazem N reads sequenciais e providers que recompõem
projeções globais no dispositivo.

Candidatos confirmados:

- `reports_screen.dart` consulta e agrega presença, financeiro, loja e alunos;
- `StudentService.getAll/listAll` é usado por relatórios/imports/listas;
- `BeltProgressionService.getEligibilitySnapshot` percorre alunos e dependências;
- `CrossAcademyService` visita academias/fichas em sequência;
- `friend_providers.dart` combina attendance, logs, classes, perfis, feed e
  ranking;
- `StoreService.createOrder` relê cada produto sequencialmente;
- `ClassService.addStudents` dispara um read/write por aluno após alterar roster;
- `bulkUnmarkPresent` busca a classe e filtra datas no cliente em um caminho;
- várias telas aplicam busca/filtro depois de carregar toda a coleção.

## 2. Regra para queries

Toda query de lista deve declarar:

- tenant e audience;
- order canônico;
- limite/página;
- cursor;
- índices necessários;
- comportamento de refresh;
- custo esperado de reads;
- estado vazio/erro;
- necessidade ou não de tempo real.

`getAll()` sem limite é reservado para job/export/admin controlado, nunca fluxo
principal de uma tela.

## 3. Paginação

Padrão:

```text
query
  .orderBy(campoEstável)
  .orderBy(documentId)
  .limit(50)
  .startAfterDocument(cursor)
```

- cursor faz parte do state do controller;
- busca server-side usa campo normalizado/prefix ou serviço específico; não
  baixar tudo para `contains`;
- paginação e stream ao vivo não devem ser misturadas sem política clara;
- tela preserva itens já carregados durante próxima página;
- filtros que mudam reiniciam cursor e cancelam request anterior.

Primeiros alvos: alunos, presenças por aluno, pedidos, financeiros, feed,
resultados de competição e histórico.

## 4. Agregações e projeções

### Relatórios

Criar projeções mensais por academia:

```text
academies/{academyId}/reportSnapshots/{YYYY-MM}
  attendance
  students
  store
  financial
  computedAt
  sourceWatermark
  projectionVersion
```

Dashboard lê um doc pequeno. Drill-down continua query paginada. Export completo
vira job e arquivo temporário.

### Contadores

Preferir `count()`/aggregation query quando não for necessário materializar cada
doc. Contador persistido só quando leituras repetidas justificarem complexidade;
deve ter reconciler.

### Cross-academy

Materializar resumo por uid, sem expor PII de tenants:

```text
users/{uid}/academyHistory/{academyId}
  academyName
  verifiedGrades
  attendanceSummary
  joinedAt/leftAt
  projectionVersion
```

O backend resolve as três eras de vínculo. Cliente não percorre paths de
academias arbitrárias.

### Social/feed

`feed_materializer.js` e triggers existentes são o ponto de convergência. Remover
gradualmente emissão/materialização por leitura no provider. Feed usa fan-out ou
fan-in limitado com cursor e audience precomputada, nunca joins ilimitados.

## 5. Query budget por jornada

Definir e medir limites iniciais:

| Jornada | Budget inicial |
|---|---:|
| Abrir lista de alunos | até 2 queries + 50 docs |
| Abrir detalhe do aluno | até 6 queries paginadas/independentes |
| Abrir diário/hub | até 5 queries; sections lazy |
| Abrir relatório mensal | 1 snapshot + drill-down sob demanda |
| Abrir feed | 1 página de 20–30 posts + likes agregados |
| Trocar academia | limpar caches tenant-bound e carregar só shell essencial |

Budgets devem ser validados com Emulator/telemetria, não tratados como dogma.

## 6. Riverpod e cache

- chave de provider sempre inclui `academyId` quando tenant-bound;
- invalidar cache ao trocar academia;
- `autoDispose` para detalhe/sheets; keep-alive só com justificativa;
- usar `select` para partes pequenas do state;
- não refazer query por rebuild;
- deduplicar requests concorrentes no repository/controller;
- stale-while-refresh para listas melhora UX sem esconder falha;
- evitar provider que escreve Firestore ao ser observado.

## 7. Índices

Antes de criar índice, registrar a query real e o owner. Manter
`firestore.indexes.json` junto do repository/guia. Remover índice apenas após
telemetria/call-site audit; índice também custa storage e write amplification.

Consultas prioritárias:

- attendance por student/date e class/date;
- students por status/normalizedName e filtros comuns;
- orders por status/createdAt e student/createdAt;
- competition enrollment por competition/student;
- jobs por status/createdAt;
- audit events por target/occurredAt;
- report snapshots por month/version.

## 8. Jobs e limites

Usar job/queue quando:

- mais de ~100 itens ou duração imprevisível;
- export/arquivo;
- API externa com rate limit;
- retry item a item;
- progresso precisa sobreviver ao fechamento da tela;
- operação pode ultrapassar limite de batch/function.

Job possui status, total, processed, failed, cursor, lease, requestedBy e itens
idempotentes. UI observa; não mantém loop principal.

## 9. Imagens e payloads

- gerar thumbnails no backend/storage trigger;
- lista nunca baixa imagem original;
- limitar tamanho/tipo/dimensões em Storage Rules e pós-processamento;
- modelos de lista não carregam blobs/arrays grandes de detalhe;
- feed/showcase usa projeções compactas e versionadas.

## 10. Métricas

Acompanhar por release:

- reads por sessão/jornada;
- p50/p95 de primeira renderização e command;
- docs retornados por query;
- Functions cold start/error/retry;
- tamanho de snapshots principais;
- rebuilds de widgets críticos em profile mode;
- jobs partial/failed e tempo até conclusão;
- custo Firestore/Functions por academia ativa.
