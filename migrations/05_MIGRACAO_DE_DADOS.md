# 05 — Migração de dados Firestore → Postgres

> **Por que este doc é o mais crítico.** Os docs 01–04 falam de **código**. Este doc fala de **dados**. Migração de dados malfeita é a forma mais comum de quebrar uma migração: você termina o backend, libera o frontend, e descobre que a tabela `students` no Postgres tem 200 registros enquanto o Firestore tem 1.847. Ou pior: estão lá mas com `belt = 'azul'` (em português) enquanto o backend espera `belt = 'blue'`. Esses bugs não aparecem em PR review — aparecem no app quebrado dos usuários.
>
> Este doc é o runbook completo: descoberta → mapeamento → ETL → validação → corte → rollback.

---

## 1. Princípios

1. **Forward-only no banco, idempotente no ETL.** Migrações Postgres avançam; o script de carga pode ser rodado 10 vezes sem corromper.
2. **Dual-write antes do cutover.** Por uma semana mínima, escritas vão para Firestore **e** Postgres. Leituras podem trocar gradualmente.
3. **Diff contínuo.** Job que compara contagens e checksums Firestore vs Postgres a cada hora; alerta se divergir.
4. **Cutover é one-way.** Quando viramos a chave, leituras vão 100% para Postgres. Rollback = re-deploy do app antigo + restore do Firestore (que continua intocado durante o dual-write).
5. **Nada de hard-delete durante a transição.** Soft-delete em Firestore garante que dados "removidos" continuam disponíveis no rollback.

---

## 2. Inventário de descoberta (executar ANTES de qualquer código)

Sem números reais, o resto é palpite. Rode este script no Firebase project `arpjj-76350` antes de mais nada:

```bash
# scripts/firestore-discovery.sh
#!/bin/bash
# Conta documentos por collection group e mede tamanho médio.
# Output: discovery.csv

gcloud config set project arpjj-76350

# Para cada collection group, conta agregada e amostra 100 docs para tamanho
COLLECTIONS=(
  "users"
  "userAcademyMapping"
  "academies"
  "academies/*/students"
  "academies/*/classes"
  "academies/*/attendance"
  "academies/*/plans"
  "academies/*/financials"
  "academies/*/wallet"
  "academies/*/walletTransactions"
  "academies/*/competitions"
  "academies/*/competitionEnrollments"
  "academies/*/competitionResults"
  "academies/*/competitionPhotos"
  "academies/*/achievements"
  "academies/*/beltProgressions"
  "academies/*/assessments"
  "academies/*/storeProducts"
  "academies/*/storeOrders"
  "academies/*/notifications"
  "academies/*/billingContactLog"
  "academies/*/linkCodes"
  "academies/*/instructorLinkCodes"
  "academies/*/settings"
)

echo "collection,doc_count,avg_size_bytes,total_size_mb" > discovery.csv

for col in "${COLLECTIONS[@]}"; do
  # Implementação: use Firestore REST API com pageSize=1 retornando total_count
  # OU export para BigQuery e SELECT count(*).
  # Pseudo-código abaixo — preencher no run real.
  echo "→ $col"
done
```

**Output esperado** (template para você preencher):

| Collection | Doc count | Avg size | Total | Comentário |
|---|---|---|---|---|
| users | ? | ? | ? | escala com nº de usuários globais (provavelmente milhares) |
| userAcademyMapping | ? | ? | ? | ≈ users |
| academies | ? | ? | ? | dezenas |
| students (agregado) | ? | ? | ? | provavelmente ~200/academia × N academias |
| attendance (agregado) | ? | ? | ? | **a maior** — N alunos × frequência × tempo |
| financials | ? | ? | ? | ≈ alunos × meses |
| competitionPhotos | ? | ? | ? | **maior por bytes** (URLs apontam para Storage; docs leves) |

**Por que importa.** Determina:
- Estratégia de export (Firestore → GCS export funciona até alguns GB; BigQuery acima).
- Janela de cutover (dual-write de 1k docs/dia é trivial; de 1M docs/dia exige Pub/Sub).
- Se vale a pena particionar (`attendance` precisa de partitioning desde o dia 1; `competitions` não).

---

## 3. Mapeamento campo-a-campo — a tabela canônica

Para cada collection, uma seção com 4 colunas: **Firestore path → Postgres column → Type conversion → Edge cases**.

