# Plano — cobranças via Meta Cloud, PIX pessoal e Mercado Pago

## Objetivo

Consolidar o envio de cobranças por WhatsApp na **Meta Cloud API**. O Baileys
permanece somente como fallback quando a Meta não aceitar ou não conseguir
entregar o envio. Cada academia poderá escolher se prefere receber por Mercado
Pago ou pela sua chave PIX pessoal, com fallback automático para o outro meio
quando disponível.

O plano também elimina a edição de mensagens de WhatsApp por academia: os
textos oficiais serão os templates aprovados no WhatsApp Manager. A edição de
templates de e-mail continua independente.

## Resultado esperado

Para cada cobrança, o sistema resolve um único meio de pagamento antes de
enviar o lembrete:

| Meio resolvido | O que o aluno recebe | Rastreamento |
| --- | --- | --- |
| Mercado Pago | Template Meta com PIX copia-e-cola e botão de checkout | Webhook do Mercado Pago dá baixa automaticamente |
| PIX pessoal | Template Meta com a chave PIX da academia, sem botão | Professor/recepção confirma o pagamento manualmente |
| Nenhum | Template Meta sem instrução de pagamento, orientando o aluno a falar com a academia | Cobrança continua pendente até uma baixa manual |

## Estado atual encontrado

### Templates e envio

- O app possui textos de WhatsApp locais em
  `lib/services/billing_reminder_service.dart` (`defaultWhatsAppTemplates`) e
  permite textos personalizados por academia.
- Esses textos personalizados são gravados no Firestore em
  `academies/{academyId}/settings/billingReminders.messageTemplates.whatsapp`.
- Os templates oficiais da Meta estão documentados em
  `notification-server/TEMPLATES_META.md`, mas as versões que valem para o
  envio ficam no WhatsApp Manager.
- O app já envia manualmente e em lote para
  `/api/send-whatsapp-template` quando `WHATSAPP_USE_TEMPLATES` está ativo.
  O notification server encaminha nome do template, variáveis e botão para a
  Meta, usando Baileys apenas se a Cloud API falhar.
- As cobranças automáticas das Cloud Functions ainda montam texto livre e
  chamam `/api/send-whatsapp`; portanto, nesse fluxo o Baileys ainda é o
  caminho principal. Isso deve ser migrado antes de considerar a transição
  concluída.

### Meios de pagamento

- A academia já possui `pixKey` e `pixKeyType` em
  `academies/{academyId}`, configurados pela tela de configurações.
- Mercado Pago é configurado por academia com `mpConnected` e a geração do
  PIX gera/persiste `gatewayPaymentId`, `pixCode`, `pixTicketUrl` e expiração
  na cobrança.
- Os lembretes automáticos só tentam gerar PIX Mercado Pago. A chave PIX
  pessoal ainda não participa da escolha de envio.
- No portal do aluno, a chave PIX pessoal só é mostrada quando nenhum gateway
  online está conectado; ainda não há uma preferência comum entre portal e
  WhatsApp.
- O webhook `mercadoPagoMarketplaceWebhook` liquida cobranças Mercado Pago e
  registra a origem como `mp-webhook`.
- A baixa manual existente oferece apenas “pago em dinheiro”, embora o modelo
  já suporte `PaymentMethod.pix`.

## Decisões de produto

### Preferência configurável por academia

Adicionar uma configuração comum de recebimento, próxima às configurações de
PIX e Mercado Pago:

- **Preferir Mercado Pago**
- **Preferir chave PIX pessoal**
- **Não incluir instrução de pagamento** (opcional, mas recomendado para dar
  controle explícito ao mestre)

Essa escolha vale tanto para lembretes de WhatsApp quanto para a tela
Financeiro do aluno. Ela não remove o fallback: se o método preferido estiver
indisponível, o sistema usa o outro método configurado.

### Algoritmo de resolução

1. Se a academia desativou instruções de pagamento, resolver `none`.
2. Se a preferência é PIX pessoal e existe uma chave válida, resolver
   `manual_pix`.
