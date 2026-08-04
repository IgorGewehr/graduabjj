# RELATÓRIO ANTI-HIDRA — GraduaBJJ (branch `ux-ativacao`)

## 1. Veredito

**O código aguenta mais uma leva de features, mas não aguenta o pivô generalista em volume sem virar hidra — e o motivo não é estético, é estrutural e já está causando bug real em produção.**

O repo tem duas caras. `functions/access_control/` prova que o time sabe modularizar bem quando trata um domínio como próprio desde o início (arquivos <700 linhas, responsabilidade única, README). O problema não é falta de habilidade — é que os dois pontos que o pivô fight/fitness/hybrid vai golpear com mais força nunca receberam esse tratamento:

1. **O eixo "esporte/vocabulário" está hardcoded em BJJ em pontos críticos de escrita.** Isso não é risco teórico: toda academia não-BJJ/não-fitness criada a partir de hoje grava `sports:['bjj']` tanto no client (`create_academy_screen.dart`) quanto no servidor (`functions/index.js:664-711`, comentário próprio confirma o hardcode). É um bug ativo bloqueando o pivô, não uma preocupação de manutenção futura.
2. **Os god-files que crescem a cada sessão (`student_detail_screen.dart` 6274L, `server_functions.js` 7533L, `diario_screen.dart` 4307L — os dois últimos ganharam linhas nesta própria sessão) são exatamente os arquivos que absorverão os novos campos/esportes do perfil generalista.** Sem decomposição, cada PR de expansão vira merge-conflict magnet, e a mistura do gateway MP vivo com o AbacatePay morto linha a linha em `server_functions.js` já é perigosa por si só (um dev "mexendo em pagamento" precisa discernir manualmente qual dos dois é real).
3. **Não há rede de segurança para refatorar com confiança.** Zero testes automatizados rodam em CI (analyzer é `continue-on-error`, `functions/` não tem script `test`), e as 3 funções puras mais críticas do produto (paywall, streak, janela de check-in) não têm nenhum teste — inclusive uma delas já derrubou a tela inteira em produção uma vez, documentado no próprio código.

Combinação: quando alguém decidir finalmente separar `student_detail_screen.dart` em abas, vai fazer isso sem teste que confirme que não quebrou nada. Isso é o que transforma "código grande mas funcional" em hidra de verdade — não o tamanho do arquivo isoladamente, mas tamanho + zero verificação automatizada + convenções não documentadas (não há `CLAUDE.md` na raiz; a prova é que esta própria sessão inventou uma 4ª grafia de dia-da-semana e um 3º local para widget de esporte quando já existiam 2-3 alternativas).

Não é "reescrever tudo". É: parar o sangramento do hardcode de esporte agora, adicionar rede de teste nos 3 pontos pure-function, documentar convenção, e só então atacar os god-files com uma sequência de splits mecânicos (a maioria já tem os nomes de método prontos para virar arquivo).

---

## 2. Achados que importam (ranqueados por risco de manutenção)

**1. `sports:['bjj']` hardcoded em criação de academia e aprovação de vínculo — bug ativo, bloqueia o pivô**
`lib/screens/auth/create_academy_screen.dart` não tem seletor de `SportId`; `auth_provider.dart:525` só grava `academy.sports` quando profile é `fitness`; `functions/index.js:699-711` (`decideJoinRequest`) grava `sports:['bjj'], primarySport:'bjj'` pra qualquer perfil não-fitness. `Academy.effectiveSports` (`academy.dart:419`) foi criado pra resolver isso mas tem zero call sites — é código morto que deveria ser o fix. **Ação:** adicionar seletor de modalidade no wizard + usar `effectiveSports` nos dois pontos de escrita (client e `decideJoinRequest`). Sem isso, toda academia de Judô/Muay Thai/Karatê criada agora nasce com ficha errada, silenciosamente.

