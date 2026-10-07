# Roteiro de teste — 06/out/2026

Branch `feat/onboarding-quiz-interactive` (commits `8cbff0b` … `f66e98e`)
**+ a mudança do ícone de notificação push** (ainda sem commit: manifest,
cor e vetor `ic_stat_mydojo`) → **Teste 7**.
Academia de teste: **Lobisomens Jiu Jitsu** · conta admin: a que você usa no app (a que é dona da academia).

Marque cada passo: ✅ passou · ❌ falhou (anote o que apareceu) · ⏭ pulou.
Print de qualquer ❌ ajuda muito.

---

## 0. Antes de começar

### 0.1 Instalar o APK
- Arquivo: `dist/graduabjj-5.0.0-120-teste-0610.apk` (na pasta do projeto).
  O `…teste-0210.apk` é o build anterior (sem o ícone de push): não use os dois.
- **Atenção à assinatura:** este build sai assinado com a chave de **debug**
  (não existe `key.properties` nesta máquina). Duas situações:
  - Se no celular já está um APK instalado **de uma máquina com a mesma chave
    de debug** (ex.: o `graduabjj-5.0.0-120.apk` de 15/set): instala por cima.
  - Se o app instalado veio da **Play Store** (outra assinatura): o Android
    recusa ("app não instalado / conflito de pacote"). Desinstale o app antes.
    Seus dados ficam no servidor, só precisa logar de novo.
- Mesmo número de versão (5.0.0+120) de um APK anterior também pode ser
  recusado por alguns aparelhos. Se acontecer, desinstale e instale de novo.

### 0.2 Login e escolha da academia
1. Abra o app e entre com a sua conta de admin.
2. Confirme que está na **Lobisomens Jiu Jitsu** (nome no topo / menu).

### 0.3 Dados de teste (recomendado: script)
Os testes usam alunos e planos marcados com **[QA]** (ids `qa_*`). Nada que já
existe é alterado.

No PC, na pasta do projeto, uma vez logado no Google Cloud
(`gcloud auth application-default login`):

```
node functions/scripts/qa_seed_lobisomens.js --email=SEU_EMAIL                 # só mostra o que faria
node functions/scripts/qa_seed_lobisomens.js --email=SEU_EMAIL --apply         # cria os dados
```

Para o **Teste 2** (seu admin vinculado a uma ficha), rode com a opção extra
**somente quando for fazer esse teste** — ela mexe no SEU acesso (com backup):

```
node functions/scripts/qa_seed_lobisomens.js --email=SEU_EMAIL --apply --admin-link
```

O que o script cria:

| Aluno | Situação |
|---|---|
| [QA] Ana | Plano Mensal · **valor personalizado** R$ 150 |
| [QA] Bruno | Plano Mensal · valor R$ 120 **e** vencimento dia 20 |
| [QA] Carla | Plano Mensal · **vencimento personalizado** dia 15 |
| [QA] Davi | Plano Mensal · sem personalização |
| [QA] Edu | Plano Mensal **e** Plano Extra → **conflito** |
| [QA] Fabio | sem plano |
| [QA] Gil | conta de aluno **vinculada** (conta fake, sem login real) |
| [QA] Hugo | só com `--admin-link`: vinculado ao **seu** admin |

Planos: **[QA] Plano Mensal** (R$ 200, vence dia 10) e **[QA] Plano Extra** (R$ 100).

> **Sem o script?** Dá para testar os itens 3 a 6 criando à mão (Alunos → novo
> aluno; Financeiro → Planos → novo plano; e na ficha do aluno,
> "PLANO E VALOR" → editar valor/dia). Os Testes 1 e 2 **precisam** do script
> (exigem uma conta vinculada).

---

## Teste 1 — Desvincular conta de **aluno**

Alunos → busque **[QA] Gil** → abra a ficha.

1. Toque no menu **⋮** (canto superior direito).
   - **Esperado:** aparece **"Desvincular Conta"**. **Não** aparece "Gerar
     Codigo de Acesso" (ficha já tem conta).
