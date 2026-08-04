> **Arquivado (2026-07):** veredito de prontidão para um deploy específico de
> 2026-06 (rules + backfill de permissões de instrutor). Esse deploy já foi
> feito; documento é um runbook histórico, não um checklist recorrente.

# Veredito FINAL de Production-Readiness — GraduaBJJ (`firebase-production` → arpjj-76350)

## Veredito

**PRONTO-COM-RESSALVAS**

Há exatamente **1 blocker**, mas é um blocker de *ordem de deploy*, não de código: as novas `firestore.rules` que passam a exigir `extraPermissions` granulares para instrutores vão **trancar instrutores legados** (cujo papel vive só no doc de usuário, sem `academyDetails`) no momento em que forem publicadas, A MENOS que o backfill rode antes. O fix existe, está pronto (`functions/scripts/backfill_instructor_permissions.js`) e é idempotente. Com o runbook abaixo respeitado, o deploy é não-quebrante.

Tudo o mais é aditivo e graceful-OFF: build limpo (`dart analyze` 0 erros, `node --check` OK nos 3 arquivos de functions), catraca/access-control desligado por padrão, estados terminais de financials/storeOrders já gateados nas telas vivas.

---

## Blockers

### B1 — Instructor write-gating quebra instrutores legados se as rules forem ao ar antes do backfill `[breaksLegacy]`

**Localização:** `firestore.rules` (attendance write ~547, financials create ~684, competitions create/update/delete ~898, competitionResults ~940); migração: `functions/scripts/backfill_instructor_permissions.js`.

**Causa raiz:** `isAcademyInstructor()` reconhece o instrutor via mapping OU via `academies/{id}/users/{uid}.role == 'instructor'`, mas `hasExtraPermission()` lê **somente** o mapping. Instrutor legado (papel só no user-doc, sem `academyDetails.extraPermissions`) passa no check de instrutor e **falha** no de permissão → trancado de chamada / lançar cobrança / competições.

**Fix exato (obrigatório — ORDEM DE DEPLOY):** contra `arpjj-76350`:

```
GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa.json \
  node functions/scripts/backfill_instructor_permissions.js --dry-run
```

Inspecionar os contadores impressos. Atenção especial a **`createdEntries`** (= `of which new entries`): esses são exatamente os instrutores user-doc-only em risco de lockout. Conferir que `granted` cobre todos os pares (uid, academy) não-admin. SÓ ENTÃO rodar para valer (sem `--dry-run`), confirmar `APPLIED`, e **só depois** publicar `firestore.rules`. Registrar essa ordem no runbook.

**Fix recomendado (eliminar o footgun de ordenação — opcional mas reduz risco a zero):** adicionar grace transitório nas rules tratando ausência do array `extraPermissions` como acesso legado pleno no ramo do instrutor:

```
function instructorLegacyOrHas(academyId, permission) {
  let mapping = getUserAcademyMapping();
  return isAcademyInstructor(academyId) && (
    hasExtraPermission(academyId, permission) ||
    !(mapping.keys().hasAll(['academyDetails']) &&
      mapping.academyDetails.keys().hasAll([academyId]) &&
      mapping.academyDetails[academyId].keys().hasAll(['extraPermissions']))
  );
}
```

e usar `isAcademyAdmin(academyId) || isMonitor(academyId) || instructorLegacyOrHas(academyId, 'attendance:take')` (idem `financial:create` / `competitions:create`). Isso torna as rules seguras em qualquer ordem; após o backfill popular todos, apertar removendo o fallback em PR de follow-up. Relaxa levemente o least-privilege durante a transição — aceitável, pois só restaura capacidade pré-existente.

> Recomendação: aplicar o backfill SEMPRE; o grace transitório é o cinto-de-segurança caso a ordem seja violada. Não dispensa o backfill.

---

## Riscos residuais aceitáveis