A não-trivialidade está nas conversões. Vou cobrir as armadilhas reais.

### 3.1 `users/{uid}` → `global_users`

| Firestore | Postgres | Conversão | Edge cases |
|---|---|---|---|
| (doc id) | `uid TEXT PK` | string raw | Firebase UID, **não UUID**. Manter como text. |
| `email` | `email CITEXT` | string | Lowercase via `citext`. Validar formato no import — alguns docs podem ter strings sujas. |
| `displayName` | `display_name TEXT` | string | Vazio = NULL, não `""`. |
| `photoUrl` | `photo_url TEXT` | string | Pode apontar para `googleusercontent.com` (Google Sign-In). Manter. |
| `phone` | `phone TEXT` | string | **Normalizar** para E.164 (`+55119...`). Telefones em `(11) 99999-9999` no banco velho. |
| `birthDate` | `birth_date DATE` | Timestamp → date (UTC). | Firestore Timestamp; só a porção da data. Cuidado com TZ. |
| `cpf` | `cpf TEXT` | string | Remover pontuação: `123.456.789-09` → `12345678909`. Validar checksum CPF. |
| `weight` | `weight_kg NUMERIC(5,2)` | número → decimal | Validar `> 0`. Há docs com `"75kg"` string — limpar. |
| `accountType` | `account_type TEXT` | enum | Valores válidos: `free`, `linked`. Default `free`. |
| `jiujitsuStartDate` | `jiujitsu_start_date DATE` | Timestamp → date | Nullable. |
| `highestBelt` | `highest_belt TEXT` | enum | Valores válidos PT→EN: `branca→white`, `azul→blue`, `roxa→purple`, `marrom→brown`, `preta→black`, `cinza→kids_grey`, `amarela→kids_yellow`, `laranja→kids_orange`, `verde→kids_green`. **Há docs com PT, EN, abreviações** (`'wht'`, `'b'`). Mapping table abaixo. |
| `highestStripes` | `highest_stripes SMALLINT` | int | Validar `0 ≤ s ≤ 4`. |
| `isProfilePublic` | `is_profile_public BOOLEAN` | bool | Default `false`. |
| `createdAt` | `created_at TIMESTAMPTZ` | Timestamp → tz-aware | Pode estar como `serverTimestamp()` ou `Timestamp` ou string ISO. Tratar 3 casos. |
| `updatedAt` | `updated_at TIMESTAMPTZ` | idem | idem |

**Belt translation table** (canônico):

```python
BELT_NORMALIZE = {
    # PT-BR
    "branca": "white", "branco": "white",
    "azul": "blue",
    "roxa": "purple", "roxo": "purple",
    "marrom": "brown",
    "preta": "black", "preto": "black",
    "cinza": "kids_grey", "cinza-branca": "kids_grey",
    "amarela": "kids_yellow", "amarelo": "kids_yellow",
    "laranja": "kids_orange",
    "verde": "kids_green",
    # EN (já correto)
    "white": "white", "blue": "blue", "purple": "purple", "brown": "brown", "black": "black",
    "kids_grey": "kids_grey", "kids_yellow": "kids_yellow", "kids_orange": "kids_orange", "kids_green": "kids_green",
    # Variações sujas
    "wht": "white", "b": None,  # ambiguo, exigir intervenção manual
}
```

Documentos cujo valor cai em `None` ficam em **DLQ (dead-letter queue)** — uma planilha para revisão humana.

### 3.2 `userAcademyMapping/{uid}` → `user_academy_mappings`

Este é o mais complicado: cada doc Firestore vira **N rows** no Postgres (uma por academy).

```python
# Pseudo-código de transformação
def transform_mapping(doc):
    uid = doc.id
    academy_ids = doc.get('academyIds', [])
    primary = doc.get('primaryAcademyId')
    details = doc.get('academyDetails', {})

    rows = []
    for academy_id in academy_ids:
        d = details.get(academy_id, {})
        rows.append({
            'uid': uid,
            'academy_id': academy_id,
            'role': normalize_role(d.get('role', 'student')),
            'student_id': d.get('studentId'),  # nullable
            'joined_at': d.get('joinedAt') or doc.get('createdAt'),
            'status': d.get('status', 'active'),
            'extra_permissions': normalize_perms(d.get('extraPermissions', [])),
            'is_primary': (academy_id == primary),  # vai virar denormalização
        })
    return rows
```