2. Toque em **Desvincular Conta**.
   - **Esperado:** diálogo **"Desvincular conta"**: *"Isso desfaz o vínculo
     entre [QA] Gil… e a conta (qa_fake@example.invalid)…"*, com 3 bullets; o
     **terceiro** avisa que *"Se for conta de aluno, ela perde o acesso a esta
     academia até ser vinculada novamente."* (esse bullet só existe no APK
     novo), e fecha com *"Presenças, financeiro e histórico do aluno NÃO são
     afetados."*
   - **Não** deve aparecer o aviso *"Esta é a SUA conta"* (não é a sua).
3. Toque **Desvincular**.
   - **Esperado:** aviso verde **"Conta desvinculada."** e a ficha recarrega.
4. Abra o menu **⋮** de novo.
   - **Esperado:** agora aparece **"Gerar Codigo de Acesso"** e **sumiu**
     "Desvincular Conta".
5. A ficha continua com nome, presenças e financeiro intactos.

**Se falhar:** anote a mensagem de erro (toast vermelho "Erro ao desvincular: …").

## Teste 2 — Desvincular a **sua própria** conta de admin (a correção)

*Pré-requisito: rodou o seed com `--admin-link`.* Este teste valida que o admin
**não perde acesso** ao desvincular.

Alunos → **[QA] Hugo** → ⋮ → **Desvincular Conta**.

1. **Esperado no diálogo (APK novo):** além dos bullets, o parágrafo
   **"Esta é a SUA conta. Seu acesso de equipe/admin é mantido, mas a ficha
   deixa de estar ligada ao seu login."**
2. Toque **Desvincular** → **"Conta desvinculada."**
3. **O ponto central:** continue usando o app. Você ainda deve conseguir:
   - abrir **Financeiro**, **Alunos**, **Configurações** (itens de admin);
   - o menu lateral/“Mais” continua mostrando os itens de admin.
4. Feche o app por completo, abra de novo e confirme que **entra como admin**
   normalmente.
5. [QA] Hugo → ⋮ → agora mostra "Gerar Codigo de Acesso" (ficha órfã).

**Se você perdeu o acesso de admin:** NÃO se desespere — rode
`node functions/scripts/qa_seed_lobisomens.js --email=SEU_EMAIL --cleanup`, que restaura seu
acesso a partir do backup (`functions/scripts/.qa_backup.json`). Depois me
avise: significa que a correção não funcionou.

---

## Teste 3 — Financeiro → Planos → "Gerenciar Alunos" (filtro)

Financeiro → aba **Planos** → card **[QA] Plano Mensal** → **Gerenciar Alunos**.

Anote **N** = o número depois de "Todos ·" (total de alunos ativos da academia).

1. **Esperado:** três abas **`Todos · N`**, **`No plano · 5`**, **`Fora · N-5`**
   (os 5 do plano: Ana, Bruno, Carla, Davi, Edu).
2. Em **Todos**: quem está **fora** do plano aparece primeiro; os 5 [QA] do
   plano ficam no fim (comportamento antigo preservado).
3. Toque **No plano**: só os 5 [QA]. Ordem alfabética.
4. Toque **Fora**: todos os demais. [QA] Fabio e [QA] Gil estão aqui.
5. Busque **[QA]** com a aba "No plano" ativa: só os de plano que casam.
6. **Linha não pula:** na aba **Fora**, toque em **[QA] Fabio** para
   adicioná-lo ao plano.
   - **Esperado:** o card dele fica verde ("Vinculado") **mas ele continua no
     mesmo lugar da lista**; os números das abas mudam na hora
     (`No plano · 6`, `Fora · N-6`).
7. Toque em **Fabio** de novo para **desfazer** (volta a "Adicionar").
8. Troque de aba (ex.: **No plano** → **Fora**): agora o agrupamento reflete
   o estado atual.
