# Jornada Multi-Esporte — Plano de Implementação

> Síntese técnica para tornar **presenças, turmas, graduações, Perfil e Treinei** coesos e profissionais, com **multi-esporte no centro**. Branch alvo: `b2c` (modelo aditivo sobre `firebase-production`).
>
> Princípio-mestre: **NÃO há schema novo de coleção para o core multi-esporte** — `sportsList`, `sportData`, `primarySport` e o campo `sport` em `attendance`/`beltProgressions`/`classes` JÁ existem e o legado `null` já é tratado como `'bjj'` em todos os call sites. As únicas coleções novas são para o conteúdo **auto-declarado** (graduações/competições do próprio lutador).
>
> Decisões do dono incorporadas: (1) Vitrine → **JORNADA**; própria = infos de treino + editável (sem herói decorado), visitante = decorada read-only; (2) multi-esporte gerido no **Perfil** (adicionar esportes + escolher principal); (3) edição de graduações com **TETO verificado**; (4) graduação-por-presença bem mostrada; (5) competições editáveis (academia + externas), tudo na timeline.

---

## 1. Modelo de dados coeso

### 1.1 O eixo único: `sport` carimbado da turma até a Jornada

```
TURMA (BJJClass.sport)
   │  class.getSport()  (class_service.dart:106, default 'bjj')
   ▼
PRESENÇA (Attendance.sport)            ← carimbada no check-in
   │  markPresent :456 / bulk :699 / manual :530  (payload['sport'] = sport ?? 'bjj')
   ▼
CONTAGEM POR ESPORTE
   │  belt_progression_service.getWeightedAttendanceCount(sportId) :458-477
   │     filtra (a.sport ?? 'bjj') == sportId, conta desde effectiveCountAtPromotion
   ▼
ELEGIBILIDADE / GRADUAÇÃO POR ESPORTE
   │  checkEligibility :288-358  →  promote() :826-971
   │     grava beltProgressions{sport} + sportData.<sport>.currentGrade/Stripes
   ▼
JORNADA / VITRINE
      showcase_builder _buildGraduations :98-137 (agrupa por sport :106)
      timeline_builder (sportFilter, tag sportId por evento)
```

A turma é a **fonte de verdade do esporte**. Tudo a jusante (presença, contagem, faixa, timeline) herda esse carimbo. Qualquer feature por-esporte depende do carimbo correto — ver gap "membership sem enrollment" (§5).

### 1.2 Representação do aluno (já existe — `lib/models/student.dart`)

| Campo | Linha | Papel |
|---|---|---|
| `sportsList` (array `sports`) | `student.dart:330` / parse `:462` | esportes que o aluno treina |
| `sportData` (Map por esporte) | `:331` / parse `:463` | `{sport: {currentGrade, currentStripes, ...}}` |
| `primarySport` | `:332` / parse `:466` | esporte em destaque (hero/Jornada) |
| `getSports()` | `:581` | fallback `['bjj']` |
| `getPrimarySport()` | `:589` | fallback 1º de `getSports()` |
| `getGrade(sport)` | `:596-607` | BJJ sem sportData → legado `currentBelt/currentStripes`; senão `sportData[sport]` |

**BJJ espelha no legado** `currentBelt/currentStripes`; demais esportes vivem só em `sportData`. `category` (kids/adult, `:65`) é **global** do aluno, não por esporte (gap conhecido — §5).

### 1.3 VERIFICADO vs AUTO-DECLARADO

| Dimensão | VERIFICADO (= TETO) | AUTO-DECLARADO (editável pelo aluno) |
|---|---|---|
| Origem | turma (`_enrollStudentInSport`) + `beltProgressions` (staff promove) | aluno declara no Perfil/Jornada |
| Graduação | `academies/{aid}/beltProgressions` (staff-write, `firestore.rules:1097-1103`) | **nova** coleção `selfGraduations` |
| Competição | `achievements` (type `competition`, gerado por staff) | **nova** coleção `selfCompetitions` |
| Esporte | tem turma OU beltProgression na academia | `sportData[sport].source == 'self'` |
| Escrita do aluno | **proibida** (read-only) | permitida (add / editar data / excluir) |

