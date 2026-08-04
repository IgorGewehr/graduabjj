# Relatório de Produto & Cultura — GraduaBJJ
### A mente do lutador, a cultura do tatame, e como construir um app que *cria* cultura entre lutadores

---

## 1. Sumário executivo

O jiu-jitsu não é um esporte de performance — é um **sistema de identidade vitalício** com a estrutura de um RPG da vida real. Essa única verdade reordena todas as decisões de produto. Quatro insights mudam o produto:

1. **O problema central do nicho é retenção de PESSOAS, não receita.** 70–90% dos faixas-brancas largam no primeiro ano; 50–70% largam na azul ("blue belt blues"); só ~1–3% chega à preta. A causa raiz não é técnica — é **a motivação extrínseca (a faixa) sumir sem nada intrínseco a substituir**, somada a **falta de pertencimento** e **invisibilidade do progresso** (que no BJJ é lentíssimo). Um app que torna o progresso visível e cria pertencimento ataca diretamente a causa da evasão. Isso é a tese de cultura/não-lucro do projeto, e ela é defensável por dados.

2. **O ecossistema está fragmentado em 5 baldes que não conversam, e as redes sociais verticais de BJJ morreram todas de cold-start (feed vazio).** O GAP que ninguém ocupou: uma rede social de **identidade do lutador, em português, com cultura brasileira**, que já nasce com **grafo social vivo** (vindo da operação real da academia) e que **também funciona em modo solo**. Nenhum concorrente fecha os 4 vértices ao mesmo tempo (log de baixa fricção + identidade/cultura + comunidade com efeito-rede + vínculo com academia real).

3. **A vantagem estrutural do GraduaBJJ é que ele não tem cold-start.** Marune e os outros tentam construir o grafo social do zero; o GraduaBJJ já o tem por construção (colegas de turma, professor, academia, presença real, faixa dada pelo professor). A presença real da academia pode virar evento na timeline **sem o aluno digitar nada** — o "auto-log" que os concorrentes apenas sonham.

4. **A arquitetura atual está com a "gravidade do dado invertida" e isso é o teto de crescimento.** Hoje o lutador "real" é o `Student`, que vive **dentro** de uma academia; o `GlobalUser` é só uma sombra derivada. Um lutador sem academia cai num portal quebrado. Para destravar o modo solo (e o loop viral de aquisição), é preciso **inverter a gravidade**: `/users/{uid}` (perfil de lutador) vira o agregado-raiz, e as academias passam a ser **fontes que alimentam** esse perfil — não o contêiner dele.

**A frase-síntese:** construa o "Strava + identidade do lutador brasileiro" — onde o tracker é commodity, mas cultura + grafo social que já existe + modo solo são o fosso. Premie **jornada e consistência** (o que retém faixa-branca/azul, exatamente quem larga), não vaidade competitiva.

---

## 2. A mente do lutador

### 2.1 A faixa como identidade, não como ranking

A faixa não é um marcador de skill — é um **marcador de identidade vitalício**. A jornada branca→preta leva 10+ anos, o que transforma a cor num símbolo de "quem eu sou", não de "o que eu sei". A escassez alimenta a identidade: ~10–15% chegam à azul, ~3% à roxa. Cada graduação vira **conquista de vida**. A estrutura graus→faixa é, literalmente, um sistema de XP/level-up: os graus (stripes) são checkpoints intermediários que mantêm o senso de progresso entre faixas distantes.

**Tensão crítica que a cultura revela:** faixas-pretas alertam contra a "obsessão com a cor da faixa" — quem foca no próximo belt aprende mais devagar; quem evolui mais rápido foca em técnica e qualidade de treino. **Lição de produto, não-negociável:** gamificar o *processo* (consistência, técnica, mat-time), nunca só o *resultado* (a faixa). Um app que só celebra a faixa reforça o vício errado e frustra na espera longa de anos.