9. Estado vazio: abra **Gerenciar Alunos** do **[QA] Plano Extra** (só tem o
   Edu), toque no **Edu** para removê-lo e depois troque para **Todos** e volte
   para **No plano** (a lista só reagrupa ao trocar de aba). **Esperado:**
   *"Nenhum aluno neste plano ainda"*. **Recoloque o Edu** tocando nele de novo.
10. **Concluir** fecha a folha.

> Ao final, o plano deve estar como começou (5 alunos). Se mexeu no Plano Extra,
> o Edu tem que estar nele.

---

## Teste 4 — Selos de personalizados (lista editável)

Financeiro → **Planos** → card **[QA] Plano Mensal**.

### 4.1 O card
- Chip **"5 alunos ativos"**.
- Caixa verde **RECEITA ESPERADA POR MÊS**: **2 × R$ 200,00 + 2 personalizados
  (R$ 270,00) = R$ 670,00**. (Edu fica de fora: está em conflito.)
- Abaixo, três selos:
  - **"2 valores personalizados ›"** (com seta)
  - **"2 vencimentos personalizados ›"** (com seta) ← selo novo
  - **"1 conflito fora do cálculo"** (sem seta, não é clicável)
- No topo da aba: aviso *"1 aluno em mais de um plano…"*.
- Card **[QA] Plano Extra**: *"Nenhum aluno ativo considerado no cálculo"* e o
  selo de conflito.

### 4.2 A lista de valores
1. Toque **"2 valores personalizados"**.
   - **Esperado:** folha **"Personalizados"** / "[QA] Plano Mensal", aba
     **`Valor · 2`** ativa, `Vencimento · 2` ao lado.
   - Linhas (ordem alfabética): **[QA] Ana — R$ 150,00 · padrão R$ 200,00** e
     **[QA] Bruno — R$ 120,00 · padrão R$ 200,00**. Cada uma com um lápis.
   - **Não** aparece Edu nem Carla.
2. Toque na aba **Vencimento · 2**:
   - **[QA] Bruno — Dia 20 · padrão dia 10** e
     **[QA] Carla — Dia 15 · padrão dia 10**.

### 4.3 Editar na própria lista
1. Aba **Valor**, toque em **[QA] Ana**. Diálogo com o nome dela, *"Valor padrão
   do plano: R$ 200,00"*, campo **Valor do aluno** (150.00) e **Dia de
   vencimento** (10).
2. **Validação** — apague o valor e digite `0` → **Salvar**.
   - **Esperado:** erro vermelho *"Informe um valor maior que zero"* e o diálogo
     **não** fecha.
3. Valor `150`, dia `40` → **Salvar** → erro *"Informe um dia de 1 a 31"*.
4. Dia `10` e valor `180` → **Salvar**.
   - **Esperado:** fecha; a linha da Ana agora diz **R$ 180,00**.
5. Toque de novo em Ana, mude o valor para **200** (igual ao padrão) → **Salvar**.
   - **Esperado:** a Ana **sai da lista** de valores (voltou ao padrão) e a aba
     passa a **`Valor · 1`**.
6. Em **Bruno** (aba Valor) toque **Restaurar valor do plano**.
   - **Esperado:** Bruno sai da lista de valores; **continua** na de vencimento
     (só o valor foi restaurado). Aba vira `Valor · 0` e aparece
     *"Nenhum aluno com valor personalizado"*.
7. Aba Vencimento → **Bruno** → **Restaurar vencimento do plano**.
8. Abrir um diálogo e tocar **Salvar** **sem mudar nada**: fecha sem gravar.
9. Feche a folha. **Esperado:** o card **atualiza** (selos e a receita esperada
   mudam: sem os 2 valores, vira **4 × R$ 200,00 = R$ 800,00**).

### 4.4 Reconferir na ficha do aluno
- Alunos → **[QA] Carla** → seção **PLANO E VALOR**: plano mostra vencimento
  **dia 15** (ainda personalizado).
