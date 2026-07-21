> **Arquivado (2026-07):** este documento (2026-06) auditou a catraca como
> "implementada mas não wired, não deployada, sem UI" e propôs o plano de UI
> de configuração. **Esse plano já foi construído e deployado** — `AdminDevices
> Screen`/`DeviceEnrollmentScreen` existem, `accessEvents`/`devices` têm regras
> no `firestore.rules`, e a catraca está em produção (piloto Control iD). Ver
> `functions/access_control/README.md` para o estado vivo. Mantido como
> registro histórico do gap que motivou a UI.

Confirmed: `accessEvents`/`devices` have zero rules (finding validated). All findings are accurate against the actual code. Here is the report.

---

# Validação da Catraca (Controle de Acesso) + Plano de Implementação

## 1. Resumo

A camada **backend** da catraca (Arquitetura C / push-cloud) está **implementada, sólida e segura** — mas **não wired, não deployada e sem nenhuma UI Flutter**. Validei os 4 arquivos núcleo e confirmo:

- `financial_gate.js` — gate de inadimplência **fail-open + default OFF**, reusa a definição canônica de "vencido" (`overdue_util.js`) compartilhada com o cron. Correto. (confirmado `financial_gate.js:48-96`)
- `ingest.js` — núcleo de ingestão com idempotência estrita, sanitização de path (C1), registry estático de adapters, gate financeiro pré-transação, contrato de resposta por fabricante. Correto. (confirmado `ingest.js:240-430,435-621`)
- `kiosk_screen.dart` — totem fullscreen funcional, lê `kioskLatestEventProvider`. (confirmado `:66-78`)
- `canonical.js` — vocabulário `VENDORS=['controlid','zkteco','intelbras']`. (confirmado `:70-72`)

**Lacunas confirmadas que impedem ligar a feature end-to-end:**

| # | Lacuna | Severidade | Evidência |
|---|--------|-----------|-----------|
| A | Sem flag `accessControl` em `AcademySettings` — não há onde ligar/desligar | high | `settings_service.dart:112,227,401` (só `musculacaoEnabled` etc., zero `accessControl`) |
| B | Sem card "Controle de Acesso" na aba Funcionalidades | high | `settings_screen.dart:1635-2096` (cards de musculação/muaythai/checkin, nenhum de catraca) |
| C | Rota `/kiosk` **acessível por qualquer usuário autenticado, sem guard** | medium | `app.dart:604-611` (GoRoute sem redirect); redirect global `:452-548` não trata `/kiosk` |
| D | `firestore.rules` **não tem regra** para `accessEvents`/`devices`/`deviceRateLimits` → kiosk lê e leva **PERMISSION_DENIED** | high | `grep -c accessEvents firestore.rules` = **0** |
| E | Sem CRUD de devices (vendor/secret/userMap) — impossível parear uma catraca física | medium | nenhuma tela; `ingest.js:467` lê `academies/{id}/devices/{deviceId}` |
| F | Sem whitelist/override por aluno (bolsa/acordo) | low | `financial_gate.js:64` (nenhuma leitura de isenção) |
| G | Vendors duplicados em 3 lugares sem fonte única; sem template de adapter; sem HOW-TO no README; sem teste de conformidade | low-medium | `canonical.js:70` vs `ingest.js:70-74` vs (futuro) Flutter; `functions/test/` sem cobertura de adapters |

**Decisão de arquitetura validada:** NÃO criar `FeatureId.accessControl`. O enum `FeatureId` (`nav_catalog.dart:7-19`) carrega a invariante "todo FeatureId tem NavEntry no menu". A catraca **não é um item de menu** (é um totem + um gate de portão), então criar o enum quebraria a invariante. Gatear por **flag pura em `AcademySettings`** (espelhando `musculacaoEnabled`/`studentCheckinEnabled`) + uma **seção dedicada** na aba Funcionalidades.

---

## 2. Settings → Funcionalidades → Catraca (toggle + seletor de marca)

### Desenho exato

Card novo `_SettingsCard(title:'Controle de Acesso (Catraca)', icon: LucideIcons.scanFace)`, inserido **depois do card de Musculação** (`settings_screen.dart:~1844`), com:

