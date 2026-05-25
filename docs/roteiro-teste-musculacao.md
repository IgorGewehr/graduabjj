# Roteiro de teste manual — Musculação (Fases 2–5)

> Marque cada item ao validar. Foco no que **não dá para testar estaticamente** (runtime, regras, Storage, iOS/Android).

## 0. Pré-requisitos (deploy)

- [ ] `firebase deploy --only functions:selfCheckin` (check-in QR/botão)
- [ ] `firebase deploy --only firestore:rules` (blocos `workoutPlans`, `content`, `workoutLogs` + helper `isAssignedStudent`)
- [ ] `firebase deploy --only storage` — **revisar `storage.rules` antes** (arquivo novo)
- [ ] `flutter pub get` + **build de device** (iOS pod install / Android gradle) por causa do `file_picker`

## 1. Setup

- [ ] Logar como admin/instrutor de uma academia de teste.
- [ ] Cadastrar **Aluno A** com a modalidade **Musculação** (form de aluno → aba Academia → adicionar Musculação). Confirmar que **não aparece faixa/graduação** para ele.
- [ ] Cadastrar **Aluno B** só com BJJ (para testar segmentação/privacidade).
- [ ] Vincular contas de app aos alunos A e B (código de link) — necessário para o lado do aluno e para notificações.
- [ ] Confirmar no portal do Aluno A: home **sem badge de faixa** e **sem card de graduação**.

---

## 2. Check-in flexível (configurável)

Settings › Funcionalidades › **Check-in da Musculação**.

### 2a. Modo Manual (não precisa de Cloud Function)
- [ ] Definir modo **Recepção (manual)** e salvar.
- [ ] Admin: menu › **Musculação** → ver lista de alunos de musculação.
- [ ] Marcar Aluno A como **Presente** → muda para "Presente ✓".
- [ ] Firestore: existe `academies/{id}/attendance/{alunoA}_musculacao_AAAAMMDD`; `attendanceCount` do aluno +1.
- [ ] Recarregar a tela → Aluno A continua "Presente" (dedup do dia).

### 2b. Modo QR fixo (requer deploy da função)
- [ ] Definir modo **QR fixo**; configurar **horário de funcionamento** incluindo o horário atual; salvar.
- [ ] Admin: menu › Musculação → exibe o **QR estático**.
- [ ] App do Aluno A: home mostra card "Treino de musculação" com **Escanear QR** → escanear → "Presença registrada".
- [ ] Escanear de novo → "Você já registrou presença hoje" (dedup).
- [ ] Mudar horário de funcionamento para **não** incluir agora → escanear → "Fora do horário de funcionamento".
- [ ] Tentar com Aluno B (sem musculação) → "Você não está matriculado na musculação".

### 2c. Modo Botão
- [ ] Definir modo **Botão no app**; salvar.
- [ ] App do Aluno A: home mostra card com **Cheguei** → tocar → "Presença registrada" → botão vira "Check-in feito".
- [ ] Tocar/abrir de novo no mesmo dia → continua bloqueado (dedup).

---

## 3. Treinos estruturados (todas as modalidades)

- [ ] Admin: menu › **Treinos** → **Novo treino** → título, modalidade, público **Toda a academia** → adicionar 1 dia + 2 exercícios (séries/reps/carga) → **Salvar**.
- [ ] App do Aluno A: menu › Treinos → ver o treino → abrir → dias/exercícios renderizados.
- [ ] **Segmentação por modalidade:** criar treino com modalidade **Musculação** e público **Por modalidade** → Aluno A vê; **Aluno B (só BJJ) NÃO vê**.
- [ ] **Privacidade (alunos específicos):** criar treino público **Alunos específicos** atribuído só ao Aluno A → **A vê, B não vê** (testar com as duas contas).
- [ ] Editar e excluir um treino (admin) → some da lista do aluno.

---

## 4. Vídeos (links + upload)

- [ ] Admin: menu › **Vídeos** → Novo → **Link** → colar URL do YouTube → público Academia → Salvar.
- [ ] App do Aluno A: menu › Vídeos → tocar → **abre o app/site do YouTube**.
- [ ] Admin: Novo → **Upload** → selecionar vídeo da galeria (≤ 15 min) → Salvar (aguardar upload).
- [ ] App: tocar no vídeo enviado → abre no navegador/player externo.
- [ ] Segmentação por modalidade e por alunos: mesmos testes da seção 3.
- [ ] Excluir um vídeo de upload (admin) → confirmar que some (e o arquivo sai do Storage).

---

## 5. Planilha em arquivo + polish

### 5a. Arquivo (PDF/imagem)
- [ ] Admin: Treinos › Novo → tipo **Arquivo (PDF/imagem)** → selecionar um **PDF** → Salvar.
- [ ] App do Aluno A: abrir o treino → **Abrir PDF** → abre o arquivo.
- [ ] Repetir com uma **imagem** (.jpg/.png).

### 5b. Marcar exercício como feito
- [ ] App do Aluno A: abrir um treino **estruturado** → marcar checkboxes → "Concluídos hoje: X/Y" atualiza; itens marcados ficam riscados.
- [ ] Sair da tela e voltar → checks **persistem** (mesmo dia).
- [ ] (Opcional) No dia seguinte → checks **resetam** (log é por dia).

### 5c. Notificação de novo conteúdo
- [ ] Admin: criar um treino **e** um vídeo com público **Alunos específicos**, atribuídos ao Aluno A (que tem conta vinculada).
- [ ] App do Aluno A: recebe notificação **"Novo treino disponível"** / **"Novo vídeo disponível"**; tocar leva a Treinos/Vídeos.
- [ ] Conteúdo público "Academia"/"Modalidade" **não** dispara notificação (esperado — broadcast ficaria para uma Cloud Function futura).

---

## 6. Checks de plataforma (iOS e Android)

- [ ] **Câmera** (QR): pede permissão na 1ª vez; scanner abre.
- [ ] **Galeria de vídeo** (image_picker): pede permissão de fotos; seleciona vídeo.
- [ ] **file_picker**: abre o seletor de documentos (iOS) / SAF (Android) e retorna PDF/imagem.
- [ ] **url_launcher**: abre YouTube, navegador e PDF corretamente.
- [ ] Rodar em **iOS e Android** (uploads grandes, permissões e abertura externa diferem por SO).

---

## 7. Regressão rápida (não quebrou o que já existia)

- [ ] Upload/remoção de **foto de perfil** ainda funciona (storage.rules novo).
- [ ] Upload de **foto de competição** ainda funciona.
- [ ] Check-in de **turmas (BJJ)** por QR/horário continua igual.
- [ ] Graduação/auto-promoção de modalidades com faixa continua igual (musculação nunca gradua).
