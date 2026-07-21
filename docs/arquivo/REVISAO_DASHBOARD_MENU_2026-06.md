> **Arquivado (2026-07):** revisão pontual de gating de navegação (2026-06).
> Registro histórico dos 15 achados; não confirmado se todos foram corrigidos —
> tratar como ponto de partida para nova varredura se a área for revisitada.

Locations match the findings. The data is verified and ready to compile into the report.

# Relatório — Dashboard / Menu (Gating e UI/UX)

## Resumo

Auditoria de gating de navegação e dos dashboards (admin + portal do aluno). 15 achados: **1 high**, **7 medium**, **6 low**, **1 info**.

O tema dominante é **gating só na camada de navegação (esconder item de menu), sem guarda nem na tela nem no servidor** — então tanto features desligadas vazam quanto telas gateadas são alcançáveis por deep-link/URL direta. O achado mais grave (`high`) é vazamento de dados financeiros no dashboard admin para staff sem `financial:view`. Há ainda dois vazamentos no portal do aluno (loja e ranking) e uma quebra estrutural: a tela `/admin/financeiro` está no bottom-nav mas **não existe no catálogo**, ficando inacessível em desktop/tablet/menu "Mais".

Por severidade:
- **High (1):** dashboard admin vaza financeiro para staff sem permissão.
- **Medium (7):** loja não checa `storeEnabled`; 4 rotas do portal sem guarda de tela (deep-link); `/admin/financeiro` fora do catálogo; bottom-nav admin hardcoded; sem guarda de rota nas telas admin; ranking vaza no home do aluno; dashboard admin engole erros de load.
- **Low (6):** `portal_presencas` duplicado pro monitor; bottom-nav admin drifta do catálogo; `adminBypassesPermission:false` é no-op; `admin_musculacao` sem permission gate; home do aluno em branco quando sem matrícula; estados de erro do StatsCarousel ambíguos; quick actions admin não role-aware.
- **Info (1):** `FeatureId.payments` definido mas sem nav entry (comportamento defensável).

---

## Menu/gating do aluno (features off que vazam / on que somem)

### 1. [medium] Loja: master switch `storeEnabled` NÃO é checado no menu do aluno — só `storePublished`
`lib/core/navigation/nav_catalog.dart:450-457`; `nav_resolver.dart:114-163`; `settings_service.dart:726-743`; `settings_screen.dart:2297-2318,511-513`; `store_screen.dart:69-81`

O `NavEntry portal_loja` usa apenas `portalGate: PortalContextGate.storePublished`. Se o admin desliga a loja (`storeEnabled=false`) mas a flag `storePublished` ficou `true` em estado obsoleto, o item continua aparecendo pro aluno — divergente do entry admin que exige ambas. **Causa raiz:** `published` não é forçado a `false` quando `enabled=false`.

### 2. [medium] Rotas gateadas do portal sem guarda de tela (deep-link bypassa o gate do menu)
`striking_screen.dart` (sem `strikingEnabled`); `videos_screen.dart` (sem `trainingVideosEnabled`); `workouts_screen.dart` (sem `workoutPlansEnabled`); `evolution_screen.dart` (sem `physicalEvolutionEnabled`); rotas em `lib/app.dart:713,737,820,829`

Quatro telas do portal são escondidas no menu quando a feature está off, mas **não têm guarda interna** — qualquer URL/deep-link direto abre a tela normalmente. `store_screen.dart` e `jornal_screen.dart` já têm o padrão `FeatureDisabledState`; estas quatro não.

### 3. [low] `portal_presencas` aparece no menu "Mais" também para monitor (duplicado do bottom-nav)
`lib/core/navigation/nav_catalog.dart:349-355`; `portal_shell.dart:72-92`

"Presenças" já está no bottom-nav do monitor e reaparece no "Mais", diferente de Horários/Reservas que usam `hideForMonitor`. Decisão de produto: ou adicionar `portalGate: PortalContextGate.hideForMonitor`, ou documentar que é intencional.

---

## Menu/gating do admin (+ ranking pra staff)

### 4. [medium] Bottom-nav vai pra `/admin/financeiro` (AdminFinancialScreen) — tela SEM entry no catálogo
`admin_shell.dart:764-768,812` vs `nav_catalog.dart:248-274`; rota `lib/app.dart:1088-1095`

A tela existe e é o destino do tile financeiro do bottom-nav (phone), mas **não tem `NavEntry`** — sidebar desktop, rail do tablet e o menu "Mais" nunca a alcançam. Inconsistência entre superfícies.

### 5. [medium] Sem guarda de rota nas telas admin — gating é só nav, qualquer logado abre tela gateada por URL
`lib/app.dart:454-557` (redirect do router); `financial_screen.dart:20-58` (sem gate interno)

Esconder o item do menu não impede navegação direta. **O fix real é no servidor:** `firestore.rules:675` libera `financials` read via `isAcademyStaff` genérico — qualquer staff lê financeiro chamando o Firestore direto, mesmo sem `financial:view`. Precisa de check permission-aware (`isAcademyAdmin || (isAcademyInstructor && instructorHasPermission('financial:view'))`).