**Regra de ouro:** o aluno **nunca** escreve em `beltProgressions`. O TETO de auto-promoção é o `sportData.<sport>.currentGrade/currentStripes` **verificado**.

### 1.4 Onde guardar os auto-declarados + rules

Modelo aditivo, sem tocar em `beltProgressions`:

```
academies/{aid}/students/{sid}/selfGraduations/{id}
  { sport, grade, stripes, date (editável), source:'self',
    createdBy: uid, createdAt }

academies/{aid}/students/{sid}/selfCompetitions/{id}
  { sport, name, date, placement, result, external:bool,
    externalAcademy?, source:'self', createdBy: uid, createdAt }
```

(No mundo B2C solo sem academia: `fighterProfiles/{uid}/selfGraduations` e `.../selfCompetitions` — mesmo contrato.)

**Rules novas (esboço):**

```
match /academies/{aid}/students/{sid}/selfGraduations/{id} {
  allow read: if isAuthed();                       // espelhado pela Jornada pública
  allow create: if isOwnStudentRecord(aid, sid)
                && request.resource.data.source == 'self'
                && request.resource.data.createdBy == request.auth.uid;
  allow update: if isOwnStudentRecord(aid, sid)
                && resource.data.source == 'self'
                && request.resource.data.source == 'self'; // source imutável
  allow delete: if isOwnStudentRecord(aid, sid)
                && resource.data.source == 'self';
}
// selfCompetitions: idêntico.
```

As Rules garantem **ownership** + **source imutável** + **proibição de escrever em beltProgressions**. O que as Rules **não conseguem** validar é a posição na escada (o teto), porque a ordenação vive só no Dart (`getGradesForSport`, `sports.dart:368`). Por isso o teto é enforced em **duas camadas**: (1) client — o seletor só oferece graus ≤ verificado; (2) **Cloud Function `onWrite`** validadora que rejeita grau acima do teto verificado (defesa em profundidade).

### 1.5 O teto de promoção (auto-declarado)

```
TETO(sport) = posição_na_escada(sportData[sport].currentGrade verificado, currentStripes)
            via getGradesForSport(sport) (sports.dart:368)

auto-declarado VÁLIDO  ⟺  posição(grade auto) ≤ TETO(sport)
```

O aluno pode: **adicionar** faixas/graus passados até o teto, **editar datas**, **excluir** um grau errado — **nunca** se promover acima do verificado. Esportes `GradeSystem.none` (boxe/MMA/musculação) não têm faixa → nenhuma auto-graduação, só presença.

---

## 2. Multi-esporte

### 2.1 Representação (já end-to-end no dado)

Multi-esporte **já existe** na leitura e no cálculo: presença, contagem ponderada, elegibilidade, distribuição de faixas e timeline já são **por esporte**. Falta só a **camada de GESTÃO pelo aluno** e a **hierarquia visual** da Jornada.

Catálogo — `lib/core/sports.dart`:
- `enum SportId` (`:9`) com 9 esportes; `SportDefinition.gradeSystem` = `belt | armband | none` (`:34`).
- `GradeSystem.none` → boxe (`:298`), MMA (`:319`), musculação (`:331`) = **presença pura**, `adultGrades: []`.
- Muay Thai = `armband` com **duas federações** (CBMT/CBMTT); a vigente vem de `AcademySettings.muaythaiGradeSystem`; `resolveMuaythaiVariant(gradeId)` (`:391`) deduz a escada do próprio grade salvo.
- Helpers: `getGradesForSport` (`:368`), `getGradeLabel/Color/Definition`, `sportChipColors`, `sportOptions`.

### 2.2 Gestão no Perfil (a peça que falta)

Hoje só o **admin** grava `sportsList`/`primarySport`/`sportData` (`student_form`, `monitor_student_form`, `graduation_screen`). O aluno não tem superfície nenhuma. `lib/screens/portal/my_sports_screen.dart` é **100% read-only** (`:12`, `:81` usa `getGrade`).