**2. `GRADELESS_SPORTS` sincronizado manualmente em 3 lugares (não 2)**
`lib/core/sports.dart` → `functions/self_graduation_guard.js:95` → `functions/index.js:1465` (`SELF_CHECKIN_SPORTS`, adicionado nesta sessão). O próprio código já documenta o risco com TODO explícito, mas cada esporte novo sem faixa (crossfit, funcional — já citado como TODO) precisa ser lembrado em 3 arquivos, sem teste que garanta consistência. **Ação:** exportar a constante de um único módulo consumido pelos outros dois — é um refactor pequeno e mecânico, faça no P0.

**3. `server_functions.js` (7533L) mistura MP vivo com AbacatePay morto, linha a linha**
`createPixPayment/createOrderPixPayment/createCardPayment` (AbacatePay, desligado em prod) intercalados com `createMpPixPayment...cancelMpPix` (MP, vivo, ~1600 linhas). Também concentra triggers, jobs agendados e reservas de aula sem separação de módulo. **Risco concreto:** um dev editando "pagamento" pode alterar o gateway errado sem perceber que está morto. **Ação:** extrair por domínio (padrão `access_control/`); isolar/marcar claramente o AbacatePay como legado desligado antes de tocar em qualquer coisa de billing do pivô.

**4. `index.js` tem dois webhooks MP com nomes quase idênticos e propósitos opostos**
`mercadoPagoWebhook` (index.js:2080, assinatura SaaS/Cakto da própria plataforma) vs `mercadoPagoMarketplaceWebhook` (server_functions.js:5702, MP das academias cobrando aluno). Nome quase igual, sistemas totalmente diferentes — armadilha clássica de "mexi no webhook errado". **Ação:** renomear para deixar a distinção óbvia no nome (ex.: `platformSubscriptionWebhook` vs `academyMarketplaceWebhook`) e separar em arquivos distintos.

**5. `student_detail_screen.dart` (6274L) e `diario_screen.dart` (4307L) — as duas telas que o pivô mais vai tocar já são god-classes e cresceram nesta sessão**
`_AdminStudentDetailScreenState` tem ~5270 linhas com 6 abas completas como métodos privados (nomes já prontos: `_buildInfoTab`, `_buildAttendanceTab`, `_buildFinancialTab`, `_buildAchievementsTab`, `_buildPhysicalAssessmentTab`, `_buildBehaviorTab`, `_buildHistoryTab`). `_DiarioScreenState` ganhou +352 linhas nesta sessão só para o check-in generalista e mistura 4 "páginas" com ~15 widgets-átomo genéricos presos como método privado. **Ação:** split por aba/seção — a costura já existe nos nomes dos métodos, é trabalho mecânico, não invenção de arquitetura.

**6. `cross_academy_service.dart` só resolve 1 das 3 eras de vínculo conta↔ficha — perda silenciosa de histórico**
A mesma checagem (`academyDetail == null || academyDetail.studentId == null → continue`) se repete 3x no arquivo e cobre só a era "mapping". As eras b (`academies/{aid}/users/{uid}.studentId` legado) e c (`students.where('linkedUserId','==',uid)`), já corretamente tratadas em `functions/fighter_baggage.js:44-73`, não têm equivalente aqui. Um lutador com conta antiga (a própria memória do projeto cita a base T23 como exemplo real) simplesmente não aparece no histórico cross-academy, sem log nem exceção — parece só "não tem histórico". **Ação:** portar o fallback de 3 eras de `fighter_baggage.js` para cá.

**7. Zero execução automatizada de teste — o multiplicador de risco de tudo acima**
`functions/package.json` não tem script `test`; o único workflow de CI builda só o `.exe` Windows e o step de analyzer Flutter é `continue-on-error: true`. Os 4 arquivos de teste em `functions/test/` (qualidade alta — pinam bugs reais já corrigidos: double-charge PIX, race de gamificação) só rodam se alguém digitar o comando manualmente. Os 36 arquivos em `test/` do Flutter nunca rodam via automação. **Ação:** ligar `node --test functions/test/` e `flutter test` no CI, tirar o `continue-on-error` do analyzer assim que o baseline estabilizar. Sem isso, qualquer split dos god-files acima é feito no escuro.

