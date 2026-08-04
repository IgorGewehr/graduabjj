# A Ciência da Retenção: apps fitness, cultura do jiu-jitsu e o sistema de RIVAIS — Pesquisa & Estratégia (b2c)

> Pesquisa profunda de 2026-07-01 (deep-research multi-agente: 5 ângulos de busca → 30 fontes → extração de claims falsificáveis → verificação adversarial com 3 votos por claim).
> Complementa e CORRIGE a pesquisa interna de jun/2026 (`PESQUISA_RETENCAO_B2C_2026-06.md`, `PESQUISA_CULTURA_LUTADOR_2026-06.md`).
> Missão: transformar o GraduaBJJ numa máquina de retenção — aluno feliz, treinando, motivado e competitivo.

**Como ler os níveis de evidência usados neste doc:**
- **[A]** — claim verificado adversarialmente (3 verificadores independentes tentaram REFUTAR; sobreviveu 3-0, citação conferida verbatim na fonte primária).
- **[B]** — extraído diretamente da fonte primária com citação verbatim, mas sem a passada adversarial completa.
- **[C]** — fonte fraca (dado de vendor não-auditado, folclore da comunidade, amostra pequena/enviesada) — usar como direção, nunca como número de decisão.

---

## 0. TL;DR executivo — o que a ciência realmente diz

1. **Kudos/validação social funciona de verdade e é causal** [A]: receber "likes" no treino faz o atleta treinar mais e com mais frequência (estudo longitudinal de rede em clubes reais do Strava). É a mecânica social com a evidência mais forte de todas — e nós já temos o like no feed. O que falta é densidade e reciprocidade.
2. **MAS a influência social assimila PARA BAIXO** [A]: atletas convergem para o comportamento dos amigos que treinam MENOS, não mais (confirmado em 2 estudos independentes, um com 1,1 milhão de corredores). "Seguir alguém melhor que você" não puxa ninguém para cima automaticamente.
3. **Comparação ascendente só motiva em dose certa** [A]: alvos moderadamente acima do próprio nível motivam; alvos muito distantes DERRUBAM a motivação. E acesso irrestrito a outros usuários comprovadamente "não atende às necessidades dos usuários". Tradução: **rival tem que ser do seu tamanho, e o matchmaking tem que ser curado**.
4. **Gamificação empilhada sem encaixe = zero** [A]: o RCT Active Team (feed + presentes + leaderboard + streaks) não moveu atividade física objetiva (p=0,84). E o próprio Duolingo copiou uma mecânica do Gardenscapes com resultado "completamente neutro" [B]. Mecânica sem significado cultural não retém.
5. **Rivalidade tem efeito positivo médio sobre performance — com base causal** [B]: meta-análise (18 papers, 26.215 observações) + painel Topcoder (4,6 MILHÕES de encontros, atribuição aleatória) + corrida amadora (rival presente = ~4,9 s/km mais rápido). **Rivalidade individual > rivalidade de grupo**; rivalidade de grupo só é positiva justamente em ESPORTES.
6. **Mas rivalidade reverte em dois casos precisos** [B]: prejudica os MENOS habilidosos e quem está sob **risco de perder status** (+1 DP de rivalidade = 22,5% mais chance de cair uma posição quando há risco de rebaixamento). Rival + mecânica de demotion = receita de fuga.
7. **No BJJ, competição é quase universal entre quem persiste** [A]: 95% dos faixas-pretas já competiram vs 34% dos faixas-brancas (survey Gold BJJ, ~1.948 respondentes). Mas o motor declarado da regularidade do praticante amador é **saúde e prazer — competitividade é 4ª e sociabilidade é ÚLTIMA** [B, corroborado]. Competição é eixo de identidade e progressão, não o combustível diário.
8. **Os benchmarks internos de junho precisam de correção** (ver §2.4): o "+34% de streak" é dado de vendor mal-atribuído; o "-53% do bottom 40%" está errado em direção e magnitude — os estudos fortes mostram que leaderboard ajuda sedentários (+15%) e prejudica os JÁ ativos, com zona morta no MEIO da tabela, não no fundo.

---

## 1. Metodologia e limites

- Workflow deep-research: decomposição em 5 ângulos → buscas paralelas → fetch das ~15 melhores fontes por relevância → extração de claims falsificáveis com citação verbatim → 3 verificadores adversariais por claim (2/3 refutações matam o claim) → síntese.
- 107 agentes, ~30 fontes primárias fetched, 24 claims no funil de verificação final, 10 achados sintetizados com voto 3-0; 1 claim refutado 0-3 e descartado ("quase não havia estudos de eficácia de comparação social até 2020" — overreach da fonte).
- **Vieses conhecidos do corpo de evidência**: quase toda a ciência de comparação social vem de corredores/universitários contando passos, não de atletas de combate — a extrapolação para o BJJ é inferência de design. O survey Gold BJJ é auto-selecionado (audiência de loja de kimonos dos EUA), não amostra brasileira. Os dados de motivação BJJ brasileiros são de amostras pequenas (n=40 UFRGS 2010; corroborado por n=228 de 2023).