3. Se a preferência é Mercado Pago, tentar gerar ou reutilizar o PIX Mercado
   Pago. Só considerar o meio disponível se essa operação der certo.
4. Quando o meio preferido não estiver disponível, tentar o outro:
   - Mercado Pago indisponível/sem PIX funcional -> chave PIX pessoal;
   - chave PIX ausente -> Mercado Pago.
5. Se nenhum dos dois funcionar, resolver `none`.

`mpConnected` isoladamente não é suficiente: a conta pode não ter PIX ativo,
o token pode ter expirado ou a geração pode falhar. Por isso a decisão final
precisa ocorrer no servidor, no momento em que a cobrança é enviada.

## Estratégia de templates Meta

Templates Meta não possuem condicionais: uma variável preenche um trecho já
aprovado, mas não remove linhas nem botões. Não devemos enviar variáveis ou
URLs vazias para tentar reutilizar um único template.

Cada estágio terá três variantes, totalizando 18 templates:

| Modo | Nome recomendado | Variáveis | Botão |
| --- | --- | ---: | --- |
| Mercado Pago | `cobranca_d0` ... `cobranca_d30` | nome, academia, valor, vencimento, PIX copia-e-cola | URL dinâmica do checkout |
| PIX pessoal | `cobranca_d0_pix_manual` ... `cobranca_d30_pix_manual` | nome, academia, valor, vencimento, chave PIX | Não |
| Sem pagamento | `cobranca_d0_sempix` ... `cobranca_d30_sempix` | nome, academia, valor, vencimento | Não |

Os do primeiro e terceiro grupos já estão descritos em
`notification-server/TEMPLATES_META.md`; criaremos somente os seis de PIX
pessoal. Os novos textos devem dizer **“Chave PIX para pagamento”**, não
“PIX copia e cola”, pois uma chave pode ser CPF, e-mail, telefone ou aleatória.

Os templates atuais falam em “mensalidade”, porém a mesma régua pode alcançar
cobranças avulsas. Como padrão, a nova redação deve usar “cobrança” ou
“pagamento em aberto”, evitando uma segunda matriz de 18 templates só para
cobranças não mensais. Caso o produto exija mensagens diferentes por tipo,
essa decisão deve ser tomada explicitamente antes do cadastro na Meta.

## Alterações por componente

### 1. Modelo e configuração da academia

- Criar um campo persistido, por exemplo
  `billingPaymentPreference: 'mercado_pago' | 'manual_pix' | 'none'`.
- Definir comportamento retrocompatível para academias existentes: preferir
  Mercado Pago quando conectado; caso contrário, usar a chave PIX pessoal;
  sem nenhum dos dois, não incluir instrução.
- Exibir a preferência na tela de configurações junto de chave PIX e Mercado
  Pago, com explicação do fallback automático.
- Manter `pixKey` e `pixKeyType` como dados da academia; não duplicá-los nos
  documentos de cobrança.

### 2. Resolvedor único de instrução de pagamento

- Criar uma função server-side que receba academia, cobrança e preferência e
  retorne `mercado_pago`, `manual_pix` ou `none`, junto dos dados mínimos de
  envio.
- Para Mercado Pago: criar/reutilizar o PIX válido e retornar código e URL.
- Para PIX pessoal: retornar apenas a chave PIX da academia.
- Para nenhum: não retornar código, chave, URL ou botão.
- Usar o mesmo resolvedor para lembretes automáticos e, quando aplicável,
  para as telas do app. A regra não deve ficar duplicada em Dart e JavaScript.

### 3. Notification server e Cloud Functions

- Migrar `sendBillingReminderWhatsApp` em
  `functions/server_functions.js` para chamar
  `/api/send-whatsapp-template`, em vez de `/api/send-whatsapp`.
- Enviar apenas `templateName`, variáveis e `buttonUrl` quando o modo for
  Mercado Pago.
- Manter o fallback Baileys no notification server, mas com uma cópia fixa e
  controlada da mensagem correspondente ao template — nunca uma mensagem
  editável por academia.