- **Restaure o estado original** (para testes seguintes): reponha Ana R$ 150,
  Bruno R$ 120 + dia 20 (editando pela lista ou pela ficha) — ou rode o seed de
  novo depois de `--cleanup`.

> **Permissão:** só admin edita. Se tiver uma segunda conta **não-admin** com
> acesso ao Financeiro, a lista deve abrir **sem lápis** e com a frase
> *"Somente administradores podem editar."*

---

## Teste 5 — Cobrança (preferências, linguagem simples)

Financeiro → atalho **"Ir para Cobranças"** (ou menu **Cobrança**).

### 5.1 Card "Automação de cobrança"
1. Dois interruptores: **"Gerar mensalidades automaticamente"** (o texto agora
   termina com *"Planos mensais no cartão continuam pela assinatura
   automática."*) e **"Avisar quando a parcela for criada"**.
2. Linha nova **"Como você recebe"** com o resumo e botão **Alterar**:
   - Mercado Pago conectado e preferido → *"Mercado Pago"*.
   - MP desconectado e PIX cadastrado → *"PIX pessoal (Mercado Pago não está
     disponível)"*.
   - Nada configurado → *"Nenhuma configurada ainda"*.
   - Toggle "Incluir forma de pagamento" desligado → *"Desligado — as mensagens
     vão sem forma de pagamento"*.
   **Anote o que aparece na sua academia e se bate com a realidade.**
3. Toque **Alterar**: abre **Configurações** na aba **Financeiro**, com o card
   **Mercado Pago** rolando até a tela e **destacado por ~2,5 s**.
   (O botão Voltar leva ao Dashboard/Financeiro, não necessariamente à
   Cobrança — comportamento esperado.)
4. Se o Mercado Pago estiver **desconectado**: a caixa amarela mostra
   *"Mercado Pago desconectado. As cobranças automáticas usarão o PIX pessoal
   configurado."* **com o botão "Conectar Mercado Pago"**, que leva ao mesmo
   lugar.
5. Interruptor do card: ligue/desligue **"Gerar mensalidades"** → aviso na hora
   (*"Geração automática ativada!"* / *"desativada."*). **Volte ao estado
   original.**

### 5.2 Diálogo "Configurações" (engrenagem no topo)
1. Seções: **Canais de Cobrança**, **Avisos antes e no dia do vencimento**,
   **Mensagens**.
2. **Não** devem existir aqui: "Gerar mensalidades automaticamente", "Avisar
   quando a parcela for criada" (agora só no card) nem a caixa de prontidão do
   Mercado Pago.
3. O texto do toggle **"Incluir forma de pagamento nas mensagens"** deve dizer:
   *"…definida em Configurações › Financeiro (veja "Como você recebe" no card
   de Automação)."* — **não** "definida em Financeiro" nem "fallback".
4. Mude um chip de aviso (ex.: "2 dias antes") e **Salvar** → *"Configurações
   salvas!"*. Reabra: continua marcado. **Desfaça** depois.

### 5.3 Mensagens (o editor)
Em **Mensagens**, toque **Ver e editar**.

1. **Chips** (sem siglas): `Parcela criada`, `A vencer`, `Vence hoje`,
   `Atraso 1–2 dias`, `Atraso 3–6 dias`, `Atraso 7–14 dias`,
   `Atraso 15–29 dias`, `Atraso 30+ dias`.
2. Percorra **todos os chips**. Em cada um (exceto Parcela criada) a caixa
   verde **"WhatsApp — como o aluno recebe"** mostra a mensagem **já
   preenchida**: nome **Maria**, **R$ 150,00**, datas e o **nome da sua
   academia**.
   - **Nunca** pode aparecer: `{nome}`, `{valor}`, `[[PIX]]`, `{{1}}`, `D+7`,
     `CREATED`, `UPCOMING`, "Meta".
   - Embaixo: *"Exemplo com um aluno fictício."*
3. Chip **A vencer**: tem mensagem (diz algo como *"vence em 3 dias"*).
   (Antes o app dizia, errado, que não existia.)