### 2.2 Por que COMEÇAM e por que DESISTEM — a "Blue Belt Curve"

A retenção é o problema central do nicho, e a evasão tem mecanismos psicológicos mapeados:

| Causa da desistência | Mecanismo psicológico |
|---|---|
| **Paradoxo da meta atingida** | A azul era o "objetivo final" imaginado. Atingir remove a motivação extrínseca sem substituir por intrínseca → "and now what?" |
| **Platô / descompasso de dopamina** | Branca = revelação a cada aula (dopamina de aprendizado rápido). Azul = ganhos de 1% ao longo de semanas, que não ativam a mesma recompensa → sensação de estagnação apesar de progresso real |
| **Síndrome do impostor** | Faixas superiores "param de pegar leve" → as lacunas ficam expostas → "talvez eu não seja tão bom" |
| **Sumiço do andaime (scaffolding)** | Como branca, instrução clara e constante. Como azul, espera-se autonomia → desorientação |
| **Custo físico** | Anos de tatame: o corpo "começa a guardar registro"; lesões viram impossíveis de ignorar |
| **Vida** | Casamento, filho, hipoteca → tempo espremido |
| **Cultura de comparação** | Redes sociais mostram outliers → "todo mundo está me passando" (survivorship bias) |

### 2.3 Por que os que FICAM, ficam

Os retentores trocam motivação **extrínseca (faixa)** por **intrínseca**. Os pilares:

1. **Mat as therapy** — o motivo mais citado e mais profundo. O BJJ "acalma o sistema nervoso", é válvula de estresse/ansiedade/depressão, usado em recuperação de vício. Revisão sistemática (BMC Psychology, 2021): treino marcial em grupo aumenta bem-estar social e reduz solidão. O tatame "tira camadas do ego e expõe o eu verdadeiro".
2. **Comunidade / pertencimento** — o **preditor #1 de permanência**. As pessoas voltam pelas pessoas.
3. **Vício saudável** — o loop de "resolver o jogo" (BJJ como "xadrez físico"), flow, presença.
4. **Evolução contínua** — quem fica é process-oriented.
5. **Linhagem (lineage)** — identidade *relacional*: de quem eu venho.

**Insight central de retenção:** quem fica trocou faixa por *terapia + comunidade + evolução + linhagem*. **O app vence se acelerar essa troca** — fazer o lutador descobrir os motivos intrínsecos *antes* de bater no platô da azul. E, crucialmente, **identidade, marcos, comunidade e linhagem independem da academia estar no app** — por isso o modo solo é viável.

### 2.4 Os marcos emocionais (os momentos sagrados)

A jornada é pontuada por **first-times** de altíssima carga emocional — os picos que o app deve capturar, celebrar e ajudar a compartilhar:

- **Primeira graduação / primeiro grau** — primeira validação externa; "eu pertenço".
- **Primeira competição** — medo + superação; ritual de passagem.
- **Primeira finalização** — primeira prova de que "funciona"; virada de identidade ("agora eu faço jiu-jitsu de verdade").
- **Promoção de faixa** — o pico máximo, raro, carregado de linhagem (quem te promoveu importa tanto quanto a faixa).
- **Aniversários de tatame** — "1 ano treinando", marcos de consistência.
- **Marcos "escondidos"** — sobreviver a um faixa-preta, escapar de posição ruim, voltar depois de lesão, "não sou mais o cara perdido do dia 1". A cultura pede explicitamente para celebrar esses momentos que a faixa não captura.

**Linhagem como marco relacional:** a faixa-preta carrega a árvore genealógica — Maeda→Gracie→...→seu professor→você. Ser promovido te insere numa *legacy* viva. É identidade relacional que gera orgulho, humildade e conexão — e funciona mesmo para o lutador solo, que registra a própria linhagem.

---

## 3. O ecossistema atual de BJJ e o GAP de mercado

