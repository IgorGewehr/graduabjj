# Arquitetura — Onboarding self-signup + pedido de entrada + aprovação do professor

> Plano gerado por workflow de arquitetura (read-only). Feature 100% aditiva; coexiste com o fluxo de código atual.

## Resumo executivo
Proponho um SEGUNDO caminho de entrada (self-signup + descoberta + pedido) que coexiste com o fluxo de codigo atual e ATERRISSA NO MESMO estado final de membership, sem duplicar plumbing. O perfil auto-reportado pre-academia vive no GlobalUser (/users/{uid}), que ja possui jiujitsuStartDate/highestBelt/highestStripes/weight/cpf/birthDate; estendemos com selfReportedBelt/selfReportedStripes/selfReportedCategory/selfReportedSports[]/selfReportedClassesCount/selfReportedTrainingStartDate, todos auto-reportados, NAO-confiaveis, e separados dos campos highest* (fonte de verdade do ranking). A descoberta usa um espelho publico opt-in academyDirectory/{academyId} (colecao raiz, write:false, mantido por CF mirrorAcademyDirectory copiando o template exato de mirrorStudentPublicProfile em server_functions.js:802-856), com allowlist de campos seguros (name/nameLower/city/cityNormalized/state/logoUrl/sports/searchKeywords) e DENYLIST de PII/segredos (cnpj/email/phone/address/pixKey/mp*/asaas*/subscription/ownerId). Academy ganha flag isDiscoverable (default false, opt-in via settings admin); academies/{id} permanece fechado a nao-membros (firestore.rules:294). O pedido vive em academies/{id}/joinRequests/{uid} com doc-id=uid (idempotencia + anti-spam: 1 pedido pendente por par user,academia), carregando um SNAPSHOT sem PII sensivel do perfil auto-reportado (so nome/foto/faixa-declarada/categoria/esportes/tempo); cpf/telefone NAO entram no snapshot e ficam server-side ate o aceite. O professor ve o inbox (read gateado por isAcademyStaff), e o ACEITE roda obrigatoriamente em CF Admin SDK (acceptJoinRequest) porque as rules de userAcademyMapping (firestore.rules:259-283) proibem o cliente de adicionar 2a+ academia ou escrever academyDetails de outro uid. A CF clona o miolo transacional de joinAcademy (functions/index.js:168-271): arrayUnion academyId + academyDetails[id]={role:student,studentId,status:active} + upsert academies/{id}/users/{uid} + bump accountType free->linked, fechando o request na MESMA transacao. O aceite tem dois modos: mode='link' reusa o guard de student orfao (functions/index.js:195-210) para carimbar linkedUserId=uid num Student existente sem sequestrar registro ja vinculado; mode='create' reusa o plumbing de StudentService.quickCreate semeando do snapshot, mas faixa/categoria entram como SUGESTAO editavel pelo professor (nunca viram verdade graduacional; syncHighestBelt continua fonte de verdade). rejectJoinRequest e cancelJoinRequest completam os estados. Roteamento: free user (academyIds vazio) ganha rota dedicada de descoberta em vez de cair cru no /portal (app.dart:519). register_screen.dart ganha a 3a porta ('Criar conta de aluno' -> AuthService.createAccount, ja existe em auth_provider.dart:219). Feature 100% aditiva: joinAcademy/linkCodes/redeemInstructorCode intactos.

## Modelo de dados
COLECOES NOVAS/ALTERADAS:

1) /users/{uid} (GlobalUser, ALTERADA — lib/models/user.dart:75-202). Adicionar campos auto-reportados PRE-MEMBERSHIP, separados dos highest* (fonte de verdade do ranking via syncHighestBelt):
   selfReportedBelt:string?, selfReportedStripes:int?, selfReportedCategory:'kids'|'adult'?, selfReportedSports:string[], selfReportedPrimarySport:string?, selfReportedClassesCount:int? (nº de aulas declarado — NUNCA vira attendanceCount, derivado de /attendance; no maximo initialAttendanceCount se o professor aceitar), selfReportedTrainingStartDate:timestamp?.
   Por que aqui: /users ja e editavel pelo dono (firestore.rules:202-204, update de tudo exceto role/academyId); accountType='free' ja significa 'sem academia'. Evita pendingProfile separado. Prefixo selfReported* sinaliza NAO-verificado.
   REGRA: sem mudanca — o update generico ja cobre (nao tocam role/academyId).

