# Plano de Implementação — Modalidade Musculação

> **Status (2026-07): IMPLEMENTADO em produção** — `SportId.musculacao` em
> `lib/core/sports.dart`, `lib/services/musculacao_checkin_service.dart`,
> `lib/screens/admin/musculacao_admin_screen.dart`, CF `selfCheckin` em
> `functions/index.js`. Mantido como especificação de referência do que foi
> construído.
> Contexto: app Flutter + Firebase (iOS e Android) que hoje atende artes marciais.
> Objetivo: adicionar a modalidade **musculação**, que tem particularidades:
> sem graduação, sem horário de aula fixo, com entrega de vídeos e planilhas de treino.

## Decisões confirmadas

- **Check-in:** configurável por academia (QR fixo / botão no app / recepção manual).
- **Vídeos:** links externos (YouTube/Vimeo) **e** upload no Storage.
- **Planilhas:** montador estruturado no app **e** upload de arquivo (PDF/imagem).
- **Conteúdo (vídeos/planilhas):** recurso **geral** para todas as modalidades, exibido conforme o sport do aluno.

---

## 1. Diagnóstico: o que já existe a nosso favor

A base multi-sport já é madura, então boa parte do trabalho é configuração + features novas, não refatoração.

| Já pronto | Onde |
|---|---|
| Enum de modalidades e registry de definições | `lib/core/sports.dart:9` |
| `GradeSystem.none` (sem graduação) — Boxe já usa | `sports.dart:29`, `sports.dart:236` |
| `GradeDisplay` retorna vazio quando `GradeSystem.none` | `grade_display.dart:55` |
| Aluno multi-sport (`sportsList`, `sportData`, `primarySport`) | `student.dart:284-287` |
| Turma/aula com campo `sport` e `isOpenClass` | `class_service.dart:46,56` |
| Presença com snapshot de `sport` | `attendance_service.dart:25-28` |
| Auto-promoção pula sport sem graduação (`getNextPromotion`→null) | `belt_progression_service.dart:178` |
| Menus role-adaptive com "gates" condicionais | `portal_shell.dart:184-211`, `admin_shell.dart` |
| Upload de fotos no Storage (padrão a seguir) | `photo_upload_service.dart` |

**Conclusão:** "musculação sem graduação" sai quase de graça. O esforço real está em
**(A) check-in sem turma fixa**, **(B) display do aluno por modalidade** e
**(C) biblioteca de conteúdo (vídeos + planilhas)** — que hoje **não existe**.

### Achado de segurança importante
As regras (`firestore.rules:352-361`) só permitem **staff/monitor** gravar em `attendance`.
Hoje o `qr_attendance_service` chama `markPresent` direto do cliente (`qr_attendance_service.dart:247`),
o que só funciona quando quem escaneia é monitor/staff. Logo, o **self check-in da musculação
(botão + QR escaneado pelo aluno) precisa de uma Cloud Function** — não devemos afrouxar a regra.

---

## 2. Plano por fases

### Fase 0 — Fundação do sport `musculacao`
Mudança pequena e isolada, base para todo o resto.

- `lib/core/sports.dart`: adicionar `musculacao` ao enum `SportId:9`; criar `SportDefinition` com
  `gradeSystem: GradeSystem.none`, `adultGrades: []`, `supportsKids` conforme regra de negócio,
  ícone (`Icons.fitness_center`); registrar em `sports:180`, `sportOptions:255` e `sportChipColors:319`.
- Valor de string no Firestore: `"musculacao"` (consistente com `SportId.value`).
- **Sem migração de dados:** academias existentes mantêm fallback `['bjj']`
  (`academy.dart` → `effectiveSports`). Habilitar musculação = adicionar à lista `sports` da academia.

**Resultado:** musculação aparece em seletores, chips e formulários, já sem faixa/graduação
em qualquer lugar que use `GradeDisplay`.

### Fase 1 — Display do aluno adaptado por modalidade
Hoje a home mostra faixa + progresso de graduação do `primarySport`
(`home_screen.dart:76-81,113-121`).

- **Esconder faixa e card de graduação** quando `primarySport` for `GradeSystem.none`.
  O `GradeDisplay` já some sozinho, mas o *welcome header* e o `_GraduationProgressCard`
  precisam de guarda explícita por `gradeSystem`.
- **Substituir por cards relevantes:** "Meu treino atual" (planilha ativa),
  "Vídeos recomendados", "Frequência no mês", botão de check-in (ver Fase 2).
- Tornar a home **sport-aware**: aluno multi-sport (BJJ + musculação) vê as duas coisas.
  Seções condicionais por `getSports()`.
- `student_form_screen.dart` já hidrata grades por sport (`:57-70`) — adicionar guarda para
  **não renderizar aba de faixa** para sports `GradeSystem.none`.

### Fase 2 — Check-in flexível (configurável por academia)
A maior mudança de lógica. Modelo recomendado: representar musculação como uma
**"turma aberta sem horário"** (`isOpenClass: true`, `schedule: []`, `sport: 'musculacao'`)
para reaproveitar todo o pipeline de `attendance`/relatórios/contagem, mudando só a validação de janela.

**Configuração (settings da academia):**
- Novo campo em `AcademySettings` (`settings_service.dart`):
  `musculacaoCheckinMode: 'qr' | 'button' | 'manual'` + `operatingHours` (abre/fecha por dia da semana).
- UI na tela de configurações (`settings_screen.dart`, aba Funcionalidades) — seletor de modo + horários.

**Validação de janela (mudança central):**
- `checkin_service.dart:isInCheckinWindow` (`:10`) e `qr_attendance_service.dart:214-236` hoje exigem
  `ClassSchedule`. Adicionar caminho: se a turma é sport sem horário, validar contra **horário de
  funcionamento da academia**. ID determinístico de presença: `studentId_musculacao_YYYYMMDD`
  (um check-in/dia).