1. **Toggle master** `_ModernSwitch` — `value:_accessControlEnabled`, subtitle: *"Integra catracas/totem de acesso. Desligado: nada aparece para a academia."* Default **false** (graceful OFF).
2. **`if(_accessControlEnabled)...`**: revela
   - **Seletor de marca** `_TurnstileVendorSelector` (modelado em `_MuaythaiGradeSystemSelector`, `:1859`) que lê de `kTurnstileRegistry` — é o **default/dica de setup**, não o vendor real (o real é por-device).
   - **Botão "Abrir totem (Kiosk)"** → `context.go('/kiosk')`.
   - **Botão "Catracas cadastradas"** → `context.go('/admin/catracas')` (CRUD de devices).
   - **Segundo toggle** "Bloquear inadimplentes no portão" — `value:_blockOnOverdue` (default **false**, segundo nível explícito; ligar a catraca **não** começa a prender ninguém).

### Modelo de persistência (crítico — alinhar com o backend)

O backend já lê `academies/{id}.accessControl` como **MAPA**: `financial_gate.js:14-15` espera `{ blockOnOverdue, graceDays, blockTypes }` e `ingest.js:539` lê `acad.accessControl`. **Gravar TUDO sob esse mapa** para não brigar:

```
academies/{id}.accessControl = {
  enabled: bool,                 // master switch (lido por ingest E pela UI)
  vendor: string,                // default/dica de setup (vendor real é por-device)
  blockOnOverdue: bool,          // segundo toggle (já lido por financial_gate.js:51)
  graceDays: int,                // já lido por financial_gate.js:63
  blockTypes: [string],          // já lido por financial_gate.js:61, default ['monthly_tuition']
  enforcementMode: 'monitor',    // novo (ver §4)
  exemptStudentIds: [string],    // novo (ver §4)
  message: string,               // copy custom do totem
}
```

### Arquivos a mudar

| Arquivo | Mudança |
|---|---|
| `lib/services/settings_service.dart:112-451` (class `AcademySettings`) | Adicionar campos derivados do mapa: `final Map<String,dynamic> accessControl;` + getters `bool get accessControlEnabled => (accessControl['enabled'] ?? false) == true;`, `String get accessControlVendor => accessControl['vendor'] ?? '';`, `bool get blockOnOverdue => (accessControl['blockOnOverdue'] ?? false) == true;`. Parse em `fromFirestore` (`:401`): `accessControl: (data['accessControl'] as Map<String,dynamic>?) ?? const {}` |
| `lib/services/settings_service.dart:~838` | Novo método `updateAccessControl({bool? enabled, String? vendor, bool? blockOnOverdue, int? graceDays, List<String>? blockTypes, String? enforcementMode})` — `_academyRef.set({'accessControl': {...}, 'updatedAt': ...}, SetOptions(merge:true))` (espelha `updateMusculacaoEnabled` `:816`). **Usar `set merge` com sub-mapa `accessControl` completo** ou `update` com chaves `accessControl.enabled` (dot-path) para não apagar campos do mapa. |
| `lib/screens/admin/settings_screen.dart:109-110` (estado) | Adicionar `bool _accessControlEnabled=false; String _accessControlVendor=''; bool _blockOnOverdue=false; int _graceDays=0;` |
| `lib/screens/admin/settings_screen.dart:291-292` (`_loadSettings`) | `_accessControlEnabled = settings.accessControlEnabled; _accessControlVendor = settings.accessControlVendor; _blockOnOverdue = settings.blockOnOverdue;` |
| `lib/screens/admin/settings_screen.dart:511` (batch save) | `service.updateAccessControl(enabled:_accessControlEnabled, vendor:_accessControlVendor, blockOnOverdue:_blockOnOverdue, graceDays:_graceDays),` |
| `lib/screens/admin/settings_screen.dart:~1844` (`_buildFeaturesTab`) | Inserir o `_SettingsCard` novo (desenho acima) |
| `lib/core/access_control/turnstile_registry.dart` **(novo)** | Registry único (ver §5) |

