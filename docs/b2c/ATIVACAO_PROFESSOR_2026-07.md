# O que fazer com as 37 academias mortas — e o que consertar antes

## 1. Resposta direta

Na ordem, e a ordem importa: **(1)** conserte esta semana as duas armadilhas que ainda matam qualquer professor que voltar — a tela de Chamada com zero turmas é um beco sem saída sem botão de criar turma (`lib/screens/admin/attendance_screen.dart:955-995`), e cadastrar aluno não matricula em turma nenhuma (`student_form_screen.dart`, 1759 linhas, zero ocorrências de turma/classId) — são dias de trabalho, não semanas; **(2)** rode um script de ~30 linhas setando `subscription.paidUntil = now+14d` nas ~32 academias mortas reais (o modelo prioriza `paidUntil` sobre trial — `lib/models/academy.dart:165-172` — então isso reabre o acesso sem nenhum code change, sem banner de "Assinar" e sem e-mail duplicado); **(3)** dispare a campanha de win-back abaixo — WhatsApp 1:1 manual do seu número pros 3 VIPs no D0, três e-mails do seu e-mail pessoal em 21 dias, com os rascunhos prontos na seção 4 — **começando esta semana**, porque a janela de reengajamento de 90 dias da coorte de maio (24 das 36 morreram entre 11-29/mai) fecha entre 9 e 27 de agosto. Expectativa honesta: 2-4 reativações e talvez 1 pagante — o valor real da campanha são as respostas (pesquisa de churn grátis) e descobrir qual canal trouxe a onda de maio e qual trouxe LEAU/Drakkar, porque o seu funil frio real converteu ~0-2 em 32, e o futuro do produto está em consertar a ativação da PRÓXIMA coorte e no loop dos 300+ alunos, não nos mortos.

---

## 2. Por que eles morreram

Não foi preço. Um único cancelamento explícito em 36 (CT Batista, que voltou 2 meses depois só pra cancelar). Foi **morte no dia 1**: na maioria das mortas, `updatedAt == createdAt`. O mecanismo tem quatro engrenagens:

**a) O produto ordena setup antes de valor, e a travessia mata.** O checklist "Comece por aqui" tem 6 passos onde "Registre a 1ª presença" é o ÚLTIMO (`lib/widgets/onboarding/activation_checklist.dart:110-162` — perfil, turma, planos, MP, alunos, presença), cada passo é um deep-link solto sem costura (criar turma termina em pop+snackbar, `classes_screen.dart:854-860`; salvar aluno só volta pra lista). A autópsia mostra a morte exatamente nessa travessia: **19 de 36 montaram alunos/planos/turmas e nunca fizeram 1 chamada**; 11 nem começaram.

**b) Dois becos sem saída literais no código — ainda vivos hoje.**
- Chamada com 0 turmas: dropdown vazio + "Escolha uma turma acima para registrar as presenças" **sem nenhum botão de criar turma** (`attendance_screen.dart:955-995`; não existe branch para `_classes.isEmpty`). Foi assim que "Kimura Team Jorjão" recriou a academia 3 vezes, ficou com 17 alunos e 0 turmas, e desistiu sem nunca descobrir o problema.
- Cadastro de aluno sem turma: o form matricula em **plano financeiro** mas não em turma (`student_form_screen.dart:1720`) — e a chamada filtra por `_selectedClass!.studentIds` (`attendance_screen.dart:563-567`). Resultado: 17 alunos cadastrados = 17 alunos invisíveis pra chamada. O checklist marca "Cadastre seus alunos" como concluído sem matrícula nenhuma (`activation_checklist.dart:106,146-153`).

**c) O loop do dinheiro — o que 19 deles vieram comprar — também é beco.** Gerar cobrança é ato deliberado (sheet manual "Gerar mensalidades", `financial_screen.dart:874-905`), então HOOKS (10 alunos + 5 planos + 5 cobranças) e ES Team **disseram com o dedo** que vieram resolver mensalidade, não presença. Mas a cobrança gerada é inerte: com os defaults do dia 1 (`whatsappEnabled`/`emailEnabled`/`autoTuitionEnabled` = false, `billing_reminder_service.dart:493-498`), a única ação voltada ao aluno é "Lembrar", que abre wa.me com **texto puro sem PIX e sem link — mesmo com MP conectado** (`payment_service.dart:1094-1117` nem aceita parâmetro de link). O valor flagship em R$ morre no primeiro toque.

