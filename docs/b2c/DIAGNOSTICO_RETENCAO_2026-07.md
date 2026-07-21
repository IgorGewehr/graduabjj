# Diagnóstico definitivo: por que o app do lutador não retém

*Baseado em leitura de código (branch b2c), dados de produção (Firestore arpjj-76350, 2026-07-20) e refutação adversarial de 10 hipóteses. Tudo abaixo tem evidência em arquivo:linha ou contagem de prod.*

---

## 1. O veredito

Vocês não construíram um app pro aluno — construíram um extrato bancário do treino, mudo, que sai de fábrica desligado. Não existe motivo para abrir o app num dia sem treino (todos os 5 loops derivam de presença; o streak muda no máximo 1x/semana; não há um único conteúdo gerado pelo app), e mesmo quando haveria motivo, ninguém fica sabendo: **81% dos usuários não têm token de push nenhum, iOS recebe zero push desde junho, nenhum push deep-linka, e o momento da presença verificada — o pico de receptividade — é um comentário `// Handlers futuros` no código**. O "social" que deveria salvar tudo tem, em toda a produção, **3 arestas de amizade, 1 par mútuo e 13 likes na história** — porque não há UGC, não há share externo e amigo se adiciona ditando código pelo WhatsApp, que é exatamente o app que vence o seu por W.O. E a pergunta número 1 de qualquer aluno de BJJ — "quanto falta pro meu grau?" — é irrespondível por default, atrás de dupla trava que o professor nunca liga. Tudo isso era previsível: **a própria pesquisa de vocês mandou construir três pilares (Treinei 1-tap, Motor de Cards, densidade/descoberta) e instrumentar desde o dia 1 — vocês construíram o polimento psicológico em volta deles e pularam os três, sem um único evento de analytics para perceber**. O fracasso não é de gosto do aluno; é aritmético, e foi invisível até doer no bolso porque o app não mede nada.

---

## 2. As causas-raiz, ranqueadas

### CR1 — Não existe razão-para-abrir-hoje: o app é um espelho passivo do treino

**Mecanismo.** Streak, conquistas, feed, jornada e recap derivam exclusivamente de `attendance`/`training_logs` (functions/feed_materializer.js:295-542; achievement_service.dart:565-588). O streak é semanal — o número muda no máximo 1x/semana (weekly_streak.dart:110-193). A meta mensal nasce invisível (default 0, settings_service.dart:357), a barra de graduação nasce desligada (dupla trava default false, :328/:333 → SizedBox.shrink no hub :1099-1102). Marcos de streak disparam **5 vezes na vida** com id determinístico sem data — quem quebra e reconstrói nunca é celebrado de novo (feed_post.dart:331-332). Não existe nenhum conteúdo gerado pelo app: zero desafio, zero técnica, zero prompt (busca exaustiva em lib/screens/fighter e lib/screens/portal). Até o ponto vermelho do sino do hub é hardcoded, sem dado atrás (lutador_hub_screen.dart:456-465). O único delta em dia sem treino é o treino dos *outros* — e ele colapsa para zero em academia com baixa adoção (feed exige conta fighter vinculada, feed_materializer.js:306-309), o cenário realista de cold-start. O aluno 2x/semana aprende em duas semanas que "nunca tem nada". Cada abertura sem novidade reduz a chance da próxima — extinção comportamental de manual.

**Invalida do roadmap:** qualquer iteração que melhore a *leitura* do espelho (novos cards no hub, Rivais R1, polimento do card VOCÊ). Melhorar o espelho não cria motivo de voltar.

### CR2 — A camada de gatilho externo está fisicamente quebrada (e vocês não sabiam)

**Mecanismo.** Hábito nascente vive de gatilho externo. Aqui: (a) **iOS recebe zero push desde jun/2026** — FCM desligado inteiro no main.dart (guard `!Platform.isIOS`, commit 1ddf1e7); prod confirma: 1 token iOS na história, 0 depois de 30/06. (b) **Só 45 de 235 usuários (19%) têm token qualquer** — salvamento só acontece em evento de login (auth_provider.dart:230/259/542/592). (c) **Nenhum push deep-linka**: o roteador de tap só lê `data['actionUrl']` (push_notification_service.dart:144) e nenhum sender envia actionUrl (push_functions.js:305-306, feed_like_counter.js:113, server_functions.js:643-647) — todo tap abre a última tela. (d) O push no ato da presença — o momento goal-gradient que a pesquisa manda capturar — é literalmente o comentário "Handlers futuros (§9.1)" (retention_functions.js:16); `ATTENDANCE_HANDLERS = [retention, feed]` e nada mais (:256-259). Todo o trabalho de pushes (streak em risco, recap, like) foi construído em cima de um cano furado: a maioria absoluta dos alunos **nunca recebeu nada**.

