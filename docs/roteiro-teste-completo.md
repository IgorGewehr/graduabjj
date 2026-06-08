# Roteiro de teste manual — módulos da branch `feat/evolucao-modulos`

> Guia de QA para validar tudo que entregamos antes do merge p/ produção.
> Marque `[x]` conforme for testando. Cada bloco diz **com qual conta** testar
> (admin = dono/instrutor; aluno = portal).
>
> **Contas de teste** (seed em 2026-06 — senhas simples, descartáveis, apagar no fim):
> - **Academia:** Lobisomens Jiu Jitsu (`nZJ00BMyGJ8xJGPQzVKL`)
> - **Admin:** sua própria conta (você é dono da Lobisomens)
> - **Aluno 1 (BJJ + Muay Thai):** `aluno1.lobi@teste.com` / `teste123` — já tem 8 presenças no mês
> - **Aluno 2 (Musculação):** `aluno2.lobi@teste.com` / `teste123`
> - **Aluno 3 (BJJ):** `aluno3.lobi@teste.com` / `teste123`
>
> Limpeza no fim: `…/seedLobisomensTest?secret=lobo-seed-7x9q2&action=clean` (depois deletar a function).

## 0. Pré-condições (admin → Ajustes → Funcionalidades)
- [ ] Ligar: **Reserva de aula**, **Trocação**, **Treinos**, **Vídeos**,
      **Graduação**, **Evolução**, **Loja**, **Musculação**, **Ranking**, **Jornal**.
- [ ] Em **Gamificação**, definir **Meta mensal = 12**.
- [ ] Ter ≥1 turma com **horário** e **limite de alunos** baixo (ex.: 2).

---

## A1 — Reserva de aula com vaga + lista de espera
**Admin (Ajustes):** ligar a feature; steppers Janela(7d)/Corte(60min)/Limite(3).
**Aluno (portal → Reservar aula):**
- [ ] Vê ocorrências dos próximos 7 dias, agrupadas por dia, com `X/Y vagas`.
- [ ] Aluno 1 e 2 reservam a mesma turma cheia (limite 2) → confirmam.
- [ ] 3º aluno → entra na **lista de espera** com posição.
- [ ] Aluno confirmado **cancela** → 1º da espera é **promovido** automaticamente + recebe aviso.
- [ ] Aula que começa em < 1h → botão Cancelar **desabilitado** com aviso.
- [ ] Tentar 4ª reserva futura (limite 3) → erro "Limite atingido".
- [ ] Turma fechada (com roster) não aparece p/ quem não é matriculado; turma aberta aparece p/ todos.
**Admin (Gestão → Reservas):**
- [ ] Lista de ocorrências `confirmados/limite · espera N`.
- [ ] Abrir ocorrência → **adicionar** aluno (busca) e **remover** (promove a fila).
- [ ] **No-show**: em aula encerrada, confirmado sem check-in aparece "Faltou".

## Trocação — C1 (timer + registro)
**Aluno (portal → Trocação):**
- [ ] **Iniciar timer** → ajustar rounds/duração/descanso → contagem, virada de cor round↔descanso, vibra/bipa nos 10s/3s e na virada, play/pause/pular.
- [ ] Ao fim → "Treino concluído" → **Registrar sessão** (pré-preenchido).
- [ ] Registrar: tipo (saco/manoplas/sparring/clinch/técnica), rounds, duração, RPE, notas → aparece no **histórico** por mês.
- [ ] Excluir uma sessão (confirma).

## Trocação — C3 (cartel/ficha de luta)
**Admin (abrir aluno → aba Cartel):**
- [ ] **Adicionar luta**: resultado (V/D/E/NC), método (KO/TKO/Decisão/Finalização/DQ), evento*, data, adversário, peso, rounds, vídeo, notas.
- [ ] Resumo no topo "XV-YD-ZE" + chips "N por nocaute/finalização".
- [ ] Editar e excluir luta.
**Aluno (portal → Trocação → Meu cartel):**
- [ ] Mesmo resumo + lista (read-only); botão de vídeo abre o link. Aluno **não** edita.