**Transformar `my_sports_screen.dart` em editor** ("MODALIDADES"), único ponto de gestão do aluno:

1. **Adicionar modalidade** — escolhe do catálogo `sports.dart`. Esporte com turma na academia entra **travado/verificado**; demais entram **auto-declarado** (`sportData[sport].source = 'self'`). Grava via `StudentService.updateSports` (`student_service.dart:281`) + semeia `sportData[sport]` reusando a lógica de `_enrollStudentInSport`.
2. **Definir como principal** — radio → `StudentService.updatePrimarySport` (`:288`).
3. **Selo por esporte** — verificado (tem turma/beltProgression) vs auto (`source:'self'`), via `getGrade` + flag.
4. **Remover** modalidade auto-declarada.

**Extrair helper compartilhado** de `class_service._enrollStudentInSport` (`:420-478`): hoje ele é o único writer que semeia `sportData[sport]` (menor grau via `getGradesForSport().first`, variante MT da academia, define `primarySport` se ausente `:471`). A gestão manual no Perfil deve **reusar o mesmo contrato**, só sem turma — extrair para `SportEnrollment.seedSportData(sport, academySettings)` chamável por ambos.

### 2.3 Quando o multi-esporte "liga"

Conforme decisão do dono: a Jornada só vira multi-esporte quando
```
getSports().length > 1   OU   existe esporte com source == 'self'
```
Checagem barata via `Student`. Single-sport mantém UI simples (sem abas).

Dois caminhos que habilitam um esporte:
- **Com academia:** matrícula em turma de outro esporte → `class_service.addStudent` → `_enrollStudentInSport` (`:403-478`). (Já existe.)
- **Sem academia / declarado:** aluno adiciona no Perfil → mesmo contrato de seed, `source:'self'`. (A construir.)

### 2.4 Faixa / presença por esporte

- **Faixa**: `sportData[sport].currentGrade/currentStripes`; BJJ espelha legado. `getGrade(sport)` resolve.
- **Presença**: `Attendance.sport`; já separável. **Gap a fechar**: streak e contador total são **globais** (`getStreakInfo`/`getStudentStreak` `attendance_service.dart:325-412` ignoram sport; `student.attendanceCount` é único inteiro). Ver §5/§6.

---

## 3. Jornada (rename Vitrine → Jornada)

### 3.1 Rename

`lib/screens/fighter/diario_screen.dart` é a aba **Treinei** = `[ VITRINE | HISTÓRICO ]` (segmented control `:547-560`, labels `:559-560`, docstring `:18-38`). **Renomear o label "VITRINE" → "JORNADA"** (`:559`) e os comentários/docstrings que falam "vitrine" (`:18`, `:21`, `:33`, `:593`, `:609`). A aba HISTÓRICO (feed unificado verified+self-log, `TrainSource` `:50-77`, ordenação `:288`) permanece.

> Atenção: `TrainSource.verified/self` em `diario_screen.dart:50` é de **TREINOS (logs)**, não de graduações. Não confundir com o `source` novo das graduações auto-declaradas (§1).

### 3.2 Visão PRÓPRIA (editável, sem herói decorado)

Foco em **infos de treino + editável**. Sem grande herói de foto/faixa/apelido (isso é da visão do visitante). Mostra:
- Esporte **principal** em destaque + chips/abas **só dos esportes do aluno** (`getSports()`, **não** `sports.values` como faz hoje o `_sportChips` do editor de log `:1361/:1365` — corrigir esse vazamento de catálogo inteiro).
- Graduações (`_graduationsSection` `:744`) **editáveis** (add/edit/delete só nos auto; verified read-only).
- Competições editáveis (academia + externas).
- Graduação-por-presença da academia atual mostrada como progresso verificado.

### 3.3 Visão VISITANTE (decorada, read-only)

