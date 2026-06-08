# Roteiro de teste manual — módulos da branch `feat/evolucao-modulos`

> Guia de QA com os **nomes reais** de menus, abas, botões e campos do app.
> Marque `[x]` conforme testar. Cada passo diz a navegação exata e com qual conta.
>
> **Contas de teste** (seed Lobisomens — senhas descartáveis, apagar no fim):
> - **Academia:** Lobisomens Jiu Jitsu (`nZJ00BMyGJ8xJGPQzVKL`) — acesso liberado (sem paywall)
> - **Admin:** sua própria conta (você é dono da Lobisomens)
> - **Aluno 1 (BJJ + Muay Thai):** `aluno1.lobi@teste.com` / `teste123` — já tem 8 presenças no mês
> - **Aluno 2 (Musculação):** `aluno2.lobi@teste.com` / `teste123`
> - **Aluno 3 (BJJ):** `aluno3.lobi@teste.com` / `teste123`
>
> Limpeza no fim: `…/seedLobisomensTest?secret=lobo-seed-7x9q2&action=clean` (depois deletar a function).

## Mapa de navegação (nomes reais)
- **Menu admin** (agrupado por seção):
  - **Gestão:** Dashboard · Alunos · Chamada · Turmas · **Reservas** · Graduação · Campeonatos · Musculação · Jornal da Academia · Importar alunos
  - **Financeiro:** Cobrança · Relatórios
  - **Conteúdo:** Treinos · Vídeos · **Combinações** · **Periodização** · Loja
  - **Conta:** **Configurações** · Código de equipe
- **Menu portal (aluno):** Horários · Presenças · **Reservar aula** · Jornada · Evolução · **Graduação** · Minhas Modalidades · **Treinos** · **Trocação** · Vídeos · Ranking · Competições · Comportamento · Financeiro · Loja
- **Ligar features:** menu **Configurações** → aba **Funcionalidades** (cada feature é um card com switch "Habilitar …"). _(Já deixei tudo ligado no seed, mas é aqui que se mexe.)_

> As features novas só aparecem no menu quando ligadas em Configurações → Funcionalidades. O seed já ligou todas + meta mensal 12.

---

## A1 — Reserva de aula com vaga + lista de espera
**Config (admin → Configurações → Funcionalidades → card "Reserva de aula"):** switch "Habilitar reserva de aula"; ao ligar aparecem os steppers **"Janela de reserva"**, **"Corte p/ cancelar"**, **"Limite por aluno"**.
**Aluno (portal → "Reservar aula"):**
- [ ] Ocorrências dos próximos 7 dias, agrupadas por dia, com "X/Y vagas".
- [ ] Aluno 1 e Aluno 3 reservam a turma **"BJJ Adulto (teste)"** (limite 2) → botão **"Reservar"** → badge **"Confirmada"**.
- [ ] Pra ver fila com só 2 alunos: admin → **Turmas** → BJJ Adulto → mudar limite p/ **1**. Aí Aluno 1 reserva (lota); Aluno 3 vê **"Espera"** → reserva → badge **"Na espera"** com posição.
- [ ] Aluno 1 toca **"Cancelar"** → Aluno 3 é **promovido** automaticamente.
- [ ] Aula que começa em < 1h → botão de cancelar vira **"Sem cancelar (<60min)"** (desabilitado).
- [ ] 4ª reserva futura (limite 3) → erro "Limite de 3 reservas ativas atingido."
**Admin (menu → Reservas):**
- [ ] Lista de ocorrências com "confirmados/limite" e "espera N". Tocar uma ocorrência.
- [ ] Sheet com **"Confirmados (N)"** e **"Lista de espera (N)"**; botão **"Adicionar"** (busca aluno); lixeira remove (promove a fila).
- [ ] **No-show:** numa ocorrência encerrada, confirmado sem check-in aparece com **"Faltou"**.

## Trocação — C1 (timer + registro de sessão)
**Aluno (portal → "Trocação"):**
- [ ] Botão **"Iniciar timer"** → tela **"Configurar rounds"** (steppers "Rounds", "Duração do round", "Descanso") → **"Iniciar"**.
- [ ] Conferir: contagem regressiva, cor muda na virada round↔descanso, vibra/bipa nos 10s/3s e na virada, controles play/pause/pular.
- [ ] Ao terminar → tela verde → **"Registrar sessão"** (já vem com rounds/duração).
- [ ] No formulário **"Registrar sessão"**: "Tipo" (chips Saco/Manoplas/Sparring/Clinch/Técnica), "Rounds", "Duração total (min)", "Esforço (RPE)" (slider), "Notas" → **"Salvar sessão"**. Aparece no **"Histórico"** por mês.
- [ ] Botão **"Registrar"** (sem passar pelo timer) também abre o formulário.
- [ ] Excluir uma sessão (lixeira → confirma).