### 3.1 Os 5 baldes fragmentados

- **A) Instrucional / conteúdo (loja de vídeo):** BJJ Fanatics (e-commerce de instrucionais de elite — você compra, assiste, não volta), FloGrappling ("Netflix do grappling", US$29,99/mês — consumo passivo). Zero identidade, zero retenção diária.
- **B) Diário de treino / tracker (a maior briga hoje):** **Marune** é o concorrente mais perigoso e mais próximo da visão — log gi/no-gi, timeline de faixas, multimodalidade, sync Apple Health/Google Fit, **community feed**, botão "OSS" em vez de "like", **web profiles públicos**. É "Strava + Instagram do artista marcial". BJJ Notes / Grappling Notes / Kimura etc. são manuais e solitários ("feels like documentation work rather than motivation… a completely isolated experience"). Onda nova 2025–26: **AI voice journaling** (Grappling AI, Jits AI, MatTime) — você fala depois do treino e a IA extrai técnicas. Jits AI gamifica mas é criticado por focar em vanity metrics; MatTime se posiciona como "comunidade autêntica".
- **C) Rede social pura de BJJ (o cemitério):** BJJLINK Social, BJJ Network, TheBJJApp. Existem, mas **nenhuma virou o lugar onde o lutador vive** — morreram de feed vazio (cold-start). BJJLINK só sobrevive colado no gym-management software.
- **D) Competição:** **Smoothcomp** — padrão global de inscrição/chaveamento. Infraestrutura, não engajamento diário; só "liga" quando tem torneio.
- **E) Descoberta/mobilidade:** BJJGym, Jiu Jitsu Junkie — achar academia/open mat viajando. Nichado, datado, isolado.

### 3.2 O que cada um faz bem e mal

| Faz bem | Faz mal (= seu espaço) |
|---|---|
| Fanatics/Flo: conteúdo de elite | Consumo passivo; zero identidade; não retém |
| Marune: o pacote social+log mais completo | Multiarte bagunçado (tudo que não é gi vira "no-gi"); sem confirmação de presença pelo parceiro; sem backup; feed raso; **EUA-cêntrico, em inglês**; não nasceu colado a academia |
| AI apps: tiram fricção do log via voz | Recém-nascidos; foco indivíduo+IA, comunidade fraca; caros |
| Smoothcomp: competição | Frio, transacional |
| BJJGym: achar mat/parceiro | Datado, sem camada de identidade |

**Padrão dominante (citável, recorrente nas fontes):** *"Most apps treat BJJ like any other workout — missing the cultural, technical and community aspects that make grappling unique"* e *"BJJ is inherently social, but most apps ignore the community aspect or treat it as an afterthought."* O nicho **rejeita ativamente o genérico** (Strava/MyFitnessPal falham porque o lutador fica "rodeado de não-grapplers").

### 3.3 O GAP que ninguém ocupou

Quatro vértices que nenhum app fecha simultaneamente:
1. Diário de treino de baixa fricção (Marune/AI têm)
2. Identidade/cultura de lutador (fragmentado e raso em todos)
3. Comunidade viva com efeito-rede (todas as redes sociais puras morreram)
4. Vínculo com a academia real (só os gym-management têm — incluindo o **próprio GraduaBJJ**)

**O vértice 4 é o que mata as redes sociais de BJJ — e é o trunfo do GraduaBJJ.** Você não tem cold-start: o grafo social já existe por construção. **E há um vazio absoluto de produto culturalmente brasileiro** — o Brasil é o berço do jiu-jitsu, com densidade gigante de praticantes, e o ecossistema é quase todo anglófono. Não existe um produto em português, com cultura BR, que funcione mesmo sem a academia.

---

## 4. Cultura & compartilhamento

### 4.1 O que o lutador REALMENTE posta

O lutador não posta por vaidade genérica — posta **prova de pertencimento a uma tribo dura**. Seis baldes de conteúdo que circulam de verdade:

1. **Graduação (faixa/grau)** — o momento de maior compartilhamento orgânico do esporte; promoções viram cerimônia pública documentada religiosamente.
2. **Medalha/pódio de competição** — postam independente da colocação; há até uma subcultura sobre *legitimidade* da medalha.
3. **Marcos de tempo/consistência** — "X meses de tatame", aniversário de faixa, volta de lesão. A cultura tem fixação com "marathon not a sprint".
4. **Clipe técnico / finalização** — a moeda principal no TikTok/Reels (`#bjjlifestyle #jiujitsutiktok`).
5. **Identidade/afiliação (lineage)** — sempre com a academia tagueada; afiliação é status.
6. **Marcos "escondidos"/emocionais** — primeira finalização, sobreviver a um faixa-preta. A cultura pede para "celebrar quietamente" o que faixa/grau não capturam.

**Insight-chave:** o lutador compartilha **status + jornada + tribo**, não números frios — ao contrário do corredor (que posta performance/mapa). O cartão do GraduaBJJ tem que vender *identidade de guerreiro e pertencimento*.

### 4.2 Design do cartão compartilhável (destilado de Strava, Spotify Wrapped, Duolingo)

**A faixa é o "mapa-herói".** No Strava, o mapa é o herói porque comunica esforço espacialmente, e a linha laranja virou símbolo universal de "fui ativo hoje". O equivalente no BJJ é **a faixa estilizada** — reconhecível mesmo em thumbnail. Hierarquia visual proposta:
1. **Identidade:** avatar de kimono + nome + academia + linhagem.
2. **Herói visual:** a faixa (cor + graus) como elemento gráfico dominante e brandado — o "laranja do BJJ".
3. **A conquista:** título do momento ("Faixa Roxa", "1 ano de tatame", "1ª finalização", "Ouro – Open SP").
4. **Prova/números:** dias de tatame, presenças, finalizações no ano, tempo na faixa.
5. **Marca:** logo GraduaBJJ discreto mas onipresente (vetor de aquisição).

**Os 4 gatilhos psicológicos que fazem postar:**
- **Status/sinalização** — o cartão tem que fazer a pessoa parecer mais forte do que uma selfie faria (rank, grau, lineage, ranking interno).
- **Progresso (storytelling de dados)** — Wrapped funciona porque mostra **o usuário, não a marca**; pessoas espalham porque "representa a identidade delas". Antes/depois, streaks, "você vs. você há 1 ano".
- **Identidade/tribo** — linguagem e estética interna do nicho (oss, tatame, roll, drilar), nunca copy genérico de fitness.
- **Autenticidade (feature, não enfeite)** — a cultura **execra** medalha fácil e auto-promoção. O cartão só pode afirmar o que é verdade verificável. **"Verificado pela academia X"** dá legitimidade que nenhuma selfie tem.

**Craft prático:** formatos nativos 9:16 + 1:1 gerados automaticamente; tipografia bold, alto contraste; estética brandada consistente (o "laranja"); **fricção zero** (1 toque para gerar, 1 para postar no story).

### 4.3 Os momentos-gatilho (o app empurra o cartão no pico da emoção)

Princípio: **empurrar o cartão no instante exato da emoção**, não esperar o usuário procurar.
- **Alta intensidade (cartão automático):** graduação de faixa (com data, professor que graduou, tempo na faixa anterior); novo grau/stripe; medalha de pódio.
- **Jornada/tempo (cartões "Wrapped"):** aniversário de faixa; "100 presenças"/"1 ano de treino"; Wrapped mensal/anual ("Seu ano no tatame"); streaks ("voltou depois da lesão", "30 dias seguidos").
- **Emocionais "escondidos" (diferencial que NENHUM concorrente captura):** primeira finalização, primeiro roll com faixa-preta, "sobreviveu X minutos".