Casos especiais:
- `academyIds` tem ID que **não existe** em `details` → criar row com defaults + flag de "incomplete_mapping" no `linhas_dlq`.
- `primaryAcademyId` aponta para academy que não existe → setar `primary_academy_id` em `global_users` como NULL e logar.
- `details` tem chave que **não está** em `academyIds` → órfão, ignorar (mas logar).

### 3.3 `academies/{academyId}` → `academies`

| Firestore | Postgres | Notas |
|---|---|---|
| (doc id) | `id UUID` | **Conversão crítica.** Firestore IDs são strings auto-geradas (20 chars). Precisamos de UUIDs no Postgres. Estratégia: derivar UUID determinístico a partir do doc id via `uuid_v5(NAMESPACE_DNS, "academies/" + doc_id)`. **Imutável + reproduzível**. Crítico: o frontend precisa do mesmo mapping para que deep-links antigos não quebrem. |
| `name`, `slug`, `cnpj`, `email`, `phone` | mesma coisa | Normalizar CNPJ removendo pontuação. |
| `pixKey`, `pixKeyType` | mesmo | Enum: `cpf|cnpj|email|phone|random` |
| `address.*` | `address_street`, `address_city`, etc | Flatten do nested object. |
| `subscription.plan` | `subscription_plan` | Flatten. |
| `subscription.status` | `subscription_status` | idem |
| `subscription.expiresAt` | `subscription_expires_at` | timestamp |
| `abacatePayEnabled`, `asaasEnabled` | bool | |
| `asaasOnboardingStatus` | enum | `pending|approved|rejected` |
| `asaasApiKey` (legacy?) | `→ asaas_sub_accounts.encrypted_api_key` | **Criptografar** com AES-256-GCM antes de inserir (item `internal/platform/crypto`). |
| `autoGraduationEnabled` | bool | |
| `autoGraduationAttendances` | int | |
| `useClassWeights` | bool | |
| `storeEnabled`, `storePublished` | bool | |
| `studentCheckinEnabled` | bool | |
| `ownerId` | `owner_uid TEXT` | É o Firebase UID do dono. |
| `createdAt`, `updatedAt` | timestamptz | |

**Settings nested** (`academies/{id}/settings/*`) — converter para JSONB `academies.settings` OU manter na tabela separada `academy_settings(academy_id, key, value)` que o backend já modela. Recomendado: a tabela separada (queryable, audita-vel).

### 3.4 `academies/{academyId}/students/{studentId}` → `students`

Esta é a tabela com **mais armadilhas**.

| Firestore | Postgres | Notas |
|---|---|---|
| (doc id) | `id UUID` | Mesmo truque do academy — uuid_v5 determinístico. |
| `academyId` (implícito no path) | `academy_id UUID` | Resolver via path do parent. |
| `fullName` | `full_name TEXT` | Trim + Title Case (cliente entra com tudo maiúsculo às vezes). |
| `nickname` | `nickname TEXT` | nullable |
| `birthDate` | `birth_date DATE` | TZ awareness |
| `cpf`, `rg` | text | Normalizar |
| `phone`, `email` | text | Normalizar |
| `photoUrl` | text | Pode apontar pra Firebase Storage — **mantemos a URL existente durante a transição** (sem mover bytes). Renomear de `photoUrl` (Firebase) para `photo_path` no schema final, mas durante migração: 2 colunas (`legacy_photo_url`, `photo_path`) e `COALESCE` na leitura. |
| `address.*` | flatten | |
| `guardian.*` (kids) | flatten OU JSONB | Recomendo JSONB `guardian` para preservar estrutura. |
| `startDate`, `jiujitsuStartDate` | dates | |
| `currentBelt` | `current_belt TEXT` | Usar `BELT_NORMALIZE`. |
| `currentStripes` | smallint | 0–4 |
| `category` | enum | `kids|adult` |
| `teamId` | `team_id UUID nullable` | **Lembrar:** doc 04 §2 — decidir antes se vai dropar ou criar `teams`. Se dropar, ignorar este campo. |
| `weight` | `weight_kg NUMERIC` | |
| `beltHistory[]` | **destino: `belt_progressions` rows separadas** | Cada item vira uma row em `belt_progressions`. Carregar via ETL separado. |
| `status` | enum | `active|injured|inactive|suspended|removed` |
| `statusNote` | text | |
| `tuitionValue`, `tuitionDay` | numeric / int | |
| `planId` | uuid (nullable) | Resolver via uuid_v5 |
| `medicalCertificateUrl` | text → `medical_certificate_path` | Igual à foto: 2 colunas durante transição |
| `healthNotes`, `bloodType`, `allergies`, `emergencyContact` | text | |
| `linkedUserId` | `linked_user_uid TEXT` | É o Firebase UID. |
| `isProfilePublic` | bool | |
| `attendanceCount`, `initialAttendanceCount` | int | **CUIDADO:** o `attendance_count` no Postgres é mantido por trigger. **Não copiar.** Em vez disso, deixar o trigger contabilizar quando os attendance rows forem carregados. `initial_attendance_count` é uma migração legada — sim, copiar (representa presenças anteriores ao sistema). |
| `sportsList`, `primarySport`, `sportData` | text[] / text / jsonb | Manter JSONB para `sport_data` (estrutura é dinâmica). |
| `createdAt`, `updatedAt` | timestamptz | |