## Trocação — C3 (cartel/ficha de luta)
**Admin (menu Alunos → abrir um aluno → aba "Cartel"):**
- [ ] Botão **"Adicionar luta"**: campos "Resultado" (Vitória/Derrota/Empate/Sem resultado), "Método" (Nocaute (KO)/Nocaute técnico (TKO)/Decisão/Finalização/Desqualificação/Outro), "Evento *", "Data", "Adversário", "Categoria de peso", "Rounds", "Link do vídeo", "Notas" → **"Salvar luta"**.
- [ ] Resumo no topo "XV-YD-ZE" + chips "N por nocaute / por finalização". Ex.: 1 vitória por KO + 1 por finalização + 1 derrota → "2V-1D-0E".
- [ ] Tocar uma luta → editar; lixeira → excluir.
**Aluno (portal → "Trocação" → "Meu cartel"):**
- [ ] Mesmo resumo + lista (somente leitura); ícone de play abre o vídeo. O aluno **não** edita.

## Trocação — C2 (combinações)
**Admin (menu Conteúdo → "Combinações"):**
- [ ] Biblioteca vazia → botão **"Usar modelos prontos"** semeia boxe/MT/kick.
- [ ] Chips de modalidade no topo; lista por nível; botão **"Nova"** (FAB) → campos Nome, Modalidade, Nível, "Golpes (separados por vírgula)", "Link do vídeo", "Descrição" → **"Salvar combinação"**.
- [ ] Com a biblioteca já populada numa modalidade, o botão de "modelos prontos" **não** reaparece (evita duplicar).
**Aluno (portal → "Trocação" → "Combinações"):**
- [ ] Golpes como chips com setas, por nível; botão **"Vídeo"** abre o link.

## A4 — Gamificação (meta mensal + surfacing)
**Config:** Configurações → Funcionalidades → card **"Gamificação"** → stepper **"Meta mensal"** (já em 12).
**Override por aluno:** menu Alunos → editar aluno → seção de mensalidade → campo **"Meta de frequência mensal (Opcional)"**.
**Aluno (home do portal — Aluno 1, que tem 8 presenças):**
- [ ] Card **"Seu mês"**: barra "8/12 aulas" + (se houver ranking) chip "Xº no ranking".
- [ ] Card **"Conquistas recentes"** (até 3) + link **"Ver todas"** → abre a **Jornada**.
- [ ] Aluno sem meta/sem ranking/sem conquista → a seção **some** (não polui).
- [ ] (Já existentes) streak no card do topo (Hero), badges na Jornada, tela de Ranking.

## E2 — Calculadora de 1RM + metas de carga
**Aluno (portal → "Treinos" — use o Aluno 2 (Musculação)):**
- [ ] Ícone **"Calculadora de 1RM"** na AppBar (calculadora) → "Carga (kg)" 100 + "Reps" 5 → mostra "1RM estimado" (~116kg) + "Tabela de %1RM".
- [ ] **Meta de carga** (precisa de um treino com exercício + 1 série registrada): abrir um Treino → num exercício, botão **"Progresso"** → na tela, card **"Meta de carga"** → **"Definir"** → 100kg → barra (melhor PR vs meta) + "faltam Xkg / Meta batida". Editar/Remover. Só o aluno edita.
  > _Pré-requisito: admin cria um Treino (menu Conteúdo → Treinos) com 1 exercício e atribui ao aluno; o aluno registra 1 série. Sem isso, só dá pra testar a calculadora._

## E1 — Periodização (mesociclo)
**Admin (menu Conteúdo → "Periodização"):**
- [ ] FAB **"Novo"** → Nome, "Para quem" (Toda a academia / Por modalidade), "Início (opcional)" = hoje, botão **"Semana"** adiciona semanas (campos "Foco", "Prescrição", switch "Semana de deload") → **"Salvar mesociclo"**.
**Aluno (portal → "Treinos" → ícone "Periodização" na AppBar):**
- [ ] Mesociclo com badge **"Você está na semana X de N"** destacada; semana de deload em amarelo.
- [ ] Sem data de início → lista as semanas sem destaque. Mesociclo inativo → some do portal.

## E4/E5 — Katas (Karatê) / Waza (Judô)
**Admin (menu Graduação → ícone "Currículo de técnicas" no topo):**
- [ ] Trocar a modalidade para **Karatê** (adulto), currículo vazio → botão **"Usar template básico"** → semeia katas por faixa.
- [ ] Idem **Judô** → semeia nage-waza/katame-waza/ukemi por grau.
**Aluno de Karatê/Judô (portal → "Graduação"):** técnicas/katas por faixa.

## Push (A2/F2)
> Só funciona após a config APNs (iOS) + nova versão publicada (ver o passo a passo que te passei).
- [ ] (pós-release) Login → app pede permissão de notificação (aceitar).
- [ ] Disparar algo (comunicado / lembrete) → chega no aparelho com app fechado. Android funciona; iOS depende da chave APNs no Firebase.

---

## Regressão — features anteriores (conferir que seguem ok)
- [ ] **Graduação** (menu Graduação + ícone Currículo de técnicas): requisitos, elegibilidade; aluno → "Graduação".
- [ ] **Avaliação física / Evolução** (portal → "Evolução"): medidas, fotos privadas, gráficos, PDF.
- [ ] **Treino/execução** (menu Conteúdo → Treinos; portal → "Treinos"): registrar séries, "Progresso".
- [ ] **Chamada / Turmas / Presenças**, **Cobrança** (inclui assinatura recorrente nova), **Ranking** por modalidade.

## Limpeza (no fim)
- [ ] `…/seedLobisomensTest?secret=lobo-seed-7x9q2&action=clean` → me avisa que eu deleto a function de seed.