**d) O dia 2 não existe, e a coorte de maio foi queimada duas vezes.** Após a 1ª chamada: um snackbar (`attendance_screen.dart:453-455`). Dia seguinte: silêncio — os 3 crons de push miram exclusivamente ALUNOS (`functions/push_functions.js:443,514,599`); o único lifecycle do dono é 1 e-mail D-2 de um trial de 7 dias, cuja query só olha contas dos últimos 7 dias (`functions/index.js:2176-2187`) — **a coorte de maio nunca recebeu nem esse**. Pior: em 27/mai, no meio da onda, o commit 5651b50 cortou o trial de 30 pra 7 dias **retroativamente** (o modelo ignora de propósito o `trialEndsAt` gravado — `academy.dart:147-158`); quem cadastrou 11-20/mai acordou com paywall hard-lock sem aviso (`admin_shell.dart:38-44`, showClose:false, sem export, sem modo leitura). Parte da coorte não abandonou — foi trancada pra fora com promessa quebrada.

E o contexto que muda a leitura: **todo o onboarding atual (checklist, carrossel, Radar) só existe desde 30/jun-02/jul** (commit 1ddf1e7 em diante). A coorte de maio morreu num dashboard intocado desde fevereiro, cheio de zeros, com o card "R$ 0,00 · 0%" que o próprio código admite em comentário que "parecia o app quebrado". Isso é ruim pro passado — e é o seu gancho honesto de win-back: *"o app que você testou não existe mais"*.

---

## 3. Mostrar valor no dia 1 — mudanças de produto ranqueadas

### P0 — Matar os dois becos (pré-requisito de TUDO, inclusive do win-back) — 2-4 dias

1. **CTA "Criar turma agora" quando `_classes.isEmpty` na Chamada**, abrindo bottom-sheet de 1 campo e auto-selecionando. O `PolishedEmptyState` já suporta `actionLabel`/`onAction` (`polished_empty_state.dart:24-25,75-81`) — hoje simplesmente não é passado. É quase literalmente duas linhas mais um sheet.
2. **Seção "Turmas" no form de aluno** (chips multi-select), pré-marcada quando a academia tem exatamente 1 turma. Elimina o degrau invisível onde os 19 caíram.
3. **Auto-matrícula como default**: ao criar a PRIMEIRA turma numa academia que já tem alunos (o estado exato do Kimura e do HOOKS), checkbox pré-marcado "Matricular todos os X alunos". O write é o mesmo update de `studentIds` que o `_ManageStudentsSheet` já faz (`classes_screen.dart:2054`). Adicionar "Selecionar todos" nesse sheet (hoje é toggle um-a-um).
4. **Degrau de matrícula no checklist** — hoje ele marca sucesso num passo que não entrega nada.

*Não fazer:* criar um segundo caminho novo de adicionar aluno no empty state — a Chamada JÁ tem botão "Adicionar" que matricula+marca em 1 toque (`attendance_screen.dart:893-911`); o problema dele é descoberta, então reuse-o no empty state em vez de duplicar fluxo.

### P0 — Wizard "primeira chamada em 3 minutos" como primeira tela pós-cadastro — dentro do sprint

Inverter setup→valor: após criar a academia, em vez de dashboard+checklist, 3 telas que TERMINAM na chamada feita: (1) "Crie sua turma de hoje" — 1 campo + chips de sugestão; (2) "Quem treina hoje?" — nomes em sequência OU "importar planilha", todos auto-matriculados; (3) a própria chamada pré-filtrada, tap por aluno, celebração no final. Perfil/planos/MP viram checklist DEPOIS. É orquestração de `ClassService`/`StudentService`/`AttendanceService.markPresent` que já existem — não é feature nova. Bônus: este wizard É a promessa do e-mail de win-back.

### P1 — Cobrança que se sente em 3 minutos (a métrica de ativação está errada) — 2-3 dias