### 6. [low] Bottom-nav admin é lista hardcoded, não o catálogo resolvido — lógica de gating drifta de `resolveAdminCatalog`
`admin_shell.dart:781-816` (`_bottomNavItemsFor`)

Os 4 tiles primários são hardcoded; gating fica duplicado e diverge do `nav_resolver`. Deriva direto da causa do achado #4.

### 7. [low] `adminBypassesPermission:false` NÃO restringe admins de verdade — `hasPermission()` retorna `true` pra qualquer admin
`nav_resolver.dart:38-56` (`_permissionSatisfied`) + `user.dart:444-451` (`hasPermission`); entries `nav_catalog.dart:197-198,254-255,263-264,272-273`

A flag é no-op para admins (graduacao/cobranca/relatorios/assinaturas). Recomendado: limpar a flag + corrigir comentários (`nav_catalog.dart:95-99`, `nav_resolver.dart:36-37`), pois não existe conceito de "admin sem permissão" hoje.

### 8. [low] `admin_musculacao` tem feature gate mas nenhum permission gate — todo instrutor vê/abre Musculação (flag default ON)
`nav_catalog.dart:218-226`; default `settings_service.dart:342` (`musculacaoEnabled=true`)

Diverge dos pares staff-restricted. Decidir política: adicionar `requiresPermission` ou documentar que é aberto a todo instrutor (como `admin_ranking:206-208` e `admin_jornal:233-237`).

### 9. [info] `FeatureId.payments` definido e ligado a `isPaymentEnabled` mas nenhum nav entry usa
`nav_catalog.dart:12` + `nav_resolver.dart:18-19`; único consumidor `settings_screen.dart:356,1223-1224`

Comportamento defensável: `isPaymentEnabled` = "gateway online conectado", e cobrança manual/cash deve continuar disponível mesmo sem gateway. Sem fix de código; opcionalmente documentar a intenção.

---

## UI/UX dos dashboards

### 10. [high] Dashboard admin vaza dados financeiros pra staff sem `financial:view`
`admin_dashboard_screen.dart:338-487` (card Mensalidades); `:247-255,:295-303,:458-487` (quick-action Financeiro / alerta de inadimplência)

Card de Mensalidades, alerta de overdue, quick-action Financeiro e o card "Receita do Mês" no carousel são renderizados sem checar permissão. Qualquer staff vê o financeiro da academia. Precisa gatear tudo em `canSeeFinancial = currentUser.hasPermission('financial:view')` (que já é `true` para admins).

### 11. [medium] Home gamification vaza posição no ranking mesmo com `rankingVisibleToStudents` desligado
`gamification_section.dart:27,43-88,154-157` (consumido por `home_screen.dart:154-161`)

A pill de rank é exibida sem checar a config da academia. Aluno vê sua posição mesmo quando a academia desligou a visibilidade. Computar `rank=null` quando `!rankingVisible` — meta mensal e timeline/conquistas ficam intactos.

### 12. [medium] Dashboard admin engole erros de load — mostra dados zerados sem mensagem de erro/vazio
`admin_dashboard_screen.dart:43-66` (`_loadDashboardData`) e `:261-456`

Falha de fetch vira "tudo zero", indistinguível de academia nova/legitimamente vazia. Adicionar `_loadError` + estado de erro com "Tentar novamente".

### 13. [low] Home do aluno renderiza tela quase em branco quando não há matrícula vinculada
`home_screen.dart:77-103,114-185`

`student==null` colapsa as seções sem explicação. Adicionar card de onboarding "Sua matrícula ainda não foi vinculada" + CTA de contato. `_QuickAccessSection` já renderiza sempre (a sugestão de "surfacear" é moot).

### 14. [low] Estados de erro de medalha/treino no StatsCarousel são inconsistentes e ambíguos
`home_screen.dart:468-531`

Erro de load mostra `'0'` (medalhas, linha 526) e `'-'` (treinos, 486) — `'0'` se confunde com valor real. Usar sentinela não-numérica consistente (`'—'`) em ambos.

### 15. [low] Quick actions do dashboard admin não são role-aware (Novo Aluno / Chamada / Financeiro pra todo staff)
`admin_dashboard_screen.dart:222-258`

Três CTAs fixos sem gating. Construir a lista dinamicamente: Chamada (`attendance:take`), Novo Aluno (`students:create`), Financeiro (`financial:view`). Mesmo problema de rota-sem-guarda do #5/#10 aplica aos destinos.

---

## Plano priorizado (file:line + diffs)

Ordem = severidade × superfície de exposição de dados. **P0/P1 fecham vazamentos reais; P2 são consistência/UX.**

### P0 — Vazamento financeiro (servidor + dashboard) — achados #10, #5

