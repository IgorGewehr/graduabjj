# Arquitetura de pagamentos e modernização do MyDojo

**Status:** plano de execução, ainda não implementado  
**Base auditada:** branch `ux-ativacao`, commit `60d4efb`, em 2026-08-10  
**Escopo:** recebíveis aluno → academia, cobrança por WhatsApp, Mercado Pago,
backend Firebase, cliente Flutter, site público, segurança, testes e redução da
dívida estrutural relacionada.

## Decisão em uma frase

O MyDojo continuará usando a conta Mercado Pago que cada academia conecta por
OAuth, mas deixará de mandar uma tentativa PIX descartável no WhatsApp: enviará
um **link público estável do MyDojo**, sem login, que consulta a cobrança ao vivo
e só cria o checkout depois de um clique humano em **Pagar agora**.

```text
WhatsApp
  -> https://bjjeasy.netlify.app/p/<token-opaco>
  -> página pública MyDojo
  -> backend valida a cobrança
  -> Mercado Pago da academia
  -> webhook assinado
  -> financial marcado como paid
```

O MyDojo não abre conta de pagamento, não segura saldo e não assume KYC. O KYC
e o recebimento continuam no Mercado Pago da própria academia.

## Ordem de leitura

1. [Diagnóstico e decisões](00_DIAGNOSTICO_E_DECISOES.md)
2. [Arquitetura-alvo do pagamento público](01_ARQUITETURA_ALVO_PAGAMENTOS.md)
3. [Decomposição do backend Firebase](02_DECOMPOSICAO_BACKEND.md)
4. [Emagrecimento e reorganização do Flutter](03_REORGANIZACAO_FLUTTER.md)
5. [Dados, segurança e observabilidade](04_DADOS_SEGURANCA_OBSERVABILIDADE.md)
6. [Migração, rollout e testes](05_MIGRACAO_ROLLOUT_TESTES.md)
7. [Matriz arquivo por arquivo](06_MATRIZ_ARQUIVOS.md)
8. [Roadmap de qualidade geral](07_ROADMAP_QUALIDADE_GERAL.md)
9. [Definition of Done](08_DEFINITION_OF_DONE.md)

## O que este plano preserva

- Os nomes públicos das Cloud Functions durante a migração.
- A geração v1/v2 atual de cada função; decompor arquivo não autoriza migrar
  runtime no mesmo passo.
- O OAuth por academia e o dinheiro liquidado diretamente para ela.
- `financials.amount` em **reais**.
- `external_reference` no formato atual para mensalidade, pedido e assinatura.
- O webhook HMAC, a validação server-side de valor, a idempotência, o tratamento
  de duplicidade, os estornos e chargebacks já existentes.
- Compatibilidade aditiva enquanto versões antigas do app ainda estiverem vivas.

## O que este plano deliberadamente não faz

- Não migra as academias para Asaas.
- Não cria BaaS, carteira MyDojo ou KYC interno.
- Não reescreve todos os pagamentos de uma vez.
- Não coloca a página pública dentro do Flutter autenticado.
- Não renomeia uma função deployada sem uma janela formal de compatibilidade.
- Não aperta Firestore Rules antes de existir backend e app compatíveis.

## Fontes externas da decisão

- O Checkout Pro aceita comprador convidado, Pix e cartão:
  <https://www.mercadopago.com.br/developers/pt/docs/checkout-pro/overview>
- O modelo marketplace usa o access token OAuth de cada vendedor:
  <https://www.mercadopago.com.br/developers/pt/docs/checkout-pro/how-tos/integrate-marketplace>
- A preferência é criada no backend para cada fluxo de pagamento:
  <https://www.mercadopago.com.br/developers/pt/docs/checkout-pro/create-payment-preference>
- Notificação por preferência é apropriada para múltiplos vendedores:
  <https://www.mercadopago.com.br/developers/pt/docs/checkout-pro/payment-notifications>
- O Mercado Pago recomenda ao menos três dias para vencimento de Pix no
  Checkout Pro:
  <https://www.mercadopago.com.br/developers/pt/docs/checkout-pro/additional-settings/expiration-date>

## Como manter estes documentos vivos

- Cada etapa concluída deve ganhar `[x]` no documento de rollout e a referência
  do PR/commit.
- Mudança de contrato deve atualizar primeiro o documento de dados e a matriz de
  arquivos.
- Se o código divergir do documento, o código em produção é a fonte factual; o
  documento deve ser corrigido no mesmo PR que detectar a divergência.
- Depois de 100% implementado, este conjunto deixa de ser “plano” e vira a
  referência operacional viva da plataforma.