O aha-moment oficial é a chamada, mas 19 dos 32 mortos vieram comprar COBRANÇA — preferência revelada. E o carrossel já promete "Mensalidade no automático" (`onboarding_gate.dart:115-124`) enquanto o produto entrega 6 passos, 3 toggles OFF e zero prova (o passo MP é o único `dismissible:true` do checklist — o produto trata a própria promessa flagship como dispensável).
1. **Injetar PIX/link de pagamento no lembrete manual do WhatsApp** — o código de injeção já existe no canal proxy (`includePaymentLink` defaulta true, `billing_reminder_service.dart:504`), só não chega no wa.me.
2. **"Cobrança-teste no SEU WhatsApp"** como passo do checklist: o app monta a mensagem real com PIX pra o número do próprio dono, zero alunos necessários. Hoje não existe nenhum envio-teste no app.
3. Reordenar o checklist money-first pra quem sinaliza esse caminho.

*Não fazer:* prometer "o app cobra por você" sem o opt-in explícito — a cobrança automática exige toggles + MP; a frase honesta é "ative e o app cobra por você".

### P1 — Religar o import CSV (o wow de migração está órfão) — ~2 botões

A rota `/admin/importar-alunos` existe (`lib/app.dart:1243-1247`) e a tela é ótima — wizard de 4 passos com **turma obrigatória** e matrícula automática (`student_import_service.dart:345-425`, teria prevenido estruturalmente o caso Kimura) — mas os dois entry-points foram removidos por acidente colateral no commit 06cde61 (01/jul). Restaurar o botão na lista de alunos + caminho paralelo no wizard do dia-1. O lead de maior potencial (Escola Alessandro Silva, 27 alunos importados) provou que a feature atrai exatamente a academia grande que paga. Nota honesta: Alessandro viveu o wow completo e morreu mesmo assim — import é piso da categoria (Gymdesk faz migração white-glove grátis, ABC EVO vende "5.000+ migrações"), necessário mas não suficiente.

### P1 — O dia 2 do PROFESSOR — 1 sheet + 1 cron

(a) Bottom-sheet de celebração após a primeira chamada da vida da academia (hoje: snackbar; ironia — o admin ganha confetti ao conectar MP, criar aluno e graduar, a chamada é a única cerimônia sem festa) + preview do que o aluno vê no app dele. (b) Cron `ownerChamadaReminder`: turma agendada hoje + 0 presenças 2h após o horário → push "Treino das 19h sem chamada — registre em 1 toque". Não é o primeiro push ao dono — `notifyAdminCF` e o cron diário de inadimplência já existem (`server_functions.js:636-655,1001`) — é **redirecionar um canal que hoje só faz nag de dívida para fazer ativação**. Cap de 1/dia, quiet hours, e **suprimir o nag de overdue para leads ressuscitados** (o Alessandro tem 31 cobranças velhas; sem supressão ele volta e leva cobrança diária antes de qualquer valor).

### P2 — Instrumentar o funil admin ANTES do disparo — 2-3 dias

Zero eventos hoje; esta autópsia precisou de queries manuais 2 meses depois. 6 eventos: `academy_created`, `class_created`, `student_created`, `enrollment_done`, `first_attendance`, `owner_d1_return`. Sem isso, nenhuma hipótese é falseável e os leads reativados morrem invisíveis de novo — e é a segunda e ÚLTIMA chance deles.

### P2 — Mostrar o app do aluno ao dono + adiar CPF/CNPJ

A adoção do aluno correlaciona com sobrevivência (LEAU 95%, T23JJ 25%, Drakkar 15%, mortas ~0) e é o único diferencial que caderno e planilha não copiam — mas nenhuma tela mostra "veja o que seu aluno vê", e o convite em massa por código da academia está deployado no backend (5 CFs em prod) sem build de cliente que o exponha. CPF/CNPJ com validação de dígito bloqueando o cadastro (`create_academy_screen.dart:113-192`) deveria ir pro checkout — mas 40 academias passaram por esse gate, então é a menor prioridade do pacote.

---

## 4. A campanha de win-back — pronta pra executar

### Pré-voo (não negociável, nesta ordem)

