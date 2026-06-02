# Roteiro de Teste Manual — Avaliação Física (A3)

> Branch: `feat/evolucao-modulos`. Testar em device/emulador real (Android e, se
> possível, iOS) antes do merge para `firebase-production`.
> Marque `[x]` conforme for passando. Anote qualquer divergência.

## 0. Pré-requisitos (montar o cenário)

- [ ] Logado como **admin/instrutor** de uma academia de teste.
- [ ] **Aluno A (adulto)** com conta **vinculada** (linkedUserId) — para testar fotos,
      notificação e o portal logando como ele.
- [ ] **Aluno K (kids)** — para testar o bloqueio de fotos de menores.
- [ ] Um 2º device/sessão (ou logout/login) para entrar no **portal como o Aluno A**.

> Dica: dá pra usar `! <comando>` no prompt pra rodar coisas locais se precisar.

---

## 1. Fase 1 — Avaliação básica (admin)

Aluno A → aba **"Av. Física"** no detalhe do aluno.

- [ ] Aba aparece com o ícone de balança e contador (0 no início).
- [ ] Estado vazio mostra "Nenhuma avaliação física ainda".
- [ ] **Nova avaliação** → preencher **Peso** e **Altura**.
  - [ ] **IMC** atualiza **ao vivo** ao digitar peso/altura, com classificação coerente.
- [ ] Validações: digitar `abc` ou `80,5,5` → erro "Número inválido"; `0` → "maior que zero";
      peso `5` → "Mín. 20"; altura `300` → "Máx. 250".
- [ ] Salvar com **tudo vazio** → bloqueia ("Preencha ao menos uma medida ou foto").
- [ ] Preencher só perimetria (seção recolhível) → salva.
- [ ] Salvar → volta pra lista, card aparece com data + Peso/IMC/%G.
- [ ] Criar uma **2ª avaliação** com peso diferente → card mostra **delta** (ex.: `-1,5 kg`).
- [ ] **Editar** uma avaliação (tocar no card) → valores pré-preenchidos (com **vírgula**),
      alterar e salvar → reflete.
- [ ] Editar e **limpar** um campo → some do registro (não persiste lixo).

---

## 2. Fase 2 — Fotos de evolução (somente adultos)

- [ ] No **Aluno A (adulto)**: seção **"Fotos de evolução"** aparece (3 slots: Frente/Lado/Costas).
- [ ] No **Aluno K (kids)**: a seção **NÃO** aparece.
- [ ] Tocar num slot → escolher **Câmera** e **Galeria** (testar os dois).
- [ ] Foto aparece no slot; **X** remove.
- [ ] Salvar com foto → reabrir a avaliação → foto carrega (vinda do storage).
- [ ] Substituir uma foto e salvar → nova foto fica; a antiga não deixa lixo visível.
- [ ] **Privacidade:** copie a URL de download de uma foto e abra numa aba **anônima/deslogada**
      → deve **falhar/negar** (foto privada). *(Se abrir, é regressão de `storage.rules`.)*

---

## 3. Fase 4 — Sexo, Pollock e bioimpedância

### 3.1 Sexo no cadastro
- [ ] Editar o **Aluno A** → seção Dados Pessoais → campo **"Sexo (opcional)"** com
      Masculino/Feminino/Não informado. Definir e salvar.
- [ ] Reabrir o cadastro → sexo persistiu.

### 3.2 Estimativa de % gordura (Pollock)
- [ ] Garantir que o Aluno A tem **sexo** e **data de nascimento** definidos.
- [ ] Nova avaliação → seção **"Dobras cutâneas"** → preencher as 3 dobras do protocolo:
  - Homem: **Peitoral + Abdominal + Coxa**; Mulher: **Tríceps + Supra-ilíaca + Coxa**.
  - [ ] Aparece **"% gordura estimada (Pollock 3 dobras): X%"**.
  - [ ] Botão **"Usar"** preenche o campo **% Gordura**.
- [ ] Sem sexo definido → a caixa mostra a dica "Defina o sexo do aluno…".
- [ ] Sem data de nascimento → dica pedindo a data.
- [ ] Faltando uma das 3 dobras → dica listando as dobras do protocolo.

