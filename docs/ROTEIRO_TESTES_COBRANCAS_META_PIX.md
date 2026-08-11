# Roteiro de testes — cobranças Meta, Mercado Pago e PIX pessoal

## Objetivo

Validar, em uma academia de teste, toda a alternância de cobrança e os dois
tipos de baixa:

- Mercado Pago: confirmação automática pelo webhook;
- PIX pessoal: confirmação manual e auditável pelo administrador;
- sem meio disponível: cobrança sem instrução de pagamento;
- Meta Cloud como canal principal e Baileys somente como fallback.

Não faça os testes de falha, duplicidade ou cancelamento com alunos reais.

## Preparação

Antes de começar, confirme:

- [ ] Cloud Functions e regras do Firestore desta versão foram publicadas.
- [ ] Notification server desta versão está ativo.
- [ ] O app foi encerrado e iniciado novamente com as configurações do
  notification server; hot reload não atualiza essas configurações.
- [ ] Os 18 templates de cobrança estão aprovados na Meta: seis Mercado Pago,
  seis PIX pessoal e seis sem pagamento.
- [ ] A academia de teste possui um administrador, um instrutor e um aluno.
- [ ] O aluno de teste possui telefone WhatsApp e e-mail válidos.
- [ ] Há uma cobrança de baixo valor que possa ser recriada para cada cenário.
- [ ] Existe uma conta Mercado Pago de teste/homologação conectada.
- [ ] A chave PIX pessoal usada é controlada pela equipe de teste.

Guarde, para cada caso, o ID da cobrança, uma captura do app, o resultado do
envio e o horário. Isso facilita comparar app, Firestore, Meta e Mercado Pago.

## 1. Configuração e regra de fallback

Execute a matriz abaixo. Salve, volte à tela e abra novamente para também
validar a persistência da configuração.

| Preferência | Mercado Pago | Chave pessoal | Resultado esperado |
| --- | --- | --- | --- |
| Mercado Pago | configurado | configurada | Mercado Pago |
| Mercado Pago | indisponível | configurada | PIX pessoal |
| Mercado Pago | indisponível | ausente | Sem pagamento |
| PIX pessoal | configurado | configurada | PIX pessoal |
| PIX pessoal | configurado | ausente | Mercado Pago |
| PIX pessoal | indisponível | ausente | Sem pagamento |
| Sem instrução | configurado | configurada | Sem pagamento |

Em cada linha:

- [ ] O texto explicativo da tela informa corretamente principal e fallback.
- [ ] A escolha permanece igual após fechar e abrir o app.
- [ ] Nenhuma chave PIX pessoal aparece em campos de transação Mercado Pago.

Para academia antiga, sem preferência gravada:

- [ ] Mercado Pago é o padrão quando está funcional.
- [ ] A chave pessoal é usada como fallback quando o Mercado Pago não funciona.

## 2. Cobrança individual por WhatsApp

Use o botão **Cobrar aluno** em uma cobrança com telefone.

Repita para cada modo:

### Mercado Pago

- [ ] A mensagem usa o template Meta do estágio correto.
- [ ] Nome, academia, valor e vencimento estão corretos.
- [ ] O PIX copia-e-cola e o botão/link pertencem ao Mercado Pago.
- [ ] O documento da cobrança contém os campos da transação Mercado Pago.

### PIX pessoal

- [ ] A mensagem usa o template `*_pix_manual` do estágio correto.
- [ ] A chave mostrada é exatamente a configurada pela academia.
- [ ] A mensagem não possui botão de checkout.
- [ ] A chave não foi gravada como `pixCode`, `gatewayPaymentId`,
  `pixTicketUrl` ou `pixExpiresAt` na cobrança.

### Sem pagamento

- [ ] A mensagem usa o template `*_sempix`.
- [ ] Não há chave, código PIX ou botão.
- [ ] A orientação é entrar em contato com a academia.

Repita pelo menos uma vez para cada estágio aprovado: D0, D1, D3, D7, D15 e
D30. Os estados `created` e `upcoming` não enviam WhatsApp enquanto não houver
templates específicos aprovados para eles.