## Trocação — C2 (combinações)
**Admin (menu Conteúdo → Combinações):**
- [ ] Biblioteca vazia → **"Usar modelos prontos"** semeia boxe/MT/kick.
- [ ] Filtrar por modalidade; lista por nível; **Nova/editar** (golpes separados por vírgula).
- [ ] Com a biblioteca já populada, o botão de seed **não** reaparece (evita duplicar).
**Aluno (portal → Trocação → Combinações):**
- [ ] Golpes como chips com setas, por nível; botão "Vídeo" abre o link.

## A4 — Gamificação (meta mensal + surfacing)
**Admin:** Ajustes → Gamificação → Meta = 12; opcional override no cadastro do aluno.
**Aluno (home do portal):**
- [ ] Card **"Seu mês"**: barra "N/12 aulas" + (se treinou) chip "Xº no ranking".
- [ ] Bater a meta → barra verde + "Meta batida!".
- [ ] Override por aluno (cadastro → "Meta de frequência mensal" = 8) sobrepõe o padrão.
- [ ] Card **"Conquistas recentes"** (3 últimas) + "Ver todas" → timeline.
- [ ] Aluno sem meta/sem ranking/sem conquista → a seção **some** (não polui).
- [ ] (Já existentes do amigo) streak no hero, badges na timeline, tela de ranking.

## E2 — Calculadora de 1RM + metas de carga
**Aluno (portal → Treinos):**
- [ ] Ícone **calculadora** (AppBar) → carga 100 + reps 5 → 1RM ~116kg + tabela de %.
- [ ] Tela de evolução de um exercício → card **"Meta de carga"** → Definir 100kg → barra PR vs meta + "faltam Xkg / Meta batida". Editar/Remover. Só o aluno edita.

## E1 — Periodização (mesociclo)
**Admin (menu Conteúdo → Periodização):**
- [ ] **Novo**: nome, "Por modalidade"→Musculação, início = hoje, 4 semanas (Força 5x5 / Hipertrofia 4x10 / Pico 3x3 / Deload). Salvar.
**Aluno (portal → Treinos → ícone calendário):**
- [ ] Mesociclo com **"Você está na semana X de 4"** destacada; deload em amarelo.
- [ ] Sem data de início → lista semanas sem destaque. Inativo → some do portal.

## E4/E5 — Katas (Karatê) / Waza (Judô)
**Admin (Graduação → Currículo):**
- [ ] Modalidade **Karatê** (adulto), vazio → **"Usar template básico"** → semeia katas por faixa.
- [ ] Modalidade **Judô** → semeia nage-waza/katame-waza/ukemi por grau.
**Aluno de Karatê/Judô (portal → Minha Graduação):** técnicas/katas por faixa.

## Push (A2/F2)
> Só funciona após a config APNs (iOS) + nova versão publicada. Ver `docs/` e o passo a passo que te passei.
- [ ] (pós-release) Login → app pede permissão de notificação (aceitar).
- [ ] Disparar algo (comunicado do mestre / lembrete) → chega no aparelho com app fechado.
- [ ] Android funciona; iOS depende da chave APNs no Firebase.

---

## Regressão — features anteriores (não tocadas, conferir que seguem ok)
- [ ] **Graduação** (B1–B4): currículo, requisitos compostos, elegibilidade, aba Currículo/Minha Graduação.
- [ ] **Avaliação física** (A3): medidas, fotos privadas, Minha Evolução, PDF.
- [ ] **Treino/execução** (A5/A6): catálogo de exercícios, registrar séries, progresso/PR.
- [ ] **Check-in / chamada / turmas**, **financeiro** (inclui assinatura recorrente nova do amigo), **ranking por modalidade**.

## Limpeza (no fim)
- [ ] Apagar a academia de teste e as contas de teste (ver instruções do seed).
