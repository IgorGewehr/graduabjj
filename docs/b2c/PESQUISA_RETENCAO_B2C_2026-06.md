# Relatório de Pesquisa de Mercado + Playbook de Retenção — Portal do Lutador (GraduaBJJ)

**Autor:** Head of Product/Growth
**Escopo:** o que faz o lutador VOLTAR todo dia por vontade própria e o que cria CULTURA — explicitamente NÃO monetização.
**Tese de uma frase:** o GraduaBJJ já tem todos os *troféus* (faixa, conquistas, ranking, streak, timeline), mas o loop hoje é dirigido pela academia (presença marcada pelo professor). Falta tudo que faz o lutador abrir o app num dia sem treino. A virada B2C é tratar `student` como *lutador-com-uma-jornada* — e não como *aluno-de-uma-academia*.

---

## 1) Sumário executivo — as 7 mecânicas que mais importam

Ordenadas por evidência de retenção e por aderência ao caso BJJ.

1. **Mesma ação, dois consumidores.** O registro administrativo (presença) tem que virar simultaneamente um post de identidade do lutador. Não criar fluxo novo — instrumentar o existente. *Strava cresceu transformando o ato de "registrar" no ato de "ser visto"; o criador correu ~2x mais no 1º ano só porque o esforço virava capital social visível.*

2. **A rede > a academia (grafo cross-academy).** O lock-in do Strava não é a feature, é a rede ("usuários entram pelo network, não pelas features"). O lutador precisa seguir outros lutadores de qualquer academia. Isso descola a retenção da adoção da academia — é o pivô central do B2C. Marune (concorrente direto) já faz "add and connect with friends" + diretório de 11.600 escolas; o GraduaBJJ não tem conceito de amizade/seguir.

3. **Kudos = "Oss/Respeito" (validação de 1 toque).** Não é cosmético: o estudo *"Kudos make you run"* comprova contágio social — receber/dar kudos muda o comportamento de treinar. Strava registrou **14 bilhões de kudos em 2025 (+20% YoY)**; features sociais aumentam a duração média de streak em **+34%**. Hoje no GraduaBJJ não existe like/kudos/comentário/reação em lugar nenhum. É provavelmente o **maior ROI de retenção não-explorado**.

4. **Streak resiliente (estilo Gentler/Whoop, NÃO Duolingo diário).** Streak é o motor nº1 via *loss aversion*: Duolingo retém **2,4x** quem tem streak de 7+ dias; freeze elevou a média de **11,62 → 17,19 dias (+48%)**. MAS o BJJ se treina 2-4x/semana e exige recuperação. O streak tem que sobreviver ao descanso e à lesão (**streak SEMANAL + freeze**), nunca punir o corpo do atleta.

5. **Leaderboards SEMPRE segmentados e por consistência, nunca global por performance.** A faca de dois gumes: ranking competitivo dá +41% de frequência ao top 20%, mas o **bottom 40% reduz logs em 53%**. Solução comprovada: cohorts (faixa/peso/cidade/círculo), ranquear *streak/consistência/progresso* (não "quem é melhor lutador"), **esconder o fundo da tabela**, e tudo opt-in. Liga local funciona (Duolingo: retenção 12%→55%); ranking global humilha 99%.

6. **Cards nativamente instagramáveis.** Strava teve que *inventar* a assinatura visual (o mapa da rota); o BJJ já tem rituais visuais nativos — faixa, grau, fita, pódio, finalização. Hoje isso é **literalmente impossível** no app (sem `share_plus`, sem `RepaintBoundary→toImage`). Aquisição viral grátis presa dentro do app.

7. **Retorno diário é social + cultural, não de treino.** O lutador descansa muito. O motivo de abrir o app num dia de folga precisa vir de feed dos seguidos, dar "oss", defender status no ranking e conteúdo de cultura/lore — não de uma aula agendada. Hoje 3 dos 4 elementos do "hero do dia" dependem de aula marcada; o 4º (streak) é passivo.

**Princípio de monetização (para não trair o objetivo):** Free = social/identidade/compartilhável (o motor de hábito e aquisição). Paid = análise de performance e/ou a camada academia (o B2B que já existe). **Jamais** cobrar pela camada que gera o hábito B2C: feed, perfil, card de graduação, seguir, "oss".

---

## 2) Teardown por app — o que copiar e o que evitar