4. Chip **Parcela criada**: caixa cinza *"WhatsApp — sem mensagem pronta nesta
   etapa"* + *"Nesta etapa o aluno é avisado no app e por e-mail…"*.
5. **E-mail:** com **Cobrança via Email DESLIGADO** (lá em cima), a seção mostra
   só *"Para editar os textos de e-mail, ligue "Cobrança via Email" lá em
   cima."*
6. **Ligue** Cobrança via Email: aparecem **Assunto do e-mail** e **Corpo do
   e-mail** com a ajuda *"Você pode usar: {nome} (aluno), {valor},
   {vencimento} e {academia}…"* (em "Atraso" também cita `{dias}`; em "A vencer"
   cita `{diasAteVencimento}`).
7. **Seus textos são preservados:** anote o assunto atual de **Vence hoje**;
   troque por `TESTE QA`; **Salvar**; reabra → **Ver e editar** → Vence hoje:
   deve estar `TESTE QA`.
8. **Restaurar texto padrão desta etapa** → o assunto volta ao padrão
   (*"Lembrete: Sua mensalidade vence hoje - …"*). **Salvar.**
   **Se você já tinha um texto seu antes, recoloque-o.**
9. Desligue o canal de e-mail, **Salvar**, religue e confira que os textos
   continuam (o editor some quando desligado, mas **os textos não se perdem**).

### 5.4 Envio (prévia; só envia se VOCÊ mandar)
Para aparecer o botão do WhatsApp o aluno precisa de **telefone**:
edite **[QA] Ana** e ponha **o seu número** (assim qualquer envio real chega só
em você).

1. Na tela **Cobrança**, ícone **+ (Nova Cobrança)** → aluno **[QA] Ana**,
   **Tipo de Cobrança: Cobrança Única** (não "Plano do Aluno": nesse tipo a
   data fica presa ao dia do plano e não dá para escolher "ontem"), descrição
   `QA teste`, **Valor** `10`, **Data de Vencimento** = ontem → criar.
   (Se a Ana não aparecer na lista de alunos, confirme que ela tem telefone.)
2. Na lista, toque **Cobrar aluno** na linha da Ana.
   - **Esperado:** diálogo de prévia com *"Prévia da mensagem de WhatsApp
     (modelo pronto e aprovado). Este texto não pode ser editado."* e uma linha
     **"Pagamento pelo Mercado Pago"** / **"…pelo PIX pessoal"** / **"Sem forma
     de pagamento na mensagem"** — **nunca** um nome tipo
     `cobranca_d1_pix_manual` nem a palavra "Template".
   - Avisos amarelos (se houver) terminam com *"Será usado o PIX pessoal, se
     estiver cadastrado."* — **nunca** "fallback" nem "backend".
3. **Só se quiser o envio real** (chega no SEU número): **Enviar**.
   - Mensagem de sucesso: *"WhatsApp enviado para …!"*. Se o Mercado Pago
     falhar, deve dizer o que aconteceu, ex.: *"Mercado Pago estava
     indisponível; a cobrança foi com o PIX pessoal."* ou, sem PIX cadastrado,
     *"…a cobrança foi sem forma de pagamento — cadastre seu PIX pessoal."*
4. **Apague a cobrança de teste** pelo app: **lixeira vermelha** da linha
   ("Excluir Cobrança") e tire o seu telefone da ficha da Ana, se quiser.

---

## Teste 6 — Passada rápida de regressão (2 min)

Abra, sem erro/tela branca: **Dashboard**, **Alunos** (lista + busca),
**Chamada**, **Financeiro → Pagamentos**, **Cobrança**, **Configurações**.
Em **Financeiro → Pagamentos** o botão **Gerar** abre o diálogo "Gerar
Mensalidades" normalmente (não gere de verdade, a menos que queira).

---

## Teste 7 — Ícone das notificações push (mudança nova)