1. **Fixes P0 primeiro.** Os e-mails dizem "consertei o que te travou". Com a armadilha viva, isso é fraude contra você mesmo: o lead volta, cai no MESMO beco, e você queimou o único gancho honesto que tinha.
2. **Script `paidUntil = now+14d`** em cada academia morta. `hasAccess` prioriza `paidUntil` (`academy.dart:165-172`), o gate do AdminShell é stream (efeito imediato), `isTrialing` vira false (sem banner "Assinar" desde o minuto 1) e o `trialExpiryReminder` pula a conta. O prazo expira sozinho = deadline honesta. **O script deve pular qualquer conta com `paidUntil` futuro ou plano pago.**
3. **Higiene:** excluir as ~4 academias de teste suas e o CT Batista (quem voltou só pra cancelar não pode receber "reabri seu trial" — no máximo o e-mail-pergunta do toque 3). Checar cobrança recorrente fantasma nos 32: o CTA de assinar cria recorrência por default (`functions/index.js:2046`) e não existe UI in-app pra cancelar — se algum lead está sendo cobrado sem usar, ele recebe PRIMEIRO um contato de regularização ("quer que eu cancele e devolva o último mês?") e NUNCA win-back. Suprimir hard-bounces do toque 1 em diante.

### Segmentos e tratamento

| Segmento | Quem | Tratamento |
|---|---|---|
| **VIP** (3) | Rilion Gracie (franquia, morreu 19/jun — o lead mais quente, dispara PRIMEIRO), Escola Alessandro Silva (27 alunos + 31 cobranças — quem mais investiu), Kimura Team Jorjão (vítima 3x da armadilha) | WhatsApp 1:1 manual do SEU número + oferta de call de 20 min "eu monto com você" |
| **B** (~19) | Montou-sem-chamada (HOOKS, ES Team...) | E-mails 1+2+3, mensagem do DINHEIRO com os números da conta deles |
| **C** (~5) | Testou-e-sumiu (Lagoa: 1 semana real, parou 9 dias ANTES do trial acabar — preço não foi o motivo) | E-mails 1+2+3 + pergunta direta; Lagoa merece WhatsApp |
| **A** (~11) | Cadastrou-e-sumiu | Só e-mails 2 e 3 (custo marginal zero, expectativa ~0), hook status/app-do-aluno |

### Cronograma

- **D0** — script paidUntil + WhatsApp VIP (manual, WhatsApp Business comum — blast frio pela API oficial é proibido pela Meta desde nov/2024 e derruba o número; e o proxy de notificação é infra de cobrança de aluno, não de marketing).
- **D+1** — E-mail 1 (segmentos B/C, merge-fields do Firestore).
- **D+5** — E-mail 2 (TODOS, incluindo A).
- **D+12** — E-mail 3 (deadline + pergunta + oferta de exportar os dados deles — desarma o hard-lock que hoje mantém os dados reféns; é o e-mail que mais gera resposta).
- **D+14** — paidUntil expira sozinho. Credibilidade.
- **D+21** — fim. Quem não abriu/logou/respondeu sai da lista PARA SEMPRE. Sem "só mais um toque".

Tudo do seu e-mail pessoal com reply-to real — o objetivo nº 1 é RESPOSTA, não clique. Quem responde "depois" ganha 1 follow-up agendado e mais nada.

### Os rascunhos (copiar e mandar; merge-fields entre chaves)

**E-MAIL 1 — D+1, segmento B**
Assunto: `você cadastrou {N} alunos no BJJEasy e travou — a culpa foi minha`

> Oi {nome}, aqui é o Igor, eu que fiz o BJJEasy.
>
> Fui rever as academias que testaram o app em maio e vi a {academia}: {N} alunos cadastrados, planos montados... e nenhuma chamada. Você parou exatamente onde o app te deixava na mão — a tela de Chamada pedia uma turma e não te mostrava como criar, e o aluno cadastrado não entrava em turma nenhuma. Não era você. Era o app.
>
> Consertei isso, e o painel agora te guia passo a passo em vez de te mostrar um monte de zeros.
>
> Reabri seu acesso por 14 dias, sem cartão e sem refazer nada: seus {N} alunos continuam lá do jeito que você deixou, é só logar com este e-mail. A primeira chamada agora leva menos de um minuto.
>
> Se não fizer sentido, me responde só com o motivo — eu leio tudo.
>
> Oss, Igor

**E-MAIL 2 — D+5, todos (inclusive segmento A)**
Assunto: `o BJJEasy que você testou em maio não existe mais`

> Oi {nome}. Semana passada reabri seu acesso (14 dias, sem cartão). O que mudou desde maio:
>
> — Cobrança no WhatsApp com PIX: ative a cobrança automática e o app cobra a mensalidade dos seus alunos por você.
> — App do aluno: presença, graduação e notificação no celular dele, com o nome da SUA academia — seu aluno baixa de graça.
> — Guia "Comece por aqui": turma, alunos e primeira chamada em 5 minutos, na ordem certa.
>
> Seu acesso expira dia {data} e depois disso não reabro (é o justo com quem assina).
>
> Igor