### Strava — o blueprint do loop social
**Loop:** registrar → upload vira post automático com stats → kudos + comentários → leaderboard local de segmentos → volta pra defender/melhorar.
**Copiar:**
- Registro = ser visto (mesma ação, dois consumidores).
- Três camadas de grafo: **seguir** (feed assíncrono), **clubes** (academia/equipe/faixa/cidade com leaderboard próprio), **desafios** (meta com prazo).
- Free retém o que gera rede: uploads ilimitados, kudos, comentários, clubes, top-10. Paid = análise (Fitness&Freshness, predições, filtros, IA).
- Gatilhos de retorno disparados por **humanos**, não pelo sistema (críveis, não-spam): "Fulano deu oss", "você caiu pro 3º", "seu rival treinou hoje". Mais o "Year in Sport" anual (retrospectiva = pico de compartilhamento e reativação).
**Evitar:** ranking global; paywall na camada social.

### Duolingo — o motor de streak e ligas (com ressalva ética)
**Copiar:**
- Streak como compromisso de identidade + *loss aversion*.
- **Freeze/proteção** (contra-intuitivo: 2 freezes > 1; flexibilidade AUMENTA retenção porque reduz a ansiedade que faz desistir de vez).
- **Ligas com matching por hábito/nível** (não global): benign envy + aversão de perda assimétrica (medo de cair > vontade de subir).
**Evitar (crítico):** streak DIÁRIO obrigatório, mascote culpado, notificação loss-framed/spam. A coruja virou meme de culpa; usuários abandonam o app inteiro pra não "quebrar" o recorde. **40% dos teens (2025)** já limitam uso por ansiedade/FOMO. Para um app de atleta, isso é veneno duplo (overtraining + lesão).

### BeReal — o caso de fracasso (o que NÃO fazer)
MAU caiu de ~73M (ago/22) → 33M (mar/23). Lições:
- **Urgência aleatória forçada degrada a qualidade do conteúdo** e empurra o usuário a encenar/fingir.
- Sem ferramentas de criador e feedback social, não há razão de longo prazo.
- Trazer marcas/celebridades matou a premissa central.
**Tradução BJJ:** não force "registre AGORA"; não deixe a academia/marca diluir a premissa centrada no lutador; dê analytics pessoais e feedback social reais.

### Whoop — dado como identidade (loop diário sem gamificação óbvia)
**Copiar:** razão diária de abrir = "como meu corpo/jogo está hoje". O dado fica mais valioso com o tempo (baseline pessoal). Mat hours, carga semanal de tatame, evolução de submissões/sweeps, "prontidão para treinar" — o lutador volta pra *ver quem ele está virando*, desacoplado da academia. Uso diário associado a +91 min de atividade/semana.

### GymRats / Peloton / Discord — accountability e comunidade
**Copiar:**
- **Check-in "1-tap + foto"** (selfie suada / foto do tatame). Atrito baixo é o produto.
- **Buddy/time > meta individual:** +40% de adesão após 6 meses com amigos; RCT de 1.247 adultos → **+38% retenção em 30 dias** e **2,3x mais atividade** em desafios de time com threshold coletivo.
- **High-Five / micro-gestos:** Peloton — quem interage socialmente treina **15% mais**; tribos = **+20% retenção**.
- **Discord como benchmark de qualidade humana:** grupos peer-led tiveram **+42% adesão em 90 dias** *porque havia menos vergonha de dias perdidos* — e **sem likes/followers/contadores**. A ausência de métricas de vaidade cria espaço para autenticidade.
**Tradução BJJ:** o "clube" NÃO deve ser a turma da academia, mas um **círculo auto-escolhido (3-30 pessoas)** — parceiros de treino, amigos de outras academias, gente de campeonato. É o container de accountability que sobrevive à troca de academia, viagem e lesão.

---

## 3) A psicologia do retorno diário

**Streak / loss aversion.** Depois de investido, o medo de perder pesa mais que a vontade de avançar. É o mesmo princípio do lutador "não querer zerar a frequência". Mas funciona só se o streak respeitar a fisiologia do esporte — daí streak **semanal + freeze**, modelo *Gentler Streak* ("move consistently, not constantly"; o streak sobrevive a dias de descanso e o app *sugere* descanso se você força demais). Eticamente defensável E mais retentivo.

**Identidade (a camada que torna o hábito permanente).** Atomic Habits: mudança real vem de identidade, não de resultado. "Sou um lutador" > "quero treinar mais". Cada interação diária deve reforçar *"eu sou um jiujiteiro"* — não "complete sua tarefa". Toda graduação, mat hour, roll registrado, foto de treino = prova acumulada de identidade. O streak não conta dias; conta *quem ele está se tornando*.

