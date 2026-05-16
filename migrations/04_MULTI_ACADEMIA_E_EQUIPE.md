# 04 — Multi-academia & conceito de equipe (audit profundo)

> **Por que este documento existe.** Os docs 01–03 trataram dos *primitivos* técnicos (`userAcademyMapping`, role enum, RLS por `academy_id`) mas não auditaram em profundidade três fluxos que dependem desses primitivos:
>
> 1. **Trocar entre academias** quando o mesmo Firebase uid tem múltiplos vínculos.
> 2. **Conceito de "team"/equipe** — `student.teamId`, `monitor`/`instructor`, monitor groups.
> 3. **Guardian → múltiplos filhos** (potencialmente em academias diferentes).
>
> Este doc fecha essas lacunas, identifica ambiguidades reais do modelo Firestore atual, e sinaliza ajustes que o backend Tatami precisa absorver.

---

## TL;DR

| Subsistema | Status atual no app | Risco | Ação na migração |
|---|---|---|---|
| Multi-academia (estado ativo) | Bem arquitetado — `selectedAcademyIdProvider` + `AcademySwitcher` no shell | 🟢 baixo | Manter o padrão; **adicionar academyId nas URLs** (`/portal/{academyId}/...`) |
| Multi-academia (status=removed) | Modelo permite, código ignora | 🟠 médio | Backend filtra; cliente deixa de mostrar academias removidas |
| Multi-academia (mesmo user com 2 roles) | Role é singular — convenção previne mas nada force | 🟠 médio | Backend deve **rejeitar** explicitamente "admin + student no mesmo academy" ou tratar como prioridade explícita |
| Cross-academy reads | Não existem | 🟢 ok | Não construir até haver demanda — adicionar `GET /v1/me/notifications?across=all` se necessário |
| `student.teamId` | Campo existe, **sem collection `teams`** | 🔴 alto | **Lacuna real** — o Tatami também não tem aggregate `Team`. Decidir agora: criar ou deletar |
| `monitor` vs `instructor` | Dois sistemas separados (`UserRole.instructor` enum + `settings.monitorIds[]`) | 🟠 médio | Unificar: monitor vira `permission` no `extra_permissions` do mapping |
| Co-instrutor | `Class.instructorId` singular — não suportado | 🟠 médio | Backend já tem flexibilidade JSONB; trocar para `instructor_uids text[]` |
| Guardian → filhos | Bidirecional inconsistente (`linkedUserId` único no student, `linkedStudentIds[]` no user) | 🔴 alto | Tornar canônica a tabela `guardian_links(guardian_uid, student_id)` no backend |
| Notificações para guardian quando filho gradua | Não implementado / não confirmado | 🟠 médio | Adicionar regra explícita: ao emitir `notification` com `recipient_uid=student.linked_user_uid`, propagar a todos os guardians |

🔴 = lacuna conceitual real (não só código). 🟠 = código frágil. 🟢 = ok / out-of-scope.

---

## 1. Multi-academia — como funciona hoje

### 1.1 Pilares

A arquitetura no Flutter é dos pontos mais bem feitos do app. Três peças:

**`/lib/providers/selected_academy_provider.dart`**
- `selectedAcademyIdProvider: StateProvider<String?>` — fonte da verdade da academia ativa.
- `SelectedAcademyNotifier._initialize()` lê `userAcademyMappingProvider` e elege:
  1. `selectedAcademyId` se já houver (sessão anterior persistida)
  2. `mapping.primaryAcademyId`
  3. `mapping.academyIds.first`
- `hasMultipleAcademiesProvider` retorna bool — gate para mostrar o switcher.

**`/lib/providers/auth_provider.dart` linhas 109-174**
- Resolve `role` para a academia ativa lendo `mapping.academyDetails[academyId].role`.
- Fallbacks ordenados: `academyDetails[academyId].role` → `academies/{academyId}/users/{uid}.role` → `'student'`.
- Constrói o `AppUser` que **fixa** a role no objeto.