`lib/screens/portal/public_profile_screen.dart` (read-only por design `:54`). Hoje:
- Header mostra **só** o esporte principal: `getPrimarySport()` + `getGrade()` → um único `AnimatedBelt large` (`:376-386`) + `GradeBadge` se !bjj (`:387-394`). Stats viram STREAK·RECORDE·TREINOS (`:410-435`).
- Abas GRADUAÇÕES/COMPETIÇÕES/FOTOS (`:211`) lêem `fighterShowcaseProvider(uid)`; cada marco carrega `_SportChip` por esporte (`:1051`).

**Mudanças (principal em destaque + secundários):**
1. Header: manter o principal grande (`AnimatedBelt large`) e **adicionar abaixo um strip compacto de mini-belts** dos esportes secundários, lendo `publicProfiles.sportData`/`getSports()`. O espelho SAFE **já projeta** `sports`/`primarySport`/`sportData` (`functions/server_functions.js:849-851`) — o visitante já tem o dado, o header só não consome.
2. Tratar principal **presence-only** (`grade == null`, hoje some o bloco em `:372`): renderizar chip de modalidade, espelhando `_SportGrade` `GradeSystem.none` do Perfil próprio.

### 3.4 Graduação-por-presença bem mostrada

Configurada a **nível de academia** (não em `sports.dart`): `AcademyGraduationConfig` (`belt_progression_service.dart:26-45`), `autoGraduationEnabled` (`academy.dart:302`), `graduationRequirementsBySport`. Quando a academia atual tem auto-graduação ligada, mostrar o **progresso de presenças → próxima faixa** com destaque, tanto na própria quanto na do visitante (decisão 4). `getNextPromotion` (`:236-276`) é sport-aware. Esportes `GradeSystem.none` nunca graduam.

### 3.5 Showcase / merge

`showcase_builder._buildGraduations` (`:98-137`) hoje consome **só** `beltProgressions` (agrupa por sport `:106`). **Adicionar campo `source` a `FighterGraduation`** (`fighter_profile.dart:19-65` — hoje tem `sport` mas **não** tem `source`) e fazer o builder **MERGE** `beltProgressions` (verified) + `selfGraduations` (auto) por esporte, ordenado por data, cada marco etiquetado `verified`/`auto`. Mesmo padrão para `_buildCompetitions` (`:140-178`, hoje só achievements) + `selfCompetitions`. **Streak/cumulativeTrainings precisam virar por-esporte** (hoje globais `:90-91/:178`) para casar com graduações/competições já sport-tagged.

---

## 4. Edição (fluxos concretos)

### 4.1 Graduações auto-declaradas (com TETO)

**Fluxo "adicionar graduação passada":**
1. Aluno abre Jornada própria → esporte X → "Adicionar graduação".
2. Seletor de grau: oferece **apenas** graus ≤ TETO(X) = posição do verificado em `getGradesForSport(X)` (`sports.dart:368`). Para Muay Thai resolve a variante via `resolveMuaythaiVariant`.
3. Aluno escolhe grau + data (editável) → grava em `selfGraduations` (`source:'self'`).
4. CF `onWrite` revalida o teto server-side; rejeita se acima.
5. Builder merge → aparece na timeline com badge "auto".

**Editar data:** update do doc `selfGraduations` (source imutável). **Excluir grau errado:** delete do doc `self`. **Verificado é sempre read-only** (não editável/deletável pelo aluno).

### 4.2 Competições (academia + externas)

- **Da academia (verificado):** aluno seleciona campeonatos da academia que participou → marca como participado. Verificado, read-only.
- **Externas (auto):** "lutei por OUTRA academia" → form básico (`name`, `date`, `sport`, `placement`/`result`, `external:true`, `externalAcademy`) → `selfCompetitions`. Editável/excluível.
- Ambas entram na **mesma timeline** (`showcase_builder._buildCompetitions` merge + `timeline_builder`), etiquetadas verified/auto, com `_SportChip` por esporte.

### 4.3 Tudo na timeline

`timeline_builder` aceita `sportFilter` e tagueia cada evento com `sportId`. Graduações (verified+auto) e competições (verified+externas) viram marcos na mesma linha do tempo, filtráveis por esporte, com o **principal em destaque** na visão do visitante.

---

## 5. Telas afetadas (file:line) e o que muda

