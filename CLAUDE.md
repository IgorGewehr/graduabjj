# CLAUDE.md — GraduaBJJ

Guia de convenções para qualquer dev/agente trabalhando neste repo. Extraído
do código real (não de intenção) — se algo aqui parecer desatualizado em
relação ao código, o código é a fonte da verdade; atualize este arquivo.

Guias técnicos aprofundados: [Build Windows](docs/guias/BUILD_WINDOWS.md) ·
[Catracas por fabricante](docs/guias/CATRACAS.md) ·
[Catraca Gateway](docs/guias/CATRACA_GATEWAY.md).

## Arquitetura

**Branches** (não são só ambientes — são linhas de produto divergentes):

- `firebase-production` — prod legado, Firestore direto, estável.
- `b2c` — branch **principal** de trabalho hoje. App do LUTADOR (identidade
  portátil, multi-academia, jornada multi-esporte, social/retenção,
  gestão do balcão desktop + catracas). Deploys reais saem daqui.
- `migration` — experimental, backend Tatami (Go) via HTTP em vez de
  Firestore direto. Não cortado para produção.
- `main` — espelho/integração; branches `feat/*` são trabalho em andamento
  antes de merge.

**Backend:** Firebase (projeto `arpjj-76350`), Cloud Functions em
`functions/`, **v1 e v2 misturadas de propósito** —
`functions/server_functions.js` fica pinado em `firebase-functions/v1`
porque foi migrado literal de um repo ERP descontinuado (mesmo codebase de
deploy que apagava as funções do outro repo por engano) e o objetivo era
preservar comportamento **exato**; tudo novo (`index.js`,
`access_control/*`, `self_graduation_guard.js`, etc.) usa v2
(`onRequest`/`onCall`/`onDocumentWritten`/`onSchedule`). As duas coexistem no
mesmo app Admin default (inicializado uma vez em `index.js`) sem colisão de
nomes — não duplique uma função nova em v1 "para combinar" com o vizinho.

**Multi-tenant:** tudo mora sob `academies/{academyId}/*` (students,
classes, financials, attendance, devices, accessEvents...). Toda leitura/
escrita do lado servidor recebe `academyId` explícito — nunca assuma uma
academia default. Documentos globais (`userAcademyMapping/{uid}`) cruzam
tenants para resolver quem é quem entre academias.

**Frontend:** Flutter (`lib/`), mobile-first histórico, desktop aditivo
(Windows via `lib/services/fns.dart` + `lib/core/platform_support.dart` —
ver [BUILD_WINDOWS.md](docs/guias/BUILD_WINDOWS.md)). Navegação
catalog-driven (`kAdminNavCatalog`/`kPortalNavCatalog`) — trocar o shell
adapta o app inteiro sem reescrever tela por tela.

## Convenções de código

- **Comentários em PT-BR, densos, explicando o PORQUÊ** — não o quê. O
  código já diz o quê; o comentário existe para a decisão de arquitetura, o
  bug histórico que motivou o padrão, ou a ASSUMPTION/TODO que precisa de
  field-confirm. Identificadores (variáveis, funções, classes) ficam em
  **inglês**. Este padrão é onipresente em `functions/` e cada vez mais
  comum em `lib/` — siga-o em código novo.
- **Fail-open em caminhos de aluno.** "Nunca prender um aluno no portão (ou
  travar seu acesso) por causa de uma falha de infraestrutura." Exemplos
  reais: rate-limit da catraca (`ingest.js`) fail-open em erro; gate
  financeiro (`financial_gate.js`) fail-open total (qualquer erro/timeout
  libera); check-in diário self-service **de propósito não checa
  inadimplência** (bloqueio físico é papel da catraca, negar o *registro* de
  quem já está fisicamente na academia só produz dado errado); o gateway de
  catraca (`catraca-gateway`) libera por padrão (`offlinePolicy: "allow"`)
  quando não consegue confirmar com o servidor. **Fail-open é uma decisão de
  produto, não um acidente** — quando um caminho precisa ser fail-closed
  (ex.: HMAC sem secret ⇒ 401), isso é explícito e comentado como exceção.