**Invalida do roadmap:** qualquer conclusão sobre "pushes não funcionam" — eles nunca rodaram. E qualquer push novo antes de consertar o cano.

### CR3 — O "social" é telemetria com botão de coração: densidade estruturalmente impossível

**Mecanismo.** A pesquisa diz que o mecanismo causal comprovado é kudos + densidade de rede. O que existe não pode gerar densidade: os 6 tipos de post são todos emitidos por máquina, enum fechado, sem texto livre nem foto (feed_post.dart:7-13); o único verbo é like (grep "comment" em lib/ = 0); cada autor produz ~1 post/semana em regime estável, porque tudo o mais dispara uma vez na vida; amigo exige ditar código de 6 caracteres — que viaja pelo WhatsApp (friend_service.dart:10 admite "sem busca/descoberta"); e **não existe share externo** — pubspec sem share_plus, o marco nunca vira status no Instagram, k viral = 0 por construção. **Prod confirma o óbito: 251 posts na vida da plataforma, 24/semana no sistema inteiro, 13 likes na história, 5,2% dos posts com ≥1 like, 3 arestas de follow, 0 usuários com 3+ amigos.** O grupo de WhatsApp da turma tem foto, zoeira, aviso do professor e os amigos de verdade. O app tem headline em caps com um coração.

**Invalida do roadmap:** Rivais R1+, Liga da Chamada, qualquer aposta que pressuponha grafo social vivo. Sem densidade, o único mecanismo causal da pesquisa nunca liga.

### CR4 — A economia de status pertence ao professor, nasce desligada, e a copy rebaixa o gesto do aluno

**Mecanismo.** Aqui é preciso ser preciso, porque a forma absolutista ("o aluno é 100% espectador") foi **refutada**: a tab central chama "Treinei", o self-log alimenta o streak igual à presença verificada (weekly_streak.dart:3-5), e o card de ativação manda registrar o 1º treino. Mas o núcleo sobrevive: **todo valor profundo é professor-gated com defaults hostis**. Graduação: dupla trava default false, e o próprio código admite que a academia-vitrine (T23) não usa (diario_screen.dart:2021-2027). Presença verificada: check-in vira "pending" até o professor confirmar (checkin_service.dart:145/:314). ~8-10 entradas do menu ficam *escondidas* (nunca "locked") atrás de flags default-false que só o professor liga (nav_resolver.dart:116-170). E o gesto-mestre está sabotado: o Diário abre na Jornada (que só conta presença do professor), o botão real fica atrás do toggle Histórico rotulado **"TREINOU SEM PROFESSOR?"** e carimbado **"REGISTRO AVULSO — NÃO CONTA PRA GRADUAÇÃO"** (diario_screen.dart:2851, 2714, 2987), com docstring interna confessando: o self-log foi "REBAIXADO... NÃO alimenta os números da jornada" (:39-43). O aluno que treinou COM professor lê "não é pra mim"; o que registra descobre que não valeu. E na porta: **não existe cadastro sem academia** — só "Tenho código de acesso" ou "Sou dono" (register_screen.dart:103-151). A tese B2C "identidade com ou sem academia" é impossível no primeiro tap.

**Invalida do roadmap:** a premissa "o portal está pronto, falta o professor configurar". Os defaults SÃO o produto. Um produto cujo motor de atenção depende de um terceiro ligar não está lançado.

### CR5 — Voo cego absoluto: zero analytics

**Mecanismo.** Nenhum firebase_analytics no pubspec, nenhum logEvent em lib/ nem functions/. O north-star declarado (WAS-solo), D1/D7/D30, k viral, os guardrails que o próprio plano manda "instrumentar desde o dia 1" (00_PLANO_MESTRE.md:29, :183) — nada é medido. Por isso este fracasso só apareceu quando o dono sentiu no bolso, e por isso ninguém percebeu que iOS estava surdo há um mês ou que o grafo social tinha 3 arestas.

**Invalida do roadmap:** toda decisão de produto tomada "por sentimento" até aqui — inclusive as deste documento, que precisam virar hipóteses mensuráveis.

---

## 3. Falha estrutural vs falha de execução

