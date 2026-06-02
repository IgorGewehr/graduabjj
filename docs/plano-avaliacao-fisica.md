# Plano de Implementação — Avaliação Física / Antropometria

> Status: planejamento. Item **A3** do `docs/roadmap-modalidades.md` (transversal —
> beneficia todas as modalidades; essencial p/ musculação, útil p/ controle de peso
> de combate). Branch de trabalho: `feat/evolucao-modulos`.
>
> Objetivo: o instrutor registra avaliações físicas periódicas do aluno (peso,
> medidas, % gordura, **fotos de evolução**) e o aluno acompanha sua **evolução**
> no portal (gráficos + comparação de fotos). É a maior expectativa não atendida do
> mercado BR (Pacto/Tecnofit têm; nós só temos a avaliação técnica 1-5).

## ⚠️ Não confundir com a avaliação técnica existente
Já existe `assessment_service` = avaliação **técnica/subjetiva** (nota 1-5 por
categoria), em `academies/{id}/assessments`. A **avaliação física** é OUTRA coisa
(medidas numéricas no tempo + fotos) → **coleção separada** `physicalAssessments`,
UI própria. Não mexer na avaliação técnica.

## Decisões a confirmar (antes de codar)
1. **Lib de gráfico:** `fl_chart` (recomendado — linhas limpas) **ou** `CustomPaint`
   (sem dep nova, padrão que o app já usa em reports/financial)?
2. **Fotos de menores (kids):** permitir foto de evolução de aluno infantil? Se sim,
   exigir consentimento do responsável? (sensível — LGPD). Sugestão MVP: **fotos só
   pra adultos**; medidas pra todos.
3. **Escopo do MVP:** começar só com **peso/altura/IMC + cintura/quadril** (rápido),
   ou já perimetria completa?
4. **% gordura:** entrada **manual** (vinda de bioimpedância da academia) no MVP, e
   cálculo por **dobras cutâneas** (protocolo Pollock) só depois?

---

## 1. Diagnóstico: o que já existe a nosso favor

| Já pronto | Onde |
|---|---|
| Upload de imagem pro Storage (molde) | `photo_upload_service.dart` (`academies/{id}/students/{sid}/profile.jpg`) |
| `storage.rules` com helpers `isStaff`/`isOwnStudent`/`isImage`/`sizeUnderMb` | `storage.rules:39-93` |
| Padrão de subcoleção com `studentId` + regras (staff escreve, dono lê) | avaliação técnica: `firestore.rules:807` (`match /assessments/{id}`) |
| Seleção/recorte de imagem | `image_picker`, `image_cropper` (pubspec) |
| Aba/detalhe do aluno (onde encaixar a UI admin) | `student_detail_screen.dart` |
| Padrão de "minha jornada/timeline" no portal | `timeline_screen.dart` |
| Avaliação técnica com séries pra gráfico (padrão de service a espelhar) | `assessment_service.dart` |

**Conclusão:** quase tudo é reaproveitável. O esforço novo é: **modelo + service**,
**form de avaliação (admin)**, **upload de fotos privadas** e **tela de evolução +
gráficos (portal)**.

---

## 2. Modelo de dados

`academies/{academyId}/physicalAssessments/{assessmentId}`:
```jsonc
{
  "studentId": "...", "studentName": "...",
  "date": Timestamp,

  // Básico
  "weightKg": 82.5, "heightCm": 178,   // IMC é CALCULADO (não armazenado): peso/(altura/100)^2

  // Composição (opcional / avançado)
  "bodyFatPct": 18.2,                  // % gordura (manual no MVP)
  "leanMassKg": null, "fatMassKg": null,

  // Perimetria (cm) — todos opcionais
  "measurements": {
    "neck": 39, "chest": 104, "waist": 84, "abdomen": 88, "hip": 99,
    "armR": 36, "armL": 35.5, "forearmR": 29, "forearmL": 29,
    "thighR": 58, "thighL": 57, "calfR": 38, "calfL": 38
  },

  // Dobras cutâneas (mm) — opcional, Fase 4
  "skinfolds": { "triceps": 12, "subscapular": 14, "suprailiac": 16, "abdominal": 20, "thigh": 15 },

  // Fotos de evolução (privadas)
  "photos": [ { "url": "...", "storagePath": "...", "angle": "front", "takenAt": Timestamp } ],

  // Contexto
  "goal": "hipertrofia",               // hipertrofia | emagrecimento | condicionamento | manutencao
  "notes": "...",
  "assessedBy": "<uid>", "assessedByName": "...",
  "createdAt": Timestamp, "updatedAt": Timestamp
}
```
**Derivados (no display, não no banco):** IMC + classificação; **deltas vs.
avaliação anterior** (peso, % gordura, cintura…); série temporal por métrica.