**Os três modos:**
1. **QR fixo:** novo payload sem `classId`/sem TTL de 60s (`qr_attendance_service.dart:13`).
   Encoda `academyId` + marcador de musculação; QR estático/diário na recepção.
   ⚠️ Sem TTL curto → validação anti-fraude tem que ser **server-side**.
2. **Botão "Cheguei":** card na home do aluno de musculação.
3. **Manual:** tela de chamada da recepção/instrutor listando alunos de musculação
   (adaptar `attendance_screen.dart` para lista sem turma).

**Segurança — Cloud Function obrigatória (`functions/index.js`):**
- Criar `selfCheckin({academyId})` (callable, Admin SDK) que valida: membro ativo, sport habilitado,
  dentro do horário de funcionamento, dedup do dia, assinatura ativa.
  Modos *QR fixo* e *botão* chamam essa função; *manual* segue na escrita de staff/monitor existente.
- Conserta também a inconsistência atual onde o QR self-scan só funciona para monitores.

### Fase 3 — Biblioteca de conteúdo: base + planilhas estruturadas
Recurso **geral** (todas as modalidades), exibido por sport.

**Modelos / Firestore** (novas subcollections em `academies/{id}/`):
- `workoutPlans` — planilha estruturada:
  `{ title, sport, days: [{ name, exercises: [{ name, sets, reps, load, restSeconds, notes, videoRef? }] }], fileUrl? }`.
  Suporta o **montador** e **arquivo** (Fase 5).
- `content` — vídeos/documentos (Fase 4).
- `contentAssignments` — alvo da entrega: `academy-wide | sport | classId | studentIds[]`.

**UI instrutor/admin:** nova rota `/admin/conteudo` — montador de treino + atribuição.

**UI aluno (portal):** nova aba "Treinos"/"Biblioteca" (`/portal/treinos`) listando conteúdo atribuído,
render nativo da planilha. Gates de menu por disponibilidade (padrão `portal_shell.dart:184-211`).

**Regras Firestore:** novos blocos (staff escreve; aluno lê o atribuído ou da sua modalidade).

### Fase 4 — Vídeos (links + upload)
- **Links externos:** instrutor cola URL (YouTube/Vimeo); player embutido.
- **Upload:** vídeo no Storage em `academies/{id}/content/videos/{id}.mp4`, limite de tamanho, upload resumável.
- **Dependências novas (ver §3):** player de vídeo + player de YouTube + `file_picker`.
- ⚠️ **App Store/Play (UGC):** conteúdo enviado por usuários costuma exigir denúncia/moderação e termos.

### Fase 5 — Planilhas em arquivo + polish
- Upload de PDF/imagem da planilha (`academies/{id}/content/plans/{id}.pdf`).
- Visualização: viewer de PDF embutido **ou** abrir externamente via `url_launcher` (recomendado v1).
- Polimento: marcar exercício como feito, histórico de treinos, notificações de "nova planilha/vídeo".

---

## 3. Mudanças transversais (iOS + Android)

**Novas dependências no `pubspec.yaml`** — todas com setup específico por plataforma:
- `file_picker` — seleção de vídeo/PDF. iOS: ajustes no `Info.plist`; Android: ok.
- `video_player` (+ `chewie`) — mp4 do Storage. https do Storage dispensa exceção de ATS no iOS.
- `youtube_player_iframe` (ou `_flutter`) — embed YouTube; iOS/Android. Vimeo via webview/`url_launcher`.
- PDF: `pdfx`/`syncfusion_flutter_pdfviewer` **ou** apenas `url_launcher` (abrir externo — recomendado v1).
- Câmera (QR) já configurada via `mobile_scanner`.

**`storage.rules` — não existe hoje (gap de segurança).** Criar e registrar em `firebase.json`:
foto de perfil (já em uso), conteúdo de academia (staff escreve, membro lê), limites de tamanho/content-type.

**`firestore.rules`:** novos blocos para `workoutPlans`, `content`, `contentAssignments`.
**Não** mexer na regra de `attendance` (self check-in vai por função).

**`firestore.indexes.json`:** índices para conteúdo por `sport`, por `assignedStudentIds`
(array-contains) e atribuições. Presença por `studentId/date` já existe.

**`functions/index.js`:** adicionar `selfCheckin` (callable, Node 20, sem build step — segue o padrão
das 7 funções existentes).

---

## 4. Riscos e pontos de atenção

1. **Segurança do check-in:** QR fixo sem TTL é fácil de compartilhar. A função `selfCheckin` mitiga
   com horário + dedup + assinatura; avaliar geofencing opcional (GPS) se fraude for preocupação real.
2. **Custo de Storage/banda:** vídeos hospedados escalam custo rápido. Priorizar links externos e
   impor limites de tamanho/duração no upload.
3. **Revisão nas lojas (UGC):** vídeos enviados por usuários → precisa de denúncia/moderação e termos.
4. **`storage.rules` ausente hoje:** qualquer upload novo deve vir junto com regras.
5. **Aluno multi-sport:** garantir que quem faz BJJ + musculação veja faixa do BJJ e conteúdo da
   musculação sem conflito na home.

---

## 5. Sequenciamento sugerido

**Entregável mínimo cedo:** Fases 0 → 1 → 2 já dão "musculação funcional"
(cadastro, display sem faixa, check-in). Conteúdo (3 → 4 → 5) vem em seguida e é o de maior escopo.

Ordem recomendada:
**0 → 1 → 2 (com Cloud Function) → 3 (planilha estruturada) → 4 (vídeos) → 5 (arquivos/polish)**.