### 3.5 `academies/{academyId}/attendance/{id}` → `attendance` (particionada)

Volume típico: maior tabela do banco. Estratégia diferente.

```python
def transform_attendance(doc, academy_id_uuid):
    return {
        'id': uuid_v5(NS, f"attendance/{doc.id}"),
        'academy_id': academy_id_uuid,
        'student_id': uuid_v5(NS, f"students/{doc.get('studentId')}"),
        'class_id':   uuid_v5(NS, f"classes/{doc.get('classId')}"),
        'date': doc.get('date').date(),
        'verified_by_uid': doc.get('verifiedBy') or doc.get('createdBy'),
        'weight': float(doc.get('weight') or 1.0),
        'created_at': doc.get('createdAt'),
    }
```

**Importante:** carregar attendance **DEPOIS** de criar students + classes (FKs). E **DESLIGAR** o trigger de `update_attendance_count` durante o bulk INSERT — fazer um `UPDATE students SET attendance_count = (SELECT count(*) ...)` ao final do batch. Senão você paga 50k UPDATE triggers em vez de um único.

```sql
-- Antes do bulk INSERT
ALTER TABLE attendance DISABLE TRIGGER update_attendance_count;

-- Bulk INSERT

-- Recalcular contadores
UPDATE students s
SET attendance_count = COALESCE((
  SELECT COUNT(*) FROM attendance a WHERE a.student_id = s.id
), 0);

-- Religar
ALTER TABLE attendance ENABLE TRIGGER update_attendance_count;
```

### 3.6 Demais collections (tabela enxuta)

| Firestore | Postgres | Notas críticos |
|---|---|---|
| `classes` | `classes` + `class_students` join | **Quebrar** o array `studentIds[]` em rows da tabela join. |
| `plans` | `plans` + `plan_students` | Idem. |
| `financials` | `financials` | `amount` para `numeric(12,2)`. `status` enum. `referenceMonth` `'YYYY-MM'` texto. |
| `wallet` (1 doc por academy) | `wallets` (1 row) | Skip se não existir. |
| `walletTransactions` | `wallet_transactions` (particionada) | Mesmo cuidado da attendance: bulk + recompute final. |
| `competitions` | `competitions` | |
| `competitionEnrollments` | `competition_enrollments` | Unique (competition_id, student_id, modality). Tratar duplicatas. |
| `competitionResults` | `competition_results` | |
| `competitionPhotos` | `competition_photos` | URLs mantidas durante transição. |
| `achievements` | `achievements` | Tipo enum: `graduation|stripe|competition|milestone`. |
| `beltProgressions` | `belt_progressions` | **Ordem importa**: histórico + `effectiveCountAtPromotion` para auto-graduação. Carregar **antes** de attendance, ou rerun do recompute final precisa considerar. |
| `assessments` | `assessments` | kids. JSONB para `scores`. |
| `storeProducts` | `store_products` | |
| `storeOrders` | `store_orders` | `items` é JSONB. |
| `notifications` | `notifications` | **Decidir:** copiar histórico inteiro? Sugiro **só últimos 90 dias** + flag de "migrado". Histórico antigo fica no Firestore como arquivo morto. |
| `billingContactLog` | `billing_contact_logs` | |
| `linkCodes` | `link_codes` | Importar só **não-expirados** (`expires_at > now()`). Códigos expirados são lixo. |
| `instructorLinkCodes` | `instructor_link_codes` | idem |
| `settings` | `academy_settings` | Cada doc vira uma row (key, value). |