## 3. Cobrança em lote

- [ ] O botão **Cobrar todos** aparece quando há canal configurado.
- [ ] A contagem corresponde às cobranças exibidas.
- [ ] Cada aluno recebe somente uma mensagem para aquela execução.
- [ ] Cada cobrança usa seu estágio correto.
- [ ] O resumo final separa sucessos e falhas por WhatsApp/e-mail.
- [ ] Um aluno sem telefone falha de forma isolada e não interrompe o lote.
- [ ] Uma falha em uma cobrança não duplica as mensagens já enviadas.

## 4. Meta Cloud e fallback Baileys

Faça este bloco apenas em ambiente controlado.

- [ ] Com a Meta saudável, o envio ocorre pela Cloud API e o Baileys não é
  acionado.
- [ ] Provoque uma falha controlada da Meta e confirme que o Baileys é usado
  somente depois da falha.
- [ ] A mensagem do fallback possui texto fixo correspondente ao template.
- [ ] A mensagem não usa nenhuma versão antiga personalizada pela academia.
- [ ] O log registra canal, template e modo de pagamento, sem imprimir a chave
  PIX completa.
- [ ] O webhook de status da Meta atualiza corretamente enviado/entregue/lido
  quando esses eventos estiverem disponíveis.

## 5. Portal financeiro do aluno

Para cada linha da matriz da seção 1, entre como aluno:

- [ ] Mercado Pago: aparece a ação de pagamento online e não aparece a chave
  pessoal ao mesmo tempo.
- [ ] PIX pessoal: aparece a chave com ação de copiar e a orientação para
  enviar o comprovante; não aparece checkout Mercado Pago.
- [ ] Fallback após falha do Mercado Pago: o portal mostra a chave pessoal.
- [ ] Sem pagamento: aparece apenas a orientação para procurar a academia.
- [ ] O aluno não possui ação para marcar a própria cobrança como paga.

## 6. Confirmação do PIX pessoal

Crie uma cobrança pendente e use uma conta de administrador.

- [ ] O ícone de confirmação informa **Confirmar PIX pessoal recebido**.
- [ ] O diálogo exibe aluno e valor corretos.
- [ ] O botão de confirmação começa desabilitado.
- [ ] Ele só habilita após marcar que o recebimento foi conferido.
- [ ] Ao confirmar, a cobrança sai da lista de pendências.
- [ ] No histórico administrativo aparece quem confirmou e data/hora.
- [ ] No portal do aluno aparece **PIX confirmado pela academia**.

Confira o documento `academies/{academyId}/financials/{financialId}`:

- [ ] `status` é `paid`.
- [ ] `method` é `pix`.
- [ ] `paymentGateway` é `manual`.
- [ ] `paymentDate` foi gravado pelo servidor.
- [ ] `manualPaymentAudit.type` é `personal_pix`.
- [ ] `manualPaymentAudit.confirmedByName` e `confirmedAt` estão preenchidos.
- [ ] Campos `gatewayPaymentId`, `pixCode`, `pixQrCode`, `pixTicketUrl`,
  `pixExpiresAt`, `pixAmount` e `cardPending*` foram removidos.

Confira `academies/{academyId}/paymentAuditLogs/manual_pix_{financialId}`:

- [ ] O evento é `manual_pix_confirmed`.
- [ ] ID da cobrança, aluno, valor, administrador e horário estão corretos.
- [ ] A chave PIX pessoal não aparece no evento.
- [ ] Um administrador consegue ler o evento.
- [ ] Instrutor e aluno não conseguem criar, alterar ou apagar o evento.

Idempotência e permissão:

- [ ] Repetir a mesma chamada não muda a data original nem cria outro evento.
- [ ] Um instrutor não vê a ação de confirmação.
- [ ] Uma chamada forjada por instrutor/aluno recebe `permission-denied` e não
  altera a cobrança.