---

## 3. Graceful quando OFF

O **backend já é graceful-off** (validado): `financial_gate.js:51` `if (!cfg || cfg.blockOnOverdue !== true) return {blocked:false}`; academia legada sem device doc → `ingest.js:468` 403. O que falta endurecer é o **Flutter + rules + master switch**.

### 3.1 Guardar a rota `/kiosk` (finding C — medium)

`app.dart:604-611` não tem guard. Um aluno alcança o totem e o "sair" o joga em `/admin` (que ele não pode ver). **Fix** no `redirect()` global (`app.dart:452-548`), antes do `_sessionLanded = true; return null;`:

```dart
if (state.matchedLocation == '/kiosk') {
  final academy = ref.read(currentAcademyProvider).valueOrNull; // ou via settings provider
  final ok = user != null && user.isAdmin &&
             (academy?.settings.accessControlEnabled == true);
  return ok ? null : '/admin';
}
```

(Modelar no padrão de redirect por papel já presente em `:502-541`. Confirmar o provider de academy/settings disponível no escopo do router.) **Não** adicionar `NavEntry` para o kiosk — o acesso é o botão dentro do card de Settings (§2).

### 3.2 Master switch lido pelos DOIS lados (finding ingest — low)

Hoje `ingest.js` só respeita `accessControl.blockOnOverdue` e `device.enabled`; **não há kill-switch de academia**. Desligar a catraca em Settings não pararia as gravações de presença se um device doc ficar `enabled:true`. **Fix** em `ingest.js`, após carregar `accessControlCfg` (`:539`) ou logo antes do dispatch:

```js
if (acad.accessControl?.enabled !== true) {
  return respond(res, vendor, { granted:false, message:'Indisponivel' }); // ACK vendor-correto, não re-entrega
}
```

`academies/{id}.accessControl.enabled` vira a **única fonte de verdade** que tanto a UI quanto o ingest leem. `device.enabled` permanece como switch mais fino por-catraca.

### 3.3 firestore.rules (finding D — high) — kiosk está "broken on", não "graceful off"

Confirmado: **zero regras** para as subcoleções. Quando a academia LIGAR a catraca, o `kioskLatestEventProvider` (`kiosk_screen.dart:70-77`) recebe **PERMISSION_DENIED** e o totem nunca reage. **Fix** — dentro de `match /academies/{academyId}` (`firestore.rules:356`), adicionar:

```
match /accessEvents/{eventId} {
  allow read:  if isAcademyStaff(academyId);  // PII: só staff, não outros alunos
  allow write: if false;                       // CF escreve via Admin SDK (bypassa rules)
}
match /devices/{deviceId} {
  allow read:  if isAcademyAdmin(academyId);   // contém secret/userMap
  allow write: if isAcademyAdmin(academyId);
}
match /deviceRateLimits/{id} {
  allow read, write: if false;                 // só Admin SDK
}
```

(`isAcademyStaff`/`isAcademyAdmin` confirmados em `firestore.rules:46,73`.) **Atenção PII**: `devices` carrega `secret` — restringir read a admin, nunca staff/instructor.

### 3.4 PIN no exit do kiosk (finding kiosk-exit — low)

`kiosk_screen.dart:208-214` — o "sair" (`context.go('/admin')`) não tem PIN; controles de simulação vazam em `kDebugMode`. Enquanto o guard da §3.1 mantém não-admins fora, o risco é baixo. Plano: exigir `academies/{id}.accessControl.kioskPin` (ou re-auth admin) antes de sair.

---

## 4. Bloqueio de check-in (plano robusto)

O **núcleo está correto** e não deve regredir: fail-open (`financial_gate.js:92-95`), default OFF (`:51`), fonte canônica de vencido compartilhada com o cron (`:29,85-86`), `DEFAULT_BLOCK_TYPES=['monthly_tuition']` (mensalidade só — loja/private_lesson/overcharge nunca prendem, `:31-35,79-81`). Evoluções, em ordem de valor:

### 4.1 Whitelist/override por aluno (finding F — low, alto valor de UX)
Cenário comum (bolsista, atleta de competição, acordo verbal). Sem isso, o dono escolhe entre constranger um aluno conhecido no totem ou desligar o bloqueio para todos. **Fix**: em `financial_gate.js`, antes do loop (`:64`):
```js
if (Array.isArray(cfg.exemptStudentIds) && cfg.exemptStudentIds.includes(studentId))
  return { blocked:false, reason:null, amountOverdue:0 };
```
Alternativa mais durável: ler `students/{studentId}.accessExemptUntil` (Timestamp) — 1 read extra, já temos `studentRef`. Na tela do aluno, toggle "Liberar catraca mesmo inadimplente" com motivo; idealmente setado automaticamente quando a recepção registra um acordo/parcelamento.

### 4.2 Modo monitor/dry-run ao ligar (finding monitor — low, evita crise no dia 1)
Ligar de uma vez numa base com inadimplência histórica (+ risco de falso-positivo por dados legados reais×centavos — ver memória do projeto) barra dezenas no dia 1. **Fix**: `cfg.enforcementMode: 'monitor'|'enforce'` (default ao ligar = `'monitor'`). Em monitor, `ingest.js` grava outcome `'would_block_overdue'` e **LIBERA** o giro → a academia vê no painel quem *seria* bloqueado por uma semana antes de virar a chave. Combina com a auditoria de dados legados já anotada.

### 4.3 Soft-warning durante o grace (finding graceDays — low)
`graceDays` existe (`:86`) mas libera silenciosamente — o aluno é surpreendido no portão. **Fix em 2 degraus**: durante o grace, gate retorna `{blocked:false, warn:true, daysOverdue}` e `ingest` anexa `displayMsg` de aviso ("Mensalidade vence há N dias") ao evento **granted** (verde-com-aviso no kiosk); só após o grace vira `denied_overdue`.

### 4.4 Mensagem de bloqueio acionável (finding mensagem — low)
Hoje genérica ("Financeiro pendente — procure a recepcao", `ingest.js:288`); o `amountOverdue` é calculado e **descartado** (`financial_gate.js:88,91`). **Fix**: propagar `amountOverdue` → campo do `accessEvent` → kiosk: "Mensalidade em aberto (R$X). Pague pelo app ou fale na recepção." Tornar o valor configurável (`cfg.showAmountOnKiosk`) por privacidade — o totem é público.

### 4.5 Persistir defaults sem regredir
A UI (`updateAccessControl`) deve gravar `accessControl` **preservando** os defaults do backend (`blockOnOverdue:false`, `graceDays:0`, `blockTypes:['monthly_tuition']`). Nunca enviar `blockTypes` vazio (o gate cai no default, ok, mas é melhor explícito).

---

## 5. Como adicionar uma nova catraca (dev-ease)

Hoje a lista de vendors está **duplicada e desacoplada** em ≥3 lugares (`canonical.js:70`, `ingest.js:70-74` `ADAPTER_LOADERS`, e o futuro seletor Flutter), o modo de falha de esquecer o registry é **silencioso** (`ingest.js:494-498` ACK 200 "Indisponivel", device não re-entrega, nenhum 4xx). Os exports dos adapters são **inconsistentes**: `zkteco.js:276` `{parse,vendor,...}`, `controlid.js:327` `{parse,...}` (sem vendor), `intelbras.js:461` `module.exports=parse` (export-função). Sem template e sem teste de conformidade.

### Plano para "extrema facilidade" (req 4)

**(a) Registry único Flutter** — `lib/core/access_control/turnstile_registry.dart` **(novo)**:
```dart
enum TurnstileVendor { controlid, zkteco, intelbras }
class TurnstileVendorSpec {
  final String id;        // DEVE == chave de ingest.ADAPTER_LOADERS
  final String label;     // Control iD / ZKTeco / Intelbras
  final IconData icon;
  final String docUrl;    // link da §6.x do README
  final String setupHint; // dica de pareamento
  final List<String> extraFields; // campos por-fabricante no form de device
}
const kTurnstileRegistry = <TurnstileVendorSpec>[ ... ];
```
O `id` de cada entrada **TEM** que bater com a chave de `ADAPTER_LOADERS` (`ingest.js:70-74`) — senão o seletor grava um vendor que o backend não reconhece → falha silenciosa. Cobrir com teste de drift (item e).