**a) Servidor é a autoridade real (`firestore.rules:675`).** Trocar o read coarse por permission-aware:
```
// antes
allow read: if isAcademyStaff(academyId);
// depois
allow read: if isAcademyAdmin(academyId)
  || (isAcademyInstructor(academyId) && instructorHasPermission(academyId, 'financial:view'));
```
Adicionar helper `instructorHasPermission` lendo o array de permissões do doc do instrutor. Aplicar o mesmo tratamento a `billing`/`subscriptions`.

**b) Dashboard admin (`admin_dashboard_screen.dart`).** No `build()`:
```dart
final canSeeFinancial = ref.watch(currentUserProvider).valueOrNull?.hasPermission('financial:view') == true;
```
Gatear: (1) `_buildMonthlyFinancialCard()` só quando `canSeeFinancial`; (2) `_buildAlertsSection()` (overdue) idem; (3) quick-action "Financeiro" (linhas 247-255) removida quando `!canSeeFinancial`; (4) card "Receita do Mês" do `_buildStatsCarousel()` omitido (ajustar dot/itemCount). Opcional: pular `getOverdue()`/`getMonthlySummary()` em `_loadDashboardData` quando sem permissão (evita leak na camada de dados + reduz reads).

### P1 — Vazamentos de feature/ranking no portal + rota financeira inacessível

**#1 Loja master switch.** Em `nav_catalog.dart:450-457`, adicionar `feature: FeatureId.store` ao `portal_loja` (mantendo `portalGate: storePublished`) — `resolvePortalCatalog` (nav_resolver.dart:120-123) então exige ambas. **Causa raiz:** em `updateStoreSettings` (`settings_service.dart:726-743`) ou no save de `settings_screen.dart`, forçar `published: _storeEnabled ? _storePublished : false`. Defense-in-depth em `store_screen.dart:69`: `final isStoreAvailable = (settings?.storeEnabled ?? false) && (settings?.storePublished ?? false);`.

**#2 Guarda nas 4 telas do portal.** Em cada tela, espelhar `store_screen.dart:66-75`:
```dart
final settingsAsync = ref.watch(academySettingsProvider);
final enabled = isFeatureEnabled(FeatureId.striking, settingsAsync.valueOrNull); // mapear por tela
if (settingsAsync.hasValue && !enabled) {
  return Scaffold(body: const FeatureDisabledState(...));
}
```
Mapeamento: `striking_screen`→`strikingEnabled`, `videos_screen`→`trainingVideosEnabled`, `workouts_screen`→`workoutPlansEnabled`, `evolution_screen`→`physicalEvolutionEnabled`. Só bloquear quando `hasValue` (não piscar durante load).

**#11 Ranking no home.** Em `gamification_section.dart`:
```dart
final rankingVisible = ref.watch(academySettingsProvider).valueOrNull?.rankingVisibleToStudents ?? true;
final rank = rankingVisible ? ref.watch(studentMonthlyRankProvider(student.id)).valueOrNull : null;
```
Meta mensal e timeline ficam intactos.

**#4 `/admin/financeiro` no catálogo.** Adicionar `NavEntry` em `kAdminNavCatalog` (seção financeiro):
```dart
NavEntry(
  key: 'admin_financeiro',
  label: 'Financeiro',
  icon: LucideIcons.dollarSign,
  route: '/admin/financeiro',
  section: NavSection.financeiro,
  requiresPermission: 'financial:view',
),
```
Resolve sidebar/rail/menu "Mais" + alinha com o bottom-nav.

### P2 — Consistência de gating e UX

- **#6 + #15** Derivar bottom-nav admin (`admin_shell.dart:781-816`) e quick-actions (`admin_dashboard_screen.dart:222-258`) de `resolveAdminCatalog(...)` em vez de listas hardcoded — gating num único lugar (`nav_resolver`).
- **#12** `admin_dashboard_screen.dart`: adicionar `Object? _loadError`, setar no catch, branch de estado de erro com "Tentar novamente" dentro de `RefreshIndicator`.
- **#7** Limpar `adminBypassesPermission:false` (no-op) dos entries graduacao/cobranca/relatorios/assinaturas + corrigir comentários `nav_catalog.dart:95-99`, `nav_resolver.dart:36-37`.
- **#8** `admin_musculacao` (`nav_catalog.dart:218-226`): decidir política (adicionar `requiresPermission` ou documentar que é aberto).
- **#3** `portal_presencas` (`nav_catalog.dart:349-355`): adicionar `hideForMonitor` ou comentar que é intencional.
- **#13** `home_screen.dart`: card de onboarding pro caso `student==null`.
- **#14** `home_screen.dart:486,526`: sentinela de erro `'—'` consistente em medalhas e treinos.
- **#9** Sem fix; opcionalmente documentar intenção do `FeatureId.payments`.

**Nota transversal:** P0(a) e #5 deixam claro que o gating atual é *client-only* (esconder menu). O servidor (`firestore.rules`) é a única defesa real contra exfiltração — priorizar as regras de `financials`/`billing`/`subscriptions` antes dos fixes de UI, que são UX/defense-in-depth.