**`/lib/screens/portal/portal_shell.dart` linha 120**
- `AcademySwitcher` no AppBar — chama `SelectedAcademyNotifier.selectAcademy(id)` que muta o `StateProvider` e dispara invalidação dos providers downstream via `.select()`.

### 1.2 O que está bom

- Troca de academia é **barata** (mudança de um `StateProvider`; sem refetch da identidade global).
- Providers downstream observam via `ref.watch(selectedAcademyIdProvider).select(...)` evitando cascata.
- O fallback `primaryAcademyId → academyIds.first` cobre o caso "usuário com 1 academia".

### 1.3 O que precisa mudar na migração

#### a) URL precisa carregar o academyId

Hoje:
```
/portal/students       ← qual academy? "a ativa", implicitamente
/portal/financial
```

Problema: deep-link de notificação push ("seu aluno X graduou") **abre a academia errada** se o `selectedAcademyId` no momento for outra. O ID precisa estar no link.

Proposta:
```
/portal/{academyId}/students
/portal/{academyId}/financial
```

O `go_router` (sugerido no doc 03 §11) lê `state.pathParameters['academyId']` e:
1. Verifica se o caller tem `membership` ativo nessa academy (via `currentUserProvider` que já carrega `memberships`).
2. Se sim, **muta** `selectedAcademyIdProvider` antes de renderizar.
3. Se não, redireciona para `/forbidden` ou `/portal` (academia ativa).

Vantagem secundária: compartilhar link interno entre admins (ex.: "olha esse aluno, /portal/.../students/abc") funciona.

#### b) Filtrar academias com `status='removed'`

`AcademyDetail.status` pode ser `active | inactive | pending | removed` mas o switcher mostra tudo. Resultado: o usuário pode "trocar para" uma academy que ele foi removido, vê tudo vazio (RLS bloqueia), e fica confuso.

No Tatami:
- `GET /v1/me` já retorna `memberships` com `status`.
- O cliente filtra `memberships.where((m) => m.status == 'active')` antes de exibir no switcher.
- Acessar uma academy `removed` retorna **403** com `problem.type = "https://tatami.dev/errors/membership-removed"` para o frontend distinguir de outros 403s.

#### c) Duplo-papel no mesmo academy

Cenário real: a Dona Carla é **admin** da academia (cria a academia) **e** também treina como aluna. Hoje o app força um único `UserRole`. Se a Carla quiser ver "minhas mensalidades" como aluna, a UI esconde porque o role dela é `admin`.

Tatami options:
- **Opção A (recomendada):** `role` é primário; "ver como aluno" é um modo de visualização explícito. O `AppUser` ganha `role: 'admin'` E `linked_student_id: 'xyz'` se aplicável. A UI tem um toggle "Modo aluno" que muta a visualização **sem** mudar a role do request.
- **Opção B:** Permitir `roles[]` como array. Mais flexível, muito mais código.

Eu recomendo **A** — alinhado com o que o backend já modela (`UserAcademyMapping` tem `role` singular + `student_id` opcional).

Comportamento: quando `linked_student_id != null` e `role != student`, a UI de aluno fica disponível **dentro** das telas de admin (ex.: aba "Meu portal de aluno"). Sem trocar nada no backend.

#### d) Cross-academy reads

Hoje: não existem. Cada fetch assume um único academyId.

Demanda futura provável: "Bandeja de notificações UNIFICADA — não importa de qual academy, mostra todas as pendências." Esse é o único caso real.

Solução Tatami:
- `GET /v1/me/notifications` (já existe) já é **per-uid**, não per-academy. Resolve.
- Para qualquer outra cross-academy listagem, criar endpoint dedicado quando aparecer a necessidade — não generalizar antes.

---

## 2. Conceito de "team"/equipe — onde está o buraco

### 2.1 O que o app tem hoje

**Modelo `Student` (`lib/models/student.dart` linha 257):**
```dart
final String? teamId;
```

**Modelo `AcademySettings` (`lib/services/settings_service.dart` linhas 113, 142):**
```dart
final List<String> monitorIds;  // array de STUDENT IDs (não user uids)
```