- Registrar no log o modo escolhido e o nome do template, sem expor a chave
  PIX completa em logs.

### 4. App Flutter e configuração de mensagens

- Remover o editor de **templates de WhatsApp** da tela de cobranças e parar
  de ler/gravar `messageTemplates.whatsapp`.
- Preservar os editores de assunto e corpo de e-mail.
- Remover os defaults de WhatsApp duplicados quando o fallback estiver
  centralizado no notification server; a prévia do app deve indicar o template
  Meta e seus dados dinâmicos, sem prometer texto editável.
- Alterar o mapa de estágio para selecionar também o modo de pagamento:
  Mercado Pago, PIX pessoal ou sem pagamento.
- Garantir que a tela Financeiro do aluno respeite a mesma preferência: se
  PIX pessoal for o meio escolhido, mostrar/copy a chave em vez de abrir um
  checkout Mercado Pago; se nenhum for escolhido, apenas orientar a procurar
  a academia.

### 5. Baixa e auditoria de PIX pessoal

- Adicionar uma ação explícita para equipe autorizada:
  **“Confirmar PIX manual”**.
- Gravar `method: 'pix'`, `paymentGateway: 'manual'`, data e identidade de
  quem confirmou. A cobrança não pode ser quitada pelo aluno.
- Reaproveitar as proteções existentes de baixa manual: se houver um PIX
  Mercado Pago aberto, cancelá-lo antes/depois da confirmação para reduzir o
  risco de pagamento duplicado.
- Não gravar a chave PIX pessoal em `pixCode`, `gatewayPaymentId`,
  `pixTicketUrl` ou `pixExpiresAt`; esses campos representam uma transação
  rastreável do Mercado Pago.

## Sequência de implementação

1. Cadastrar e aprovar os seis templates `*_pix_manual` na Meta; revisar a
   linguagem neutra dos 18 templates antes de ativá-los.
2. Implementar configuração e resolvedor server-side, com testes para todas
   as combinações de preferência e disponibilidade.
3. Migrar as Cloud Functions automáticas para a rota de template Meta e
   validar o fallback Baileys controlado.
4. Atualizar o app: remover edição WhatsApp, aplicar a preferência no portal e
   ajustar a prévia.
5. Adicionar confirmação de PIX manual com auditoria.
6. Testar cada cenário em uma academia de teste, incluindo confirmação de
   entrega pelo webhook da Meta e liquidação pelo webhook do Mercado Pago.
7. Só após validar os fluxos automáticos, desativar o uso direto de
   `/api/send-whatsapp` para cobranças.

## Critérios de aceite

- Uma academia com Mercado Pago preferido recebe template com PIX gerado e
  botão de checkout; pagamento confirmado pelo webhook encerra a cobrança.
- Sem Mercado Pago funcional e com chave PIX, o aluno recebe o template de
  PIX pessoal, sem botão, e a equipe consegue confirmar o recebimento como
  PIX manual.
- Sem nenhum meio configurado, o aluno recebe somente o template sem
  pagamento e a cobrança continua pendente.
- A mesma preferência é respeitada no WhatsApp, no lembrete automático e na
  tela Financeiro do aluno.
- Nenhum usuário consegue editar o texto de WhatsApp por academia.
- Baileys só é usado após falha da Meta; as cobranças automáticas não chamam
  diretamente a rota de texto livre.
- Nenhuma chave PIX pessoal ou dado de pagamento sensível aparece em logs.

## Arquivos principais envolvidos

- `lib/services/billing_reminder_service.dart`
- `lib/screens/admin/billing_reminders_screen.dart`
- `lib/screens/admin/settings_screen.dart`
- `lib/screens/portal/financial_screen.dart`
- `lib/services/settings_service.dart`
- `lib/services/payment_service.dart`
- `lib/screens/admin/student_detail_screen.dart`
- `functions/server_functions.js`
- `../notification-server/server.js`
- `../notification-server/whatsappCloud.js`
- `../notification-server/TEMPLATES_META.md`
