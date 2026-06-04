# Roteiro de Teste Manual — Treino + Exercícios (A6 + A5)

> Branch: `feat/evolucao-modulos`. Testar em device/emulador real.
> Marque `[x]` conforme passar; anote divergências.
>
> ⚠️ **Pré-deploy:** regras (`exercises`, `workoutExecutions`) **já deployadas**
> em `arpjj-76350`. A6 (registro/histórico) não precisa de índice novo (usa
> prefixo de documentId + o índice já criado na fase 0). Se der "permission
> denied", confira o deploy de regras.

## 0. Pré-requisitos
- [ ] Logado como **admin/instrutor**.
- [ ] **Aluno A** com conta **vinculada** + um **plano de treino estruturado**
      atribuído a ele (audiência: o aluno, a modalidade dele, ou a academia).
- [ ] 2ª sessão/device para entrar no **portal como o Aluno A**.

---

## 1. A5 — Catálogo de exercícios (admin)

Admin → **Treinos** → ícone **halteres** (topo) → `/admin/exercicios`.

- [ ] Catálogo vazio → botão **"Usar catálogo básico de musculação"** → semeia ~28
      exercícios agrupados por grupo muscular (Peito/Costas/Pernas/Ombros/Braços/Core).
- [ ] **Novo exercício**: nome (obrigatório), grupo muscular, equipamento (opcional),
      descrição, **vídeo URL**. Salva e aparece sob o grupo certo.
- [ ] **Editar** (toca no card) → valores pré-preenchidos → altera → salva.
- [ ] **Remover** (lixeira) → confirmação → some.
- [ ] Dentro de um grupo, os exercícios ficam em **ordem alfabética**.

---

## 2. A5 — Picker no montador + vídeo no portal

### 2.1 Montador (admin)
Admin → Treinos → abrir/criar um plano → aba de dias → adicionar exercício.
- [ ] No sheet do exercício, botão **"Escolher do catálogo"** → abre busca com a lista.
  - [ ] Buscar por nome filtra.
  - [ ] Escolher um exercício **preenche o nome** e mostra **"Vinculado ao catálogo"**.
  - [ ] **"Desvincular"** remove o vínculo (volta a texto livre).
- [ ] **Texto livre** ainda funciona (digitar o nome sem usar o catálogo).
- [ ] Salvar o plano. Reabrir → o exercício vinculado continua vinculado.

### 2.2 Portal (aluno)
Portal do Aluno A → Treinos → abrir o plano.
- [ ] Exercício **vinculado a um exercício com vídeo** mostra **"Ver demonstração"** →
      abre o vídeo (app externo/navegador).
- [ ] Exercício **sem vídeo** ou de texto livre → **sem** botão de vídeo.

---

## 3. A6 — Registro de execução (portal)

Portal do Aluno A → Treinos → abrir o plano → um exercício.

- [ ] Botão **"Registrar"** → folha de séries.
- [ ] Adicionar séries (**reps + carga**, RPE opcional). **"Adicionar série"** cria linhas;
      **x** remove (não deixa remover a última).
- [ ] Salvar → snackbar **"Treino registrado!"** + aparece o **resumo verde**
      ("3 série(s) · melhor 60 kg") no exercício, e o botão vira **"Editar registro"**.
- [ ] **Editar registro** → reabre com as séries preenchidas → alterar → salva (não duplica).
- [ ] Linha **sem reps** é ignorada; salvar **sem nenhuma série** → aviso.
- [ ] Carga em branco/0 (peso corporal) com reps preenchidos → salva.
- [ ] Reabrir o plano depois → o resumo de hoje continua lá (carregado do servidor).

---

## 4. A6 — Progresso + PR + gráfico

No detalhe do treino, exercício → botão **"Progresso"** → tela de progresso.

- [ ] **Recordes**: "Recorde de carga" e "Recorde 1RM est." (kg).
- [ ] **Gráfico**: chips **Carga / 1RM est. / Volume**; trocar a métrica muda o gráfico.
  - [ ] Com **< 2 sessões** → mensagem "Precisa de 2+ sessões para o gráfico".
  - [ ] Eixos e tooltip em **pt-BR** (vírgula); datas no eixo X.
- [ ] **Histórico**: lista de sessões (data + séries `10×60 @8` + melhor carga + notas).
- [ ] A(s) sessão(ões) que detém o recorde de carga têm **🏆** + destaque verde.
- [ ] Exercício **nunca registrado** → "Sem registros ainda".
- [ ] Sem internet → estado de **erro** com "Tentar novamente" (não "sem registros").

### 4.1 Celebração de PR
- [ ] Registrar o mesmo exercício em **outro dia** com **carga maior** que o recorde
      anterior → snackbar **"🎉 Novo recorde! X kg em <exercício>."**.
- [ ] **Primeiro** registro de um exercício → **sem** celebração (só "Treino registrado!").
- [ ] Registrar com carga **menor/igual** ao recorde → **sem** celebração.

---

## 5. Edge cases
- [ ] Plano **em arquivo (PDF/imagem)** → abre o arquivo; sem registro de série (esperado).
- [ ] Mesmo exercício (mesmo nome) em **dois planos** → o **progresso agrega** as sessões
      por nome (histórico junto).
- [ ] Catálogo vazio ao abrir o picker → mensagem orientando a cadastrar.

---

## Resultado
- Ambiente: Android [ ]  iOS [ ]
- Bugs/observações:
  -
  -