**Modelo `Competition` (do levantamento do doc 01):**
```dart
// teamPosition, teamNotes, monitorIds
```

### 2.2 O buraco

**Não existe collection `teams` no Firestore.** O `student.teamId` é uma string que aponta para nada — ou aponta para algo que existia em algum momento, foi removido, ou nunca foi modelado.

Procurei: nenhum `team_service.dart`, nenhum `Team` model, nenhuma referência a `/teams/` em paths Firestore. O campo está órfão.

O Tatami também não tem aggregate `Team` (verifiquei o spec — `student.yaml` menciona `team_id` mas não há `/v1/academies/{id}/teams` endpoint).

### 2.3 Decisão a tomar AGORA (não depois da migração)

**Opção 1 — Deletar.**
Se ninguém usa `teamId`, é só dívida. Remove do model do Student no graduabjj, remove da migração 00004 do Tatami. Adicione um campo `category` se a intenção era "kids/adult/competidor" e isso ainda não está coberto.

**Opção 2 — Modelar como aggregate completo.**
Faz sentido se a academia organiza grupos do tipo:
- "Equipe competitiva 2026" — alunos que disputam torneios juntos
- "Turma de adultos noite" — agrupamento de horário, mais leve que `Class` (que é por aula, não por grupo)

Schema sugerido:
```sql
CREATE TABLE teams (
  id          UUID PRIMARY KEY,
  academy_id  UUID NOT NULL REFERENCES academies(id),
  name        TEXT NOT NULL,
  description TEXT,
  category    TEXT,                   -- 'competition' | 'training' | 'social'
  coach_uid   TEXT,                   -- responsável
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE team_members (
  team_id    UUID REFERENCES teams(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  joined_at  TIMESTAMPTZ DEFAULT now(),
  role       TEXT,                    -- 'captain' | 'member'
  PRIMARY KEY (team_id, student_id)
);
```

Endpoints:
```
GET    /v1/academies/{id}/teams
POST   /v1/academies/{id}/teams
PATCH  /v1/academies/{id}/teams/{teamId}
DELETE /v1/academies/{id}/teams/{teamId}
POST   /v1/academies/{id}/teams/{teamId}/members  body: { student_ids[] }
DELETE /v1/academies/{id}/teams/{teamId}/members/{studentId}
```

**Recomendação:** se o produto quer organizar competidores e fazer relatórios "performance da equipe X", **modelar agora**. Se for só agrupamento informal, **deletar e usar `Class` ou tags**. Não deixar o campo `teamId` órfão.

---

## 3. Monitor vs. Instructor — dois sistemas para a mesma ideia

### 3.1 Como está hoje

São conceitos **completamente diferentes** no código:

| Conceito | Onde mora | Quem é |
|---|---|---|
| `UserRole.instructor` (enum) | `AcademyDetail.role` na `userAcademyMapping` | Funcionário/staff da academia |
| `monitor` | Flag derivada de `settings.monitorIds[]` contendo **student IDs** | Aluno avançado com acesso a algumas funções de staff |

Em `portal_shell.dart` linhas 137-143:
```dart
final allStudentIds = [studentId, ...linkedStudentIds];
final isMonitor = allStudentIds.any((id) => settings.monitorIds.contains(id));
```

### 3.2 Por que isso é frágil

- Dois sistemas de permissão. Code de UI precisa checar **ambos** (`role == instructor || isMonitor`) para decidir mostrar a tela de chamada.
- `settings.monitorIds` é um array em um documento de settings — não tem audit, mudança não dispara notificação.
- Se um aluno marcado como monitor sai da academia, ninguém limpa o `monitorIds`.

### 3.3 Como migrar no Tatami

**Unificar como permissão granular** no `user_academy_mappings.extra_permissions[]`:

```sql
-- Migração para popular:
INSERT INTO user_academy_mappings (uid, academy_id, role, student_id, extra_permissions)
SELECT
  s.linked_user_uid,
  s.academy_id,
  'student',
  s.id,
  ARRAY['monitor.attendance.write', 'monitor.students.read']
FROM students s
JOIN academy_settings ast ON ast.academy_id = s.academy_id
WHERE s.id = ANY(ast.monitor_student_ids)
  AND s.linked_user_uid IS NOT NULL;
```

Daí:
- Frontend: `currentUser.permissions.contains('monitor.attendance.write')` ao invés de `isMonitor`.
- Backend: `authz.RequirePermission("monitor.attendance.write")` middleware.
- Vantagem: granular (um aluno pode ter `monitor.attendance.write` mas não `monitor.students.read`).
- O conceito `monitor` desaparece como nome especial — é só uma combinação de permissions.

Endpoint de gestão:
```
POST   /v1/academies/{id}/memberships/{uid}/permissions  body: { add: ['monitor.attendance.write'] }
DELETE /v1/academies/{id}/memberships/{uid}/permissions  body: { remove: [...] }
```

---

## 4. Co-instrutor (uma classe, dois instrutores)

### Hoje
```dart
class BJJClass {
  final String? instructorId;   // SINGULAR
  final String? instructorName; // denormalized
}
```

### Limitação real

Academias com programas paralelos (ex.: BJJ + Muay Thai na mesma aula, ou aula com instrutor titular + auxiliar) **não** conseguem registrar isso. O cliente acaba escolhendo um e ignorando o outro.

### Como o Tatami pode resolver

Schema da `classes`:
```sql
ALTER TABLE classes
  ADD COLUMN instructor_uids TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN primary_instructor_uid TEXT;

-- Migração: copiar instructor_id existente para primary + array
UPDATE classes SET
  primary_instructor_uid = instructor_id,
  instructor_uids = ARRAY[instructor_id]
WHERE instructor_id IS NOT NULL;
```

API:
```
PATCH /v1/academies/{id}/classes/{classId}
  body: { instructor_uids: ["uid1", "uid2"], primary_instructor_uid: "uid1" }
```

`primary_instructor_uid` é quem aparece em listagens enxutas; `instructor_uids` é o conjunto completo (todos recebem notificações da turma, todos podem marcar chamada).

---

## 5. Guardian → múltiplos filhos (e o reverso)

### Como está

**Lado student:**
```dart
class Student {
  final String? linkedUserId;  // 1 guardian uid — não array!
}
```

**Lado user (cached):**
```dart
class AppUser {
  final List<String>? linkedStudentIds;  // array
}
```

### Problemas

1. **Cardinalidade quebrada.** Um aluno só pode ter **1 guardian** linkado, mas a vida real tem mãe + pai + tio responsável. Hoje quem chega segundo "rouba" o slot.
2. **Sincronização manual.** Quando o aluno é vinculado, o backend (Cloud Function?) precisa atualizar **dois lugares**: `student.linkedUserId` e `user.linkedStudentIds`. Se falha em um, fica inconsistente.
3. **Sem audit.** Não há histórico de "quando este guardian foi vinculado", "por quem", "se foi desvinculado".

### Solução canônica no Tatami

Tabela de associação `guardian_links`:

```sql
CREATE TABLE guardian_links (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid_v7(),
  guardian_uid TEXT NOT NULL,
  student_id   UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  academy_id   UUID NOT NULL REFERENCES academies(id),
  relationship TEXT,                  -- 'mother' | 'father' | 'legal_guardian' | 'other'
  is_primary   BOOLEAN DEFAULT false, -- quem recebe push primário
  linked_at    TIMESTAMPTZ DEFAULT now(),
  linked_by    TEXT,                  -- uid de quem criou o link
  unlinked_at  TIMESTAMPTZ,
  unlinked_by  TEXT,
  notes        TEXT,

  UNIQUE (guardian_uid, student_id) WHERE unlinked_at IS NULL
);

CREATE INDEX guardian_links_by_student ON guardian_links(student_id) WHERE unlinked_at IS NULL;
CREATE INDEX guardian_links_by_guardian ON guardian_links(guardian_uid) WHERE unlinked_at IS NULL;
```

