# 07 — Roadmap de qualidade geral

Este documento amplia as práticas aprendidas em pagamentos para o restante do
repositório. Não autoriza reescrita global; define uma fila incremental.

## 1. Regras arquiteturais novas

### 1.1. Backend para invariantes, cliente para experiência

Levar para Cloud Functions quando a operação:

- movimenta ou reconhece dinheiro;
- atravessa dois ou mais documentos/serviços;
- depende de permissão/tenant;
- precisa ser atômica/idempotente;
- usa secret;
- será executada por app, cron e integração;
- precisa produzir o mesmo resultado em versões diferentes do cliente.

Manter no Flutter quando é:

- layout e navegação;
- estado efêmero de formulário;
- validação de formato para feedback imediato;
- filtro/ordenação puramente visual de conjunto já autorizado;
- animação, acessibilidade e copy.

### 1.2. Limites orientativos

- screen/shell: até 400 linhas;
- widget coeso: até 250;
- service/repository/controller: até 350;
- backend domain/adapter: até 500;
- acima de 700: justificar ou abrir item de split.

Linha não é métrica absoluta, mas funciona como alarme antes de voltar a 3–7
mil linhas.

### 1.3. Composition roots

- `functions/index.js`: inicialização e exports.
- `lib/app.dart`: bootstrap do app, tema e router composto.
- Screens: composição de sections/controllers, sem repositories concretos.
- Barrel files: somente exports intencionais, nunca lógica.

## 2. Fila de decomposição

### Q0 — habilitadores

- [ ] CI obrigatório para Node/Flutter/Rules.
- [ ] baseline de analyzer sem erros.
- [ ] convenções atualizadas no `CLAUDE.md`.
- [ ] log/erro/clock/money compartilhados.
- [ ] política de ownership de campos Firestore.
- [ ] checklist de deploy que detecta Function deletada.

### Q1 — receita e segurança

- [ ] executar esta arquitetura de pagamentos;
- [ ] remover secrets do cliente;
- [ ] mover mutações financeiras;
- [ ] decompor `server_functions.js` e payment sheets;
- [ ] apertar Rules depois da versão mínima.

### Q2 — telas que bloqueiam evolução

#### `student_detail_screen.dart`

O state atual coordena sete abas e dezenas de dialogs. Extrair primeiro tab
financeiro (porque passará a usar controllers novos), depois avaliação, presença,
conquistas, comportamento, histórico e info. O shell mantém somente student
header, tabs e refresh orchestration.

#### `diario_screen.dart`

Separar domínio de registro, controller e quatro fases visuais. Vitrine e
histórico não devem compartilhar state mutável do formulário count/reward.

#### `settings_screen.dart`

Cada tab vira feature section. Saves passam de snapshot monolítico para comandos
por domínio, evitando que versão antiga sobrescreva flag nova.

#### `classes_screen.dart`

Extrair form create/edit, detail e gestão de alunos; centralizar ocorrência e
validação de horário em domínio já existente.

### Q3 — router e áreas grandes

- [ ] `lib/app.dart` usa `authRoutes`, `portalRoutes`, `adminRoutes`, `kioskRoutes`.
- [ ] route guards testados independentemente.
- [ ] reports recebe query/controller e seções.
- [ ] profile/timeline recebem sections e edit sheets separados.
- [ ] convenção única para widgets por feature substitui cópias privadas.

### Q4 — legado e limpeza

- [ ] auditar uso real antes de apagar Asaas/AbacatePay.
- [ ] remover providers/rotas sem import/call site confirmado.
- [ ] mover docs históricos para o índice correto, sem apagar história.
- [ ] eliminar reexports temporários.
- [ ] proibir novos imports de `legacy/` via lint/code review.

## 3. Reuso

### Extrair cedo

- dinheiro e percentuais;
- datas/timezone;
- IDs/path safety;
- papel/permissão;
- async result/error codes;
- form primitives comprovadamente comuns;
- tenant-aware repository base;
- status chips e actions de confirmação.

### Não compartilhar cegamente

- telas inteiras de admin e portal;
- widget com aparência parecida mas sem contrato igual;
- regra de domínio traduzida entre Dart e JS por copy/paste;
- DTO comum vivendo dentro do adapter de um provedor;
- service locator global escondendo `academyId`.

## 4. Migração de lógica do frontend

Inventário por categoria:

| Categoria | Exemplo atual | Destino |
|---|---|---|
| transição monetária | `PaymentService.markAsPaid` | callable transacional |
| operação multi-sistema | update financial + cancelar Pix | application service backend |
| secret/API interna | notification proxy | backend adapter |
| job longo | bulk WhatsApp | queue/worker backend |
| autorização | `academyId` + papel | backend shared auth |
| cálculo canônico | estágio/overdue | domínio backend/projeção persistida |
| apresentação | moeda, chips, tabs | Flutter |
| formulário | campos de cartão antes de tokenizar | Flutter/MP SDK |

Ao migrar:

1. criar contrato e teste;
2. implementar backend;
3. adaptar cliente;
4. telemetrar uso antigo;
5. impor versão mínima;
6. fechar Rules;
7. remover código legado.

## 5. Estratégia de testes por camada

- Domínio puro: unitário rápido, sem Firebase.
- Application service: fake repositories/adapters.
- Repository/Rules: Emulator Suite.
- Integração externa: contract fake + sandbox real controlado.
- Flutter controller: unitário.
- Widget: jornadas críticas, não snapshot de cada pixel.
- E2E: poucos fluxos de receita/conta/check-in.

Source-grep test é canário temporário, não substituto de comportamento.

## 6. Critério para começar um split

Antes:

- listar responsabilidades e call sites;
- identificar state compartilhado;
- criar testes de caracterização;
- definir arquivos destino;
- garantir que não há edição concorrente na mesma área;
- mover uma unidade coesa, sem nova feature.

Depois:

- analyzer/testes;
- `rg` por import/call site antigo;
- comparação de rota/copy/permissões;
- diff revisável;
- atualizar docs/índice.

## 7. Métricas de saúde do código

Acompanhar por release:

- arquivos >700 e >1500 linhas;
- screens com Firestore write direto;
- ocorrências de secrets/dart-defines sensíveis;
- APIs externas chamadas do Flutter;
- duplicações de enum/template de domínio;
- cobertura dos módulos financeiros;
- tempo e estabilidade do CI;
- exports Firebase inesperadamente deletados;
- warnings novos por módulo.

Meta não é “100% coverage” nem “nenhum arquivo grande”. É tornar regressão de
dinheiro, segurança e tenant difícil de introduzir e fácil de detectar.