---

## 4. Arquitetura do ETL

Três opções, escolha por **volume**:

### Opção A — Firestore export → GCS → BigQuery → Postgres (recomendada)

```
[Firestore]
   │ (gcloud firestore export)
   ▼
[GCS bucket: gs://tatami-migration/2026-05-15/]
   │ (bq load)
   ▼
[BigQuery dataset: arpjj_firestore_snapshot]
   │ (Python script + COPY ... FROM STDIN)
   ▼
[Postgres tatami_app]
```

Vantagens:
- BigQuery permite **SQL** em cima do snapshot. Você consegue rodar `SELECT count(*) FROM academies` em segundos, sem rodar contra produção.
- Export do Firestore é **consistente** (snapshot point-in-time).
- O job de transformação fica em SQL + um pouco de Python. Reusável.

Desvantagens:
- BigQuery cobra storage (não muito) e queries (muito pouco para o tamanho que provavelmente temos).

Comandos canônicos:

```bash
# 1) Export Firestore para GCS (~5-30 min dependendo de tamanho)
gcloud firestore export gs://tatami-migration/$(date +%F) \
  --collection-ids=users,userAcademyMapping,academies

# 2) Subcollections precisam ser exportadas via collection group
gcloud firestore export gs://tatami-migration/$(date +%F) \
  --collection-ids=students,attendance,classes,plans,financials,...

# 3) Carregar no BigQuery (auto-detect)
bq mk --location=us-central1 arpjj_firestore_snapshot
bq load --source_format=DATASTORE_BACKUP \
  arpjj_firestore_snapshot.users \
  gs://tatami-migration/.../users.export_metadata
# (repetir por collection)

# 4) Rodar transformação SQL (ver §5)
bq query --use_legacy_sql=false < transforms/users.sql > /tmp/users.tsv

# 5) Carregar no Postgres
psql "$TATAMI_DB_DSN" -c "\\copy global_users FROM '/tmp/users.tsv' WITH (FORMAT csv, HEADER true);"
```

### Opção B — Dataflow / Apache Beam (se volume gigante)

Só se a tabela `attendance` ultrapassar 10M rows. Beam permite streaming + transformação paralela. Custo é Cloud Dataflow.

### Opção C — Script Python direto (se volume pequeno)

Para volumes pequenos (até ~100k docs por collection), um script Python com `firebase-admin` + `psycopg2` resolve, sem GCS intermediário. Bom para academias pequenas no estágio MVP.

```python
# scripts/migrate_users.py — exemplo
from google.cloud import firestore
import psycopg2
import psycopg2.extras

fs = firestore.Client(project='arpjj-76350')
pg = psycopg2.connect(TATAMI_DB_DSN)

with pg.cursor() as cur:
    cur.execute("BEGIN")
    psycopg2.extras.execute_batch(cur, """
        INSERT INTO global_users (uid, email, display_name, ...)
        VALUES (%(uid)s, %(email)s, %(display_name)s, ...)
        ON CONFLICT (uid) DO UPDATE SET
          email = EXCLUDED.email,
          updated_at = now()
    """, transform_batch(fs.collection('users').stream()))
    cur.execute("COMMIT")
```

**Sempre** usar `ON CONFLICT DO UPDATE` — torna o script re-executável.

---

## 5. Transformações SQL (BigQuery) — exemplo

Pasta `migrations/etl/transforms/`:

```sql
-- transforms/global_users.sql
SELECT
  __key__.name AS uid,
  LOWER(TRIM(email)) AS email,
  NULLIF(TRIM(displayName), '') AS display_name,
  photoUrl AS photo_url,
  -- E.164 normalization
  CASE
    WHEN phone LIKE '+%' THEN phone
    WHEN LENGTH(REGEXP_REPLACE(phone, r'\D', '')) = 11
      THEN CONCAT('+55', REGEXP_REPLACE(phone, r'\D', ''))
    ELSE NULL
  END AS phone,
  CAST(birthDate AS DATE) AS birth_date,
  REGEXP_REPLACE(cpf, r'\D', '') AS cpf,
  CAST(weight AS NUMERIC) AS weight_kg,
  IFNULL(LOWER(accountType), 'free') AS account_type,
  CAST(jiujitsuStartDate AS DATE) AS jiujitsu_start_date,
  -- Belt normalization
  CASE LOWER(highestBelt)
    WHEN 'branca' THEN 'white'
    WHEN 'azul' THEN 'blue'
    WHEN 'roxa' THEN 'purple'
    WHEN 'roxo' THEN 'purple'
    WHEN 'marrom' THEN 'brown'
    WHEN 'preta' THEN 'black'
    WHEN 'preto' THEN 'black'
    WHEN 'cinza' THEN 'kids_grey'
    WHEN 'amarela' THEN 'kids_yellow'
    WHEN 'laranja' THEN 'kids_orange'
    WHEN 'verde' THEN 'kids_green'
    -- already-normalized values pass through
    WHEN 'white' THEN 'white' WHEN 'blue' THEN 'blue' WHEN 'purple' THEN 'purple'
    WHEN 'brown' THEN 'brown' WHEN 'black' THEN 'black'
    ELSE 'white'  -- safe default; log original separately
  END AS highest_belt,
  GREATEST(0, LEAST(4, CAST(highestStripes AS INT64))) AS highest_stripes,
  IFNULL(isProfilePublic, FALSE) AS is_profile_public,
  createdAt AS created_at,
  updatedAt AS updated_at
FROM `arpjj_firestore_snapshot.users`
WHERE __key__.name IS NOT NULL;
```

Um arquivo `.sql` por tabela. Comentar as decisões. Salvar o output em GCS (tabela `arpjj_firestore_snapshot.global_users_normalized`) para fácil re-execução do load Postgres.

---

## 6. Validação pós-carga

Não confie em "o job rodou OK". Sempre rode estas verificações:

### 6.1 Contagens

```sql
-- Postgres
SELECT 'global_users' AS tbl, count(*) FROM global_users
UNION ALL SELECT 'students',         count(*) FROM students
UNION ALL SELECT 'attendance',       count(*) FROM attendance
UNION ALL SELECT 'financials',       count(*) FROM financials
UNION ALL SELECT 'classes',          count(*) FROM classes
UNION ALL SELECT 'user_academy_mappings', count(*) FROM user_academy_mappings;
```

Comparar com:

```sql
-- BigQuery
SELECT 'users' AS coll, COUNT(*) FROM `arpjj_firestore_snapshot.users`
UNION ALL
SELECT 'students', COUNT(*) FROM `arpjj_firestore_snapshot.students`
-- ...
```

**Diferenças aceitáveis:**
- `userAcademyMapping` tem 1 doc / user. `user_academy_mappings` Postgres tem N rows / user (uma por academy). A diferença é matematicamente o total de `academyIds.length`.
- `notifications` se cortamos > 90 dias: documentar a diferença esperada.

**Diferenças NÃO aceitáveis:**
- Qualquer outra coisa.

### 6.2 Checksums por academy

Para cada academia, calcule um hash agregado dos campos críticos:

```sql
-- Postgres
SELECT academy_id, md5(string_agg(id::text || '|' || full_name || '|' || current_belt, ',' ORDER BY id)) AS checksum
FROM students GROUP BY academy_id;
```

Tem que bater com BigQuery (com o mesmo agregado, ajustando para o source).

### 6.3 Integridade referencial

```sql
-- Attendance órfã (student não existe)
SELECT count(*) FROM attendance a
WHERE NOT EXISTS (SELECT 1 FROM students s WHERE s.id = a.student_id);

-- Financial sem student
SELECT count(*) FROM financials f
WHERE student_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM students s WHERE s.id = f.student_id);

-- belt_progressions sem student
-- ... (uma checagem por FK)
```

Qualquer count > 0 indica que o ETL pulou um parent. Investigar.

### 6.4 Sanity values

```sql
-- Estoque negativo
SELECT id, name, stock_quantity FROM store_products WHERE stock_quantity < 0;

-- attendance no futuro
SELECT count(*) FROM attendance WHERE date > current_date + INTERVAL '1 day';

-- Tuition negativa
SELECT count(*) FROM students WHERE tuition_value < 0;

-- Stripe count fora do range
SELECT count(*) FROM students WHERE current_stripes NOT BETWEEN 0 AND 4;
```

### 6.5 RLS funcionando

```sql
SET ROLE tatami_app;
SELECT count(*) FROM students;  -- DEVE retornar 0 (sem GUC setado)

SELECT set_config('app.academy_id', '<some-academy-uuid>', true);
SELECT count(*) FROM students;  -- DEVE retornar apenas os daquela academy

RESET ROLE;
```

