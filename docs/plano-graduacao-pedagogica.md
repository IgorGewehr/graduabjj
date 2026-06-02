# Plano de Implementação — Graduação Pedagógica (B1→B4)

> Status: planejamento. Itens **B1–B4** do `docs/roadmap-modalidades.md`. Branch de
> trabalho: `feat/evolucao-modulos` (mesma da avaliação física) ou uma nova
> `feat/graduacao-pedagogica` _(decisão #0)_.
>
> Objetivo: sair de uma graduação que é **só contagem de presença** para uma camada
> **pedagógica** — currículo de técnicas por faixa, marcação de domínio por aluno,
> requisitos compostos (presença + tempo-em-faixa + técnicas) e progresso visível pro
> aluno/responsável. É o recurso **mais citado** em software de arte marcial e
> beneficia **6 modalidades** de uma vez (BJJ, Muay Thai, Karatê, Judô, Kickboxing,
> Luta Livre).

## ⚠️ Não confundir com o que já existe
- **`assessment_service` (avaliação 1-5)** = nota subjetiva por categoria (respeito,
  disciplina, técnica…). Continua existindo; o feedback **por técnica** (B4) é OUTRA
  coisa (granular por golpe/posição). Não mexer na avaliação 1-5.
- **`belt_progression_service`** = promoção + elegibilidade por presença. Vamos
  **estender** (não recomeçar) para requisitos compostos.

---

## 1. Diagnóstico — o que já temos a favor

| Já pronto | Onde | Como reaproveita |
|---|---|---|
| Escadas de faixa/grau por modalidade + helpers | `lib/core/sports.dart` (`GradeDefinition`, `getGradesForSport`, `getGradeDefinition`) | O currículo é indexado por `(sport, gradeId)` que já existem |
| Requisitos aninhados por esporte/faixa | `AcademyGraduationConfig.requirementsBySport = {sport:{gradeId:int}}` | Mesmo padrão p/ "técnicas exigidas por faixa" e p/ thresholds compostos |
| Elegibilidade per-sport (com baseline desde última promoção) | `belt_progression_service.checkEligibilityForStudent`, `EligibilityResult` | Estender p/ somar % de técnicas + tempo-em-faixa |
| Grau atual + histórico por esporte | `Student.sportData[sport]`, `beltProgressions`, `BeltProgression.promotionDate` | `promotionDate` dá "tempo em faixa"; `sportData` guarda agregados |
| Infra de vídeo/conteúdo por modalidade | `training_video_service`, `content` collection | Vídeo opcional por técnica (link ou upload já suportado) |
| Providers de progresso no portal | `beltProgressProvider`, `studentSportEligibilityProvider` | Estender p/ "faltam X técnicas" |
| Regras Firestore staff-escreve / aluno+responsável-lê | `firestore.rules` (assessments/beltProgressions) | Copiar o padrão p/ as coleções novas |
| Toggle/visibilidade de graduação | `AcademySettings.autoGraduationEnabled`, `graduationProgressVisibleToStudents`, `graduationMode` | Reusar os gates existentes |

**Conclusão:** o esforço novo é **2 coleções** (currículo de técnicas + progresso de
skill por aluno), **telas** (montar currículo, marcar domínio, ver progresso) e a
**extensão da elegibilidade**. Nada de reescrever graduação.

---

## 2. Decisões (CONFIRMADAS 2026-06)

0. **Branch:** seguir em **`feat/evolucao-modulos`** (mesma da avaliação física).
1. **Dono do currículo:** **por academia** (customizável) **+ template BJJ básico
   opcional** que semeamos pra não começar do zero.
2. **Rigidez dos requisitos compostos (B2):** **configurável por academia**, default
   **informativo** (não quebra a auto-promoção por presença atual); academia pode
   ativar “exigir ≥X% das técnicas” depois.
3. **Granularidade do domínio:** **escala de 3 níveis** — `aprendendo / praticando /
   dominado`. Só `dominado` conta pro progresso.
4. **Exame/banca (B3):** MVP usa a **promoção existente + lembrete**; evento formal de
   exame fica como extra opcional depois.
5. **Vídeo por técnica:** **`videoUrl` opcional** (link/Storage) no MVP; integração com
   a biblioteca `content` fica pra depois.

---

## 3. Modelo de dados (proposto)

### 3.1 Currículo de técnicas — `academies/{id}/syllabus/{techniqueId}`
```jsonc
{
  "sport": "bjj",              // SportId.value
  "gradeId": "blue",           // faixa em que a técnica é exigida/ensinada
  "category": "guarda",        // agrupador livre (guarda/passagem/finalização; kata; chute; soco…)
  "name": "Triângulo da guarda",
  "description": "…",          // opcional
  "videoUrl": "…",             // opcional (B1 / decisão #5)
  "order": 10,                 // ordenação dentro da faixa
  "active": true,
  "createdBy": "<uid>", "createdAt": ..., "updatedAt": ...
}
```
> Indexado por `(sport, gradeId, order)`. Currículo é **por academia** (decisão #1).

### 3.2 Progresso de skill por aluno — `academies/{id}/skillProgress/{id}`
```jsonc
{
  "studentId": "...", "sport": "bjj", "gradeId": "blue",
  "techniqueId": "<syllabus doc id>",
  "level": "dominado",         // aprendendo | praticando | dominado  (decisão #3)
  "ratedBy": "<uid>", "ratedByName": "...",
  "notes": "...",              // feedback por técnica (B4)
  "updatedAt": ...
}
```
> 1 doc por (aluno, técnica). Indexado por `(studentId, sport)`. Espelha o padrão de
> `assessments` (staff escreve; aluno/responsável lê).

### 3.3 Extensão de configuração (B2) — em `AcademySettings`
```jsonc
"graduationSkillPolicy": "informative",   // informative | required  (decisão #2)
"graduationMinSkillPct": 80,              // se required: % de técnicas "dominadas" exigido
"graduationMinDaysInBelt": { "bjj": { "blue": 365 } }  // tempo-em-faixa por sport/faixa (opcional)
```

### 3.4 Derivados (no display, não no banco)
- **% do currículo dominado** na faixa atual = técnicas dominadas / técnicas exigidas.
- **Tempo em faixa** = hoje − `beltProgressions` (última promoção naquela faixa/sport).
- **Elegibilidade composta** = presença (já existe) **+** (se `required`) skill% ≥ alvo
  **+** tempo-em-faixa ≥ alvo.

---

## 4. Telas

**Admin / instrutor:**
- **Montador de currículo** (config da academia ou aba no detalhe da modalidade):
  CRUD de técnicas por `(sport, faixa)`, com categoria, ordem e vídeo opcional.
- **No detalhe do aluno** (nova aba “Currículo/Graduação” por esporte): lista as
  técnicas da faixa atual; instrutor marca o **nível** e deixa **feedback** por técnica;
  mostra **% dominado** + elegibilidade composta.
- **Lista de elegíveis** (já existe): passa a refletir os requisitos compostos.

**Portal / aluno (e responsável):**
- **“Minha Graduação”**: faixa atual + barra "faltam X aulas / Y técnicas / Z dias",
  e o **checklist de técnicas** da faixa (dominado/praticando/aprendendo), com vídeo.
  Gate por `graduationProgressVisibleToStudents`.

---

## 5. Plano por fases (entrega incremental)

### Fase 0 — Fundação
- Modelos `SyllabusTechnique` + `SkillProgress` + serviços (CRUD + queries).
- `firestore.rules`: blocos `syllabus` (staff escreve; membros leem) e `skillProgress`
  (staff escreve; aluno/responsável leem os próprios) — espelha `assessments`.
- Índices: `syllabus(sport, gradeId, order)`, `skillProgress(studentId, sport)`.

### Fase 1 — B1: Montador de currículo (admin) — *valor cedo*
- CRUD de técnicas por modalidade/faixa, com categoria, ordem e vídeo opcional.
- (Opcional, decisão #1) seed de template BJJ básico.

### Fase 2 — B4 (admin): Marcar domínio + feedback por técnica
- Aba no detalhe do aluno: checklist da faixa atual, marcar nível + nota por técnica;
  mostra **% dominado**.

### Fase 3 — B4 (portal): Progresso visível
- “Minha Graduação” no portal: barra composta + checklist com vídeo. Gate de
  visibilidade.

### Fase 4 — B2: Requisitos compostos
- Estender `checkEligibility*` para somar skill% e tempo-em-faixa conforme a política
  (`informative`/`required`). Default informativo (não quebra auto-promoção).

### Fase 5 — B3: Elegibilidade composta + lembrete (+ exame opcional)
- Lista de elegíveis reflete os requisitos compostos; lembrete de “apto a graduar”.
- (Opcional) registro de evento de exame/banca.

---

## 6. Regras e segurança
- **`syllabus`**: leitura por qualquer membro da academia; escrita por staff
  (admin/instrutor com `graduation:manage`). Currículo não é sensível.
- **`skillProgress`**: escrita por staff; leitura pelo próprio aluno + responsável
  (espelha `assessments`). Feedback por técnica pode ser pessoal → não público.
- Sem novos uploads públicos (vídeo de técnica usa a infra/regra de `content` ou URL).

## 7. Dependências
- Nenhuma nova prevista (reutiliza fl_chart se quiser mini-gráfico; vídeo via infra
  atual). Possível índice/regra novos (Fase 0).

## 8. Sequenciamento
**0 → 1 (currículo) → 2 (marcar domínio) → 3 (portal) → 4 (requisitos compostos) →
5 (elegibilidade/exame).** A Fase 1+2 já entrega “currículo + acompanhamento por
técnica”; a Fase 3 dá o “uau” pro aluno; 4–5 fecham a graduação pedagógica.