- [ ] Uma cobrança já paga por dinheiro ou Mercado Pago não pode ser sobrescrita
  como PIX manual.
- [ ] Uma cobrança cancelada/reembolsada não pode receber baixa manual.

## 7. Proteção contra pagamento duplicado

### PIX Mercado Pago ainda pendente

- [ ] Gere um PIX Mercado Pago e não o pague.
- [ ] Confirme o recebimento manual da mesma cobrança.
- [ ] A baixa manual só conclui depois de cancelar o pagamento no Mercado Pago.
- [ ] O código/link antigo não aceita mais pagamento.
- [ ] O documento termina pago via `manual`, sem os campos do PIX antigo.

### Cancelamento inconclusivo

- [ ] Em um ambiente controlado, torne a consulta/cancelamento do Mercado Pago
  indisponível mantendo uma cobrança concorrente.
- [ ] A baixa manual é recusada.
- [ ] A cobrança permanece pendente e sem evento de auditoria manual.

### Mercado Pago já aprovado

- [ ] Ao pagar pelo Mercado Pago, o webhook vence a corrida e dá baixa via
  `paymentGateway: mercadopago`.
- [ ] A confirmação manual não consegue sobrescrever esse pagamento.
- [ ] Se o teste conseguir manter momentaneamente o documento pendente com o
  pagamento já aprovado, o servidor orienta aguardar a baixa automática.

## 8. Webhook do Mercado Pago

- [ ] Pague uma cobrança pelo checkout/PIX Mercado Pago.
- [ ] A cobrança muda automaticamente para `paid`.
- [ ] `paymentGateway` é `mercadopago` e `gatewayPaymentId` é o pagamento real.
- [ ] `manualPaymentAudit` não existe.
- [ ] A cobrança desaparece das pendências e aparece no histórico.
- [ ] Reentregar o mesmo webhook não gera uma segunda baixa/notificação.
- [ ] Um valor divergente não quita a cobrança e gera aviso de conciliação.

Se usar cobrança de aula particular:

- [ ] Tanto o webhook Mercado Pago quanto o PIX manual concedem a presença uma
  única vez.
- [ ] Repetir webhook/confirmação não incrementa a presença novamente.

## 9. E-mail e edição de mensagens

- [ ] Assunto e corpo de e-mail continuam editáveis e persistem.
- [ ] Envio individual e em lote por e-mail continuam funcionando.
- [ ] Não existe editor de mensagem WhatsApp na academia.
- [ ] Alterações antigas em `messageTemplates.whatsapp` não afetam novos envios.

## 10. Regressão rápida

- [ ] Criar, editar e cancelar uma cobrança aberta continua funcionando.
- [ ] Cobrança individual aparece para aluno com telefone.
- [ ] Filtros Todas/A vencer/Vencidas exibem contagens corretas.
- [ ] Atualizar a tela não duplica cobranças nem contatos.
- [ ] Academia sem canal configurado recebe aviso claro e não tenta lote.
- [ ] Navegação Financeiro, Alunos e Menu continua normal.
- [ ] Nenhum segredo de API ou chave PIX completa aparece nos logs do app,
  Functions ou notification server.

## Registro do resultado

Para cada falha, anote:

| Campo | Valor |
| --- | --- |
| Cenário | Seção e item deste roteiro |
| Academia / cobrança | IDs de teste |
| Horário | Data e hora com fuso |
| Resultado esperado | O item marcado acima |
| Resultado obtido | Mensagem, estado ou tela observada |
| Evidência | Captura e trecho de log sem dados sensíveis |

## Critério para liberar

O corte final só deve ocorrer quando:

- [ ] Todas as linhas da matriz de preferência passaram.
- [ ] Envio individual e em lote passaram nos três modos.
- [ ] Baixa manual, permissões, auditoria e antiduplidade passaram.
- [ ] Webhooks Meta e Mercado Pago foram observados no ambiente de teste.
- [ ] Baileys foi confirmado apenas como fallback.
- [ ] Não restou falha crítica ou risco de cobrança/pagamento duplicado.