**8. Paywall (`AcademySubscription.hasAccess`) sem nenhum teste**
`lib/models/academy.dart:165-171` — getter puro que decide se a academia inteira é bloqueada, ordem de prioridade (`freeOverride > premium/enterprise > paidUntil > trial`) nunca exercitada por teste. Um refactor que inverta um `if` ou troque `isAfter` por `isBefore` passa no analyzer e trava academia pagante (ou libera inadimplente) sem sinal nenhum. **Ação:** ver seção 5.

**9. `AcademyVocab` existe e foi bem desenhado, mas as 2 telas de maior superfície social nunca foram migradas**
`greetingInterjection` foi desenhado explicitamente para ocultar vocabulário de luta em academias fitness ("`null` quando o perfil não tem essa cultura"), mas tem zero consumidores. `cena_screen.dart` hardcoda "lutador"/"oss"; `dashboard_radar_sections.dart` hardcoda "tatame" — inclusive na mensagem de WhatsApp real disparada a aluno inativo ("Sentimos sua falta no tatame"). Um admin de academia de musculação pura vai mandar essa mensagem. **Risco:** é o tipo de bug que só aparece quando o primeiro cliente fitness puro reclamar, e por essa altura já estará em mais telas.

**10. Widgets duplicados em 12+ telas sem existir 1x em `lib/widgets/`**
`_ModernTextField` (4+ arquivos, já divergindo em parâmetros), `_StatCard/_InfoChip/_FilterChip` (12+ telas), `_sectionHeader` (3 implementações diferentes). Não é auto-fixável (não são idênticas), mas é literalmente o mecanismo do apelido "hidra": cada tela nova do pivô tende a copiar em vez de importar, e cada cópia já nasce divergente.

**11. `NumberFormat.currency('pt_BR','R$')` reconstruído em ~12 arquivos**
Nenhum importa um formatter compartilhado apesar de `lib/core/formatters.dart` já existir e já ter `formatPhone`. Mudança de formatação de moeda (ex.: suporte a outra moeda no futuro) exige tocar 12 arquivos.

**12. Sem `CLAUDE.md` na raiz do repo — a causa-raiz do padrão de drift observado**
Convenções reais (divisão `lib/screens/{admin,portal,fighter,auth,kiosk}`, qual barrel está vivo, qual pasta de widgets usar por persona, branch `firebase-production` vs `migration`) vivem só na cabeça do dono. Prova concreta de que isso já causa dano: **esta própria sessão** criou `fighter_share_card.dart` solto na raiz de `widgets/` (3ª convenção concorrente) e uma 4ª grafia de array de dias da semana quando já existiam 3.

---

## 3. Roadmap de refatoração em fases

### Fase 0 — antes de qualquer coisa (dias, baixo esforço, alto retorno)
| Item | Esforço | Trade-off |
|---|---|---|
| Matar o hardcode `sports:['bjj']` (seletor no wizard + `decideJoinRequest` usando `effectiveSports`) | M | Bloqueante — sem isso o pivô cria dado errado a cada academia nova |
| Consolidar `GRADELESS_SPORTS` numa única fonte | S | Puramente mecânico |
| Testar `hasAccess`, `computeWeeklyStreak`, `isInCheckinWindow` (funções puras, sem I/O) | S | Compra a rede de segurança pra tudo que vem depois |
| Ligar `node --test` e `flutter test` no CI (não-bloqueante no início) | S | Visibilidade imediata, zero risco de quebrar deploy |
| Escrever `CLAUDE.md` na raiz com as convenções atuais | S | Maior ROI por hora do lote inteiro — impede a próxima sessão de inventar uma 5ª convenção |