2) /academyDirectory/{academyId} (NOVA, colecao RAIZ — espelho publico opt-in). Mantida por CF mirrorAcademyDirectory (onWrite em academies/{id}). Raiz (nao subcolecao) para query por cidade entre academias. Campos ALLOWLIST (espelhando PUBLIC_PROFILE_SAFE_FIELDS server_functions.js:777-791): name, nameLower (lowercase sem acento), city, cityNormalized, state, logoUrl, sports[], slug, isDiscoverable (bool concreto), searchKeywords[] (tokens+prefixos 3+ chars sem acento), mirrorUpdatedAt. DENYLIST (NUNCA espelhar): cnpj, email, phone, address, zipCode, responsibleBirthDate, pixKey, pixKeyType, mpUserId, mpPublicKey, asaasOnboardingStatus, subscription, ownerId, settings.
   REGRA: match /academyDirectory/{academyId} { allow read: if isAuthenticated() && resource.data.isDiscoverable==true; allow write: if false; } — leitura so autenticados, nunca anonima; write so Admin SDK.

3) /academies/{id} (ALTERADA — academy.dart:254). Adicionar isDiscoverable:bool (default false). academies/{id} permanece read:if belongsToAcademy (firestore.rules:294) — NAO abrir.

4) /academies/{id}/joinRequests/{uid} (NOVA — doc-id=uid: idempotencia/anti-spam, 1 pedido pendente por par). Campos: userId(==doc id), status:'pending'|'accepted'|'rejected'|'cancelled', createdAt, updatedAt, decidedAt?, decidedBy?, snapshot:{displayName,photoUrl,selfReportedBelt,selfReportedStripes,selfReportedCategory,selfReportedSports,selfReportedPrimarySport,selfReportedClassesCount,selfReportedTrainingStartDate}. SEM cpf/telefone/email/endereco no snapshot (CF le server-side de /users/{uid} no aceite).
   REGRA: create if auth.uid==uid && data.userId==uid && data.status=='pending' && exists(academyDirectory/{academyId}); read,list if isAcademyStaff(academyId) || auth.uid==uid; update if auth.uid==uid && status=='cancelled' && resource.status=='pending' && affectedKeys().hasOnly(['status','updatedAt']); accept/reject SO via CF; delete if false.

INDICES NOVOS (firestore.indexes.json, padrao :96-111): academyDirectory (cityNormalized ASC, nameLower ASC); academyDirectory (cityNormalized ASC, searchKeywords ARRAY_CONTAINS); nameLower single-field auto (range startAt/endAt para prefixo); joinRequests (status ASC, createdAt DESC) para o inbox.

ELO Student<->User reusado no aceite: Student.linkedUserId (student.dart:319) <-> academyDetails[id].studentId (user.dart:261). mode='link' carimba ambos; mode='create' cria Student ja com linkedUserId=uid.

## Fluxos
A) SELF-SIGNUP + PERFIL: register_screen.dart ganha 3a opcao 'Criar conta de aluno' (hoje so 'Tenho codigo'->/link-code linha 70 e 'Sou dono'->/criar-academia linha 99) -> AuthService.createAccount (auth_provider.dart:219, ja cria Auth+/users free+mapping vazio). Free user roteado (app.dart:519) para nova rota /perfil-jiujitsu (nao existe hoje) em vez de /portal cru. Edita faixa declarada, categoria, esportes, tempo de treino, nº de aulas; persiste via updateGlobalProfile estendido (auth_provider.dart:347). Banner 'dados declarados'.

