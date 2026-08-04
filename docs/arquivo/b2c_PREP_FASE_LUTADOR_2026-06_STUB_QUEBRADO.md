Documento criado em `/Users/igorgewehr/WebstormProjects/graduabjj/docs/PREP_FASE_LUTADOR_2026-06.md`.

Estrutura entregue (PT-BR, Markdown):
1. **## Visão** — o lutador volta todo dia, cultura, compartilhar, independente da academia; com nota de que o detalhamento de produto virá das duas pesquisas de mercado em paralelo (retenção B2C + cultura do lutador).
2. **## O que o app JÁ tem como fundação** — 8 blocos com file:line: identidade `/users/{uid}` (`user.dart:73-210`), índice de portabilidade `userAcademyMapping` (`user.dart:212-308`), mirror público PII-safe (`server_functions.js:821-896`), eventos/timeline (`achievement_service.dart:9`), `CrossAcademyService` (`cross_academy_service.dart:74-332`), rollup `syncHighestBelt` (`global_user_service.dart:325-399`), ranking (`ranking_service.dart:14-90`) e a prova multi-academia/transferência.
3. **## Global/portátil vs. acoplado à academia** — tabela-mapa por sinal (uid ✅ vs. studentId 🔒) com a regra de ouro de manter source-of-truth academy-scoped.
4. **## A ponte arquitetural** — o que multi-academia/transferência já preparou + os 4 deltas A→B→C→D (re-key do perfil para uid → rollup event-driven → grafo social/feed → ranking person-level) + uma seção 4.3 com as dívidas da etapa atual (incluindo o BLOCKER de read-only nas rules) a validar antes de avançar.
5. **## Próximos passos sugeridos** — roadmap-ponte em Passos 0-4 (sem implementar), decisões de produto pendentes, e apêndice de referências de código.

Verifiquei as referências load-bearing (`user.dart:73`/`212`, `cross_academy_service.dart:74`, `global_user_service.dart:325`, `server_functions.js:896`) contra o código real antes de escrever — todas conferem.