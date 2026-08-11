# 00 — Diagnóstico e prioridades

## 1. Como a auditoria foi feita

Foram cruzados:

- contagem de linhas de `lib/`, `functions/`, telas, serviços e providers;
- classes, widgets, dialogs e responsabilidades nos maiores arquivos;
- imports e gravações diretas de Firestore nas telas;
- transações, batches, chamadas HTTP e callables nos services;
- exports e composition roots de `functions/index.js` e
  `functions/server_functions.js`;
- ownership efetivo em `firestore.rules`;
- testes existentes, `functions/package.json`, analyzer e GitHub Actions;
- os padrões e decisões já documentados em
  `docs/arquitetura-pagamentos/` e `CLAUDE.md`.

Contagem de linhas é um alarme, não prova de design ruim. A prioridade abaixo
considera também dinheiro, segredo, tenant, concorrência, atomicidade, custo de
consulta e frequência de mudança.

## 2. Foto objetiva do repositório

| Indicador | Estado auditado |
|---|---:|
| Arquivos Dart | 317 |
| Dart acima de 600 linhas | 76 |
| Dart acima de 1.000 linhas | 44 |
| Dart acima de 1.500 linhas | 23 |
| Screens | 99 |
| Screens acima de 600 linhas | 58 |
| Screens acima de 1.500 linhas | 20 |
| Services acima de 350 linhas | 23 |
| Services acima de 700 linhas | 6 |
| Screens que importam `cloud_firestore` diretamente | 13 |
| Testes Flutter | 39 arquivos |
| Testes Node | 4 arquivos |
| Testes de Firestore Rules | 0 |
| Workflows de CI | 1, voltado a build Windows |
| Resultado de `flutter analyze` | 265 issues; CI atual não bloqueia |

Maiores arquivos confirmados:

| Arquivo | Linhas aproximadas | Responsabilidades observadas |
|---|---:|---|
| `functions/server_functions.js` | 7.558 | notificações, billing, perfis, mensalidades, gamificação, gateways, MP, assinaturas, booking |
| `lib/screens/admin/student_detail_screen.dart` | 6.274 | 7 abas, dialogs, permissões, presença, financeiro, graduação, avaliação e exclusão |
| `lib/screens/fighter/diario_screen.dart` | 4.307 | feed, vitrine, editor de treino, recompensa, graduação e competição autodeclaradas |
| `lib/screens/admin/settings_screen.dart` | 3.541 | configurações gerais, branding, pagamentos, KYC, features e uploads |
| `lib/screens/admin/financial_screen.dart` | 3.452 | coberto pelo plano de pagamentos |
| `lib/screens/admin/billing_reminders_screen.dart` | 3.156 | coberto pelo plano de pagamentos |
| `lib/screens/admin/classes_screen.dart` | 2.608 | lista, filtros, form, detalhe e gestão de alunos |
| `lib/screens/portal/profile_screen.dart` | 2.450 | perfil, privacidade, 3 editores, academias, conta e senha |
| `lib/screens/portal/timeline_screen.dart` | 2.433 | jornada, timeline, rivais, autodeclarações e editor de lutas |
| `functions/index.js` | 2.482 | auth, membership, academia, check-in, paywall, webhooks, trial e exports |
| `lib/screens/admin/reports_screen.dart` | 2.410 | consultas, agregações, export e quatro relatórios |
| `lib/providers/friend_providers.dart` | 915 | espelho social, vitrine, audiência, feed, colegas e ranking |

As contagens variam com comentários e quebras de linha. Elas identificam ordem
de grandeza; a matriz de responsabilidades é o dado arquitetural importante.

## 3. Padrões bons que devem ser preservados

- `functions/access_control/` já separa canonical, gate, resolver e adapters.
- `retention_functions.js` materializa risco e snapshots server-side; a UI nova
  lê projeções em vez de varrer presença e financeiro.
- reserva de aula já converge em callables server-side com regras de ocorrência.
- o fluxo novo de `joinAcademy` resolve e vincula conta/ficha no backend.
- `publicProfiles` e `retentionSnapshots` já são server-write-only nas Rules.
- presença unitária usa doc-id determinístico e transação em parte dos fluxos.
- catraca usa validação de path, HMAC, anti-replay e idempotência no ingest.
- pagamento/assinatura possuem settle e webhooks autoritativos; devem servir de
  modelo, não ser reimplementados em outros domínios.