**Regra de ouro:** ofereça o cartão **no pico emocional** (logo após o professor registrar a graduação/presença) **e no momento social** (domingo à noite / fim de mês).

### 4.4 Share → aquisição (o viral loop)

Cada cartão postado é **prova social brandada e gratuita** — o mecanismo provado por Wrapped/Strava (awareness em escala que mídia paga não replica). Como projetar no GraduaBJJ:
1. **Marca onipresente e reconhecível** (o "laranja") — sem branding consistente, o post celebra o lutador mas não traz ninguém.
2. **CTA/atribuição embutida** — handle @graduabjj + link/QR no story → cai no **perfil público** (o app já tem `publicProfiles`, espelho sem PII, perfeito como landing de aquisição).
3. **Loop sem academia (lutador solo)** — permitir cadastro solo, registrar histórico/graduação auto-declarada (com selo "não-verificada"), gerar e postar cartões. O amigo que vê pensa "posso registrar minha jornada também" → cadastro → eventualmente puxa a própria academia. **O lutador vira vetor de aquisição da própria academia (bottom-up).**
4. **Validação de 1 toque (oss/kudos)** dentro do app — o feedback loop que faz voltar diariamente (Strava: ~35 aberturas/mês vs <15 dos concorrentes, graças à camada social).
5. **Convite contextual** — depois do post: "quem mais treina com você? convide seu parceiro de drill". Referral nasce do orgulho, não de banner.

**Métrica a instrumentar:** cartões gerados → compartilhados → cliques no link → cadastros atribuídos (coeficiente viral *k*). Meta de design: **cada graduação postada deve trazer ≥1 visitante ao perfil público.**

---

## 5. O "lutador solo" — valor independente da academia, o que está acoplado hoje, e a arquitetura de "perfil de lutador" global

### 5.1 O diagnóstico estrutural: a gravidade do dado está invertida

Existe uma camada de identidade global (`GlobalUser` em `/users/{uid}`), mas ela é uma **sombra derivada**, não o lar do lutador. Quem é "você de verdade" é o `Student` — e o `Student` vive **dentro** de uma academia. Provas no código:

- **Tudo que constitui a vida de treino é academy-scoped.** `lib/services/firebase_service.dart:30-100` (`class Collections`) — todo o universo do lutador pende de `academies/{id}/...`:
  - presença → `attendance` (`firebase_service.dart:41`)
  - faixa/graduação → `beltProgressions` (`:54`) + `beltHistory` no doc do aluno (`lib/models/student.dart:302`)
  - conquistas → `achievements` (`:42`; academy-scoped confirmado em `achievement_service.dart:251`)
  - rolls/lutas → `fightRecords` (`:69`), `strikingSessions` (`:68`)
  - treino/musculação → `workoutExecutions` (`:65`), `skillProgress` (`:63`), `physicalAssessments` (`:61`)
  - financeiro, planos, loja, competições, syllabus, horários → todos academy-scoped (`:46-72`)
- **A camada global (`RootCollections`, `firebase_service.dart:103-119`) só tem DUAS coisas:** `users` e `userAcademyMapping`. Nada de treino.
- **A faixa "global" nem é própria — é computada da academia.** `GlobalUser.highestBelt/highestStripes` (`lib/models/user.dart:91-97`) só é preenchida por `syncHighestBelt()` (`global_user_service.dart:325-399`), que itera `academyIds` e retorna cedo se a lista estiver vazia (`:338`). **Um lutador sem academia não consegue nem ter faixa.**
- **Até o perfil público é academy-scoped.** O espelho social vive em `academies/{academyId}/publicProfiles/{studentId}` (`functions/server_functions.js:821, 896`); o ranking lê desse mirror (`ranking_service.dart:65`). A identidade pública está literalmente aninhada dentro da academia.

### 5.2 O que acontece HOJE com um lutador sem academia (modo solo de fato)