- **Imutabilidade de estado terminal em financials/storeOrders** (`firestore.rules` ~684-705, ~795-840): as telas vivas já gateiam edição/exclusão aos estados não-terminais que as rules mantêm abertos. Não quebra prod. Qualquer reversão genuína de dinheiro/estado (refund manual / reabrir) deve passar por Cloud Function com Admin SDK (bypassa rules).
- **`lib/screens/admin/store_orders_screen.dart` (AdminStoreOrdersScreen) órfã**: o `_OrderDetailsSheet` (962-976) monta botões de re-status para delivered/cancelled que seriam silenciosamente negados pelas novas rules. Não está roteada hoje → sem impacto. Higiene opcional: deletar para evitar que um dev futuro a ligue.
- **Posts legados sem `postType`** (`event_detail_screen.dart` 79-90; `academy_event.dart` 74-83): caem no fallback `event` e ficam visíveis ao aluno mesmo com jornal OFF. Edge case cosmético; endurecimento opcional (gate na presença crua do campo, ou backfill estampando `postType`).
- **Catraca / access-control**: graceful-OFF (`accessControl` default `const {}`), atrás do master switch em Settings, sem entrada em nav_catalog/admin_shell/more_menu. Sub-coleções net-new não afetam clientes legados. Manter `kTurnstileVendors` (Flutter) em lock-step com `ADAPTER_LOADERS` (ingest.js) / `VENDORS` (canonical.js) ao adicionar fabricante.

---

## CHECKLIST DE DEPLOY (ordem exata)

1. **Sanity das rules (pré-deploy):** rodar `firebase deploy --only firestore:rules,storage:rules --dry-run` (ou os testes de unit das rules no emulator) como compile/semantic CEL real. Chaves/parênteses balanceados são necessários mas não suficientes.

2. **BACKFILL PRIMEIRO (obrigatório — B1):**
   - dry-run: `GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa.json node functions/scripts/backfill_instructor_permissions.js --dry-run`
   - inspecionar `granted` / `createdEntries` (lockout-risk) vs `already complete`
   - aplicar (sem `--dry-run`), confirmar `APPLIED` e cobertura de todos os pares instrutor não-admin.

3. **`firebase deploy --only firestore:rules`** — só depois do passo 2 confirmado.

4. **`firebase deploy --only storage:rules`** — aditivo, seguro.

5. **`firebase deploy --only firestore:indexes`** — índice aditivo, não destrutivo.

6. **`firebase deploy --only functions`** — `index.js` / `server_functions.js` / `access_control/ingest.js` passam `node --check`. (+1715 em server_functions.js é a maior mudança — smoke-test pós-deploy dos fluxos MP e aula particular.)

**O que NÃO ativar:**
- **`accessControl` (catraca) fica OFF.** Não tocar no master switch em Settings; nenhuma turnstile vendor habilitada em produção. Feature fica latente até decisão explícita.

**O que precisa de release do app Flutter:**
- As telas que consomem o gating granular de instrutor (chamada, lançar cobrança, competições, Settings → Equipe), a UI de aula particular e a de catraca/devices só aparecem para os usuários após **release do app Flutter**. O backend (functions + rules + indexes) pode ir ao ar antes; o app entra depois. Garantir que o release do app saia DEPOIS do backfill+rules para evitar janela em que a UI nova bate em rules que negam.

---

## O que ainda é follow-up (não-bloqueante)

1. **Apertar least-privilege das rules de instrutor:** se aplicar o grace transitório do B1, remover o fallback legado em PR posterior, depois que o backfill popular `extraPermissions` para todos.
2. **Deletar `lib/screens/admin/store_orders_screen.dart`** (AdminStoreOrdersScreen órfã) para evitar reroteamento futuro de uma tela cujos writes seriam negados.
3. **Backfill / hardening de `postType`** nos posts legados de evento (estampar campo ou gatear na presença crua do campo) para fechar o edge case de visibilidade do jornal OFF.
4. **Testes de unit das rules no emulator** como CI gate permanente (hoje só temos dry-run + node --check).
5. **Doc do runbook:** persistir a ordem "backfill → rules → storage → indexes → functions → app release" no runbook de deploy do projeto para os próximos ciclos.