## 4. Achados prioritários

### P0.1 — ciclo de segredo da catraca está no Flutter

`lib/screens/admin/devices_screen.dart:297-400` lê o segredo existente, gera
novo segredo com `Random.secure`, monta URL com `?k=<segredo>` e grava o valor em
`devices`. As Rules em `firestore.rules:1073-1077` deixam o doc completo legível
e gravável por admin. O RNG não é o problema; o problema é um app distribuído
ser o gerenciador e leitor permanente de um segredo de infraestrutura.

Destino: callables `createDevice`, `rotateDeviceSecret`, `updateDeviceConfig` e
`disableDevice`. O backend gera o segredo, armazena hash/versão, devolve o valor
uma única vez e registra rotação. A UI nunca relê segredo antigo.

### P0.2 — pedido, estoque e status comercial são coordenados pelo cliente

`StoreService.createOrder` busca produto e preço no cliente antes de criar o
pedido (`store_service.dart:644-744`). `updateOrderStatus` e
`markOrderAsPaid` validam e decrementam estoque em loops de writes separados,
depois limpam Pix e mudam status (`817-945`). Duas compras simultâneas podem
passar pela mesma leitura; falha entre decrementos deixa estoque/pedido parcial.

Destino: domínio `commerce/orders` no backend. Preço, política, estoque,
transições, pagamento manual e cancelamento devem usar transação/idempotência.

### P0.3 — lifecycle de conta/academia ainda tem caminhos multi-write no cliente

O join moderno já usa Function, mas `AuthService.unlinkFromAcademy` ainda altera
student, academy user e mapping em passos separados
(`auth_provider.dart:404-439`). Criação de academia executa Auth + global user +
academy + academy user + mapping em vários passos (`466-604`).
`GlobalUserService` mantém métodos diretos de link/unlink/upsert e sincronização
cross-tenant (`global_user_service.dart:193-456`).

Destino: após criar o Firebase Auth user, uma callable idempotente finaliza a
academia; leave/unlink/primary academy também passam por commands server-side.
Push subscribe/unsubscribe continua como efeito cliente best-effort.

### P0.4 — contratos HTTP apontam para backend ausente neste repositório

`TotpService` declara usar rotas Next.js em `/api/auth/totp/*` e
`settings_screen.dart:649-685` consulta `/api/payments/onboard/documents`.
As buscas no repositório encontraram consumidores, mas nenhuma implementação
dessas rotas em `site/` ou `functions/`. Adapters Asaas e AbacatePay também
apontam para `/api` legado.

Destino: inventariar uso/flags reais. Funcionalidade viva ganha callable/HTTP
Function com teste; funcionalidade morta é escondida e removida após janela.
Não deixar botão de segurança ou KYC depender de endpoint presumido.

### P1.1 — presença é autoritativa no cliente em vários caminhos

`AttendanceService` tem 1.069 linhas e combina queries, estatísticas, streak,
criação, remoção, bulk, contador desnormalizado e milestone. Escrita unitária é
transacional, mas bulk usa auto-id após uma consulta prévia
(`attendance_service.dart:768-857`), o que não impede duas operações bulk
concorrentes. `unmarkPresent` apaga e decrementa em operações separadas
(`734-752`). Relógio e identidade do ator vêm do cliente.

Destino: commands de presença no backend, preservando doc-id determinístico,
timezone BR, origem, contador e idempotência. Consultas simples continuam no
Flutter repository.

### P1.2 — promoção mistura decisão e três documentos no cliente

`BeltProgressionService` calcula elegibilidade e grava progressão, student e
achievement. O caminho com chave é transacional, mas o caminho manual legado
usa três writes separados (`belt_progression_service.dart:1028-1035`). Rules
autorizam o papel, mas não conseguem provar a transição de faixa nem a coerência
entre os três documentos.

Destino: `promoteStudent`, `correctGraduation` e `undoGraduation` server-side;
domínio puro testado por modalidade/categoria. Flutter pode calcular preview,
mas o backend relê o estado e decide.

### P1.3 — exclusão permanente de aluno é uma cascata client-side