Já existe a conta "free" (`AccountType.free`, `user.dart:50`; `isFreeUserProvider`, `auth_provider.dart:59-62`), mas ela leva a um beco:
- `auth_provider.dart:121-139` devolve um `AppUser` free **sem `academyId` e sem `studentId`**.
- O router manda esse usuário para `/portal` mesmo assim (`lib/app.dart:551`).
- Mas `PortalShell` e `home_screen` são construídos sobre `currentStudentProvider` (null para free) e `academySettingsProvider` (null) — `portal_shell.dart:168, 257`; `home_screen.dart:49, 639-640`. **Resultado: o lutador solo cai num portal vazio/quebrado.** Não há home solo, nem onboarding sem-academia além de `academies_screen`.

**Conclusão:** portabilidade existe como esqueleto de identidade, mas **zero valor diário sem academia**.

### 5.3 A linha de corte: o que é da ACADEMIA vs. o que é do LUTADOR

A pergunta de design é **"quem é a autoridade do dado"**:

**Fica academy-scoped (a academia é a autoridade — o registro que ela tem de você):**
- Presença **verificada** (`attendance:41`), promoção de faixa **verificada** (`beltProgressions:54`), financeiro/mensalidade (`financials:46`, irrelevante ao solo), planos, horários, loja, competições geridas, syllabus, avaliação física.
- O comentário em `student.dart:6-8` já admite a consequência do modelo atual: quando o aluno sai (`StudentStatus.transferred`, `:9`), "a ficha e todo o histórico permanecem **na academia**". Hoje **sair = perder acesso ao próprio histórico** — exatamente o que mata a portabilidade.

**Deveria ser portátil/pessoal (o lutador é a autoridade — vive em `/users/{uid}/...`):**
1. **Diário de treino pessoal** (mat log): data, gi/no-gi, rounds, técnicas drilladas, finalizações a favor/contra, energia/humor, lesão, notas. Hoje o mais próximo (`fightRecords`, `strikingSessions`, `workoutExecutions`) é tudo academy-scoped. **Hook de retenção nº 1** — é o que Marune e BJJ Notes vendem.
2. **Jornada de faixa própria** (auto-declarada + verificada por cima): `beltHistory` hoje mora no `Student` (`:302`); deveria morar no fighter.
3. **Metas / streak / mat-time** desde `jiujitsuStartDate` (campo já existe em `GlobalUser`, `user.dart:91`). Hoje `monthlyAttendanceGoal` está no `Student` (`:310`).
4. **Fighter card + showcase de conquistas** — hoje em `publicProfiles` academy-scoped.
5. **Grafo social / feed / comunidade** — não existe ainda; nasce naturalmente global.

### 5.4 Por que o lutador solo voltaria todo dia

Fundamentado no nicho: 75% dos brancas largam antes da azul, ~50% larga na azul, e as causas dominantes são *falta de senso de progresso* e *falta de pertencimento* — não a técnica. Um log pessoal que torna o progresso **visível** ataca a raiz. O sistema de stripes existe justamente para dar reconhecimento frequente entre faixas — replicável com micro-conquistas pessoais ("10 treinos", "100 rounds", "1 ano de azul"). E a cultura já é de postar marcos → o fighter card é distribuição orgânica embutida.

Valor diário concreto sem academia: logar o roll de hoje em 10s → streak + mat-time da semana → "há 8 meses na azul" → meta 3x/semana com push (`push_notification_service` já existe) → caderno "o que estou treinando" → feed/seguir lutadores → card de promoção pra postar.

### 5.5 A arquitetura: **inverter a gravidade**

Hoje `Student` (academia) é o real e `GlobalUser` é sombra. Proposta: **`/users/{uid}` (fighter profile) vira o agregado-raiz**, e as academias passam a ser **fontes que alimentam** o perfil.