### Fase 1 — antes de escalar mais (2-4 semanas, esforço médio, mecânico na maior parte)
| Item | Esforço | Trade-off |
|---|---|---|
| Separar `server_functions.js` por domínio (MP vivo, gamificação, jobs agendados, reservas); isolar/marcar AbacatePay como legado | L | Mecânico (mover+require), mas grande — priorizar antes de mexer em billing do pivô |
| Renomear/separar os 2 webhooks MP de `index.js` | M | Remove a armadilha "editei o webhook errado" |
| Split de `student_detail_screen.dart` em 6 arquivos por aba | L | Nomes de método já existem, é costura, não invenção |
| Consolidar widgets duplicados (`_ModernTextField`, `_StatCard`, `_sectionHeader`, formatter de moeda) em `lib/widgets/`+`lib/core/formatters.dart` | M | Trava a divergência antes que mais telas do pivô copiem |
| Migrar `cena_screen.dart` e `dashboard_radar_sections.dart` para `AcademyVocab` | S-M | Impede vazamento de vocabulário BJJ pra academias fitness |
| Fallback de 3 eras em `cross_academy_service.dart` (portar de `fighter_baggage.js`) | M | Corrige perda de histórico já acontecendo com contas legado em prod |
| `settings_screen.dart`: mecanismo genérico dirigido por `sports.dart` em vez de 1 classe por esporte | L | Só pode esperar Fase 2 **se** nenhum esporte novo entrar antes; senão puxar pra cá |

### Fase 2 — pode esperar / fazer oportunisticamente ao tocar no arquivo
- Split de `diario_screen.dart` (Vitrine/Historico/Count/Reward) e dos dialogs de `billing_reminders_screen.dart`/`financial_screen.dart`.
- Decisão de produto (não é limpeza cega) sobre os 6 providers órfãos de billing (`billing_provider.dart`, `financial_report_provider.dart`) — parecem feature "aha de cobrança" incompleta, não lixo.
- Resolver rotas órfãs: deletar `/admin/ranking`, `/admin/importar-alunos`, `/portal/home`; **investigar** `/portal/chamada` (`MonitorAttendanceScreen`) antes de deletar — pode ser bug funcional real (monitor sem caminho de UI pra bater chamada).
- Unificar convenção de pasta de widget-por-persona (portal usa `widgets/portal/`, admin usa `screens/admin/widgets/`, fighter não tem nenhuma).
- Remover os 2 docs órfãos na raiz (`GALERIA_INTEGRACAO.md`, `MIGRATION_COMPARISON.md`) ou movê-los pra `docs/`.

---

## 4. O que já está bem feito — preservar como padrão

- **`functions/access_control/`** é a referência positiva do repo: `canonical.js`, `class_resolver.js`, `financial_gate.js`, `ingest.js`, `overdue_util.js` + `adapters/` + README, nenhum arquivo passa de 700 linhas, responsabilidade única. É o template a copiar para o split de `server_functions.js`/`index.js` — não precisa inventar arquitetura nova, só aplicar a que já existe.
- **`_selfCheckinCore` extraída deliberadamente sem I/O** (`functions/index.js:1494-1517`) para ser testável sem mockar Firestore — o instinto está certo, só falta escrever o teste que o próprio comentário promete.
- **Comentários que documentam o "porquê" e incidentes reais**: o TODO em `index.js:1454-1464` sobre `GRADELESS_SPORTS`; o header de `weekly_streak.dart:23` afirmando "não toca em I/O" como decisão de design; o comentário em `schedule_screen.dart:29-30` documentando o crash real de tela branca por `int.parse` malformado. Isso é exatamente o tipo de contexto que evita repetir erros — manter esse hábito.
- **Padrão modular já aplicado a código novo**: `index.js:2425-2460` (require+export de `ingestAccessEvent`, `onAttendanceWrite`, `streakRiskCheck`) mostra que quando o time trata um domínio como próprio desde o início, o resultado é limpo. O problema nunca foi capacidade — foi não retroaplicar aos arquivos legados.
- **Catálogos de fonte única já existentes e corretos onde adotados**: `DayOfWeekLabels` (`lib/core/constants.dart`), `sports.dart`, `AcademyVocab` — a arquitetura-alvo já existe no repo, falta só adoção consistente.