### 3.3 Bioimpedância manual
- [ ] Seção **"Bioimpedância"** → preencher Massa magra, Massa gorda, Gordura visceral, TMB.
- [ ] Salvar e reabrir → valores persistem nos campos.
- [ ] Avaliação **só com bioimpedância** (sem peso/medidas) → salva.

---

## 4. Fase 4.1 — Meta numérica

### 4.1 Pelo cadastro do aluno
- [ ] Editar Aluno A → seção **"Meta / Objetivo"** → definir **Peso-alvo** e **% Gordura-alvo**.
- [ ] Salvar e reabrir → persistiu.

### 4.2 Pelo atalho no form de avaliação
- [ ] Nova avaliação → seção "Objetivo e observações" → linha **"Meta"** mostra a meta atual.
- [ ] **Editar** → diálogo com peso-alvo/%gordura-alvo pré-preenchidos → alterar → Salvar
      → "Meta atualizada!".
- [ ] Sair do form **sem salvar avaliação** → reabrir o form → a meta editada aparece
      atualizada (recarregou).
- [ ] Deixar os dois campos **em branco** no diálogo → remove a meta.

---

## 5. Fase 3 — Portal "Minha Evolução" (logar como Aluno A)

Portal → menu → **Treinos → Evolução**.

- [ ] Item **"Evolução"** aparece no menu.
- [ ] **Snapshot** da última avaliação: Peso, IMC (+ classificação), % Gordura, com **variação**
      vs. a anterior (seta).
- [ ] **Chip da meta** aparece (ex.: "Meta: …").
- [ ] **Card Meta** com **barra de progresso** (ex.: `82 → 78 kg`, "Faltam X / Y%").
  - [ ] Se a meta for ultrapassada (ex.: emagreceu além do alvo) → **"Meta atingida! 🎉"**.
- [ ] **Gráfico**: chips de métrica (Peso, IMC, % Gordura, Massa magra/gorda, G. visceral,
      TMB, Cintura, Quadril) — só aparecem as que têm **≥2 pontos**. Trocar de métrica funciona.
  - [ ] Tocar no gráfico mostra **tooltip** com valor + data.
  - [ ] Eixos e valores em **pt-BR** (vírgula).
- [ ] **Comparação de fotos** (se houver ≥1 foto): Antes/Depois por ângulo; chips de ângulo.
- [ ] **Histórico** lista as avaliações (data + pills).
- [ ] **Pull-to-refresh** atualiza (inclusive a meta recém-definida pelo admin).
- [ ] Aluno **sem nenhuma avaliação** → estado "Nenhuma avaliação ainda".

---

## 6. Fase 5 — Notificação, lembrete, PDF

### 6.1 Notificação
- [ ] Como **admin**, criar uma **nova** avaliação para o Aluno A.
- [ ] No portal do Aluno A → **sino de notificações** → aparece **"Nova avaliação física"**;
      tocar leva para **/portal/evolucao**.
- [ ] **Editar** uma avaliação (não criar) → **não** gera notificação nova.
- [ ] Aluno **sem conta vinculada** → criar avaliação não quebra o save (sem notificação).

### 6.2 Lembrete de reavaliação
- [ ] (Se tiver como simular data) Avaliação mais recente com **≥ 90 dias** → banner
      "Última avaliação há X dias. Considere registrar uma reavaliação." na aba do admin.

### 6.3 Export PDF
- [ ] No card de uma avaliação (admin) → ícone **Exportar PDF**.
- [ ] Abre a folha nativa (imprimir / salvar PDF / compartilhar).
- [ ] PDF contém: nome do aluno, data/sexo/idade, medidas, composição, perimetria, dobras,
      objetivo/notas. **Sem fotos** (proposital).
- [ ] Rodapé "Gerado pelo BJJEasy em …" com **data/hora atuais** (não a data da avaliação).
- [ ] Números em **pt-BR** (vírgula).

---

## 7. Edge cases / negativos

- [ ] Avaliação com **só 1 registro** → portal: gráfico oculto (precisa de 2 pontos), mas
      snapshot e histórico aparecem.
- [ ] Sem internet ao abrir o portal de evolução → estado de **erro** com **"Tentar novamente"**.
- [ ] Girar device / voltar e abrir o form de novo → sem crash, estado coerente.
- [ ] Kids: confirmar que medidas funcionam, mas fotos continuam ocultas.

---

## Resultado

- Ambiente testado: Android [ ]  iOS [ ]
- Bugs/observações:
  -
  -