- **Mover identidade + jornada para a raiz:**
  - `/users/{uid}/trainingLog/{sessionId}` — sessões auto-registradas; flag `verified` quando nascem de check-in de academia.
  - `/users/{uid}/beltJourney/{entryId}` — faixa auto-declarada (`source: self`) + entradas verificadas (`source: academy/{id}`, escritas por CF quando o professor gradua).
  - `/users/{uid}/goals`, `/users/{uid}/achievements` (showcase global).
  - **`/publicProfiles/{uid}`** keyed por lutador (agregando across academies), substituindo `academies/{id}/publicProfiles/{studentId}` (`server_functions.js:896`).
- **Belt deixa de ser só derivada:** `highestBelt` ganha fonte própria (auto-declarada) que `syncHighestBelt` (`global_user_service.dart:325`) apenas *eleva* quando a academia confirma algo maior.
- **Trust model é o ponto central de design:** dado **verificado** (presença/faixa da academia) entra no ranking cross-academy; dado **self-logged** do solo é pessoal mas não-verificado — **visualmente distinto** e **fora do ranking competitivo**, para não inflar. Resolve a tensão "lutador solo conta vantagem" sem tirar o valor pessoal dele (coerente com o mirror que o ranking já consome).
- **Ciclo de vida vira contínuo, não destrutivo:** entrar numa academia = **link** (o histórico pessoal permanece, a academia começa a adicionar entradas verificadas); sair (`StudentStatus.transferred`, `student.dart:9`) = a camada pessoal **persiste com o lutador**, em vez de ficar órfã. O lutador solo de hoje é o aluno verificado de amanhã — o mesmo cadastro serve aos dois.

---

## 6. Princípios de produto para criar CULTURA (não features soltas)

1. **Processo > resultado, sempre.** Premie consistência, mat-time, técnica e jornada — nunca só a faixa. Gamificar o resultado reforça o vício que faixas-pretas alertam e frustra na espera de anos. (Ataca a causa raiz da evasão na azul.)

2. **O app é extensão da "terapia do tatame", não mais um estressor.** Tom calmo, de presença e válvula — o check-in diário quase como um "diário de bem-estar de lutador". NÃO é mais uma fonte de notificações ansiosas e vanity metrics.

3. **Comunidade primeiro — pertencimento é o preditor #1 de retenção.** O lutador volta pelas pessoas, não pelo dado. Mesmo no solo, conectar a outros na mesma faixa/fase/dor. A validação de 1 toque (oss) é o motor do retorno diário.

4. **Autenticidade é feature, não enfeite.** A cultura execra medalha fácil e auto-promoção. Distinção visual rígida entre **verificado pela academia** e **auto-declarado (solo)**. O selo "verificado" é a legitimidade que nenhum concorrente tem.

5. **Ritualizar os first-times e os marcos escondidos.** Capturar/celebrar/compartilhar os picos emocionais (1ª finalização, 1º grau, sobreviver a um faixa-preta) — onde NENHUM concorrente atua. É o que cria cultura E o loop viral orgânico.

6. **Cultura brasileira, em português, na estética e na linguagem do nicho** (oss, tatame, roll, drilar). O vazio de mercado é exatamente este. Não imitar o copy genérico anglófono de fitness.

7. **Honrar a linhagem (identidade relacional).** Árvore de linhagem no perfil — de quem o lutador vem. Gera orgulho e conexão, e funciona mesmo solo.

8. **Aproveitar o trunfo estrutural: zero cold-start + auto-log.** A presença real vira evento na timeline sem digitação. Não construir o grafo do zero (erro fatal das redes sociais mortas) — usar o que já existe.

9. **Não competir com Smoothcomp/Flo/BJJ Fanatics — integrar.** Ser a camada de **identidade e comunidade diária**; deixar competição e instrucional como satélites linkáveis no perfil.

10. **Visibilidade do progresso lento.** O BJJ evolui devagar; o diário pessoal e o Wrapped tornam visível o progresso que o platô esconde — exatamente onde a motivação morre.

