# 08 — Definition of Done

O projeto só pode declarar a nova arquitetura **100% concluída** quando todos os
itens abaixo estiverem atendidos. Entregar apenas uma página ou trocar a URL na
mensagem não basta.

## 1. Jornada do aluno

- [ ] Recebe no WhatsApp um link MyDojo estável e legível.
- [ ] Abre em navegador sem criar conta/instalar app.
- [ ] GET e preview não criam pagamento.
- [ ] Vê academia, descrição, valor, vencimento e status corretos.
- [ ] Consegue pagar conforme `both`, `pix_only` ou `card_only`.
- [ ] Pix expirado é regenerado pelo mesmo link após clique.
- [ ] Link pago mostra confirmação e não permite segunda cobrança.
- [ ] Link cancelado/revogado não expõe dados nem cria checkout.
- [ ] Valor alterado invalida tentativa antiga.

## 2. Jornada do professor

- [ ] Continua conectando Mercado Pago pelo OAuth atual.
- [ ] Não realiza onboarding Asaas/KYC MyDojo.
- [ ] Envia cobrança unitária e em lote sem gerar Pix antecipado.
- [ ] Reenvio usa o mesmo link estável.
- [ ] Visualiza progresso/falhas de lote.
- [ ] Pagamento aprovado marca automaticamente o financial.
- [ ] Expiração de tentativa não aparece como cancelamento da dívida.
- [ ] Pode marcar pago, cancelar, reativar e editar por ações server-side.
- [ ] Recebe alerta acionável para mismatch, duplicidade, unmatched e OAuth.

## 3. Dinheiro e conciliação

- [ ] OAuth e saldo continuam por academia.
- [ ] `financials.amount` permanece em reais e valor é derivado no servidor.
- [ ] `external_reference` continua parseável/tenant-safe.
- [ ] Webhook HMAC/anti-replay/fetch server-to-server preservado.
- [ ] Settle idempotente cobre Checkout Pro, Pix e cartão.
- [ ] Método de pagamento não reduz “todo não-Pix = cartão”.
- [ ] Refund, partial refund e chargeback testados.
- [ ] Estoque e aula particular continuam exactly-once.
- [ ] Aprovação tardia após manual paid/cancel entra em conciliação de duplicidade.
- [ ] Reconciler encontra attempts pagas sem settle.

## 4. Segurança

- [ ] Credencial de notificação antiga rotacionada/revogada.
- [ ] Nenhum secret em Flutter, `build.sh`, site ou logs.
- [ ] Raw payment token não é armazenado/logado.
- [ ] Link/attempt/job são server-write-only nas Rules.
- [ ] Financials são server-write-only após corte de versão.
- [ ] Tenant e permissão validados em toda callable.
- [ ] API pública possui rate limit, idempotência, body/origin/method guards.
- [ ] Resposta pública não possui PII desnecessária.
- [ ] CSP/no-store/no-referrer/noindex configurados.

## 5. Arquitetura e código

- [ ] `server_functions.js` é shim pequeno ou foi removido com segurança.
- [ ] `index.js` é composition root.
- [ ] Pagamentos academia e plataforma vivem em módulos distintos.
- [ ] Billing manual e automático usam o mesmo core.
- [ ] DTOs comuns não vivem em gateway legado.
- [ ] Telas financeiras foram divididas por seção/controller.
- [ ] Flutter não faz write monetário nem chama proxy de notificação.
- [ ] Gateways legados foram isolados/removidos após auditoria.
- [ ] Exports Firebase e runtimes preservados ou migrados por plano explícito.

## 6. Testes e operação

- [ ] CI bloqueia Node tests, Flutter tests e erros do analyzer.
- [ ] Rules tests cobrem acesso, tenant e campos server-owned.
- [ ] Unit/contract/integration tests cobrem matriz do rollout.
- [ ] Sandbox MP cobre guest Pix/cartão/expiração/webhook.
- [ ] Canário real concluído sem perda de conciliação.
- [ ] Métricas do funil e alertas estão ativos.
- [ ] Runbook de secret, OAuth, webhook, mismatch e rollback está disponível.
- [ ] Rollback foi ensaiado e não desliga settle de pagamentos existentes.

## 7. Documentação e limpeza

- [ ] `docs/PAGAMENTOS_MP.md` descreve o estado implementado.
- [ ] `docs/recorrencia-mp-contract.md` aponta paths novos.
- [ ] `docs/INDEX.md` e `CLAUDE.md` estão atualizados.
- [ ] Scripts de backfill têm dry-run, idempotência e resultado registrado.
- [ ] Flags temporárias, reexports e placeholders legados foram removidos.
- [ ] Nenhuma dívida do rollout ficou escondida em TODO sem owner/prioridade.

## Resultado final esperado

Uma academia nova conecta o Mercado Pago em minutos. O professor cria ou gera
mensalidades e envia cobranças pelo WhatsApp. O aluno, mesmo sem conta MyDojo,
paga pelo link duradouro. O dinheiro cai diretamente na academia; o webhook
marca a cobrança; reenvios e expirações não poluem a operação; e o código que
sustenta essa receita está modular, testado, observável e server-authoritative.