B) DESCOBERTA: /descobrir-academia. Por cidade: academyDirectory where('cityNormalized','==',norm) orderBy nameLower (indice cityNormalized+nameLower). Por nome: prefixo orderBy('nameLower').startAt(q).endAt(q+'') OU array-contains searchKeywords; combinacao usa indice cityNormalized+searchKeywords. SUBSTITUI add_academy_screen.dart:366 (varredura client-side de todas academias = leak+brute-force). Resultado so campos safe.

C) ENVIAR PEDIDO: CF requestToJoinAcademy({academyId}) — valida discoverable + nao-ja-membro (espelho index.js:181-184); monta snapshot safe; grava joinRequests/{uid} status='pending' (doc-id=uid idempotente). Aluno pode cancelar (update status='cancelled').

D) INBOX PROFESSOR: aba 'Pedidos de entrada' no AdminShell; lista joinRequests where status=='pending' orderBy createdAt (read isAcademyStaff). Card mostra snapshot com selo 'NAO VERIFICADO'. Para linkar-a-existente: sugere matches reusando listAcademyMembers (index.js:597) e query students por nome/cpf (padrao promoteToInstructor:432).

E) ACEITAR (CF acceptJoinRequest, Admin SDK): mode='link'+existingStudentId valida isStaff; transacao clonando joinAcademy:168-271 — re-le joinRequest(pending), valida Student e linkedUserId null/igual (guard orfao index.js:200-208), carimba linkedUserId=uid; arrayUnion academyId; academyDetails[id]={role:student,studentId,status:active}; upsert academies/{id}/users/{uid}; bump accountType->linked; fecha request status='accepted' na MESMA transacao. mode='create': professor confirma/edita dados declarados (sugestao); CF cria Student (plumbing quickCreate student_service.dart:367) semeando do snapshot + cpf/phone server-side; Student nasce linkedUserId=uid; selfReportedClassesCount->initialAttendanceCount so se aceito.

F) REJEITAR: CF rejectJoinRequest({academyId,requesterUid}) isStaff -> status='rejected'.

ESTADOS: pending -> accepted|rejected|cancelled. Idempotencia por doc-id=uid. Apos accepted, aluno vira membro e roteia ao /portal.

## Contratos de Cloud Functions
Todas onCall v2/https Admin SDK. Reusam requireAuth (index.js:36), isStaff (index.js:86), isAdmin (index.js:76).

1) requestToJoinAcademy({academyId}) — auth qualquer (para si). Valida academyDirectory/{academyId} existe+isDiscoverable; usuario nao ja vinculado (le userAcademyMapping, espelho index.js:181-184); /users/{uid} existe. Anti-spam: doc-id=uid (idempotente) + rate-limit opcional. Monta snapshot SAFE de /users/{uid} (displayName,photoUrl,selfReported*). Grava joinRequests/{uid} status='pending'. Retorno {success,status:'pending'}.

2) acceptJoinRequest({academyId,requesterUid,mode:'link'|'create',existingStudentId?,overrides?}) — auth isStaff. Transacao: re-le joinRequests/{requesterUid} (deve estar pending, senao failed-precondition — fecha race de duplo-aceite); re-le mapping (se ja in academyIds -> fecha accepted e retorna, guard double-join index.js:181); mode='link': re-le Student, valida linkedUserId null|==requesterUid (guard orfao index.js:200-208), carimba se orfao; mode='create': cria Student (plumbing quickCreate student_service.dart:367) com snapshot+overrides validados, cpf/phone de /users server-side, linkedUserId=requesterUid, initialAttendanceCount overrides|0 (nunca attendanceCount). arrayUnion academyId + academyDetails[id]={studentId,role:student,joinedAt,status:active}; upsert academies/{id}/users/{requesterUid}; bump accountType->linked; joinRequests status='accepted',decidedBy,decidedAt. Retorno {success,studentId}.