Se a primeira query retornar > 0, RLS está mal configurada — **bloqueador**.

---

## 7. DLQ — fila de exceções

Crie uma tabela `migration_dlq`:

```sql
CREATE TABLE migration_dlq (
  id          BIGSERIAL PRIMARY KEY,
  source      TEXT NOT NULL,         -- 'users', 'students', etc
  source_id   TEXT NOT NULL,         -- Firestore doc id ou path
  reason      TEXT NOT NULL,         -- 'belt_unparseable', 'orphan_mapping', etc
  payload     JSONB,                 -- doc Firestore inteiro para revisão
  status      TEXT DEFAULT 'pending', -- pending | resolved | discarded
  reviewed_at TIMESTAMPTZ,
  reviewed_by TEXT,
  notes       TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);
```

Toda exceção do ETL grava aqui. Após a carga inicial:

```sql
SELECT source, reason, count(*)
FROM migration_dlq
WHERE status = 'pending'
GROUP BY 1, 2
ORDER BY 3 DESC;
```

Lista priorizada do que precisa intervenção humana antes do cutover.

---

## 8. Estratégia de cutover por fase

### Fase A — Carga inicial (read-only)

1. Export Firestore (point in time T0).
2. ETL → BigQuery → Postgres.
3. Validação (§6).
4. **Postgres está atrasado em T0; produção continua escrevendo no Firestore.**

Estado: Tatami está em standby, cliente continua usando 100% Firestore. Postgres está populado mas obsoleto.

### Fase B — Dual-write (uma semana mínimo)

Cliente passa a chamar **ambos**:
- Toda escrita Firestore continua acontecendo.
- Cada escrita também é enviada como evento (Pub/Sub ou direct call) para o Tatami **ingerir** no Postgres.

Implementação prática: **Cloud Functions** que ouvem mudanças no Firestore (`onWrite`) e fazem POST para um endpoint interno `/v1/_sync/...` do Tatami.

Vantagens:
- Cliente continua confiando no Firestore (zero risco de regressão).
- Postgres fica em paridade contínua.
- Diff job roda hourly e alerta sobre divergência.

### Fase C — Switch de leituras (gradual por feature)

Telas migram uma a uma para ler do Tatami:
1. `/v1/me` (mais simples)
2. Listagens (alunos, turmas, financials)
3. Dashboards
4. Operações de escrita (estas continuam dual-write até a Fase D)

Feature flag por tela: `useTatamiAPI` (remote config + override local para QA).

Estado: leituras vêm do Postgres, escritas ainda vão para ambos.

### Fase D — Cutover de escritas

1. Anunciar janela de manutenção (~30 min).
2. **Drenar Cloud Functions:** parar de aceitar novas escritas Firestore via security rules: `allow write: if false` para clients.
3. **Sync final**: rodar diff + import dos últimos eventos pendentes.
4. **Trocar flag**: cliente para de escrever no Firestore; escreve só via Tatami.
5. **Reativar security rules**: leituras Firestore ainda permitidas por mais 7 dias (fallback de rollback).

### Fase E — Encerramento (após 30 dias estáveis)

1. Cloud Functions de sync são desativadas.
2. Firestore vira read-only para o público; apenas como arquivo.
3. Após 90 dias sem rollback, exportar Firestore para arquivo cold (Coldline GCS).
4. Apagar collections (com aprovação).

---

## 9. Diff contínuo durante dual-write

Job `make migration-diff` (ou cron Cloud Run):

```sql
-- Diff de contagens por academia
WITH pg_stats AS (
  SELECT academy_id, COUNT(*) AS n_students FROM students GROUP BY 1
)
SELECT academy_id, n_students AS pg_count
FROM pg_stats;

-- comparar contra BigQuery snapshot diário do Firestore
```

Output em Slack / email. Diff > 1% por collection = alerta. Diff > 5% = pager.

---

## 10. Rollback

Em qualquer ponto antes da Fase E:

1. **Cliente:** desligar feature flag `useTatamiAPI`. Volta a usar Firestore.
2. **Backend:** parar de aceitar escritas (security rules ou flag de circuit breaker).
3. **Postgres:** snapshot do estado é mantido — não dropar.
4. **Diff:** rodar para entender o estado e decidir se vamos retentar ou recuar de vez.

