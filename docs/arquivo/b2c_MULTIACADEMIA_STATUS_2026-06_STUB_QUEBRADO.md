Documento criado em `/Users/igorgewehr/WebstormProjects/graduabjj/docs/MULTIACADEMIA_STATUS_2026-06.md`.

Estrutura entregue (PT-BR, Markdown):
- **TL;DR de risco** no topo destacando o blocker.
- **1) O que está pronto** — identidade (`/users/{uid}`), índice de portabilidade (`userAcademyMapping`), CFs (`transferStudent`/`applyTransfer`/`leaveAcademy`/`joinAcademy`), agregação cross-academy, e as garantias que passaram (auth, retenção, idempotência, custo, autoTuition seguro, roster).
- **2) Validação** — 5 achados com severidade e fix, **destacando o blocker de read-only não-enforçado nas rules** (writes de presença/contador/ficha/checkins/reservas/loja na academia que o aluno saiu) + cancelamento de assinatura MP (high) + 3 achados de leaveAcademy.
- **3) Tarefas restantes** em tabela priorizada por risco×esforço: rules read-only (blocker), cancelar preapproval MP, switcher Histórico, discovery gate, sair-da-academia, custo `_validateCode`, joinRequests (fase 3).
- **4) Decisões tomadas** + decisões de produto pendentes + apêndice de ponte para a fase lutador (A→B→C→D).