**Prova social (o churn killer).** Visibilidade muda a psicologia da consistência: quem é visto por pessoas que importam treina mais consistentemente. Capital social compartilhável é o maior anti-churn comprovado.

**Recompensa variável.** Kudos/comentários/reações chegam de forma imprevisível (vêm de outras pessoas) — é o reforço variável que cria o check ansioso. Ligas e defesa de posição no ranking adicionam incerteza saudável.

**FOMO ético.** Use a urgência social *real* ("seu rival treinou hoje", "desafio termina amanhã"), nunca a urgência fabricada e aleatória (erro do BeReal) nem a culpa fabricada (erro do Duolingo). A regra: o gatilho vem de um humano, é verdadeiro, e o usuário pode optar por sair.

**A diferenciação verificada do GraduaBJJ.** O espaço "log social de BJJ" NÃO está vazio — existem MatTime ("Strava for BJJ", 50+ academias), BJJ Notes (20k+ users), BJJBuddy, Jiu-Jitsu Logs, Marune. Todos são **auto-reportados**. A vantagem única do GraduaBJJ é o acoplamento já existente com a academia real (presença/faixa/financeiro verificados) virando **prova social VERIFICADA** — graduação real, não auto-declarada. Isso nenhum standalone tem.

---

## 4) Conteúdo compartilhável/instagramável — o que faz QUERER postar

O que faz alguém postar é "transformar esforço individual em capital social" e fazer a conquista "parecer tão épica quanto foi". O BJJ herda de graça os rituais visuais que o Strava teve que inventar:

- **Card de graduação/grau** — a foto da faixa nova já é ritual nativo do BJJ. Maior alavanca.
- **Card de streak / "X aulas este mês" / horas no tatame.**
- **Card de competição** — medalha, chave, vitória por finalização. O *tipo de finalização* é a "rota" do Strava: a assinatura técnica do atleta.
- **Card de milestone** — 100 rolas, 1 ano de treino, primeira fita.
- **"Year in BJJ" anual** — total de horas, finalizações, graus, pódios.

**Requisitos de produto:** bonito por default; leva a marca pra fora (aquisição viral grátis); postável direto no Story em 1 toque. A `AnimatedBelt` e a `timeline_screen` já são os ativos mais "instagramáveis" do app — só falta a ponte técnica (`share_plus` + `RepaintBoundary→toImage`), hoje inexistente.

---

## 5) O que o GraduaBJJ já tem vs gaps (com file:line)

### Já temos (os artefatos de gamificação)

| Mecânica | Onde vive | Estado real |
|---|---|---|
| Streak | `lib/services/attendance_service.dart:325` (`getStudentStreak`); `lib/widgets/portal/home_hero_card.dart:400-507` (`_StreakHero`) | Dias **consecutivos de calendário** (`diff == 1`, linha 342). Quebra com treino seg/qua/sex — o padrão real do BJJ. Sem freeze, sem meta semanal. Oposto do necessário. |
| Conquistas/badges | `lib/services/achievement_service.dart` (7 tipos) | Catálogo decente, mas quase tudo é criado pelo professor/server (`createdBy`). Milestones automáticos só em 50/100/200/500/1000 (`createAttendanceMilestone:572`) e aniversários (`createAnniversaryMilestone:600`). |
| Ranking | `lib/screens/portal/ranking_screen.dart`; `gamification_section.dart:30` | Ranking de presença **DA TURMA** — some sem academia. Períodos só semana/mês (`RankingPeriod:282`), sem ligas/divisões. |
| Meta mensal | `lib/core/gamification.dart`; `gamification_section.dart:56` (`_monthCard`) | Barra "X/Y aulas", boa — mas meta definida pela academia (`academyDefault`, gamification.dart:10). |
| Timeline/jornada | `lib/screens/portal/timeline_screen.dart`; `lib/services/timeline_builder.dart` | Ativo mais instagramável (`AnimatedBelt`, medalhas, marcos). Mas read-only, **sem botão compartilhar**. |
| Perfil público | `lib/screens/portal/public_profile_screen.dart`; `isProfilePublic` em `lib/models/student.dart:335` | 3 abas, faixa hero. Espelho `publicProfiles` sem PII já existe — boa fundação B2C. |
| Faixa animada | `lib/widgets/common/animated_belt.dart` | Melhor elemento de identidade. Candidato nº1 a card compartilhável. |
| Celebração | `Celebration.confetti` em `home_screen.dart:1045` | Dopamina existe, mas dispara raríssimo (só perto da graduação). |