**Execução (consertável iterando, mais barato do que parece):**
- Push iOS, captura de token fora do login, actionUrl nos senders, push no ato da presença — encanamento.
- Promover o Treinei: a refutação provou que **o pipeline já funde self-log no streak, no feed e nos pushes** (weekly_streak.dart, student_provider.dart:284-372, feed_materializer.js:9-17). Rebaixá-lo foi decisão de UI/copy — e des-rebaixar também é.
- Defaults das flags, celebração de comeback, CTA que despeja o aluno na tela errada (lutador_hub:962 → diario `_view=0`), motor de cards/share, analytics.

**Estrutural (exige mexer na tese do produto):**
1. **Cliente pagante ≠ usuário.** Quem paga é o dono da academia, e a arquitetura reflete isso: a moeda "verificada" (graduação, contagem oficial) sempre pertencerá ao professor enquanto for a âncora anti-fraude da graduação-por-presença. Dá pra suavizar a copy; não dá pra fingir que o aluno é dono do status oficial. É um app B2B com casca B2C, e escolher servir o lutador de verdade implica aceitar tensão com o cliente que paga.
2. **Cold-start de duas pontas.** O valor social do app é função da adoção da academia — e o job social já está resolvido pelo WhatsApp. Competir com o WhatsApp como *destino* é aposta perdida por estrutura; a única via é usá-lo como *distribuição* (share).
3. **Espelho sem estoque.** Um app que só reflete treino de quem treina 2x/semana tem, por construção, ~2 momentos de novidade própria por semana. Ou o app ganha uma fonte de valor independente do treino (conteúdo, share, identidade), ou aceita ser utilitário de baixa frequência — o que também é uma tese válida, mas incompatível com "app social do lutador".
4. **Identidade sem academia** exige porta de entrada nova e modelo de dados (selfRecords retorna null sem academyId — diario_screen.dart:71-74). Não é refactor de tela; é decisão de produto.

---

## 4. O que a própria pesquisa já avisava — e foi ignorado ou meio-implementado

A pesquisa foi lida e a metade **barata** foi construída com fidelidade: hub abre no progresso próprio, streak com freeze/lesão, oss recíproco, card VOCÊ no meio da tabela, missão anti-blues, rival dentro dos gates. Essa calibragem está correta e não é o problema.

Os pilares que a pesquisa e o plano dizem **carregar** a retenção foram todos pulados:

1. **Big bet nº1 — "Treinei" 1-tap <10s como gesto central** ("a tela de save É a recompensa", 00_PLANO_MESTRE.md:53): **revertido**. Docstring literal: "REBAIXADO para a aba HISTÓRICO... NÃO alimenta os números da jornada" (diario_screen.dart:24-45). O oposto do north-star WAS-solo.
2. **Motor de Cards — "a maior alavanca viral"** (00_PLANO_MESTRE.md:56, :86; roadmap listava "Deps faltantes hoje: share_plus"): **nunca construído**. Zero share em todo o app.
3. **Densidade/descoberta (Fase 2, "a virada de curva")**: **não existe** — sem busca, sem sugestão, sem geo, sem QR de convite. A pesquisa é explícita: kudos é causal *mas* "o que falta é densidade e reciprocidade". Sem rede, o mecanismo não tem combustível — e prod confirmou: 3 arestas.
4. **"Instrumentar desde o dia 1" / "a régua de toda decisão: move D1, D7 ou D30?"**: **zero eventos**. A régua nunca existiu.
5. **"App que vale a N=1, sem a academia dentro dele"** (00_PLANO_MESTRE.md:9): **impossível na porta** — cadastro exige código.
6. A pesquisa avisou que **BJJ para a maioria = saúde + prazer, não competição** — e o único conteúdo recorrente do feed é estatística de volume e ranking, exatamente a gramática competitiva que ela manda dosar.

Executaram o polimento; o motor ficou no doc.

---

## 5. Os 5 movimentos que importariam de verdade (por alavancagem)

**M1 — Religar o cano físico de gatilhos.** Reativar FCM no iOS (resolver o crash do iOS 26 — é um workaround de init, não uma feature), capturar token em toda abertura autenticada (não só login), colocar `actionUrl` em todos os senders + deep-link no tap, e implementar o push do ato da presença que está comentado há um mês (retention_functions.js:16). *Ataca CR2.* Sem isso, tudo o mais é inaudível — hoje 4 de 5 alunos não podem ser alcançados. **Deixar de fazer:** desktop Windows e expansão da catraca (congelar no field-confirm do piloto), F4/F5 da repaginada admin. Nenhum deles move retenção de aluno.