- **Idempotência por doc-id determinístico.** Padrão repetido em todo o
  backend: presença = `attendance/{studentId}_{classId}_{YYYYMMDD}` (wall-
  clock BR); eventos de catraca = `accessEvents/{deviceId}_{eventId}`
  (`.create()` em transação — reentrega é no-op atômico); aula particular =
  mesmo padrão em `grantPrivateLessonAttendance`. Nunca usar
  `add()`/id-aleatório num caminho que pode ser reexecutado (retry, reentrega
  de webhook, reentrega de device).
- **Tudo é ADITIVO.** Nunca quebrar academias existentes. Campos novos têm
  default seguro e leitura tolerante a ausência (`?? valorPadrão`); "greenfield"
  significa exportado e testável, mas **não** deployado/wired até estar
  pronto (ver `access_control/`, ainda não ligado a nenhuma catraca real).
  Mudanças de produto radicais nunca acontecem "do nada" — incrementais,
  aplicadas onde já existe o padrão (ex.: `AcademyPageHeader` compartilhado:
  uma variante nova melhora todas as telas de uma vez).
- **Teto de segurança da graduação.** O aluno **nunca** escreve
  `sportData` (o grau *verificado*, staff/promoção-only — bloqueado nas
  Firestore Rules). Ele pode declarar auto-graduações passadas
  (`selfGraduations/`, coleção separada, aditiva) mas **nunca acima do teto**
  do grau verificado — validado em 2 camadas: client filtra o seletor
  (`sports.dart`), e `self_graduation_guard.js` (`onWrite`) **replica a
  mesma ordenação de escadas em Node** e deleta qualquer doc acima do teto
  (fail-closed: grau não reconhecido na escada = rejeitado, nunca aceito por
  omissão). Esportes `GradeSystem.none` (sem faixa) não têm auto-graduação —
  qualquer doc é rejeitado.
- **As 3 ERAS de vínculo conta↔ficha** — sempre trate as três como
  fallback, nesta ordem (ver `functions/fighter_baggage.js`, comentário
  verbatim):
  1. `userAcademyMapping/{uid}.academyDetails[academyId].studentId` (formato
     atual);
  2. `academies/{academyId}/users/{uid}.studentId` (formato **legado**,
     academy-scoped — contas antigas ainda vivem aqui);
  3. `students` com `linkedUserId == uid` (fallback por query).
  Qualquer código novo que precise resolver "qual é a ficha deste usuário
  nesta academia" precisa considerar os três, não só o primeiro.
- **`financials.amount` é sempre REAIS** (não centavos) — campo canônico.
  Houve um bug histórico de reais×centavos especificamente na integração
  Mercado Pago, já corrigido no backend; ao tocar em qualquer código de
  pagamento, confirme a unidade antes de multiplicar/dividir por 100.
- **Espelhos cliente↔servidor exigem sync manual** — o caso canônico é a
  lista de esportes **sem faixa/sem turma** (`GradeSystem.none` no catálogo).
  Vive em **3 lugares que precisam concordar manualmente** (não há import
  compartilhado):
  1. `lib/core/sports.dart` — catálogo cliente, `gradeSystem: GradeSystem.none`
     (fonte da verdade de produto: hoje `musculacao`, `boxing`, `mma`);
  2. `functions/self_graduation_guard.js` — `GRADELESS_SPORTS` (réplica
     estática para rejeitar auto-graduação nesses esportes);
  3. `functions/index.js` — `SELF_CHECKIN_SPORTS` (réplica para o check-in
     diário self-service).
  Adicionar um esporte `GradeSystem.none` novo (ex.: crossfit) exige editar
  os 3 — esquecer um dos dois lados do servidor deixa o sistema mais
  **restritivo** (fail-closed, não é um bug de segurança, mas gera confusão
  de suporte).
- **Segurança em endpoints públicos** (a catraca não faz Firebase Auth):
  comparação de segredo sempre **timing-safe**
  (`crypto.timingSafeEqual`, nunca `===`), anti-replay por janela de tempo
  (5 min), e todo identificador que vira **segmento de path** no Firestore
  passa por charset estrito (`/^[A-Za-z0-9_-]{1,128}$/`) antes de compor um
  `db.doc(...)` — path injection é tratado como classe de vulnerabilidade
  real (`ingest.js`, comentários "SECURITY (C1)").