**Após Fase E:** rollback é caro — exige re-importar Firestore do arquivo cold para um Firestore vivo. Por isso só fechamos Fase E depois de 30 dias de estabilidade comprovada.

---

## 11. Migração de imagens e arquivos (Firebase Storage)

Strategy: **não mover bytes durante a migração de dados**.

- Mantemos as URLs do Firebase Storage no banco Postgres durante toda a transição.
- Frontend continua lendo de `https://firebasestorage.googleapis.com/...`.
- Em paralelo, um job lento copia bytes para GCS / S3 (futuro Storage do Tatami) e atualiza o `photo_path` quando estiver pronto.
- O cliente checa: `photo_path` preenchido → pede signed URL ao Tatami; vazio → usa `legacy_photo_url`.

Por que não mover junto: bytes são caros para mover, demoram, e podem ser feitos sob demanda. Dados estruturados (rows) precisam estar paritários no cutover; bytes podem ficar atrasados.

---

## 12. Cronograma sugerido

Assumindo academia média (200 alunos, 2 anos de dados, ~50k attendance):

| Semana | Atividade |
|---|---|
| 1 | Descoberta (§2), discovery.csv preenchido, decisão de Opção A/B/C |
| 2 | ETL desenvolvido + rodado em **staging**. DLQ revisada |
| 3 | Carga inicial em **prod Postgres** (read-only); validações; primeiro RLS sanity |
| 4 | Fase B: dual-write ligado via Cloud Functions; diff job rodando hourly |
| 5–6 | Fase C: telas migram pra leitura via flag (1 por dia) |
| 7 | Fase D: cutover de escritas (janela de manutenção) |
| 8–11 | Monitoramento; Firestore ainda como fallback |
| 12 | Fase E: encerramento |

**Pessoas:** 1 dev backend (ETL + validação) + 1 dev frontend (flag + switch) + 1 SRE/DBA (monitoramento + rollback) por 12 semanas part-time.

---

## 13. O que mais pode dar errado (e o que fazer)

| Falha | Sintoma | Mitigação |
|---|---|---|
| Belt em PT-BR não mapeado | `current_belt = 'white'` (default) para aluno que era roxa | Pré-rodar query de contagem por belt **antes** do ETL; ampliar `BELT_NORMALIZE`. |
| `uuid_v5` colisão | Dois students com mesmo UUID | Praticamente impossível com namespace bem definido. Se acontecer, intervir manualmente. |
| Cloud Function de dual-write atrasa | Postgres fica minutos atrás do Firestore | Diff job detecta. Considerar batch hourly em vez de live se atraso for tolerável. |
| RLS bloqueia escrita em batch ETL | INSERT falha porque `app.academy_id` não está setado | ETL roda como `tatami_migrate` (BYPASSRLS). Documentado no script. |
| Bytes do photoUrl quebrados | URLs do Firebase Storage retornam 404 | A migração mantém `legacy_photo_url` por padrão. Job paralelo migra bytes. |
| Encoding de caracteres | Acentos viram `?` no Postgres | `client_encoding=UTF8` no COPY. **Sempre.** |
| Timezones perdidos | `created_at` aparece como meio-dia em vez de 9h | Garantir que todos os Timestamps Firestore vão para `timestamptz` UTC. |
| `attendance_count` desincronizado | Após o load, `students.attendance_count` zero | Trigger desligado durante bulk; rodar `UPDATE ... SET attendance_count = ...` no final (§3.5). |
| Mappings duplicados | Erro de PK (uid, academy_id) | `ON CONFLICT DO UPDATE` sempre. |

---

## 14. Checklist resumido (para imprimir e colar na parede)

- [ ] Discovery `discovery.csv` preenchido
- [ ] Strategy escolhida (A/B/C) baseada em volume
- [ ] Belt normalization table validada com `SELECT DISTINCT highest_belt` no BigQuery
- [ ] ETL desenvolvido para cada collection
- [ ] DLQ populada e revisada → 0 itens `status='pending'`
- [ ] Validações §6 passando
- [ ] RLS sanity passando
- [ ] Dual-write Cloud Functions deployadas
- [ ] Diff job rodando hourly + alertando
- [ ] Feature flag `useTatamiAPI` testada em staging
- [ ] Rollback testado em staging
- [ ] Janela de manutenção comunicada (Fase D)
- [ ] Cutover executado
- [ ] 30 dias de estabilidade
- [ ] Encerramento (Fase E)

Sem isso, não é migração — é desejo.
