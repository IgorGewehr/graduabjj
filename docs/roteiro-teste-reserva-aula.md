# Roteiro de teste manual — A1: Reserva de aula com vaga + lista de espera

> Feature em 4 fases (commits `9edba21`, `3fd0a80`, `9d9ea8d`, + auditoria).
> **Pré-requisito: deploy** (abaixo) — as callables rodam no servidor, então a
> feature NÃO funciona só com o app local apontando p/ prod sem o deploy.

## 0. Deploy (checkpoint do dono) — a partir DESTE repo (graduabjj = fonte canônica)

```
# 1. Functions (additivas: reserveClassSlot, cancelClassReservation)
firebase deploy --only functions:reserveClassSlot,functions:cancelClassReservation
# 2. Regras (classOccurrences/classBookings — escrita só via callable)
firebase deploy --only firestore:rules
# 3. Índices (occId,status,waitlistSeq) e (studentId,status,slotStart)
firebase deploy --only firestore:indexes
```

⚠️ `firebase deploy --only functions` (sem nome) re-deploya TODAS as functions —
inclui o trabalho do amigo já em prod; ok porque a branch == firebase-production.
Deployar **só as duas novas** (acima) evita tocar o resto.
Aguardar os índices saírem de "Building" no console antes de testar a fila.

## 1. Ligar a feature (admin → Ajustes → Funcionalidades)
- [ ] Card **"Reserva de aula"** aparece. Ligar o toggle → salva (snackbar).
- [ ] Aparecem 3 steppers: **Janela** (7 dias), **Corte p/ cancelar** (60 min),
      **Limite por aluno** (3). Ajustar cada um (−/+) → persiste.
- [ ] Com a feature ON: entrada **"Reservas"** aparece no menu admin (Gestão) e
      **"Reservar aula"** no portal do aluno. Com OFF: ambas somem.

## 2. Pré-condição de dados
- [ ] Uma turma com **horário(s)** definido(s) e **limite de alunos** (`maxStudents`)
      pequeno (ex.: 2) p/ testar lotação rápido. Ter ≥3 alunos elegíveis
      (matriculados na turma, ou turma aberta).

## 3. Reserva do aluno (portal → Reservar aula)
- [ ] Lista mostra ocorrências dos próximos 7 dias, agrupadas por dia, com
      `X/Y vagas` e horário/instrutor.
- [ ] Aluno A reserva → vira **Confirmada** (badge verde), contador X sobe.
- [ ] Aluno B reserva a mesma → confirma (chega no limite 2/2).
- [ ] Aluno C reserva a mesma (cheia) → botão era **"Espera"**; vira **Na espera**
      com posição. Contador de espera sobe.

## 4. Lista de espera + auto-promoção
- [ ] Aluno A **cancela** sua reserva confirmada → snackbar "próxima da espera
      promovida". Aluno C vira **Confirmada** automaticamente.
- [ ] Aluno C recebe **notificação** "Vaga confirmada!" (in-app; push só quando
      F2 estiver real).

## 5. Corte de 1h
- [ ] Reservar uma aula que começa em **< 1h** (ou ajustar o corte p/ um valor alto
      e uma aula próxima). O botão Cancelar fica **desabilitado** com aviso
      "Sem cancelar (<60min)".
- [ ] Tentar cancelar via aula distante → permitido.

## 6. Limite por aluno
- [ ] Com limite 3: aluno reserva 3 aulas futuras. Na 4ª → erro "Limite de 3
      reservas ativas atingido."
- [ ] Cancelar uma → consegue reservar outra.

## 7. Elegibilidade
- [ ] Aluno **não** matriculado numa turma **fechada** (com roster) não vê/não
      reserva essa turma.
- [ ] Turma **aberta** (ou sem roster) aparece p/ qualquer aluno.
- [ ] Multi-esporte: turma de Muay Thai aparece p/ aluno de MT; a reserva não
      interfere na graduação (presença continua separada — ver §9).

## 8. Admin — gestão de ocorrência (Gestão → Reservas)
- [ ] Lista de ocorrências (hoje + janela) com `confirmados/limite · espera N`.
- [ ] Abrir uma ocorrência → roster: **Confirmados** + **Lista de espera** (com
      posição).
- [ ] **Adicionar** aluno (busca) → confirma ou entra na espera. Staff **ignora**
      corte/janela/limite e gate.
- [ ] **Remover** (lixeira) um confirmado → se houver espera, promove o 1º.

## 9. No-show (depende do check-in QR/presença)
- [ ] Para uma ocorrência **já encerrada** com confirmados: marcar presença
      (check-in) de alguns. No roster, confirmados **sem presença** aparecem com
      badge **"Faltou"** (vermelho) e ícone de no-show; presentes com check verde.
- [ ] Confirmar que a reserva **não** virou presença sozinha (não infla
      graduação).

## 10. Bordas
- [ ] Reservar 2× a mesma aula (re-tap) → idempotente, sem erro, sem duplicar.
- [ ] Cancelar algo já cancelado → no-op silencioso.
- [ ] Editar/excluir a turma depois de reservada → o aluno ainda consegue
      **cancelar** a reserva (occId vem do booking, não recalculado).
- [ ] Turma **sem limite** (`maxStudents` vazio) → sempre confirma, sem fila,
      mostra "Vagas livres".
- [ ] Reserva ativa de aluno removido do roster ainda aparece p/ ele cancelar.

## Regressão rápida
- [ ] `flutter test` = verde (301+).
- [ ] Graduação/check-in/turmas seguem funcionando (não tocados).
