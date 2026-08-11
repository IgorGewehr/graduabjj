# 08 — Definition of Done

Este plano só está concluído quando a arquitetura implementada satisfizer os
itens abaixo. Criar pastas novas ou mover widgets, sozinho, não basta.

## 1. Fronteiras

- [ ] Flutter não gerencia secrets nem APIs privilegiadas.
- [ ] Flutter não decide estoque, vínculo, promoção ou presença oficial
  multi-documento.
- [ ] Presentation não importa Firestore/HTTP concreto.
- [ ] Domain não importa Flutter/Firebase/Riverpod.
- [ ] Commands validam auth, tenant, role e permission no backend.
- [ ] Queries têm limite/cursor ou justificativa de conjunto pequeno.

## 2. Segurança e dados

- [ ] segredo de catraca é gerado server-side, hashed e exibido uma vez.
- [ ] TOTP possui backend seguro real ou não aparece como capacidade ativa.
- [ ] link codes são single-use, rate-limited e server-consumed.
- [ ] campos server-owned estão bloqueados nas Rules após rollout.
- [ ] matriz de Rules cobre papéis, tenants, diffs e terminal states.
- [ ] projeções públicas usam allowlist e não expõem PII/risco.
- [ ] logs não contêm tokens, secrets, códigos ou PII integral.

## 3. Operações compostas

- [ ] pedido/estoque/transição são atômicos e idempotentes.
- [ ] bootstrap/leave de academia não deixam vínculos parciais silenciosos.
- [ ] presença e contador permanecem coerentes sob concorrência/retry.
- [ ] promoção grava student/progression/achievement uma única vez.
- [ ] membership de turma e seed de modalidade convergem.
- [ ] hard delete usa job, dry-run e política versionada de retenção.
- [ ] import usa job com progresso e retry item a item.
- [ ] reconcilers detectam drift dos dados desnormalizados.

## 4. Decomposição

- [ ] nenhum arquivo de produção novo ultrapassa 600 linhas.
- [ ] backlog legado acima de 600 foi removido ou cada exceção é explícita.
- [ ] screens/shells respeitam alvo de 400 linhas.
- [ ] controllers/repositories/services Flutter respeitam alvo de 350.
- [ ] backend modules respeitam alvo de 500.
- [ ] `student_detail_screen.dart`, `diario_screen.dart`, settings, classes,
  reports e router foram divididos por responsabilidade.
- [ ] models de domínio não fazem parse direto de `DocumentSnapshot`.
- [ ] providers não executam regra ou mutação ao serem observados.
- [ ] façades/reexports temporários foram removidos.

## 5. Performance

- [ ] listas principais são paginadas.
- [ ] dashboard/relatórios usam agregações/projeções.
- [ ] export pesado usa job.
- [ ] histórico cross-academy usa projeção segura, sem N+1 no cliente.
- [ ] feed/social possui cursor e audience/projeção controlada.
- [ ] query budgets e p95 das jornadas críticas são medidos.
- [ ] troca de tenant invalida caches tenant-bound.

## 6. Testes e CI

- [ ] `functions/package.json` possui scripts de teste/check.
- [ ] CI executa Flutter, Node e Rules tests.
- [ ] analyzer é bloqueante ou baseline no-new está ativo com budget decrescente.
- [ ] architecture checks bloqueiam tamanho/imports/legacy/secret regressions.
- [ ] inventário impede exclusão acidental de Cloud Functions.
- [ ] corridas de loja, presença, código e promoção têm testes.
- [ ] god-file splits possuem testes de caracterização de rota/state/copy.
- [ ] Emulator testa tenant e ownership de campos.

## 7. Operação e rollout

- [ ] rollout segue backend -> app -> telemetria -> versão mínima -> Rules.
- [ ] backfills são dry-run, idempotentes e registrados.
- [ ] jobs possuem alerta para partial/failed/lease expired.
- [ ] logs usam requestId e redaction.
- [ ] métricas/alertas cobrem erro, p95, replay e drift.
- [ ] rollback foi ensaiado para cada command crítico.
- [ ] runtime/região/nome externo de Functions foram preservados ou migrados por
  plano explícito.

## 8. Documentação

- [ ] este roadmap registra PRs/commits concluídos.
- [ ] `docs/INDEX.md` aponta para a arquitetura viva.
- [ ] `CLAUDE.md` reflete boundaries e budgets implementados.
- [ ] ownership de coleção/campo está atualizado.
- [ ] runbooks existem para device secret, identity repair, store mismatch,
  attendance drift, deletion/import job e deploy de Functions.
- [ ] nenhum TODO crítico ficou sem owner, prioridade e fase.

## Resultado final esperado

Uma mudança em presença não exige tocar numa tela de seis mil linhas; uma
promoção não pode deixar três documentos divergentes; duas compras não vendem o
mesmo último item; uma versão antiga do app não decide invariantes novas; um
segredo de catraca não fica permanentemente legível no Flutter; relatórios não
baixam a academia inteira; e cada domínio pode ser testado, revisado, implantado
e revertido isoladamente.