Endpoints:
```
GET    /v1/academies/{id}/students/{studentId}/guardians
POST   /v1/academies/{id}/students/{studentId}/guardians  body: { guardian_uid, relationship, is_primary }
PATCH  /v1/.../guardians/{linkId}                          body: { is_primary?, relationship? }
DELETE /v1/.../guardians/{linkId}                          (soft-unlink: seta unlinked_at)
GET    /v1/me/wards                                        (do lado do guardian: quem são meus filhos?)
```

### Notificações para guardians

Hoje: presumido — quando o aluno gradua, manda pra `student.linkedUserId`. Único guardian.

Com `guardian_links` plural, o flow vira:

```go
// internal/notification/application/service.go (extensão)
func (s *Service) CreateForStudentRecipients(ctx, studentID, academyID, in CreateInput) error {
    targets := []string{}
    // 1. próprio aluno (se tem linked_user_uid)
    if uid := s.students.LinkedUID(ctx, studentID); uid != "" {
        targets = append(targets, uid)
    }
    // 2. todos os guardians ativos
    guardians, _ := s.guardians.ListByStudent(ctx, studentID)
    for _, g := range guardians {
        targets = append(targets, g.GuardianUID)
    }
    for _, uid := range targets {
        s.Create(ctx, in.WithRecipient(uid))
    }
    return nil
}
```

Resultado: pai + mãe + aluno recebem a notificação de graduação. Sem código duplicado no chamador.

---

## 6. Permissões — strings vão virar typo

### Hoje

`AcademyDetail.extraPermissions: List<String>` aceita qualquer coisa: `'financial:view'`, `'financial.view'`, `'financialView'`, `'finance:read'` — todos diferentes, todos errados em algum lugar.

### Tatami

Definir um catálogo enum-like em `internal/identity/domain/permission.go`:

```go
type Permission string

const (
    PermAttendanceWrite       Permission = "attendance.write"
    PermAttendanceRead        Permission = "attendance.read"
    PermStudentsRead          Permission = "students.read"
    PermStudentsWrite         Permission = "students.write"
    PermFinancialRead         Permission = "financial.read"
    PermFinancialWrite        Permission = "financial.write"
    PermFinancialMarkPaid     Permission = "financial.mark_paid"
    PermPlansWrite            Permission = "plans.write"
    PermClassesWrite          Permission = "classes.write"
    PermCompetitionsWrite     Permission = "competitions.write"
    PermStoreWrite            Permission = "store.write"
    PermSettingsWrite         Permission = "settings.write"
    PermMembershipsWrite      Permission = "memberships.write"
    PermBroadcastNotification Permission = "notifications.broadcast"
)

var validPermissions = map[Permission]bool{
    PermAttendanceWrite: true, /* ... */
}

func IsValidPermission(p Permission) bool { return validPermissions[p] }
```

Mapping `Role → set of Permissions` default + `extra_permissions` override:

```go
var roleDefaults = map[Role][]Permission{
    RoleAdmin: { /* tudo */ },
    RoleInstructor: { PermAttendanceWrite, PermStudentsRead, PermClassesWrite },
    RoleMonitor:    { PermAttendanceWrite, PermStudentsRead }, // role "monitor" passa a existir explicitamente
    RoleStudent:    { /* só auto-leitura */ },
    RoleGuardian:   { /* auto-leitura dos linked_students */ },
}

func ResolvePermissions(role Role, extras []Permission) []Permission {
    set := map[Permission]bool{}
    for _, p := range roleDefaults[role] { set[p] = true }
    for _, p := range extras { if IsValidPermission(p) { set[p] = true } }
    // ... return as slice
}
```

Backend valida na ingestão (`POST /v1/academies/{id}/memberships/{uid}/permissions`) rejeitando string desconhecida com 422.

Frontend mostra um picker UI com os valores conhecidos — typo impossível.

---

## 7. Checklist de migração — multi-academia & equipe

### a) No Tatami (backend)