**Service:** `PhysicalAssessmentService(academyId)` espelhando `assessment_service`:
`create`, `getByStudent`, `getLatest`, `update`, `delete`, e `series(studentId, metric)`
(retorna pontos {date, value} pro gráfico).

**Fotos:** caminho `academies/{id}/students/{sid}/assessments/{assessmentId}/{angle}_{ts}.jpg`
(espelha `photo_upload_service`).

---

## 3. Telas

**Admin / instrutor** (dentro de `student_detail_screen`):
- Nova aba **"Avaliação Física"**: lista de avaliações (data + peso/IMC/%gordura), botão **"Nova avaliação"**.
- **Form** de nova/editar: peso + altura (IMC automático ao digitar); seção recolhível de **perimetria**; seção recolhível de **composição** (% gordura/dobras); **fotos** (frente/lado/costas); meta + observações.
- **Detalhe** da avaliação: todos os valores + **delta vs. anterior** + fotos.

**Portal / aluno** — nova tela **"Minha Evolução"** (`/portal/evolucao`, gate no menu):
- Snapshot atual (peso, IMC, % gordura) + variação desde a última.
- **Gráficos** no tempo (peso, % gordura, cintura, etc.).
- **Comparação de fotos** (antes/depois lado a lado).
- Meta atual + progresso.

---

## 4. Plano por fases (entrega incremental)

### Fase 0 — Fundação
- Modelo `PhysicalAssessment` + `PhysicalAssessmentService`.
- **firestore.rules:** bloco `match /physicalAssessments/{id}` — `write: isStaff`;
  `read: isStaffOrMonitor OU isOwnStudentRecord(studentId) OU isResponsibleForStudent`
  (espelha o bloco da avaliação técnica em `:807`).
- **firestore.indexes.json:** índice `studentId` + `date desc`.

### Fase 1 — Avaliação básica (admin) — *entrega de valor cedo*
- Aba "Avaliação Física" no detalhe do aluno: lista + form (peso/altura/**IMC auto** +
  perimetria + notas) + detalhe com **delta vs. anterior**. Já dá pra registrar e ver
  histórico numérico, sem fotos/gráficos ainda.

### Fase 2 — Fotos de evolução (depende de F0 storage)
- **storage.rules:** bloco novo (fotos **PRIVADAS** — `read: isStaff || isOwnStudent`,
  **não** público como o `profile.jpg`), `isImage()` + `sizeUnderMb(10)`, limite de
  ~3 fotos/avaliação.
- Upload frente/lado/costas no form + visualização no detalhe.

### Fase 3 — Portal "Minha Evolução" + gráficos
- Tela do aluno: snapshot + variação + **gráficos** (decisão: fl_chart vs CustomPaint) +
  comparação de fotos. Gate de menu por disponibilidade (padrão `portal_shell`).

### Fase 4 — Composição avançada + metas
- % gordura por **dobras** (protocolo Pollock) ou entrada manual; campos de bioimpedância;
  **meta/objetivo** + acompanhamento contra as avaliações.

### Fase 5 — Polish
- Classificação de IMC; **notificação** "nova avaliação disponível" (reusa
  notification dispatcher); **lembrete de reavaliação** (a cada N dias);
  export PDF da avaliação (opcional — dep nova `pdf`/`printing`).

---

## 5. Regras e segurança

- **Privacidade (LGPD):** medidas corporais, % gordura e **fotos** são dados pessoais
  sensíveis. Fotos **NÃO** podem ser de leitura pública (diferente do `profile.jpg`).
  Acesso só staff + o próprio aluno (+ responsável, p/ kids). Avaliar termo de
  consentimento, sobretudo p/ menores (ver Decisão #2).
- **Custo de Storage:** limitar tamanho e quantidade de fotos por avaliação.
- **firestore.rules / storage.rules:** blocos novos descritos nas Fases 0 e 2.

---

## 6. Dependências (iOS + Android)
- `image_picker` + `image_cropper` — já existem (fotos).
- `firebase_storage` — já existe.
- **`fl_chart`** (NOVO, se escolhido) — gráficos de evolução. Alternativa: `CustomPaint`
  (sem dep, padrão atual). _(Decisão #1)_
- (Fase 5, opcional) `pdf` + `printing`/`share_plus` — export PDF.

---

## 7. Sequenciamento sugerido
**0 → 1 (registro básico, valor cedo) → 2 (fotos) → 3 (portal + gráficos) → 4
(composição/metas) → 5 (polish).**

> A Fase 1 já entrega "avaliação física funcional" (registrar + ver histórico/delta).
> Fotos e gráficos (2–3) são o que dá o "uau" de evolução pro aluno.