`StudentService.hardDelete` percorre coleções, preserva alguns financeiros,
remove rosters e por fim apaga o aluno (`student_service.dart:470-543`). Falha
no meio produz meia exclusão, não alcança todos os dados futuros e depende de
Rules/versão do app para decidir retenção legal.

Destino: job server-side idempotente com dry-run, política explícita de retenção,
status/progresso e log de cada coleção.

### P1.4 — matrícula em turma atualiza turma e ficha em passos independentes

`ClassService.addStudent/addStudents` atualiza `class.studentIds` e depois
semeia `student.sports/sportData` (`class_service.dart:406-495`). Uma falha deixa
roster e modalidades divergentes; bulk dispara N writes em paralelo.

Destino: command backend com chunks/transação e política canônica de seed de
modalidade. CRUD simples da turma pode continuar staff-direct enquanto Rules
forem suficientes.

### P1.5 — códigos legados ainda ficam enumeráveis e consumíveis no cliente

Rules permitem leitura de códigos não usados e mantêm update client-side por
compatibilidade (`firestore.rules:808-863`). O caminho novo já usa Functions,
mas `LinkCodeService.markAsUsed` ainda grava código e ficha em passos separados
(`link_code_service.dart:278-297`).

Destino: telemetrar versão antiga, impor versão mínima e fechar consumo para
server-only. Preferir lookup por hash, TTL e limite de tentativas.

### P1.6 — importação e criação em massa não têm contrato de job

`StudentImportService` valida e cria alunos no cliente em sequência. Em arquivo
grande, queda de rede gera lote parcial sem checkpoint/retry consistente.

Destino: upload/parse pode ficar local para preview; confirmação envia lote
normalizado para `studentImportJobs`, processado em chunks idempotentes.

### P2.1 — relatórios e visão cross-academy fazem fan-out no cliente

`reports_screen.dart` contém queries e agregações de presença, financeiro, loja
e alunos. `CrossAcademyService` percorre academias e fichas. Providers sociais
constroem audiência/ranking combinando várias fontes. Isso aumenta reads,
latência, rebuilds e divergência entre versões.

Destino: consultas paginadas e projeções materializadas para dashboard,
relatórios, histórico global e feed; export pesado vira job.

### P2.2 — telas e providers são também application services

Dos 58 screens acima de 600 linhas, 39 contêm sinais de write. Treze importam
Firestore diretamente. `student_detail_screen.dart` sozinho possui 13 dialogs,
sete áreas de domínio e operações sensíveis. `friend_providers.dart` reúne
providers, composição de dados e regras sociais em um único arquivo.

Destino: feature-first incremental, controllers/use cases, repositories e
sections de apresentação, conforme o guia de decomposição.

### P2.3 — router e modelos concentram mudanças não relacionadas

`lib/app.dart` declara redirect global e dezenas de rotas portal/admin no mesmo
arquivo. `models/student.dart` mistura enums, endereço, responsável, emergência,
histórico, retenção, goal, parse Firestore e entidade principal. Mudanças simples
geram diffs amplos e conflitos.

Destino: route modules e modelos/domínio + mappers Firestore separados.

## 5. O que não precisa ir para o backend

- edição de formulário e validação de formato para feedback imediato;
- preferências pessoais que alteram apenas o próprio doc sob whitelist;
- `selfGraduations` e `selfCompetitions` como declarações pessoais, mantendo o
  guard server-side do teto verificado;
- filtro/ordenação visual de dados já autorizados e paginados;
- timer de treino, animações, copy, navegação e estado efêmero;
- upload direto para Storage quando Rules validarem owner/path/tamanho/tipo e o
  backend materializar projeções necessárias.

## 6. Ordem de prioridade

| Onda | Resultado |
|---|---|
| Q0 | CI, testes de Rules, inventário de exports e ownership de campos |
| Q1 | segredo de catraca, loja, identidade e endpoints órfãos |
| Q2 | presença, graduação, turma, hard delete, link codes e import jobs |
| Q3 | decompor student detail, diário, settings, classes e app router |
| Q4 | relatórios/projeções, social, cross-academy e telas portal |
| Q5 | fechar Rules, remover shims/legado e impor budgets automaticamente |

Achados de segurança e dinheiro devem ser validados adversarialmente antes da
implementação. Este documento identifica risco estrutural; ele não autoriza
alterar comportamento de produção sem testes e rollout.