**(b) Template de adapter** — `functions/access_control/adapters/_TEMPLATE.js` **(novo)**: esqueleto comentado copy-paste, com boilerplate (`'use strict'`, requires de `normalizeDirection/normalizeMethod`, `const VENDOR='__novo__'`), `GRANTED_EVENT_CODES` marcado `// TODO field-confirm`, `parse(req,device)` montando os 10 campos do AccessEvent (contrato em `canonical.js:144-203`) com `// TODO field-confirm` em cada decisão de wire-format, e **shape de export único** `module.exports = { parse, vendor: VENDOR, _internals: {...} }`.

**(c) Drift-detector no núcleo** — em `ingest.js`, após `ADAPTER_LOADERS`: `const REGISTERED_VENDORS = Object.freeze(Object.keys(ADAPTER_LOADERS));` (exportar). Em `getAdapter()` (`:78-94`), quando o vendor está em `canonical.VENDORS` mas não em `ADAPTER_LOADERS`, logar `console.error('vendor sem adapter registrado', key)` em vez de retornar `null` silencioso.

**(d) HOW-TO no README** — adicionar `## 8. HOW-TO: adicionar um novo fabricante` (o README hoje tem só docs por-vendor §6.1-6.3 e TODOs §7, **sem receita aditiva** — confirmado):
1. `cp adapters/_TEMPLATE.js adapters/<vendor>.js` e renomear `VENDOR`.
2. Implementar `parse(req,device)`: rotear por `req.path`/`req.query`, extrair os 10 campos, `granted` via `GRANTED_EVENT_CODES` local (field-confirm), **preservar `occurredAt` ORIGINAL**, gerar `eventId` **ESTÁVEL** (id nativo do device; senão hash do conteúdo — senão a idempotência quebra silenciosamente: `recordAccessEvent` só retorna `{outcome:'bad_id'}`, `ingest.js:246`).
3. Registrar em `ingest.js` `ADAPTER_LOADERS` (`:70-74`) — único ponto que liga o vendor ao dispatch.
4. Adicionar `'<vendor>'` em `canonical.VENDORS` (`canonical.js:70`).
5. Definir o contrato de resposta em `respond()` (`ingest.js:412-430`) se o device exigir formato próprio (síncrono vs fire-and-forget).
6. Adicionar entrada em `kTurnstileRegistry` (`id` == chave do `ADAPTER_LOADERS`).
7. Rodar `node --check adapters/<vendor>.js` + o teste de conformidade (item e).
8. Documentar a config física em §6.x + TODOs de field-confirm em §7.

Tabela "Pontos de toque": `adapters/<vendor>.js` (novo) | `ingest.ADAPTER_LOADERS` | `canonical.VENDORS` | `respond()` (se síncrono) | `kTurnstileRegistry` | README §6.x+§7.

**(e) Harness de conformidade** — `functions/test/access_adapter_conformance.test.js` **(novo)**, parametrizado sobre o registry. Para cada vendor: alimentar fixture (recorte do `raw` que o núcleo loga) e asseverar — `Array.isArray(parse(req,device))`, cada item tem os 10 campos, `occurredAt instanceof Date && !isNaN`, `direction ∈ DIRECTIONS`, `method ∈ METHODS`, `typeof granted==='boolean'`, `eventId` não-vazio e **determinístico** (2× mesmo input → mesmo eventId = prova de idempotência). Caso heartbeat → `[]`; irreconhecível → `null`. Teste de drift: `Object.keys(ADAPTER_LOADERS).every(v => VENDORS.includes(v))`. (`functions/test/` hoje cobre private_lesson/gamification/mp_pix, **nada de access_control** — confirmado.)

---

## 6. Plano de implementação priorizado

### Fase 0 — Destravar (graceful + segurança). **Sem isto, ligar a feature quebra.**