## Regras de produto do dono

- **Menos é mais.** Persona majoritária é não-técnica (professor/recepção).
  1 ação óbvia por tela. Ver `docs/ux/NOTAS_FINANCEIRO_2026-07.md` para um
  caso trabalhado (título+cards de resumo comendo >50% da tela antes de
  qualquer ação; a correção foi remover redundância, não redesenhar).
- **Sem funções duplicadas na mesma tela.** Se uma informação já existe em
  outro lugar da navegação (ex.: cards de resumo financeiro já existem na
  aba Relatórios), não duplicar no topo de outra tela — linkar/mover, não
  copiar.
- **"Aha" do produto = cobrança automática.** Segundo o dono, é "a feature
  mais importante do sistema" — e o achado recorrente em auditorias de UX é
  que fica **escondida demais** na navegação. Ao tocar em fluxo de
  cobrança/financeiro, otimize para descoberta, não só para correção.
- **Generalista por design.** O app atende academias de luta, fitness puro e
  híbridas (`AcademyProfile` em `models/academy.dart`). Nunca hardcode copy
  "lutador"/"tatame"/cultura de faixa numa tela nova — use
  `AcademyVocab.of(profile)`/`ref.watch(academyVocabProvider)`
  (`lib/core/academy_vocab.dart`). Regra de zero-regressão do próprio
  arquivo: o perfil `fight` precisa sempre bater com a string literal que o
  app já tinha antes do `AcademyVocab` existir — nunca reparafrasear ao
  adicionar um termo novo.
- **Mudanças radicais nunca "do nada".** Toda mudança de UX maior parte de
  um problema mapeado no código (screenshot anotado do dono, achado de
  auditoria) e é aplicada via ponto de extensão já existente (variante
  `compact` de um widget compartilhado, não um widget novo paralelo).

## Build & release

- `./build.sh aab|apk|ipa|all` → artefatos em `dist/`, nomeados
  `graduabjj-<version>-<build>.<ext>` (versão lida de `pubspec.yaml`).
  `dart-defines` obrigatórios (URLs/API keys do notification-server) já
  embutidos no script — não rodar `flutter build` direto para release sem
  eles.
- Build Windows é workflow **separado** no GitHub Actions — ver
  [BUILD_WINDOWS.md](docs/guias/BUILD_WINDOWS.md) (não é um target do
  `build.sh`).
- **GOTCHAS aprendidos (evitar repetir):**
  1. **Nunca use `--no-codesign`** para rodar no simulador iOS — mata o
     keychain e o Firebase Auth quebra com erro genérico, sem pista de que a
     causa foi essa flag.
  2. **O cache `build/native_assets` contamina entre simulador↔device.**
     Se a máquina já rodou um build de simulador, rode `flutter clean`
     **antes** de `./build.sh ipa` — senão o `objective_c.framework` de
     simulador vaza para dentro do IPA e a Apple rejeita com "unsupported
     platform".
  3. **`functions/.env` só existe local** (gitignored — confirmado em
     `.gitignore:63`). Deploy de Cloud Functions a partir de outra máquina
     **sem esse arquivo apaga as env vars dos crons/integrações** em
     produção. Sempre confirmar que `functions/.env` está presente e
     atualizado antes de `firebase deploy --only functions` de uma máquina
     nova.
- Runbook de deploy com múltiplas peças (regra geral): **backfill → rules →
  resto**. Rodar migração de dados antes de apertar as Firestore Rules que
  passam a exigir o novo formato, e as rules antes do código que depende
  delas.

## Workflows / agentes

- Executores de workflow (agents que efetivamente escrevem código) sempre
  rodam em **Sonnet**.
- **Verificação adversarial antes de aceitar achados** — um agente que
  produz um relatório de auditoria/achados não é a palavra final; outro
  passo (humano ou agente separado) verifica antes de agir sobre o achado,
  especialmente para achados de segurança/dados financeiros.