### Gaps concretos

- **A. Nenhum motivo para abrir num dia sem aula.** Todo o `home_hero_card.dart` resolve para check-in → próxima aula → musculação → streak; os 3 primeiros dependem de aula agendada, o 4º é passivo. O aluno **não pode registrar nada sozinho** num dia de descanso.
- **B. Zero compartilhamento.** Não existe `share_plus`, `RepaintBoundary`/`toImage`, nem geração de story/card em todo o `lib/`. Instagramável é impossível hoje.
- **C. Streak frágil.** `getStudentStreak` (`attendance_service.dart:325`) quebra com 1 dia de gap. Falta streak semanal + freeze + meta semanal auto-definida.
- **D. Reconhecimento entre pares inexistente.** Nenhum kudos/like/comentário/reação no portal. Maior ROI não-explorado.
- **E. Sem grafo social.** Nenhum conceito de amizade/seguir/descobrir. Só vê quem está na mesma turma da mesma academia.
- **F. Sem diário de técnicas.** Só "presença" (booleano marcado por terceiro — `markPresent`, `attendance_service.dart:360`). Nenhum campo de técnica/gi-nogi/rola/observação do próprio aluno — exatamente o que Marune/BJJBuddy/BJJ Notes vendem.
- **G. Conquistas entregues, não conquistadas.** Quase todo `create*` em `achievement_service.dart` é chamado por staff/server. Falta catálogo que o aluno destrava agindo.
- **H. Sem feed/cultura.** O Jornal (`jornal_screen.dart`) é top-down (academia→aluno), não lutador↔lutador. Lineage/oss/técnica da semana não têm superfície.
- **I. Notificação só transacional.** `notification_dispatcher.dart` notifica conquista criada pelo professor. Sem push de retenção social.

### O acoplamento à academia (o que precisa de versão "solo")

Tudo abaixo retorna vazio se `academyId == null` (ex. `timeline_screen.dart:41`, `public_profile_screen.dart:67`):

| Recurso | Acoplamento atual | Versão solo necessária |
|---|---|---|
| Presença/streak | `markPresent` exige `classId`/`className`/`verifiedBy` (`attendance_service.dart:360-371`) | Auto-log do próprio lutador (treino em casa, viagem, academia fora do app) |
| Ranking | `classRankingProvider`, escopo turma + gate `rankingVisibleToStudents` | Liga regional/entre amigos, independente de turma |
| Meta mensal | `effectiveMonthlyGoal` puxa default da academia (`gamification.dart:10`) | Meta auto-definida pelo lutador |
| Timeline/conquistas | `BeltProgressionService(academyId)` (`timeline_screen.dart:25`); achievements em subcoleção da academia (`achievement_service.dart:246`) | Badges pessoais que pertencem AO LUTADOR, fora do escopo da academia |
| Perfil público | resolve `academyId` (`public_profile_screen.dart:57`) | Espelho `publicProfiles` já é a base ideal sem academia |

**Implicação arquitetural:** o app modela `student` como `Collections(academyId).students`. A virada B2C exige um **modelo de identidade do lutador que persista ACIMA da academia** — a academia vira vínculo *opcional* que enriquece (presença verificada, graduação oficial), não o container de tudo. O espelho `publicProfiles` é a melhor alavanca existente nessa direção.

---

## 6) Recomendações priorizadas para o portal do lutador (voltar todo dia + cultura)

Faseado por ROI de retenção / esforço. Foco em hábito e cultura — não lucro.

### Fase 0 — Fundação de identidade (pré-requisito arquitetural)
- **Promover o lutador acima da academia.** Garantir que perfil, faixa, badges pessoais e timeline persistam mesmo com `academyId == null`, usando o espelho `publicProfiles` (sem PII) como home do dado B2C. Sem isso, nada abaixo funciona "solo".

### Fase 1 — Quick wins de alto ROI
1. **Compartilhamento da faixa/timeline/conquista** (maior alavanca de aquisição+vaidade, esforço baixo): `share_plus` + `RepaintBoundary→toImage` sobre `AnimatedBelt` e cards de conquista. Marca embutida → aquisição viral grátis. *Hoje impossível.*
2. **Streak resiliente + freeze**: trocar "dias consecutivos" por **semanas de treino** + 1-2 freezes; meta semanal auto-definida. Mexe principalmente em `getStudentStreak`. Modelo Gentler/Whoop, nunca Duolingo diário.
3. **Check-in de treino "1-tap + foto" solo** desacoplado de presença: o lutador loga treino em qualquer lugar. Unidade atômica de tudo. Alimenta streak e badges sem depender do professor.

