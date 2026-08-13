# Pagamentos em produção

**Status:** infraestrutura publicada em 2026-08-12; rollout por academia ainda
desligado.
**Escopo:** recebíveis aluno → academia, Mercado Pago, links públicos e
lembretes de cobrança.

## Decisão vigente

O MyDojo usa a conta Mercado Pago conectada por OAuth em cada academia, mas não
envia uma tentativa PIX descartável no WhatsApp. Envia um link público estável,
sem login, que consulta a cobrança ao vivo e só cria checkout depois de um
clique humano em **Pagar agora**.

```text
WhatsApp → https://arpjj-76350.web.app/p/<token-opaco>
         → Firebase Hosting → Firebase Functions
         → Mercado Pago da academia → webhook assinado → baixa financeira
```

## Invariantes

- O OAuth e o dinheiro pertencem à academia; o MyDojo não recebe saldo nem faz
  KYC.
- O token do link é opaco, persistido apenas de forma protegida e não entra em
  logs.
- Criar ou reenviar lembrete não cria cobrança Mercado Pago. O checkout só
  nasce depois de um clique em **Pagar agora**.
- Webhook assinado e reconciliador são idempotentes; uma tentativa expirada não
  cancela a dívida.
- O pagamento público depende de `publicPaymentLinksEnabled=true`, OAuth ativo
  e cobrança aberta.

## Limites

- Não há backend first-party fora de Firebase Functions.
- Firebase Hosting entrega a página `site/pay` e encaminha `/api/*` para
  Functions.
- WhatsApp ainda não pode ter rollout global: o emissor atual depende de um
  proxy externo legado e será substituído por chamada direta à Meta a partir
  das Functions.

O [runbook de release](10_RUNBOOK_RELEASE_PRODUCAO.md) é a instrução única para
canário, rollout global, rollback e a migração pendente do WhatsApp. Atualize
este documento e o runbook no mesmo PR que alterar o fluxo.
