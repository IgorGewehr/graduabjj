# Roteiro de Teste Manual — Graduação Pedagógica (B1–B4)

> Branch: `feat/evolucao-modulos`. Testar em device/emulador real antes do merge.
> Marque `[x]` conforme passar; anote divergências.
>
> ⚠️ **Pré-deploy:** as `firestore.rules` (blocos `syllabus`/`skillProgress`) e o
> índice `syllabus (sport, order)` **já foram deployados** em `arpjj-76350`. Se algo
> der "permission denied" ou "needs index", confira o deploy.

## 0. Pré-requisitos
- [ ] Logado como **admin/instrutor**.
- [ ] **Graduação habilitada** (Configurações → Graduação → "Graduação automática" ON,
      senão a aba some). Defina um **threshold de presenças** baixo (ex.: 1–2) p/ testar
      elegibilidade rápido.
- [ ] **Aluno A (BJJ adulto)** com conta **vinculada** + presenças suficientes p/ ficar elegível.
- [ ] **Aluno K (BJJ kids)** — p/ testar currículo kids.
- [ ] (Opcional) **Aluno MT** (Muay Thai) — p/ testar variante de faixa.
- [ ] 2ª sessão/device p/ entrar no **portal como o Aluno A**.

---

## 1. B1 — Montador de currículo (admin)

Admin → **Graduação** → ícone **Currículo** (livro, no topo) → `/admin/graduacao/curriculo`.

- [ ] Seletor de **modalidade** mostra só esportes com graduação (BJJ, MT, Karatê, Judô,
      Kickboxing, Luta Livre) — **não** Boxe/Musculação.
- [ ] **BJJ vazio** → botão **"Usar template BJJ básico"**; toca → semeia faixas branca+azul.
- [ ] **Nova técnica**: nome (obrigatório), **faixa** (dropdown), categoria, descrição,
      vídeo URL, ordem. Salva e aparece **agrupada pela faixa** (cor + label).
- [ ] **Editar** uma técnica (toca no card) → valores pré-preenchidos → altera → salva.
- [ ] **Remover** (lixeira) → confirmação → some.
- [ ] **Toggle Adulto/Kids** aparece **só no BJJ**. Em Kids, o dropdown de faixa mostra
      as faixas infantis (cinza/amarela…); técnicas kids ficam separadas das adultas.
- [ ] Muay Thai: as faixas no dropdown batem com a **variante da academia** (CBMT/CBMTT,
      conforme Configurações).

---

## 2. B4 (admin) — Marcar domínio + feedback

Admin → detalhe do **Aluno A** → aba **"Currículo"** (8ª aba).

- [ ] A aba **só carrega ao abri-la** (lazy) — abrir o aluno e ficar nas outras abas não
      deve travar/carregar currículo.
- [ ] Mostra a **faixa atual** + **barra "X de Y técnicas dominadas"** + checklist da faixa.
- [ ] **Seletor de faixa** (dropdown) permite ver outras faixas da escada.
- [ ] Marcar nível por técnica: **Aprendendo / Praticando / Dominado** (Dominado = verde).
  - [ ] Tocar num nível marca; tocar no **nível atual** é no-op (não desmarca, não some nota).
  - [ ] O **% dominado** atualiza ao vivo conforme marca "Dominado".
- [ ] **Nota/feedback** (ícone de balão) → escreve → salva → aparece sob a técnica.
  - [ ] Trocar o nível **não apaga** a nota.
  - [ ] Abrir a nota e salvar **vazio sem nível prévio** → não cria entrada fantasma.
- [ ] **Vídeo** (ícone) abre a URL externamente (se cadastrada).
- [ ] Aluno que treina **>1 modalidade graduada** → aparece **seletor de modalidade**.

---

## 3. B4 (portal) — "Minha Graduação"

Primeiro, em **Configurações → Graduação**, ligue **"Aluno vê seu progresso"**.
Entre no **portal como Aluno A** → menu → **Treinos → Graduação**.

- [ ] Item **"Graduação"** aparece no menu **só com o toggle ligado** (com ele desligado,
      o item some / a tela mostra "Indisponível").
- [ ] Mostra **faixa atual + barra % dominado + checklist** com o **nível marcado pelo
      instrutor** (Não avaliada/Aprendendo/Praticando/Dominado) — **somente leitura**.
- [ ] Mostra o **feedback** do instrutor por técnica + botão de **vídeo**.
- [ ] Seletor de faixa e (se multi-esporte) de modalidade funcionam.
- [ ] **Pull-to-refresh** atualiza.

---

## 4. B2 — Requisitos compostos

Em **Configurações → Graduação**:
- [ ] Aparece **"Exigir técnicas do currículo"** (toggle). Desligado = **informativo**.
- [ ] Ligado → aparece o campo **"% mínimo de técnicas dominadas"** (ex.: 80).

### 4.1 Informativo (default)
- [ ] Com o toggle **desligado**, abra o detalhe do **Aluno A** (aba Info) → banner de
      elegibilidade mostra os chips **"Técnicas X/Y (Z%)"** e **tempo-em-faixa**, mas a
      elegibilidade por presença **não muda** (informativo).

### 4.2 Required (bloqueante)
- [ ] Ligue **"Exigir técnicas"**, % mínimo alto (ex.: 80). Garanta que o Aluno A está
      **elegível por presença** mas com **poucas técnicas dominadas** (<80%).
  - [ ] Detalhe do aluno: banner deixa de dizer "Elegível" e mostra **"Faltam técnicas:
        X/Y (mín. 80%)"**; chip de técnicas em **vermelho**.
  - [ ] Aba **Graduação → Elegíveis**: o aluno **não aparece** na lista (bloqueado).
- [ ] Marque técnicas dominadas até **≥ 80%** → o aluno **volta** a aparecer como elegível
      (lista + detalhe coerentes).
- [ ] Aluno **sem currículo cadastrado** na faixa → required **não bloqueia** (não dá pra
      exigir o que não foi definido).

---

## 5. B3 — Lembrete "apto a graduar" + exame

Admin → **Graduação → Elegíveis** (com aluno elegível).

- [ ] Card do elegível tem **"Avisar"** (quando o aluno tem conta vinculada) + **"Graduar"**.
- [ ] Topo da lista: **"Avisar todos (N)"** quando há >1 elegível notificável.
- [ ] Toca **"Avisar"** → no **portal do Aluno A**, sino de notificações mostra **"Pronto
      para Graduação!"**; tocar leva a **/portal/presencas** (não cai no vazio).
- [ ] Aluno **sem conta vinculada** → "Avisar" não aparece (só "Graduar").
- [ ] **Graduar** → folha de promoção com campo **"Observações / banca / exame"**;
      preencher → promove. A nota fica registrada no histórico de graduação.
- [ ] Após graduar, o aluno **sai** da lista de elegíveis e o **tempo-em-faixa zera**.

---

## 6. Edge cases
- [ ] Esporte sem graduação (Boxe/Musculação) → aba Currículo do aluno mostra
      "Modalidade sem graduação".
- [ ] Sem internet ao abrir a aba Currículo → estado de erro tratado (sem crash).
- [ ] Editar técnica e trocar a faixa → reagrupa corretamente.

---

## Resultado
- Ambiente: Android [ ]  iOS [ ]
- Bugs/observações:
  -
  -