### Fase 2 — A camada social (o motor de retenção real)
4. **Kudos / "Oss / Respeito"** (reação 1-tap) sobre `publicProfiles`/ranking e sobre check-ins. +34% de streak comprovado; maior ROI não-explorado.
5. **Grafo social cross-academy**: seguir lutadores de qualquer academia + feed assíncrono dos seguidos. Descola a retenção da adoção da academia.
6. **Círculo/clube auto-formado (3-30 pessoas)**, independente de academia, com feed de check-ins e High-Five. Container de accountability que sobrevive à troca de academia/viagem/lesão.

### Fase 3 — Profundidade e cultura
7. **Diário de técnicas** (gi/no-gi, % de rola, técnicas via hashtag, instrutor, finalizações aplicadas/sofridas): conteúdo gerado pelo lutador, cria hábito diário. Aproveita a prova VERIFICADA (presença/graduação reais) como diferencial sobre Marune/MatTime.
8. **Badges destraváveis por ação** (1ª foto, perfil completo, 10 técnicas logadas, madrugador, 100 rolas) — conquistados agindo, não entregues pelo professor.
9. **Leaderboards segmentados e por consistência** (faixa/peso/cidade/círculo/streak), fundo escondido, opt-in. Ligas estilo Duolingo, nunca ranking global de "quem é melhor".
10. **Feed de cultura/lore** (técnica do dia, debates de posição, history/lineage, highlights de campeonato) — motivo de voltar em dia de folga.
11. **Push de retenção social** (disparado por humanos): "Fulano deu oss", "você caiu pro 3º", "seu rival treinou hoje". Mais o **"Year in BJJ"** anual.

---

## 7) Riscos e anti-padrões

- **Streak tóxico (Duolingo trap).** Streak diário obrigatório + mascote culpado + notificação loss-framed faz o usuário abandonar o app inteiro pra não "quebrar". Em app de atleta é pior: incentiva overtraining e lesão. **Mitigação:** streak semanal, freeze, copy de identidade ("você é um jiujiteiro"), zero culpa.
- **Ranking global excludente.** Bottom 40% reduz logs em 53%. **Mitigação:** sempre segmentado, ranquear consistência/progresso, esconder o fundo, opt-in.
- **Métrica vira o ponto (metric fixation).** Gamificar o que a pessoa já ama (treinar) pode minar a motivação intrínseca. **Mitigação:** a métrica reforça identidade, não substitui a razão de treinar; default colaboração > comparação.
- **Erro do BeReal (urgência fabricada).** Forçar "registre agora" degrada o conteúdo e leva à encenação. **Mitigação:** urgência social real, não aleatória; dar ferramentas de criador (analytics pessoais).
- **Métricas de vaidade (lição Discord).** Inundar de contadores de seguidores/likes mata autenticidade e cria vergonha de dias perdidos. **Mitigação:** privilegiar encorajamento e identidade ("faixa-roxa, 4 anos, 1.200 rounds") sobre popularidade.
- **Marca/academia diluindo a premissa.** Se o app virar "canal da academia para o aluno" (top-down), perde o B2C. **Mitigação:** academia é vínculo opcional que enriquece; o feed é lutador↔lutador.
- **Paywall no lugar errado.** Cobrar pela camada social mata o motor de hábito e de aquisição. **Mitigação:** Free = social/identidade/compartilhável; Paid = performance/análise ou camada academia (B2B existente).
- **Privacidade / PII.** Ranking e perfil público devem ler o espelho `publicProfiles` (sem PII) e ser sempre opt-in. O lutador deve poder treinar "solo/privado" sem entrar em ranking nenhum.

---

**Conclusão.** O GraduaBJJ não precisa inventar a gamificação — ela já está no código. Precisa **inverter o dono do loop**: hoje a academia dirige (presença marcada pelo professor); amanhã o lutador dirige (check-in solo, oss entre pares, card compartilhável, streak que respeita o corpo). A diferenciação defensável contra Marune/MatTime é a **prova social verificada** (graduação e presença reais), que nenhum log auto-reportado tem. O caminho de menor esforço e maior impacto começa pelo compartilhamento da faixa e pelo streak resiliente — e culmina na camada social cross-academy, que é onde a retenção de verdade mora.