### Presenças — `lib/screens/portal/attendance_screen.dart`
Já tem filtro client-side por esporte (`SportTabBar :86-97`, `selectedSportProvider('attendance')` default primary `:57-59`, filtra `(r.sport ?? 'bjj')==selected :60-66`). **Mudança:** o card "total" sem filtro mostra o agregado **global** (`:70-72`) — pode confundir aluno multi-esporte. Trocar por contagem **por esporte** quando houver overload `getAttendanceCount(sport:)` (§6). Calendário/"este mês" já refletem o filtro.

### Turmas/Horários — `lib/screens/portal/schedule_screen.dart`
`_enrolledClassesProvider` (`:975-986`) filtra por `studentIds.contains`. `_buildUpcomingSchedules` (`:197-276`) agrupa só por **data** — aluno multi-esporte vê BJJ+Muay Thai misturados, distintos só pelo nome. **Mudança:** badge/seção **por esporte** (`class.getSport()`) e/ou filtro por `primarySport`.
Higiene em `lib/services/class_service.dart`: `addStudentToClass/removeStudentFromClass` (`:379-394`) adicionam à turma **sem** chamar `_enrollStudentInSport` → risco de turma de esporte X sem X em `student.sports`. **Unificar** com `addStudent` (`:403`, que chama enroll `:412`) ou sempre disparar o enroll.

### Graduações — `lib/services/belt_progression_service.dart` + `lib/screens/admin/graduation_screen.dart` + `lib/screens/portal/student_graduation_screen.dart`
Admin promove (sport-aware, resolve variante MT, maxStripes reais). `student_graduation_screen.dart` é **somente-leitura** (checklist). **Mudança:** **não tocar** `beltProgressions` (= TETO). Adicionar a camada `selfGraduations` na Jornada (não aqui). Limpeza: `stripeRequirements` hardcoded só-BJJ (`:15-21`) faz esportes sem config ficarem `required=0` = sempre elegível — restringir fallback a BJJ.

### Perfil — `lib/screens/portal/profile_screen.dart` + `lib/screens/portal/my_sports_screen.dart`
`_HeroHeader` (`:471`) usa `getPrimarySport()`+`getGrade()`, gating `hasBelt = gradeSystem != none` (`:490`). `_GraduationCard` (`:631-677`) **já é multi-esporte** (lista um belt por esporte, `_SportGrade :685-754`). **Mudança principal:** tornar `my_sports_screen.dart` **editável** (§2.2) — adicionar esporte, escolher principal, selo verificado/auto. Grava via `StudentService.updateSports/updatePrimarySport` → propaga automaticamente para `publicProfiles` e `fighterProfiles` pelas CFs existentes.

### Treinei/Jornada — `lib/screens/fighter/diario_screen.dart` + `lib/services/showcase_builder.dart` + `lib/screens/portal/public_profile_screen.dart` + `lib/models/fighter_profile.dart`
- Rename VITRINE→JORNADA (`diario_screen.dart:559` + docstrings).
- Própria editável (graduações/competições auto), chips só de `getSports()` (corrigir `_sportChips :1361/:1365` que usa `sports.values`).
- Visitante: strip multi-esporte no header (`public_profile_screen.dart:297-394`), fallback presence-only.
- `showcase_builder`: merge verified+self, streak/treinos por esporte.
- `fighter_profile.dart`: adicionar `source` a `FighterGraduation` (`:19`) e `FighterCompetitionMark` (`:79`).

---

## 6. Roadmap faseado

Ordenado por dependência; cada fase é entregável e aditiva (legado `null=bjj` já tratado — sem migração destrutiva).

### Fase 0 — Fundações por-esporte (sem UI nova) `[bloqueia tudo]`
- **F0.1** Extrair `SportEnrollment.seedSportData(sport, academySettings)` de `class_service._enrollStudentInSport` (`:420-478`); reusar em class_service.
- **F0.2** Overloads por esporte em `AttendanceService`: `getByStudent(sport:)`, `getStreakInfo(sport:)`, `getAttendanceCount(sport:)` — reusando filtro `(r.sport ?? 'bjj')` que `belt_progression_service.getWeightedAttendanceCount :469-472` já usa.
- **F0.3** Higiene: unificar `addStudentToClass/removeStudentFromClass` (`:379-394`) com o enroll.
- **F0.4** Restringir `stripeRequirements` hardcoded (`:15-21`) a BJJ.