**E-MAIL 3 — D+12, todos**
Assunto: `fecho seu acesso sexta — 1 pergunta antes`

> Oi {nome}, última vez que apareço. Sexta expira o acesso que reabri.
>
> Se o BJJEasy não é pra você, tudo bem — mas me responde numa linha: o que faltou pra {academia}? Preço, tempo, alguma função, já usa outro sistema? Uma palavra basta e muda o que eu construo.
>
> E se quiser os dados que você cadastrou (alunos, planos), me pede que eu te mando em planilha, sem custo nenhum.
>
> Oss, Igor

**WHATSAPP — Alessandro Silva (D0)**

> Oi Alessandro, Igor aqui, o cara que fez o BJJEasy que você testou em maio. Fui rever as contas antigas e a sua me doeu: você importou 27 alunos e montou 31 cobranças — mais que todo mundo — e o app te perdeu no dia seguinte. Consertei o que travava e reabri teu acesso; tá tudo lá do jeito que você deixou. Me dá 20 min numa chamada essa semana? Eu termino contigo ao vivo e você sai com a chamada do dia feita e a cobrança do mês pronta pra ir no WhatsApp dos alunos. Se preferir, responde "depois" que eu não encho mais. Oss.

**WHATSAPP — Rilion Gracie (D0, dispara primeiro — só ~1 mês frio)**

> Oi {nome}, Igor, fundador do BJJEasy — você testou o app em junho. Sei que academia do tamanho da Rilion não tem tempo de configurar sistema sozinha, e essa parte era culpa minha. Reabri seu acesso e quero fazer o contrário agora: você me dá 20 minutos e EU deixo tudo rodando — turmas, alunos (pode me mandar a planilha que eu importo), e a cobrança automática no WhatsApp. Sai da call funcionando ou eu não te procuro de novo. Topa essa semana?

**WHATSAPP — Kimura Team Jorjão (D0)**

> Oi {nome}, Igor aqui, do BJJEasy. Preciso te pedir desculpa por uma coisa específica: vi que você criou sua academia TRÊS vezes em maio e cadastrou 17 alunos — e nunca conseguiu fazer uma chamada. O motivo era um bug de design meu: a tela de chamada exigia uma turma e não te dizia como criar uma. Você recriou tudo achando que tinha errado. Não tinha. Consertei isso e reabri seu acesso — seus alunos ainda estão lá. Se topar, em 5 minutos no telefone eu te mostro a primeira chamada saindo. Oss.

**WHATSAPP — Lagoa (D0-D1, segmento C)**

> Oi {nome}, Igor, do BJJEasy. Você foi de longe quem mais usou o app de verdade em maio — uma semana inteira de chamadas — e parou antes mesmo do teste acabar, então sei que não foi preço. Me responde numa linha: o que te fez parar? Pergunto porque mudei muita coisa desde então e reabri teu acesso por 14 dias pra você ver. Mas a resposta me vale mais que a volta.

### Expectativa honesta

Base útil ≈ 27 contas. Só 24% leem o próprio e-mail de win-back, mas 45% dos recebedores leem alguma mensagem seguinte, com lag médio de reengajamento de 57 dias e 75% voltando em até 89 (Return Path/Validity, ~300 campanhas reais — o único estudo com dados; via validity.com/blog/7-email-reactivation-campaign-insights e martech.org/email-win-back-programs-work). Projeção só-e-mail: 1-3 voltas; WhatsApp 1:1 nos VIPs pode dobrar (benchmarks de vendor apontam 40-60% de resposta vs 3-5% no e-mail — fonte interessada, direção consensual). **Meta realista: 2-4 academias reativadas, 0-1 assinatura em 60 dias.** Ignore claims de blog tipo "15-22% de trials expirados convertem" — sem metodologia. Os dois subprodutos valem mais que as reativações: 5 respostas ao e-mail 3 já pagam a campanha (pesquisa de churn com quem viveu o problema), e a pergunta "como você conheceu o app?" nas calls VIP identifica o canal da onda de maio. Orçamento total: 1 dia de fixes críticos já contado no P0 + 2h de script/planilha + 3h de WhatsApp/calls na semana 1.

---

## 5. A lição de GTM