**M2 — Promover o "Treinei" a gesto-mestre, de verdade desta vez.** Logger como primeira tela do fluxo (não a Jornada), CTA persistente no hub, copy neutra ("Registrar treino de hoje" — matar "TREINOU SEM PROFESSOR?" e o carimbo "NÃO CONTA"), jornada exibindo self-logs com selo AUTO em vez de escondê-los, e celebrar o comeback pós-quebra de streak (hoje o sistema fica calado exatamente no momento em que retenção mais importa). *Ataca CR1 e CR4.* Custo comprovadamente baixo: o pipeline já conta self-log no streak — é mudança de UI/copy, não de fundação. A moeda verificada continua do professor (anti-fraude preservado); só para de esfregar isso na cara do aluno. **Deixar de fazer:** qualquer card novo de leitura no hub até o gesto de escrita estar a 1 tap.

**M3 — Instrumentar antes de construir mais qualquer coisa.** WAS-solo, D1/D7/D30, abertura-pós-presença, cobertura de token, taxa de share. Uma semana de trabalho. *Ataca CR5 e é o guardrail de M1, M2 e M4* — sem isso vocês vão repetir este ciclo: construir seis meses, descobrir no bolso. **Deixar de fazer:** decisões de roadmap sem número — incluindo tratar este documento como verdade permanente em vez de lista de hipóteses a medir.

**M4 — Motor de Cards + share externo.** share_plus + render de card bonito (graduação, marco de streak, aniversário de tatame) → status do WhatsApp / stories. *Ataca CR3 pela única via viável:* o WhatsApp deixa de ser o concorrente e vira o canal de distribuição; é a "maior alavanca viral" do próprio plano, e é a única forma de densidade nascer (k viral hoje = 0 por construção). **Deixar de fazer:** tentar transformar o feed interno em destino (comentários, chat — não agora), Rivais R1, Liga da Chamada. Sem grafo, são features para 3 arestas.

**M5 — Abrir a porta solo.** Terceira opção no cadastro ("Sou lutador"), perfil N=1 mínimo (faixa auto-declarada, modalidades, Treinei funcionando sem academyId — hoje selfRecords morre sem vínculo). *Ataca a impossibilidade estrutural da tese B2C.* Vem por último de propósito: só faz sentido depois que M1-M4 provarem que o loop retém alunos *vinculados* — se não retém quem já tem academia, não vai reter quem não tem. **Deixar de fazer:** features novas multi-academia e de admin até lá.

---

## 6. O que NÃO é o problema — não gastem energia aqui

- **"O app é o cobrador que espanta o aluno."** Refutado com dados de prod: o aluno linkado mediano recebeu **zero** notificações de qualquer tipo; o WhatsApp D+15 com ameaça de suspensão **nunca foi enviado uma vez** (lastReminderStage vazio em 332/332 financials); 77% de todo o tráfego de cobrança da história está na academia de **teste** do dono com mensalidades de R$5. O app não condiciona aversão — ele é **mudo**. (Fica só o defeito localizado de design: sendToUser ignora prefs/quiet-hours, e o toggle de prefs é placebo por mismatch de chave pt/en — consertar junto com M1, mas não é isso que mata o produto.)
- **Falta de gamificação ou calibragem psicológica errada.** A calibragem implementada é fiel à pesquisa (freeze, oss, meio-da-tabela, anti-blues). Mais polimento psicológico não move nada enquanto CR1-CR3 existirem.
- **"O aluno não tem nenhuma ação própria" (forma absolutista).** Falso — Treinei existe, conta pro streak, tem tela de recompensa. O problema é posicionamento e copy (CR4), não arquitetura. Não é preciso refazer fundação; é preciso parar de esconder e rebaixar o que já funciona.
- **Volume excessivo de push.** O problema é o inverso: silêncio. Cap FCFS e priorização são detalhes para depois que existir alguém recebendo push.

---

*A frase que resume tudo, e que está literalmente escrita na UI de vocês: "VERIFICADO = PROFESSOR · AUTO = VOCÊ" (diario_screen.dart:2792). Enquanto o app disser isso ao aluno — em copy, em defaults e em arquitetura de gatilhos — ele será uma ferramenta do professor com casca de app do lutador. A boa notícia deste diagnóstico é que a maior parte do conserto é encanamento e copy, não refundação. A má notícia é que nada disso aparecerá como progresso de feature no changelog — e é exatamente por isso que nunca foi feito.*