---

## 5. Os 5 testes de maior valor

1. **`AcademySubscription.hasAccess`** (`lib/models/academy.dart:165-171`) — getter puro, decide se a academia inteira é bloqueada. Testar todos os ramos e a ordem de prioridade (`freeOverride > premium/enterprise > paidUntil > trial`). Protege receita diretamente.
2. **`computeWeeklyStreak`** (`lib/services/weekly_streak.dart:123-194`) — função pura, já documentada como "pensada pra ser testável". Cobrir virada de ano na semana ISO, semana congelada/bridge, janela de graça. Protege a feature de retenção mais visível ao usuário.
3. **`isInCheckinWindow` / `getTimeUntilCheckinOpens`** (`lib/services/checkin_service.dart:18-78`) — já derrubou a tela inteira em produção uma vez (documentado no código). Cobrir string malformada/vazia, janela cruzando meia-noite, `endTime < startTime`.
4. **`_selfCheckinCore`** (`functions/index.js:1501-1517`) — smoke test já prometido no comentário. Cobrir a bifurcação de `docId` (formato legado musculação vs formato genérico por esporte) pra proteger a idempotência do dedup diário durante a expansão pra mais esportes sem faixa.
5. **`isoWeekKey`** — implementada 3x de forma independente (`retention_functions.js`, cópia byte-idêntica em `backfill_retention.js`, e uma 3ª variante com assinatura diferente em `push_functions.js`) e hoje só concordam "por sorte". Um teste com vetores-golden pega divergência silenciosa antes que corrompa buckets semanais de retenção — idealmente acompanhado de consolidar as 3 num só import.

---

## 6. Limpeza mecânica aplicada nesta rodada (8 lotes)

- Removidos 3 imports não usados: `add_academy_screen.dart:6` (`cloud_firestore`), `portal_shell.dart:16` (`academy_switcher.dart`), `team_service.dart:1` (`cloud_functions`).
- Consolidado formatter `TimeOfDay→'HH:mm'` duplicado byte-a-byte entre `classes_screen.dart` e `quick_create_class_form.dart`.
- Removido array de dias da semana duplicado em `classes_screen.dart`, substituído por `DayOfWeekLabels.short` já existente.
- Consolidado `localMonthKey`/`referenceMonthKey` (corpo idêntico) em `server_functions.js`.
- Removidos 3 membros privados não referenciados de `portal_shell.dart` (`_buildAppBarTitle`, `_showMoreMenu`, classe `_NotificationBell`) e corrigido o comentário que ficava falso após a remoção.
- Removido campo `_lastMonthRevenue` escrito e nunca lido em `reports_screen.dart`.
- Removido branch morto do parâmetro `onEdit` em `_SectionHeader` (`profile_screen.dart`), nunca passado em nenhum dos 6 call sites.
- Removido barrel morto `portal_screens.dart` (zero importadores em todo o repo).
- Removido arquivo inteiro `lib/providers/retention_provider.dart` (singular), superado por `retention_providers.dart` (plural) — zero importadores confirmados.

Todos os 8 lotes eram fixes mecânicos e seguros (código morto, imports não usados, duplicata byte-idêntica) — nenhum introduziu issue novo sobre o baseline de 279 (0 errors) do analyzer. Nenhuma refatoração estrutural foi feita nesta rodada, conforme regra do workflow — os itens de god-file, duplicação semântica (não-idêntica) e acoplamento ficam para execução deliberada conforme o roadmap da seção 3.
