# Plano — Módulo Trocação (C1–C3)

> Features para combate de trocação (Muay Thai · Boxe · Kickboxing).
> SportId de trocação: `muaythai`, `boxing`, `kickboxing` (`.value`). Gateado por
> nova `FeatureId.striking` → `AcademySettings.strikingEnabled` (opt-in, default
> off). Código em inglês (`striking…`), UI em pt-BR ("Trocação").

## Decisões do dono (2026-06)
- **Ordem:** C1 → C3 → C2 (cada uma é uma fase com auditoria).
- **C1 Timer:** portal do aluno **e** staff; presets configuráveis (rounds /
  duração do round / descanso); alerta sonoro + vibração. UI pura (sem backend).
- **C1 Registro:** o **aluno** registra a sessão (tipo + rounds + RPE 1-10 +
  notas + duração). Histórico pessoal. Espelha o registro de execução (A6).
- **C3 Cartel:** só **staff** cria/edita (cartel oficial); aluno vê. Resultado
  V/D/E + método (KO/TKO/Decisão/Finalização/Desqualif.) + evento/data/adversário/
  peso/rounds/vídeo/notas. Resumo "XV-YD-ZE (N nocautes)".

## Infra comum (reuso confirmado)
- Coleções sob `academies/{id}/` (`firebase_service.dart` Collections + barrel).
- Regras: `isAcademyStaff` / `belongsToAcademy` / `isStaffOrMonitor` /
  `isOwnStudentRecord` / `isResponsibleForStudent`.
- Nav: `FeatureId.striking` + NavEntry (portal + admin), rota em `app.dart`.
- Helper puro testável em `lib/core/` + teste em `test/core/`.

---

## C1 — Timer de rounds + registro de sessão  ← **FASE ATUAL**

### Helper puro — `lib/core/striking_timer.dart` (+ testes)
- `String fmtMmss(int seconds)` → "MM:SS".
- `List<TimerPhase> buildPhases({rounds, roundSec, restSec})` → sequência
  round/descanso (sem descanso após o último round).
- `int totalSessionSeconds(...)`.
- `TimerPhase { kind (round|rest), index, seconds }`.

### Timer (UI pura) — `lib/screens/portal/striking_timer_screen.dart`
- Presets: nº de rounds, duração do round (mm:ss), descanso (mm:ss). Defaults
  3×3min / 1min.
- Tela cheia: fase atual (Round N / Descanso), contagem regressiva grande,
  progresso, play/pause/reset, próximo/anterior.
- Alertas: `HapticFeedback` (vibração) + `SystemSound.alert` nos 10s finais e na
  virada de fase (sem dependência nova de áudio).
- Ao terminar: oferece "Registrar sessão" (pré-preenche rounds/duração).

### Registro de sessão (backend)
- Modelo `lib/models/striking_session.dart`: `StrikingSession` + enum
  `StrikingType {bag(saco), pads(manoplas), sparring, clinch, technique(técnica)}`.
  Campos: id, studentId, studentName, sport, type, rounds, roundDurationSec?,
  totalMinutes?, rpe(1-10)?, notes?, date, createdAt.
- Serviço `lib/services/striking_session_service.dart`: `create`, `getByStudent`
  (ordena por date desc). Doc auto-id (várias por dia).
- Coleção `strikingSessions`. Regras: aluno cria/lê as suas; staff lê; responsável
  lê. Espelha `workoutExecutions`.

### Portal — `lib/screens/portal/striking_screen.dart` (hub, rota `/portal/trocacao`)
- Botão grande "Iniciar timer" → timer.
- "Registrar sessão" → sheet (tipo, rounds, duração, RPE slider, notas).
- Histórico de sessões (lista, agrupada por mês) com resumo.
- (C2/C3 ganham seções/atalhos aqui depois.)

### Settings + nav
- `AcademySettings.strikingEnabled` (default false) + `updateStrikingEnabled`.
- Card "Trocação" na aba Funcionalidades (toggle).
- `FeatureId.striking` (→ strikingEnabled). NavEntry portal "Trocação"
  (`/portal/trocacao`, section treinos). Index `strikingSessions(studentId,date desc)`.

---

## C3 — Cartel / ficha de luta (fase seguinte)
- Modelo `FightRecord`: studentId, result (win|loss|draw|nc), method (ko|tko|
  decision|submission|dq|other), event, date, opponent, weightClass?, rounds?,
  videoUrl?, notes, createdBy. Coleção `fightRecords`.
- Helper puro `cartel.dart`: agrega `CartelSummary {wins,losses,draws,nc,koWins}`
  + label "XV-YD-ZE" (+ testes).
- Admin: CRUD por aluno (staff). Portal: "Meu cartel" (read-only) com resumo +
  lista. Regras: staff escreve; aluno/responsável lê o seu.

## C2 — Biblioteca de combinações (fase final)
- Clone do catálogo+audiência de `content`/`exercises`: `Combo` (name, sequence:
  List<String> de golpes, level, sport, videoUrl, audience academy|sport|students,
  assignedStudentIds). Coleção `combos`. Admin CRUD + seed; portal lista por
  esporte/nível com "Ver vídeo".

## Fora de escopo (C1–C3)
- Pontuação automática de luta / scorecards de juízes.
- Sincronização do timer entre dispositivos (cada um roda o seu).
- Conexão com o módulo de competições genérico (cartel é separado, por decisão).