---

## 2. BLOCO 1 — A ciência por trás dos apps fitness que retêm

### 2.1 O que comprovadamente puxa o usuário de volta

**Validação social (kudos) — evidência causal, a mais forte do bloco** [A]
- Franken, Bekhuis & Tolsma 2023 (*Social Networks* 72:151-164): análise SIENA/SAOM (desenhada para separar influência de seleção) de 5 clubes reais do Strava, 329 corredores, 11 ondas mensais: *"receiving kudos induced runners to run more and more often"*. Três fontes independentes convergem (etnografia de Couture 2021; mixed-methods com 225 corredores noruegueses de Kolnes & Øvretveit 2026, onde tamanho da rede correlaciona com autoeficácia, r≈0,24-0,28).
- **Aplicação GraduaBJJ**: o like do feed é a semente certa. O "oss" de 1 toque precisa ser barato de dar, notificado ao receber (push já implementado na Repaginada F2) e RECÍPROCO — quem recebe kudos tende a retribuir e o laço vira loop.

**Streaks — funcionam, mas o mecanismo é perda-aversão bem calibrada** [B]
- Duolingo (relato do ex-CPO Jorge Mazal, Lenny's Newsletter): 4 anos de trabalho de retenção (streaks, ligas, notificações) = **CURR +21% e DAU 4,5x**; usuários que chegam a 10 dias de streak têm dropoff substancialmente reduzido; a fatia do DAU com streak 7+ quase TRIPLICOU para >50% do DAU. (O "retém 2,4x" do doc de junho não foi reencontrado nesta rodada — usar os números acima, que têm fonte nomeada.)
- Streak semanal (não diário) é o precedente certo para treino: o próprio Strava só usa **semanas consecutivas** [B]; nosso streak semanal atual está alinhado com o estado da arte. Freeze/perdão: o número específico (11,62→17,19 dias) é dado de plataforma da Trophy [C] — direção confiável, número não-citável.

**Ativação no primeiro dia** [C→B]
- Usuários que completam uma conquista no 1º dia retêm 33,4% vs 20,4% em D14 (Trophy, vendor); benchmark genérico: completar uma ação significativa na 1ª sessão = 2-3x retenção (UXCam). Converge com o KPI que já adotamos ("% 1º log em 7 dias").

**Conquistas DIFÍCEIS retêm; badges fáceis não** [C]
- Retenção cresce monotonicamente com a dificuldade da conquista (32% tier mais fácil → 74% tier mais difícil, Trophy). Vendor data, mas converge com a SDT (abaixo) e com a cultura BJJ (a faixa vale porque custa). **Anti-padrão: chover badge fácil.**

**Necessidades psicológicas (SDT) — a teoria que amarra tudo** [A]
- Stancu et al. 2022 (*J. Consumer Behaviour*, N=719, experimentos de escolha discreta): features de suporte à COMPETÊNCIA (níveis de progresso + feedback que encoraja E informa) foram as preferidas nos dois países estudados; flexibilidade de escolha + feedback encorajador + gamificação são as alavancas que respondem às necessidades psicológicas. Caveat: mede preferência declarada. Caveat 2 [B]: preferências sociais variam por cultura (um cue antropomórfico agradou alemães e desagradou espanhóis) — validar localmente antes de transplantar qualquer benchmark para o Brasil.

### 2.2 O que comprovadamente NÃO funciona

- **Active Team RCT** [A]: app construído explicitamente para reter via feed estilo Facebook + presentes virtuais + leaderboard + mini-desafios com streak → **nenhuma diferença no desfecho primário de atividade física objetiva** (p=0,84 aos 3 meses, p=0,92 aos 9; Edney et al., protocolo 2017 + resultados 2020, *Am J Prev Med*). Empilhar mecânica genérica não move comportamento.
- **Gamificação copiada sem entender o porquê** [B]: Duolingo copiou o contador de moves do Gardenscapes — *"the result of all that effort was completely neutral. No change to our retention. No increase in DAU"* (Mazal). A lição para nós: cada mecânica precisa de tradução CULTURAL para o tatame (por isso "oss" e não "like", "cartel" e não "badge").

### 2.3 Leaderboards — a visão corrigida (mais rica que a de junho)

Dois estudos fortes, ambos com nuance que muda o design:

- **Estudo de larga escala com wearables** [B] (516 universitários, Fitbit, difference-in-differences, PMC10403254): leaderboard aumentou atividade média (+370 passos/dia), MAS: **sedentários ganharam ~1.365 passos/dia (+15%)** — via accountability mútua, NÃO competição — enquanto **os previamente MUITO ativos PIORARAM (−631/dia)**, principalmente em leaderboards pequenos. Tamanho ótimo: o efeito cresce até **~8 membros ativos** e depois satura.
- **Efeito curvilíneo (U-shape)** [B] (survey-experimento n=1.585 + dados de campo, *Computers in Human Behavior*): intenção/atividade são maiores no TOPO e no FUNDO do ranking; a desmotivação mora no **meio da tabela** (posições ~10-79 de 88).

**Correção do benchmark de junho**: "bottom 40% reduz logs em 53%" não se sustenta nos estudos fortes — nem a direção (quem sofre é o meio da tabela e o topo de atividade prévia) nem a magnitude. A recomendação prática MUDA: não é "esconder o fundo", é **(a) ligas pequenas (~8-30 pessoas), (b) eixo = consistência/presença (não performance), (c) atenção especial ao MEIO da tabela** (dar sub-metas: "top da sua faixa", "recorde pessoal"), e **(d) não empurrar competição para quem já é o mais assíduo da academia** — para esse, o jogo é recorde próprio e reconhecimento, não ranking.
- **Precedente de produto**: Strava **Local Legends** [B] (Medium do time de engenharia): coroa por FREQUÊNCIA no segmento (mais vezes nos últimos 90 dias), criada explicitamente como arena para quem nunca ganharia o KOM por velocidade; janela ROLANTE de 90 dias porque a simulação all-time deixava a coroa impossível de disputar. Nosso ranking por presenças já é "Local Legends por design" — a janela rolante e o reset trimestral são o que falta.

### 2.4 Benchmarks de retenção — tabela corrigida

| Benchmark (doc jun/2026) | Veredito desta rodada | Valor corrigido |
|---|---|---|
| "Kudos Strava +34% duração de streak" | **Mal-atribuído** [B]: o +34% é dado da plataforma Trophy (5,7 vs 4,3 dias de streak médio, apps com/sem streak social), não estudo do Strava | Citar Franken 2023 (efeito causal de kudos, sem % único) e tratar +34% como direção de vendor [C] |
| "Duolingo streak 7+ retém 2,4x" | Não reencontrado | Usar: CURR +21% em 4 anos, DAU 4,5x, DAU com streak 7+ triplicou para >50% [B] |
| "Leaderboard corta bottom 40% em 53%" | **Contradito** pelos estudos fortes | U-shape (meio desmotiva); sedentários +15%, muito-ativos −5%; pico de benefício ~8 membros [B] |
| "D30 fitness ~3% vs social ~5%" | Parcialmente confirmado | Fitness D30: 3% (2023, um relatório) a 5% mediana (D1 25%, D7 10%; fortes 8-12%). **Social D30 mediana: 12%** (fortes 15-20%) — o gap fitness→social é MAIOR do que assumíamos [B] |

A tese central do plano mestre sai FORTALECIDA: migrar da curva fitness para a curva social vale mais do que estimávamos (D30 5%→12%, não 3%→5%).

---

## 3. BLOCO 2 — Cultura e psicologia da comunidade de jiu-jitsu

### 3.1 Competição: quase universal entre quem persiste [A]

Survey "State of Jiu Jitsu" da Gold BJJ (~1.948 respondentes, 2024/25 — todos os números conferidos verbatim na fonte, 3-0):
- **61,2% já competiram** (43,6% nos últimos 2 anos + 17,6% antes disso); só 38,8% nunca competiram.
- **Gradiente brutal por faixa: 95% dos faixas-pretas já competiram (152/160) vs 34% dos brancas (264/784).**
- Jornada até a preta: **~13,3 anos** (2,3 branca→azul; +3,3 na azul; +3,4 na roxa; +4,4 na marrom) [B].

Leitura honesta do gradiente [A, caveat do verificador]: mistura sobrevivência (quem não compete desiste antes) com exposição cumulativa — é correlação, não causa. Mas para produto tanto faz a direção causal: **competição e persistência longa andam juntas no BJJ de um jeito que não existe no fitness genérico**. E não há dado equivalente para o BRASIL (pergunta aberta §7).

### 3.2 Mas o combustível diário é saúde e prazer — não competição nem "comunidade" [B, corroborado]

- Pacheco (UFRGS 2010, IMPRAFE-132, n=40, Porto Alegre): dimensões que mais motivam a REGULARIDADE: **Saúde (117,55) > Prazer (112,62)** > ... Competitividade 4ª nominal (93,25) e **Sociabilidade em ÚLTIMO (85,70)**. A entrada no BJJ vem por convite de amigos, mas o vínculo social não sustenta a permanência.
- Corroboração direcional em estudo peer-reviewed maior (2023, n=228, MPAM-R): Interest/Enjoyment 6,40 no topo; Social 4,47 entre os mais baixos.
- **Competição é fator de adesão E de abandono simultaneamente** [B]: pressão, ansiedade e frustração; quando a ênfase desloca da vitória para a melhora individual/coletiva, vira fator agregador. Corroborado por literatura forte de clima motivacional (clima de maestria reduz ansiedade de performance; climas de ego → ansiedade, burnout, dropout).

**Síntese de produto**: a hierarquia do app deve ser — (1º) progresso/prazer pessoal visível (jornada, streak, insights), (2º) reconhecimento social como amplificador, (3º) competição como CAMADA DE IDENTIDADE opt-in para a minoria grande que compete. Nunca inverter: um app que abre no ranking está falando com 20% dos alunos e desmotivando o resto.

### 3.3 O funil de evasão tem nome e endereço: blue belt blues [C→B]

- Folclore consolidado da comunidade (sem dado primário rastreável): **~50% desistem depois da faixa-azul; ~75% dos brancas nem chegam à azul**. A fase tem nome — *blue belt blues* — estagnação e frustração pós-promoção [B na existência do fenômeno; C nos percentuais].
- Com 3,3 anos DE MÉDIA na faixa-azul e o dropout concentrado ali, **marcos intermediários são a arma anti-evasão nº 1**: graus visíveis, metas de habilidade de curto prazo (a fonte recomenda explicitamente que instrutores definam metas de desenvolvimento técnico, não só progressão de faixa), aniversários de tatame, marcos de volume.
- Custo também expulsa [B]: mensalidade + kimono + INSCRIÇÕES DE CAMPEONATO são citados como fator de dropout — relevante para o lado B2B (academia que ajuda o aluno a competir barato retém).
- **O que o GraduaBJJ já tem pronto para atacar isso**: progresso de graus por presença (card de graduação), currículo de técnicas com % de domínio (`student_syllabus_tab`), timeline de marcos, mat milestones no feed. Falta apontar essas armas especificamente para o aluno faixa-azul (ver §6.3).

### 3.4 Lealdade tribal: creonte, equipe e o professor [B]

- **Creonte**: termo cunhado/popularizado por Carlson Gracie no fim dos anos 80, a partir do personagem desleal da novela *Mandala* (1987); designa quem troca de equipe sem avisar o professor ou sem justificativa — ofensa séria até hoje. Ainda existem academias que proíbem cross-training, vetam seminário de equipe rival e desaprovam até interação positiva em rede social com equipe concorrente. A percepção flexibilizou (mudança de cidade, evolução técnica são aceitas) — **a fronteira entre mudança legítima e "creonte" é a comunicação transparente com o professor**.
- Rickson Gracie (citado): *"Por que eu deveria desperdiçar meu conhecimento com um aluno que parece desleal?"* — o professor é o eixo da relação de lealdade.
- **Implicações de produto (importantes para RIVAIS e para o multi-academia):**
  1. A identidade de EQUIPE é sagrada — perfil e cards devem exibir bandeira/equipe com orgulho (o app já tem a academia no perfil; a equipe/linhagem é camada futura).
  2. Uma feature de rivais **jamais** pode cheirar a "vá treinar com o rival" ou aproximar o aluno da academia adversária — rival é **adversário de chave**, não colega em potencial. O frame culturalmente correto é: *acompanhe o adversário, honre sua equipe*.
  3. Nosso fluxo multi-academia/transferência já existe — enquadrá-lo como "transferência transparente" (aluno comunica, professor recebe) é aliviar a maior tensão social do esporte, não criá-la.
  4. O professor é ator de retenção central (a Repaginada já deu a ele o radar de churn; §6.3 dá a ele o papel anti-blues).

---

## 4. BLOCO 3 — A ciência da RIVALIDADE (a base do sistema de rivais)

### 4.1 O efeito positivo é real e tem base causal [B]

- **Meta-análise** (*Rivalry and Performance: A Systematic Review and Meta-analysis*): 22 papers revisados (k=35, 27.771 observações); meta-análise em 18 papers (k=28, N=26.215): **rivalidade → efeito positivo significativo sobre performance**. Rivalidade = "competição RELACIONAL" — exatamente o construto de "acompanhar um adversário específico de campeonato".
- **Painel Topcoder com identificação causal** (*When Rivalry Backfires*, Management Science): 4,6 milhões de encontros competitivos, 16.846 competidores, atribuição aleatória de salas: competir contra rivais eleva a performance **em média**, acima dos demais drivers.
- **Esporte de verdade** (Kilduff, *Driven to Win*, SPPS 2014 + estudo arquivístico): 6 anos de provas de um clube amador de corrida (82 corredores, 112 provas): presença de rival na prova = **~4,92 s/km mais rápido (~25s num 5K)**; corredores reportam ~3 rivais em média e dizem espontaneamente que rivalidade os faz treinar e correr mais forte. Efeito confirmado em laboratório controlando prêmio e antipatia — **o motor é a RELAÇÃO/histórico, não ódio nem recompensa**.

### 4.2 Como uma rivalidade nasce (= o algoritmo de detecção) [B]

Kilduff: rivalidade é impulsionada por **(1) similaridade** (idade, nível, categoria), **(2) competição repetida**, **(3) confrontos decididos por margem apertada**. Isso é literalmente uma query sobre dados de campeonato: mesmo peso/faixa/categoria + já se enfrentaram ≥2 vezes + lutas equilibradas → rival natural.

### 4.3 Quando a rivalidade REVERTE (as condições de contorno que definem o design) [A/B]

| Risco | Evidência | Regra de design |
|---|---|---|
| **Assimilação para baixo** [A] | Franken 2023: atletas convergem para os kudos-friends que treinam MENOS (corroborado por Aral & Nicolaides 2017, Nature Comm., 1,1M corredores: "less active runners influence more active runners, but not the reverse") | O feed do rival deve mostrar MARCOS (competiu, graduou, milestone), nunca o volume diário de treino — não dar régua descendente para se acomodar |
| **Alvo distante desmotiva** [A] | Arigo 2023 (N=112, 3 estudos): motivação CAI com alvos muito acima; maior ganho com alvos moderadamente acima (~190%); "acesso irrestrito não atende às necessidades dos usuários" | Matchmaking curado: mesma faixa+peso+categoria, histórico de placar próximo; NUNCA busca aberta de "qualquer atleta" como rival |
| **Prejudica os menos habilidosos** [B] | Topcoder: rivalidade beneficia os mais habilidosos e É DANOSA para os menos habilidosos; autores recomendam explicitamente cautela com iniciantes | Gate: rivais só para quem JÁ COMPETE (≥1 campeonato registrado); nunca para iniciante, **nunca kids** |
| **Risco de perder status inverte o efeito** [B] | Topcoder: +1 DP de rivalidade = 22,5% mais chance de terminar uma posição ABAIXO para quem arrisca perder status | Nenhuma mecânica de rebaixamento/demotion acoplada a rivais (sem "liga com queda" ligada a rival); rivalidade amplia desigualdade top-bottom — monitorar |
| **Lado sombrio comportamental** [B] | Kilduff: rivalidade aumenta comportamento antiético e tomada de risco | Sem incentivo a "provar" nada fora de campeonato oficial; nada de desafios diretos in-app entre rivais |
| **Subgrupos vulneráveis** [B] | "Strava made me do it" (n=114): SCO alto → mais efeitos negativos (β=0,161, p=0,043); motivação por reconhecimento social prediz dano (β=0,199); mulheres reportam mais efeitos negativos (d=−0,44); autoestima baixa idem (β=0,330). Frontiers 2023 (n=1.452): baixo autocontrole → comparação ascendente vira ameaça, usuário "deita" (desiste) | Rivais 100% OPT-IN com consentimento MÚTUO; mute/desfazer a qualquer momento sem notificar o outro; monitorar opt-out e uso feminino separadamente |
| **Lesão = período de vulnerabilidade** [A/B] | Kolnes & Øvretveit: usuários saem do Strava durante lesão para não sofrer ("deletei o Strava imediatamente... não suportava ver os outros treinando") | Modo lesão: pausa comparações/rival/streak com 1 toque, sem perder histórico (BJJ: 31% já teve lesão séria [B]) |
| **Auto-vigilância / gestão de imagem** [A] | Couture 2021 (etnografia): plataforma recompensa exibição de autodisciplina; quem deleta sessão por pace lento pontua mais alto em metas de evitação (3,62 vs 2,65, p<0,05) | Self-log continua privado por default; nunca expor treino "fraco" de ninguém; posts densos de marco (já é o design do feed) |

### 4.4 Precedentes de produto verificados

- **Duolingo leagues**: coortes pequenas (~30) por XP semanal [C/B] — precedente de liga pequena; MAS a demotion delas colide com o achado Topcoder de status-loss → nossa liga não rebaixa, expira (temporada).
- **Strava Local Legends**: competição por consistência com janela rolante de 90 dias [B] — o molde para qualquer leaderboard nosso.
- **Leaderboard ótimo ~8 membros ativos** [B] — o tamanho de uma chave de campeonato ou de um pod de treino, não de uma academia inteira.
- Head-to-head estilo xadrez online: **não sobreviveu à verificação nesta rodada** (sem fonte forte sobre efeito em retenção) — fica como pergunta aberta; não citar como precedente comprovado.

---

## 5. A máquina de retenção — princípios de desenho (evidência → produto)

**P1. A fundação é intrínseca: saúde, prazer e progresso visível.** (§3.2) O hub do Lutador abre com o SEU progresso (streak, jornada, próximo grau) — nunca com ranking. Competência-SDT: feedback que encoraja E informa (ex.: "3 treinos esta semana — seu melhor junho" em vez de "+3").
**P2. Validação social barata, recíproca e notificada.** (§2.1) Oss de 1 toque em qualquer marco; push do like já existe (Repaginada F2); adicionar retribuição fácil ("dar oss de volta") e destacar quem sempre te apoia.
**P3. Streak semanal resiliente + perdão explícito.** Já temos o streak semanal com graça; dias-esperados (plano existente) refina; freeze explícito ("semana de descanso/lesão") em vez de quebra silenciosa.
**P4. Conquistas difíceis, escada longa.** (§2.2, §3.3) A escada de marcos deve ficar MAIS difícil e MAIS espaçada conforme sobe (100/250/500/1000 aulas; 1/2/3/5 anos) — já é o design do feed; nunca inflacionar.
**P5. Competição como camada de identidade opt-in.** (§3.1) Cartel de competição, medalhas, head-to-head — profundo para quem compete, invisível para quem não quer.
**P6. Leaderboards: pequenos, por consistência, janela rolante, atenção ao meio.** (§2.3) Ranking de parceiros > ranking da academia; sub-metas para o meio da tabela ("top da sua faixa"); nunca push de posição.
**P7. O professor é mecânica de retenção.** (§3.4) Radar de churn (feito) + reconhecimento de marcos na aula (F3) + metas técnicas de curto prazo anti-blues (§6.3).
**P8. Cultura antes de mecânica.** (§2.2) Toda mecânica traduzida para o tatame: oss, cartel, camp, chave, graduação — zero vocabulário genérico de fitness-app.

---

## 6. Novas abordagens propostas

### 6.1 Sistema de RIVAIS — "Adversários de Chave" (o desenho que a evidência permite)

A ideia do usuário (acompanhar adversários de campeonato de outras academias) é **viável e diferenciada** — nenhum app comercial personaliza comparação social a diferenças individuais (lacuna documentada até 2020 e ainda aberta [A]) e nenhum app de BJJ tem o dado que nós temos (resultados de campeonato + faixa + peso + academia). Mas o desenho tem que obedecer §4.3:

**Detecção (Kilduff como algoritmo):**
- Fonte: resultados de campeonatos registrados no app (módulo de competições + medalhas já existe; selfCompetitions cobre externos).
- Sugerir "adversário de chave" quando: mesma categoria (faixa+peso+idade) E ≥1 confronto direto OU ≥2 campeonatos em comum na mesma chave; priorizar confrontos de placar apertado e reencontros. NUNCA sugerir alguém de nível distante.
- **Consentimento mútuo** (como o amigos-por-código atual): A convida, B aceita; qualquer um desfaz em silêncio.

**O que um rival VÊ do outro (regra anti-assimilação-para-baixo e anti-vigilância):**
- ✅ Cartel público: resultados de campeonato, graduações, marcos raros (mat milestones), head-to-head histórico ("Você 2 × 1 Ele", com os campeonatos).
- ✅ Sinal binário de camp: "está em camp para o Open XYZ" (se ambos inscritos no mesmo evento).
- ❌ NUNCA: volume de treino diário/semanal, streak, self-logs, horários, academia frequentada em tempo real (LGPD + §4.3 linhas 1 e 8).

**Enquadramento (mastery framing, §3.2):**
- A tela do rival é 80% SOBRE VOCÊ: "Faltam 5 semanas para o Open. Seu camp: 9 treinos nas últimas 3 semanas. Sua meta: 12." O rival aparece como contexto ("Ele também está inscrito"), não como régua diária.
- Pós-campeonato: registro do confronto no cartel dos dois; push de resultado apenas para quem lutou, jamais "seu rival venceu e você não" para terceiros.

**Gates e salvaguardas (§4.3):**
- Só para quem já tem ≥1 competição registrada; nunca kids; opt-in duplo; modo lesão pausa tudo; sem demotion; sem desafio direto in-app; monitorar opt-out/mute rate e diferenças por gênero desde o dia 1.
- Culturalmente (§3.4): copy sempre "adversário de chave"/"rival de chave", com a bandeira da EQUIPE de cada um em destaque — rivalidade entre equipes é orgulho, não convite ao cross-training.

**Por fases:**
- **R0 (sem backend novo):** head-to-head derivado dos resultados de campeonato já registrados — "vocês já se enfrentaram N vezes" no perfil público de quem compete. É leitura pura dos dados existentes.
- **R1:** convite mútuo de rival + card de camp compartilhado (evento em comum).
- **R2:** sugestão automática por chave (algoritmo Kilduff) + push de marcos do rival (respeitando caps).
- **R3 (grupo, permitido pela meta-análise §4.1 — positiva em esportes):** "Duelo de Academias" por temporada de campeonato: pontuação agregada de medalhas entre 2 academias que se enfrentam com frequência nos mesmos opens. Evento raro e festivo, nunca leaderboard permanente.

### 6.2 Ligas de consistência ("Liga da Chamada") — o leaderboard que a evidência aprova

- Pods de ~8-12 alunos da MESMA academia, pareados por frequência histórica parecida (não por habilidade), disputando CONSISTÊNCIA (presenças/semana) em temporadas de 6 semanas com janela rolante estilo Local Legends. Sem rebaixamento; ao fim, o pod se re-sorteia.
- Sedentários/irregulares ganham accountability mútua (o mecanismo comprovado para eles, §2.3); os hiper-assíduos ficam FORA por default (a evidência mostra que ranking os prejudica) — para eles, recorde pessoal e reconhecimento do professor.

### 6.3 Protocolo anti-"blue belt blues" (o ataque cirúrgico ao maior vazamento do funil)

- **Detector**: aluno faixa-azul + 6-18 meses na faixa + tendência de frequência caindo (o `retention.*` já computa) → flag específica "risco blues" no radar do professor, com playbook próprio (não é o mesmo do inadimplente).
- **Arma 1 — metas técnicas de curto prazo** [B, recomendação da fonte]: o professor define 1 meta de habilidade de 4-6 semanas no currículo do aluno (o `student_syllabus_tab` e o % de domínio JÁ EXISTEM) e o aluno a vê no hub como missão ativa.
- **Arma 2 — marcos intermediários densos na faixa-azul**: aniversário de faixa, "100 treinos de azul", progresso de grau destacado — a fase mais longa e perigosa precisa da MAIOR densidade de reconhecimento, hoje é o contrário.
- **Arma 3 — competição como reengajamento**: para o azul esfriando que JÁ competiu, sugerir o próximo open regional (a correlação competição↔persistência de §3.1 vira ferramenta).

### 6.4 Retoques nas mecânicas existentes (à luz das correções)

- **Ranking da academia**: adicionar janela rolante (90d) e corte por categoria/faixa como visão default; a visão global perde destaque (§2.3). Sub-meta para o meio da tabela.
- **Streak**: manter semanal; freeze explícito de lesão/descanso (§4.3 modo lesão) — nunca quebra silenciosa.
- **Feed**: já é denso-de-marcos por design (correto); adicionar reciprocidade de oss (P2).
- **Onboarding do aluno**: 1ª sessão termina com UMA ação significativa (1º self-log ou meta de dias) — ativação 2-3x (§2.1).
- **Cards compartilháveis**: manter foco em marcos DIFÍCEIS (graduação, medalha, aniversário de tatame) — o instagramável retém quando carrega identidade conquistada, não atividade rotineira (§2.2, P4).

---

## 7. Perguntas abertas (o que esta rodada NÃO respondeu)

1. **Taxa de competição no BRASIL** (CBJJ/IBJJF/AJP/opens regionais) — todo o dado é de amostra americana auto-selecionada. Vale puxar números de inscrições da CBJJ/FJJRio ou dos nossos próprios dados de campeonatos.
2. **Assimilação para baixo se replica em atletas de combate competitivos?** Toda a evidência é de corrida/passos recreativos. Nosso próprio app pode medir isso (coorte com/sem rival, frequência antes/depois).
3. **Precedentes head-to-head** (xadrez online, Strava segments entre rivais, ligas Duolingo) — efeitos medidos em retenção/toxicidade não sobreviveram à verificação; pesquisar de novo com foco em post-mortems e papers de plataforma.
4. **Interação rival × cultura creonte**: nenhuma fonte cobre como a comunidade BJJ brasileira reage a "seguir atleta de equipe rival" dentro de um app. Mitigação: R0/R1 são discretos e mútuos; medir report/block e feedback qualitativo com professores antes de R2.
5. Teardowns GymRats/Hevy/Whoop/BeReal — não renderam claims verificáveis novos nesta rodada; o material de jun/2026 continua sendo a melhor referência interna (com o desconto de que seus números de benchmark foram corrigidos aqui, §2.4).

## 8. Ordem de implementação sugerida (encaixe com o que já está entregue)

Dado que a Repaginada F0-F3 já está em produção (fundação de retenção + pushes + radar):

1. **Quick wins de correção** (semanas): reciprocidade de oss; janela rolante no ranking; freeze/modo lesão no streak; ativação 1ª sessão. — §6.4
2. **Anti-blues** (1-2 sprints): detector no radar do professor + metas técnicas curtas + marcos densos na azul. Ataca o maior vazamento documentado do funil. — §6.3
3. **Liga da Chamada** (1-2 sprints): pods de consistência intra-academia. — §6.2
4. **Rivais R0→R1** (leitura de dados existentes → convite mútuo): head-to-head no cartel + camp compartilhado. — §6.1
5. **Rivais R2/R3** somente após medir R1 (opt-in rate, mute rate, efeito em frequência, report rate).

---

## 9. Bibliografia (fontes fetched e usadas)

**Peer-reviewed / primárias fortes:**
- Franken, Bekhuis & Tolsma (2023). *Kudos make you run!* Social Networks 72:151-164. — kudos causal; assimilação p/ baixo
- Aral & Nicolaides (2017). Nature Communications. — corroboração assimilação (1,1M corredores)
- Arigo et al. (2020). *Social Comparison Features in PA Apps: Scoping Meta-Review.* JMIR (PMC7148546). — lacuna de personalização; backfire
- Arigo et al. (2023). *Selection of and Response to PA-Based Social Comparisons.* JMIR Human Factors e41239. — alvos ~190% vs >2000%
- Edney et al. (2017 protocolo; 2020 resultados, Am J Prev Med). *Active Team RCT.* — null de gamificação genérica
- Kilduff (2014). *Driven to Win.* SPPS 10.1177/1948550614539770 (+ press EurekAlert/ScienceDaily). — rivais na corrida; formação de rivalidade; lado sombrio
- *When Rivalry Backfires* (Management Science, 10.1287/mnsc.2023.00344). — Topcoder 4,6M encontros; moderadores habilidade/status
- *Rivalry and Performance: A Systematic Review and Meta-analysis* (ResearchGate 358834354). — 22 papers, k=35, 27.771 obs; individual > grupo
- *Health Wearables, Gamification, and Healthful Activity* (PMC10403254). — leaderboards 516 universitários; ~8 membros
- *Curvilinear effects of leaderboard positions* (Computers in Human Behavior, S074756322400400X). — U-shape
- Couture (2021). *Reflections from the 'Strava-sphere'.* QRSEH 13(1). — auto-vigilância
- Kolnes & Øvretveit (2026). *Motivational Dynamics and Strava Use in Club Runners* (PMC12938745). — rede/autoeficácia; lesão
- *"Strava made me do it"* (ResearchGate 400287585). — SCO, gênero, autoestima
- *Exercise or lie down?* (Frontiers in Public Health, 2023, n=1.452). — autocontrole como moderador
- Stancu et al. (2022). *Motivating consumers for health and fitness.* J. Consumer Behaviour (Wiley, cb.2108). — SDT/competência
- Pacheco (UFRGS 2010, lume.ufrgs.br). — IMPRAFE-132 motivação BJJ POA (+ corroboração PMC10546321, 2023, n=228)

**Indústria / comunidade (usar com caveat):**
- Gold BJJ, *BJJ Statistics* (goldbjj.com/blogs/roll/statistics). — survey ~1.948; competição por faixa; 13,3 anos
- Lenny's Newsletter — Jorge Mazal, *How Duolingo Reignited User Growth.* — CURR +21%, DAU 4,5x, fail do Gardenscapes
- Strava Engineering (Medium), *Building Local Legends.*
- Trophy.so — case studies Duolingo/Strava (dados de vendor, [C])
- UXCam / Business of Apps — benchmarks D1/D7/D30 (2026)
- filosofiajiujitsu.com + mundojiujitsu.com.br — creonte, Carlson Gracie, Mandala, lealdade
- The Jiu Jitsu Foundry — blue belt blues
- tatame.com.br — papel do professor no acolhimento
- behavioralstrategy.com — falhas de gamificação