**O que mudou:** antes, o push com o app em segundo plano/fechado mostrava o
ícone do app como um **círculo/anel genérico** na barra de status. Agora deve
mostrar a **marca MyDojo** (quatro blocos) como silhueta branca, e o nome/ícone
no cabeçalho da notificação em **vermelho** (`#B91C1C`).

> Só vale para push com o app **em segundo plano ou fechado**. Com o app
> aberto na tela o push não aparece na bandeja (comportamento já existente).

### 7.0 Preparação
1. Instale o APK **por cima ou do zero** e entre com a sua conta de admin.
2. Se o Android 13+ perguntar **"Permitir notificações?"**, toque **Permitir**.
   (Se já negou antes: Configurações do Android → Apps → MyDojo → Notificações.)
3. Deixe o app aberto uns segundos para o aparelho registrar o token, depois
   **feche o app** (tire dos recentes) ou mande para segundo plano.

### 7.1 Disparar um push de teste (sem afetar mais ninguém)
Use **"Send test message"**, que entrega para **um único aparelho** (o seu).
**Não use "Nova campanha"** — ela pode atingir todos os usuários do app.

1. **Firebase Console** → projeto **arpjj-76350** → **Authentication** → ache
   o seu e-mail de admin e copie o **UID**.
2. **Firestore Database** → coleção `users` → documento desse UID →
   subcoleção **`fcmTokens`**. O **ID do documento é o token**; copie o mais
   recente (se houver vários, o do aparelho em teste é o último a aparecer
   depois de abrir o app).
3. **Messaging** (Engage → Cloud Messaging) → **New campaign → Firebase
   Notification messages**. No editor, preencha título `Teste QA` e texto
   `Ícone novo`, clique em **"Send test message"**, cole o token, confirme com
   **+** e toque **Test**.
   - O botão de teste só existe dentro do editor de campanha. **Nunca clique em
     "Review/Publish"**: feche o editor sem publicar.

### 7.2 O que conferir (com o app fechado)
1. **Barra de status (topo):** ícone pequeno = **silhueta branca com 4 blocos**
   (dois em cima, dois embaixo, formando a marca). **Não** pode ser círculo
   cheio/anel/ícone colorido do app.
2. **Abra a bandeja** (arraste para baixo): cabeçalho da notificação com o
   mesmo ícone, **ícone e "MyDojo" na cor vermelha**; título **Teste QA** e
   texto **Ícone novo**.
3. **Tema escuro e claro do Android:** o ícone continua legível nos dois.
4. **Toque na notificação:** o app abre (sem travar) — se o push tivesse
   `data` de rota, levaria à tela certa; no teste simples só abre o app.
5. Anote **marca do celular e versão do Android** (alguns fabricantes
   recolorem o ícone — Samsung/Xiaomi — e isso não é erro do app).

**Se ainda aparecer círculo genérico:** tire um print da barra de status e da
bandeja e me envie junto com a marca/versão do aparelho. Confirme também que
instalou o APK `…teste-0610.apk` (e não o `…teste-0210.apk`).

---

## Limpeza

1. No PC: `node functions/scripts/qa_seed_lobisomens.js --email=SEU_EMAIL --cleanup`
   (remove alunos `qa_s1..s8`, planos `qa_plan_a/b`, a conta fake e **restaura
   seu acesso** se você usou `--admin-link`).
2. No app: apague as cobranças que **você** criou durante o teste.
3. Reponha o que mudou nas configurações de Cobrança (interruptores, avisos,
   textos de e-mail).
4. Tire o seu telefone da ficha da Ana (se ela ainda existir).

---

## Registro de resultado

| Teste | Resultado | Observações |
|---|---|---|
| 1 Desvincular aluno | | |
| 2 Desvincular admin | | |
| 3 Gerenciar Alunos | | |
| 4 Personalizados | | |
| 5.1 Card Automação | | |
| 5.2 Diálogo | | |
| 5.3 Mensagens | | |
| 5.4 Envio (prévia/real) | | |
| 6 Regressão | | |
| 7 Ícone do push (barra + bandeja) | | |