3) rejectJoinRequest({academyId,requesterUid}) — isStaff -> status='rejected' se atual=='pending'.

4) cancelJoinRequest({academyId}) — dono do pedido (opcional; pode ser via rule de update).

5) mirrorAcademyDirectory — trigger onWrite academies/{academyId}, clona mirrorStudentPublicProfile (server_functions.js:827-856). Se isDiscoverable==true e cidade/estado presentes: set academyDirectory/{id} com buildAcademyDirectoryProjection (allowlist + nameLower/cityNormalized/searchKeywords normalizados NO SERVER). Senao/delecao: delete academyDirectory/{id} (delete-on-delete server_functions.js:836-844).

6) backfillAcademyDirectory — script one-shot (template scripts/backfill_public_profiles.js) para academias existentes com isDiscoverable==true.

## Telas


## Segurança
PRIVACIDADE: academyDirectory com allowlist estrita (espelha PUBLIC_PROFILE_SAFE_FIELDS server_functions.js:777-791 + buildPublicProfileProjection :802-815); nunca espelhar cnpj/email/phone/address/pixKey/mp*/asaas*/subscription/ownerId. academies/{id} fechado (firestore.rules:294); descoberta nunca le academies cru. Leitura do diretorio so autenticada (evita scraping). Snapshot do pedido SEM cpf/telefone/email — professor ve so nome/foto/dados-JJ declarados antes do aceite; cpf/phone ficam server-side em /users/{uid}, materializados no Student so no aceite (consentimento mutuo).

DADO NAO-CONFIAVEL: selfReported* e declarativo; nunca escreve currentBelt/currentStripes/beltHistory/attendanceCount pelo cliente (rules ja bloqueiam: whitelist firestore.rules:383-397; +1-only attendanceCount :406-411). No aceite faixa/categoria sao SUGESTAO editavel; syncHighestBelt continua fonte de verdade do ranking. selfReportedClassesCount nunca vira attendanceCount (derivado de /attendance attendance_service.dart:143-148); no maximo initialAttendanceCount (student.dart:292) se o professor aceitar.

ANTI-SPAM: doc-id=uid em joinRequests (idempotente, 1 pendente por academia); isDiscoverable opt-in (academia que nao optou nao recebe pedidos); rate-limit por uid na CF (DECISAO do dono — sem infra hoje; ex. contar pending por uid via collectionGroup).

PERMISSOES: aceite/recusa escrevem mapping de OUTRO uid + Student -> impossivel pelo cliente (rules userAcademyMapping :259-283 proibem 2a+ academia e academyDetails alheio); obrigatoriamente CF Admin SDK gateada por isStaff (index.js:86). Aluno so cria/cancela o proprio pedido.

IDEMPOTENCIA/RACE: transacao re-le joinRequests/{uid}; se status!='pending' aborta (fecha duplo-aceite de dois professores). Guard double-join (index.js:181-184): se uid ja in academyIds, fecha accepted e retorna. mode='link' guard orfao (index.js:200-208): so carimba linkedUserId se null|==uid, recusa sequestro. Membership+claim+fechar request na MESMA transacao — request nunca fica accepted sem materializar membership.

## Coexistência / migração
FEATURE ADITIVA, zero conflito: joinAcademy (functions/index.js:125), redeemInstructorCode (:286), promoteToInstructor (:402), linkCodes, register_screen.dart/link_code_screen.dart permanecem INTACTOS. Code-flow continua util para entrada rapida sem aprovacao. Os dois caminhos convergem no MESMO estado final: userAcademyMapping.academyDetails[id]={role:student,studentId,status:active} + academies/{id}/users/{uid} + accountType linked + Student.linkedUserId. acceptJoinRequest e variacao de joinAcademy:168-271 com gatilho 'codigo'->'pedido aprovado'; reusar a mesma transacao garante consistencia.

