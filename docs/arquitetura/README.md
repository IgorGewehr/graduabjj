# Arquitetura geral e plano de modernização do MyDojo

**Status:** diagnóstico e plano de execução; ainda não implementado
**Base auditada:** branch `ux-ativacao`, commit `e58886e`, em 2026-08-10
**Escopo:** Flutter, Firebase Functions, Firestore Rules, dados, segurança,
performance, testes, CI e decomposição de arquivos fora do núcleo já coberto
por pagamentos.

## Decisão em uma frase

O Flutter passa a expressar intenção e experiência; o backend passa a ser a
autoridade de invariantes, segredos e operações compostas; e os arquivos
colossais são desmontados por feature, com testes de caracterização e limite
normal de 600 linhas por arquivo de produção.

## Relação com a arquitetura de pagamentos

Este conjunto complementa, não substitui,
[`docs/arquitetura-pagamentos`](../arquitetura-pagamentos/README.md). Pagamentos,
cobrança por WhatsApp, Mercado Pago e os splits das telas financeiras continuam
com seu plano próprio. Aqui aparecem apenas as dependências compartilhadas:
autorização, composição das Functions, Rules, CI, loja, identidade, presença,
graduação, catracas, relatórios e organização geral do Flutter.

## Ordem de leitura

1. [Diagnóstico e prioridades](00_DIAGNOSTICO_E_PRIORIDADES.md)
2. [Arquitetura-alvo e limites](01_ARQUITETURA_ALVO_E_LIMITES.md)
3. [Lógicas que devem migrar para o backend](02_LOGICAS_PARA_FIREBASE_FUNCTIONS.md)
4. [Decomposição do Flutter](03_DECOMPOSICAO_FLUTTER.md)
5. [Dados, Rules, segurança e concorrência](04_DADOS_RULES_E_SEGURANCA.md)
6. [Performance e acesso a dados](05_PERFORMANCE_E_CONSULTAS.md)
7. [Testes, CI e observabilidade](06_TESTES_CI_E_OBSERVABILIDADE.md)
8. [Roadmap e matriz de arquivos](07_ROADMAP_E_MATRIZ.md)
9. [Definition of Done](08_DEFINITION_OF_DONE.md)
10. [QR fixo da academia para presenca](09_QR_FIXO_ACADEMIA.md)

## Regras centrais

- 600 linhas é o teto normal de arquivo de produção, não uma meta de tamanho.
- Screen compõe sections e controllers; não contém Firestore, HTTP ou regra de
  domínio.
- Cloud Function valida `academyId`, vínculo, papel e permissão em toda ação.
- Operação que toca mais de um documento deve ser atômica, idempotente ou ter
  compensação explícita no backend.
- Secrets não são lidos, gerados ou persistidos pelo cliente distribuído.
- Rules são a última barreira e refletem ownership de campo; não substituem a
  regra de negócio server-side.
- Split mecânico e mudança de comportamento são PRs separados.
- Nenhuma Rules é fechada antes de backend, app compatível, telemetria e janela
  de versão mínima.

## O que este plano não propõe

- Uma reescrita total do app.
- Mover todo CRUD para Cloud Functions.
- Criar dezenas de arquivos microscópicos ou um framework interno genérico.
- Trocar Riverpod, GoRouter, Firebase ou o modelo multi-tenant.
- Renomear exports deployados sem janela de compatibilidade.
- Alterar no mesmo PR runtime v1/v2, estrutura e regra de negócio.

## Como manter os documentos vivos

- Ao concluir uma etapa, marcar o checkbox no roadmap e registrar PR/commit.
- Se uma contagem de linhas mudar, atualizar a matriz no PR que realizou o
  split; não alterar prioridades apenas por alguns deslocamentos de linha.
- Toda nova mutação deve declarar coleção, campos, ator, idempotência e trilha
  de auditoria.
- Divergência encontrada entre código e documento deve ser corrigida no mesmo
  PR; código em produção permanece a fonte factual.