- [ ] Adicionar `Role = monitor` ao enum (hoje só admin/instructor/student/guardian — graduabjj precisa).
- [ ] Definir `Permission` catalog em `internal/identity/domain/permission.go` (item 6 acima).
- [ ] Migração SQL para popular `extra_permissions` a partir de `settings.monitorIds` legado.
- [ ] Migração para `guardian_links` (substitui `student.linked_user_uid` singular).
- [ ] Alterar `students.team_id` — decidir: **dropar** OU criar contexto `team` completo.
- [ ] Alterar `classes` para `instructor_uids text[]` + `primary_instructor_uid`.
- [ ] Endpoint `GET /v1/me/wards` (guardian lista filhos).
- [ ] `NotificationService.CreateForStudentRecipients()` propagando para todos os guardians.
- [ ] `problem.type` distinto para `membership-removed` (vs. `forbidden` genérico).

### b) No graduabjj (frontend)

- [ ] `go_router` com `/portal/{academyId}/*` (item 1.3.a).
- [ ] Filtrar `memberships.where(status == 'active')` no `AcademySwitcher`.
- [ ] Trocar `isMonitor` derivado por `currentUser.permissions.contains('attendance.write')`.
- [ ] Trocar `student.linkedUserId` (single) por chamada a `GET /v1/.../students/{id}/guardians`.
- [ ] No portal do guardian: `GET /v1/me/wards` substitui `currentUser.linkedStudentIds`.
- [ ] Aba "Modo aluno" em telas de admin se `linked_student_id != null`.
- [ ] Remover dependência de `student.teamId` se o produto decidir dropar.

### c) Decisões pendentes (alinhar com produto antes da migração)

1. **Team é coisa real ou dívida?** Se real, qual o conceito — competição, treino, social?
2. **Múltiplos guardians por aluno é caso de uso?** (Quase certo que sim — pais separados, parentes responsáveis.)
3. **Co-instrutor é caso de uso?** Avaliar via entrevista com 2-3 academias.
4. **"Modo aluno" em conta de admin** é demanda real? Decide se Tatami precisa mudar o conceito de role.

---

## 8. O que o backend Tatami pode ter deixado de cobrir

Revisando o spec atual do Tatami à luz desta análise:

| Item | Estado no Tatami | Ajuste necessário |
|---|---|---|
| `Role` enum | `admin\|instructor\|student\|monitor\|guardian` ✅ | Já tem `monitor` |
| `extra_permissions` | `text[]` no `user_academy_mappings` ✅ | Adicionar catálogo `Permission` validado |
| `student.team_id` | UUID column ❓ | Decidir antes de codificar handlers |
| Endpoint de teams | ❌ não existe | Criar `team.yaml` se for opção 2 do §2.3 |
| Co-instrutor (`classes.instructor_uids[]`) | ❌ singular | Migração para array |
| `guardian_links` table | ❌ não existe | Criar migração + endpoints |
| `GET /v1/me/wards` | ❌ não existe | Spec a adicionar |
| Notificação propagada para guardians | ❌ não implementado | Estender `NotificationService` |
| `problem.type=membership-removed` | ❌ genérico | Tipo dedicado |

Essas são lacunas do backend que valem ser corrigidas **antes** do graduabjj migrar — caso contrário o cliente vai ter que reimplementar workarounds que já existem hoje no Firestore.

---

## Conclusão honesta

O Tatami cobriu **muito bem** os primitivos (RLS, mapping (uid, academy_id), role enum). Cobriu **mal**:

- `Team` é um campo órfão tanto no graduabjj quanto no Tatami — ninguém modelou de fato.
- `Monitor` foi tratado como role no Tatami, mas no graduabjj é uma flag derivada de array — a tradução não está feita.
- Guardian-múltiplo é uma realidade que nem o app nem o backend modelam.
- Co-instrutor idem.

Nenhuma dessas lacunas impede a migração — mas se forem ignoradas, viram tech-debt do dia 1 da release. Cada uma é **uma migração SQL + um endpoint OpenAPI + ~50 linhas de service**. Vale corrigir antes de portar o frontend.