FLAG: isDiscoverable (default false) e o opt-in por academia; mirrorAcademyDirectory so cria/mantem o doc quando true (deleta quando false). Academia legada sem o campo = nao aparece (default false). E o feature flag natural por academia.

MIGRACAO DA UI: add_academy_screen.dart:366 (varredura client-side) migra para query no academyDirectory; manter entrada por codigo como fallback na mesma tela; pode ser incremental.

BACKFILL: script one-shot backfillAcademyDirectory (template scripts/backfill_public_profiles.js) popula academias existentes com isDiscoverable==true. Sem backfill o diretorio comeca vazio e se popula conforme opt-in (seguro por default). Deployar novos indices (firestore.indexes.json) e novos blocos de rules (academyDirectory, joinRequests) ANTES de habilitar a UI.

## Task list (ordenada)

1. **Estender GlobalUser com campos auto-reportados** — baixo/risco baixo
   - Adicionar selfReportedBelt/Stripes/Category/Sports/PrimarySport/ClassesCount/TrainingStartDate ao GlobalUser (fromMap/toFirestore/copyWith). Verificavel: round-trip de serializacao preserva os campos.
   - arquivos: lib/models/user.dart
2. **Estender updateGlobalProfile para os selfReported*** — baixo/risco baixo (dep: 1)
   - Aceitar e persistir os novos campos em /users/{uid}. Verificavel: chamar updateGlobalProfile grava os campos sem tocar role/academyId.
   - arquivos: lib/providers/auth_provider.dart
3. **Adicionar isDiscoverable ao Academy + toggle no settings admin** — medio/risco baixo
   - Campo isDiscoverable (default false) no model + UI de opt-in que valida city/state preenchidos. Verificavel: toggle persiste e bloqueia ativacao sem cidade.
   - arquivos: lib/models/academy.dart, lib/screens/admin/settings_screen.dart
4. **CF mirrorAcademyDirectory + buildAcademyDirectoryProjection** — medio/risco medio (dep: 3)
   - Trigger onWrite em academies/{id} clonando mirrorStudentPublicProfile; allowlist de campos safe + normalizacao server-side (nameLower/cityNormalized/searchKeywords); delete quando isDiscoverable=false/deletada. Verificavel: editar academia discoverable cria doc safe no academyDirectory; desativar deleta.
   - arquivos: functions/server_functions.js, functions/index.js
5. **Rules + indices do academyDirectory** — medio/risco medio (dep: 4)
   - Bloco /academyDirectory (read autenticado+isDiscoverable, write:false) e indices cityNormalized+nameLower e cityNormalized+searchKeywords. Verificavel: emulador permite read autenticado de doc discoverable e nega write client.
   - arquivos: firestore.rules, firestore.indexes.json
6. **Backfill one-shot do academyDirectory** — baixo/risco baixo (dep: 4)
   - Script populando academias existentes com isDiscoverable==true (template backfill_public_profiles.js). Verificavel: rodar em emulador/staging popula docs esperados.
   - arquivos: functions/scripts/backfill_academy_directory.js
7. **Rules + indices do joinRequests** — medio/risco medio
   - Bloco /academies/{id}/joinRequests/{uid} (create dono, read/list staff+dono, update so cancel pelo dono, accept/reject so CF) + indice status+createdAt. Verificavel: emulador permite create do dono e nega mudanca de status para accepted pelo cliente.
   - arquivos: firestore.rules, firestore.indexes.json
8. **CF requestToJoinAcademy** — medio/risco medio (dep: 5, 7)
   - Valida discoverable+nao-membro, monta snapshot safe de /users/{uid}, grava joinRequests/{uid} pending. Verificavel: callable cria pedido idempotente; rejeita se ja membro ou nao-discoverable.
   - arquivos: functions/index.js