---

## 7. Recomendações priorizadas e faseadas

### Fase 0 — Destravar o solo (menor esforço, maior destravamento de teto)
1. **Dar um destino real ao usuário free:** uma **home solo** separada, em vez de despejar em `/portal` quebrado (`app.dart:551` + `portal_shell.dart`/`home_screen.dart` que assumem `Student`/`settings` não-nulos).
2. **Onboarding sem academia:** faixa, time/linhagem, modalidades, `jiujitsuStartDate` — perfil de lutador funcional para quem não tem academia no app.
3. **Soltar `beltJourney`/`highestBelt` da dependência exclusiva de `syncHighestBelt`** (`global_user_service.dart:325`), para o solo poder ter faixa auto-declarada.

### Fase 1 — O hook de retenção (diário pessoal portátil)
4. **`/users/{uid}/trainingLog` + tela de log rápido** (10s): gi/no-gi, rounds, técnicas (hashtags), finalizações, energia/lesão, notas. Independente de academia.
5. **Auto-log do dado verificado:** a presença real da academia (`attendance:41`) vira entrada `verified` na timeline pessoal via CF — sem digitação. (Vantagem que Marune só sonha.)
6. **Streak + mat-time + micro-conquistas pessoais** ("10 treinos", "100 rounds", "1 ano de azul"), com push (`push_notification_service` já existe). Reframe do platô como normal ("70% sente isso").

### Fase 2 — O motor de cultura e aquisição (Shareable Cards)
7. **Motor de "Shareable Cards"** com a faixa como herói visual brandado, 9:16 + 1:1 automáticos, fricção zero. **5 famílias:** Graduação/Grau · Medalha de pódio · Marco de tempo/streak · Wrapped (mês/ano) · Marco emocional escondido.
8. **Disparar no pico emocional** (logo após o professor registrar graduação/presença) **e no horário social** (domingo à noite/fim de mês).
9. **Loop de aquisição:** branding consistente + link/QR → landing no **perfil público** (`publicProfiles`). Selo **verificado (academia) vs. auto-declarado (solo)**.
10. **Repromover `publicProfiles` de academy-scoped para fighter-scoped** (`server_functions.js:896`), habilitando feed/card global e o ranking cross-academy só com dado verificado.

### Fase 3 — Comunidade e efeito-rede (o que retém de verdade)
11. **Feed + grafo social global** (seguir lutadores, oss de 1 toque, comentários) — nascendo do grafo que já existe (colegas de turma, professor) para evitar cold-start.
12. **Validação social e convite contextual** ("convide seu parceiro de drill") — referral nascido do orgulho.
13. **Instrumentar o coeficiente viral *k*** (cartões gerados → compartilhados → cliques → cadastros atribuídos). Meta: cada graduação postada traz ≥1 visitante.

### Dependências e notas
- **Graduação e presença já existem** e podem virar gatilho de cartão **imediatamente**.
- **Sync de medalhas de campeonato está deferido** (memória do projeto, hotfix 2.5.1) — o gatilho de **cartão de pódio** depende dele; priorizar quando reativado.
- **Roubar de Marune o que funciona** (OSS em vez de like, timeline de faixa, hashtags de técnica, web profile público) e **fazer melhor o que ele faz mal** (multimodalidade limpa — já existe em `sports.dart`; confirmação de presença pelo parceiro — Marune não tem e usuários pedem; cultura BR).

---

**A aposta:** o GAP não é mais um tracker — é a **rede social de identidade do lutador brasileiro**, que já nasce com grafo social vivo, funciona em modo solo, e premia jornada/pertencimento em vez de vaidade. É exatamente onde o GraduaBJJ tem vantagem estrutural que Marune e os outros não têm — e é, ao mesmo tempo, a alavanca de retenção de **pessoas no esporte**, que é a missão cultural do projeto.