### Fase 1 — Gestão de esportes no Perfil `[depende F0.1]`
- Tornar `my_sports_screen.dart` editável: adicionar/remover esporte, radio "principal", selo verificado/auto.
- Grava `updateSports`/`updatePrimarySport` + seed `sportData` (source 'gym'|'self').
- **Multi-esporte liga** quando `getSports().length>1 || any source=='self'`.

### Fase 2 — Auto-declarados (graduações + competições) `[depende F1, F0.2]`
- **Coleções novas** `selfGraduations` + `selfCompetitions` (§1.4).
- **Rules novas** (ownership + source imutável + proibir escrita em beltProgressions).
- **CF `onWrite` validadora de teto** (rejeita grau acima do verificado).
- Campo `source` em `FighterGraduation`/`FighterCompetitionMark` (`fighter_profile.dart:19/:79`).
- Espelhar `self*` no `fighterProfiles` (estender CF de materialização).

### Fase 3 — Jornada coesa `[depende F2]`
- Rename VITRINE→JORNADA (`diario_screen.dart:559`).
- `showcase_builder`: **merge** verified+self por esporte; streak/cumulativeTrainings **por esporte** (`:90-91/:178`).
- Própria editável (add/edit/delete só auto); chips de `getSports()` (corrigir `:1365`).
- Visitante: strip multi-esporte no header + fallback presence-only (`public_profile_screen.dart`).
- Graduação-por-presença destacada (própria + visitante).

### Fase 4 — Higiene de telas operacionais `[paralelo a F3]`
- Horários por esporte (badge/seção/filtro, `schedule_screen.dart`).
- Card "total" de presenças por esporte (`attendance_screen.dart:70-72`).
- `category` por-esporte em `sportData` (médio prazo, `getGrade(sport, category)`).

### Agregados a materializar
- `attendanceCountBySport` denormalizado (hoje só `attendanceCount` global) — evita varrer a lista inteira client-side (caro >365 docs).
- streak/treinos por esporte no `fighterProfiles` (materializado pela CF de showcase).

### Rules novas (resumo)
- `selfGraduations` / `selfCompetitions`: ownership, `source` imutável, delete só self (§1.4).
- Reafirmar: aluno **não** escreve em `beltProgressions` (já em `firestore.rules:1097-1103`).
- CF `onWrite` complementa o teto (Rules não ordenam a escada).

---

## Resumo executivo

O modelo de dados multi-esporte **já existe end-to-end na leitura e no cálculo** — `sportsList`/`sportData`/`primarySport` no `Student`, e o campo `sport` carimbado de TURMA → PRESENÇA → CONTAGEM → GRADUAÇÃO → JORNADA, com legado `null` tratado como `'bjj'` em todos os call sites. O que falta é **gestão pelo aluno** e **coesão visual**, não esquema novo. O plano é **100% aditivo**: (1) extrair o seed de `sportData` para reuso e adicionar overloads por-esporte em presença/streak; (2) tornar `my_sports_screen.dart` editável (único ponto de gestão: adicionar esporte + escolher principal); (3) introduzir **auto-declarados** em coleções separadas (`selfGraduations`/`selfCompetitions`) com TETO verificado enforced em client + Cloud Function, **nunca** tocando `beltProgressions`; (4) renomear Vitrine→JORNADA, fazer o `showcase_builder` dar **merge** verificado+auto por esporte e tornar streak/treinos por-esporte, com principal em destaque no visitante. Risco principal mapeado: `addStudentToClass` não dispara enrollment (turma de esporte X sem X em `student.sports`) — corrigir na Fase 0.

Arquivo escrito: `/Users/igorgewehr/WebstormProjects/graduabjj/docs/b2c/JORNADA_MULTISPORT_PLANO.md`