9. **CF acceptJoinRequest (link + create)** — alto/risco alto (dep: 8)
   - Clonar transacao joinAcademy:168-271; mode link reusa guard orfao; mode create reusa plumbing quickCreate semeando snapshot+cpf/phone server-side; fecha request na mesma transacao; idempotencia/race. Verificavel: aceite materializa mapping+student+academy-user e fecha request; duplo-aceite concorrente aborta.
   - arquivos: functions/index.js
10. **CF rejectJoinRequest (+ cancel opcional)** — baixo/risco baixo (dep: 7)
   - isStaff -> status rejected se pending. Verificavel: callable muda status; nega se nao-staff.
   - arquivos: functions/index.js
11. **register_screen 3a porta + tela de signup livre** — baixo/risco baixo (dep: 2)
   - Adicionar 'Criar conta de aluno' -> AuthService.createAccount. Verificavel: cria conta free e cai no perfil pre-membership.
   - arquivos: lib/screens/auth/register_screen.dart
12. **Tela de Perfil Jiu-Jitsu pre-membership** — medio/risco baixo (dep: 2, 11)
   - Editar faixa declarada/categoria/esportes/tempo/aulas; banner NAO-verificado; persiste via updateGlobalProfile. Verificavel: campos persistem em /users.
   - arquivos: lib/screens/portal/profile_screen.dart, lib/app.dart
13. **Tela de Descoberta + servico de busca** — medio/risco medio (dep: 5)
   - Busca por cidade/nome no academyDirectory (range prefixo + array-contains); substitui add_academy_screen.dart:366. Verificavel: busca retorna so campos safe e nao le academies cru.
   - arquivos: lib/screens/portal/discover_academy_screen.dart, lib/services/academy_directory_service.dart, lib/app.dart
14. **Roteamento de free user + tela Meu Pedido** — medio/risco medio (dep: 8, 13)
   - Free user (academyIds vazio) cai em shell de onboarding (perfil->descoberta->pedido) com estado do pedido e botao cancelar. Verificavel: usuario sem academia nao cai no /portal cru.
   - arquivos: lib/app.dart, lib/screens/portal/my_join_request_screen.dart
15. **Inbox do professor + dialogo de aceite (link/create)** — alto/risco medio (dep: 9, 10)
   - Aba Pedidos no AdminShell listando pending; dialogo com modo link (sugere matches via listAcademyMembers/query students) e create (form pre-preenchido editavel). Verificavel: aceitar via UI materializa membership; recusar fecha pedido.
   - arquivos: lib/screens/admin/join_requests_screen.dart, lib/services/join_request_service.dart

## Decisões para o dono

- OPT-IN obrigatorio do diretorio: confirmar isDiscoverable default=false (academia ATIVA para aparecer). Aceita?
- Leitura do diretorio so por AUTENTICADOS (anti-scraping) vs busca anonima pre-cadastro (mais conversao, mais exposicao). Qual prefere?
- Rate-limit de pedidos: nao ha infra. Definir politica (max N pending por aluno, cooldown apos rejeicao). doc-id=uid ja limita a 1 por academia, mas o aluno pode pedir a muitas. Qual limite?
- Faixa/categoria/tempo declarados NAO-verificados: confirmar que no aceite o professor SEMPRE revisa e que nada declarado entra em currentBelt/beltHistory/attendanceCount automaticamente. Manter syncHighestBelt como unica fonte de verdade?
- Numero de aulas declarado pode virar initialAttendanceCount no aceite (so com confirmacao do professor) ou nunca?
- Aprovacao: qualquer staff (admin+instructor, proposta atual via isStaff) ou so admin?
- Snapshot sem cpf/telefone (professor so ve PII apos aceitar). Atende o fluxo, ou ele precisa de telefone ANTES para contato (decisao de privacidade)?
- Auto-aceite: academies.settings ja tem allowStudentRegistration/requireApproval (nunca lidos). Suportar academias que auto-aprovam (sem inbox) ou aprovacao manual sempre?
- Coexistencia da entrada por codigo: manter ambos indefinidamente ou planejar deprecacao do code-flow a medio prazo?