1. **`firestore.rules:356`** (dentro de `match /academies/{academyId}`) — adicionar os 3 matches da §3.3. **[high, sem isto o kiosk recebe PERMISSION_DENIED quando ON]**
2. **`functions/access_control/ingest.js:~539`** — master kill-switch da §3.2 (`if (acad.accessControl?.enabled !== true) return respond(...,{granted:false,message:'Indisponivel'})`). **[low, mas fecha o gap de "OFF mas devices ainda gravam"]**
3. **`lib/app.dart` redirect** (`:452-548`) — guard de `/kiosk` da §3.1. **[medium, fecha "aluno alcança o totem"]**

### Fase 1 — Tornar a feature ligável (settings).

4. **`lib/services/settings_service.dart:112-451`** — campos/getters `accessControl*` em `AcademySettings` + parse em `fromFirestore` (`:401`). **[high]**
5. **`lib/services/settings_service.dart:~838`** — `updateAccessControl(...)` (espelha `updateMusculacaoEnabled` `:816`). **[high]**
6. **`lib/core/access_control/turnstile_registry.dart`** (novo) — registry único §5(a). **[high]**
7. **`lib/screens/admin/settings_screen.dart`** — estado (`:109`), load (`:291`), save (`:511`), card novo (`:~1844`) com toggle master + `_TurnstileVendorSelector` + 2º toggle `blockOnOverdue` + botões Kiosk/Catracas. **[high]**

### Fase 2 — Parear catracas físicas (CRUD).

8. **`lib/services/access_control_service.dart`** (novo) — `AccessControlService(academyId)`: `watchDevices()` sobre `academies/{id}/devices`, `addDevice/updateDevice/deleteDevice`. Modelo `TurnstileDevice(id,name,vendor,enabled,...)`. `secret` write-only no form (placeholder "deixe em branco para manter"). **[medium]**
9. **`lib/screens/admin/access_control_devices_screen.dart`** (novo) — lista + form que mostra só os `extraFields` do vendor selecionado (de `kTurnstileRegistry`). O `vendor` por-device é o que `ingest.js:471` realmente lê. **[medium]**
10. **`lib/app.dart:~1055`** (dentro do `AdminShell`) — registrar `GoRoute(path:'/admin/catracas', ...)`. **[medium]**

### Fase 3 — Bloqueio robusto (§4).

11. **`functions/access_control/financial_gate.js:64`** — whitelist `exemptStudentIds` (§4.1). **[low]**
12. **`functions/access_control/financial_gate.js` + `ingest.js`** — `enforcementMode:'monitor'` (§4.2) + propagar `amountOverdue`/`warn` (§4.3-4.4). **[low]**

### Fase 4 — Dev-ease (§5 b-e).

13. **`functions/access_control/adapters/_TEMPLATE.js`** (novo) + padronizar shape de export de `controlid.js:327`/`intelbras.js:461`. **[low]**
14. **`functions/access_control/ingest.js:70-94`** — `REGISTERED_VENDORS` export + drift log em `getAdapter`. **[low]**
15. **`functions/access_control/README.md`** — seção §8 HOW-TO (§5d). **[medium]**
16. **`functions/test/access_adapter_conformance.test.js`** (novo) — harness + drift test (§5e). **[low]**

### Ordem de deploy
rules (1) e functions (2,11,12,14) podem ir antes — são no-op em prod até alguma academia setar `accessControl.enabled=true`. O app Flutter (3-10) sai num release. Auditar dados legados (reais×centavos) **antes** de qualquer academia ligar `blockOnOverdue` — usar `enforcementMode:'monitor'` como rede de segurança.

**Arquivos-chave (absolutos):**
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/access_control/financial_gate.js`
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/access_control/ingest.js`
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/access_control/canonical.js`
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/access_control/README.md`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/kiosk/kiosk_screen.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/app.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/settings_service.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/admin/settings_screen.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/core/navigation/nav_catalog.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/firestore.rules`
- novos: `lib/core/access_control/turnstile_registry.dart`, `lib/services/access_control_service.dart`, `lib/screens/admin/access_control_devices_screen.dart`, `functions/access_control/adapters/_TEMPLATE.js`, `functions/test/access_adapter_conformance.test.js`