**O seu número real não é 3/40 — é ~0-2/32.** T23JJ é a sua própria academia (doc id `academia-principal`, id manual de seed). LEAU e Drakkar chegaram DEPOIS, por outro caminho, fora da onda de maio — e LEAU tem 95% dos alunos vinculados ao app, taxa impossível por adesão orgânica self-serve (as outras vivas: 25% e 15%); esse padrão é assinatura de rollout assistido — alguém sentou e vinculou a academia inteira. Consequência: o consolo "8% é a mediana self-serve" (ChartMogul/Poyar, 200 produtos) não se aplica — **o funil FRIO converteu 0-6%, e as academias que retiveram não vieram dele.** A jogada não é "otimizar o funil frio": é descobrir e replicar o caminho que trouxe LEAU/Drakkar, e tratar a campanha de maio como canal morto até prova em contrário — com o agravante de que aquela coorte foi queimada duas vezes (campanha + corte retroativo do trial no meio da onda), e dono de academia de jiu no Brasil é nicho denso onde 32 experiências ruins conversam entre si.

**O piso da categoria é onboarding humano.** Glofox: 4-6 semanas com manager e 3-4 calls; ABC EVO/W12: "implantação individual", "5.000+ migrações"; Zen Planner e Gymdesk: importam os dados PELO cliente, de graça (glofox.com/blog/customer-onboarding-process, w12.com.br, gymdesk.com/software/martial-arts). O caso decisivo é o Alessandro: importou 27 alunos SOZINHO — o lead de maior intenção do funil — e morreu mesmo assim. Quando até quem faz o esforço de migração morre, o problema não é willingness, é entrega. Aritmética do do-things-that-don't-scale: ~5 onboardings brancos de 20-30 min por semana ≈ **2,5h/semana de WhatsApp** — trivial pra 1 fundador, e é exatamente o serviço que os concorrentes cobram caro pra entregar. A instrumentação entra pra MEDIR o toque humano, não substituí-lo.

**O canal com tração comprovada é o ALUNO — e o loop está amputado na direção errada.** Os 300+ downloads vieram de alunos, custo zero. A infra existe (identidade portátil, hub do lutador sem academia, share cards M1-M4), mas o ÚNICO CTA do lutador sem academia é "entre com o código da academia" (`lutador_hub_screen.dart:302-318`) — código que só existe se o professor JÁ é cliente. Zero fluxos aluno→professor no app inteiro. É o loop do ClassDojo (95% das escolas K-8 dos EUA via usuário final grátis) sem o último elo. A feature de GTM de maior alavancagem do backlog não é mais nada pro dono: é **"Sua academia não usa? Convide seu professor"** no hub solo, com link que pré-cria a academia semi-pronta — transformando cada aluno num vendedor. Nota autocrítica: a última wave de engenharia (M1-M4) foi toda pro lado do funil que serve 3 pagantes; esta wave tem que ser pro professor.

---

## 6. Régua de sucesso

**Produto (a partir dos 6 eventos de funil):**
- % de academias novas com **1ª chamada em D1** — a métrica-mestra; hoje desconhecida, a autópsia sugere <20%.
- **Sentinela "estado Kimura"**: academias com alunos>0 E (turmas==0 OU todas as turmas com `studentIds` vazio). Se os fixes P0 funcionarem, esse estado deve tender a ZERO em contas novas. Se continuar aparecendo, o fix falhou.
- Retorno do dono no D7 com 2+ dias de chamada (o padrão Lagoa — rotina, não dia de teste).
- Cobrança: % de contas que enviam 1 lembrete PAGÁVEL na primeira semana.

**Campanha (planilha de 27 linhas, atualizada a cada toque):**
- Logins de contas reativadas (o script paidUntil torna isso visível no Firestore por `updatedAt`/presenças novas).
- **Respostas ao e-mail 3** — meta: 5+ em 27. É o KPI número 1, acima de reativação.
- Reativações reais (chamada feita pós-volta, não só login): meta 2-4. Assinaturas: 0-1 em 60 dias.
- Canal da onda de maio identificado (pergunta nas calls VIP): sim/não.

**Critério de encerramento:** se D+21 chegar com 0 logins e 0 respostas, a campanha morreu — encerre sem remorso e canalize tudo pra aquisição nova com o funil consertado + o elo aluno→professor. Os mortos eram a segunda chance; a próxima coorte é o jogo de verdade.
