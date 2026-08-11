# Roteiro de testes — pós-merge UX, QR fixo e cobranças

**Branch:** `feat/migracao-whatsapp-cloud-api`

**Base validada:** commit `5453001`

**Data:** 2026-08-11

## Objetivo

Validar manualmente o conjunto integrado depois do merge com `ux-ativacao`:

- nova identidade visual MyDojo;
- buscas, filtros e listas otimizadas;
- QR fixo e imprimível da academia;
- cobranças por Meta Cloud, Mercado Pago e PIX pessoal;
- confirmação manual de PIX com auditoria;
- regressões básicas de navegação, presença e financeiro.

Faça os testes em uma academia de homologação. Não provoque falhas de
pagamento, duplicidade ou cancelamento usando alunos e cobranças reais.

## Tempo sugerido

| Bloco | Duração aproximada | Prioridade |
| --- | ---: | --- |
| Preparação e smoke test | 15 min | Obrigatório |
| Branding e navegação | 10 min | Obrigatório |
| Listas e chamada | 25 min | Obrigatório |
| QR fixo | 30 min | Obrigatório após deploy |
| Cobranças principais | 45 min | Obrigatório |
| Falhas, fallback e segurança | 30–45 min | Antes da produção |
| Windows e impressão | 20 min | Se a versão desktop for liberada |

## 0. Preparação do ambiente

### Publicações necessárias

Antes de testar cobranças:

- [ ] A função `confirmManualPixPayment` está `ACTIVE` no Firebase.
- [ ] O notification server com os templates Meta está publicado e saudável.
- [ ] As credenciais da Meta Cloud e as chaves usadas pelo app estão válidas.
- [ ] Os 18 templates estão aprovados: seis Mercado Pago, seis PIX pessoal e
  seis sem instrução de pagamento.

Antes de testar o QR fixo:

- [ ] As Rules resultantes do merge foram publicadas.
- [ ] `getOrCreateFixedAcademyQr` foi publicada.
- [ ] `resolveFixedAcademyQr` foi publicada.
- [ ] `checkInWithFixedAcademyQr` foi publicada.

> A publicação anterior foi feita antes do merge e não continha o QR fixo.
> Portanto, esse bloco não funcionará enquanto as três Functions e as Rules
> mescladas não forem publicadas.

### Contas e dados de teste

Prepare:

- [ ] Um administrador da academia.
- [ ] Um instrutor.
- [ ] Um aluno ativo, com conta, telefone e e-mail válidos.
- [ ] Um segundo aluno ativo que não esteja matriculado em uma turma restrita.
- [ ] Uma turma aberta acontecendo agora.
- [ ] Uma turma restrita acontecendo agora, com somente o primeiro aluno.
- [ ] Uma turma fora da janela de check-in.
- [ ] Duas turmas simultâneas para testar a escolha após ler o QR.
- [ ] Três cobranças pequenas: Mercado Pago, PIX pessoal e sem pagamento.

Para o QR, a aula deve estar entre **30 minutos antes** e **60 minutos depois**
do horário programado.

### Inicialização correta

- [ ] Pare completamente o app pelo botão vermelho.
- [ ] Inicie novamente pelo botão verde; não use apenas hot reload.
- [ ] Confirme que o build recebeu as configurações do notification server.
- [ ] Entre como administrador e atualize os dados da academia.

## 1. Smoke test — executar primeiro

Se algum item deste bloco falhar, interrompa o restante e registre a falha.

- [ ] O app abre sem tela branca ou carregamento infinito.
- [ ] Login funciona e leva ao dashboard correto.
- [ ] Menu, Alunos, Chamada, Financeiro e Configurações abrem.
- [ ] A lista de alunos carrega e permite abrir um cadastro.
- [ ] A lista de turmas carrega e permite abrir uma turma.
- [ ] A tela de cobrança exibe as pendências.
- [ ] O botão **Cobrar aluno** aparece para aluno com telefone.
- [ ] Não há erro vermelho, fechamento inesperado ou loop de navegação.

Resultado do smoke test: [ ] aprovado  [ ] reprovado

## 2. Branding e navegação

### Android/iOS

- [ ] Ícone instalado exibe a marca MyDojo sem corte ou fundo indevido.
- [ ] Splash exibe a nova marca, sem piscar a marca antiga.
- [ ] Login, cadastro e criação de academia usam o branding correto.
- [ ] A logo não fica deformada em tela pequena ou orientação diferente.
- [ ] Voltar do login/cadastro não causa tela vazia.

### Navegação geral

- [ ] Trocar entre Dashboard, Chamada, Alunos, Financeiro e Menu preserva o
  contexto correto da academia.
- [ ] Voltar de detalhes de aluno/turma retorna para a lista anterior.
- [ ] Ações administrativas continuam ocultas para aluno.
- [ ] Instrutor enxerga somente as funções permitidas pelo seu perfil.

## 3. Lista de alunos

Use uma academia com alunos ativos, inativos, transferidos, com e sem conta.

### Busca

- [ ] Buscar pelo nome completo retorna o aluno correto.
- [ ] Buscar pelo apelido retorna o aluno correto.
- [ ] Buscar pelo e-mail retorna o aluno correto.
- [ ] Digitar rapidamente não trava nem reconstrói a tela a cada tecla.
- [ ] Limpar a busca restaura a lista imediatamente.
- [ ] Uma busca sem resultado mostra o estado vazio correto.

### Filtros

- [ ] Sem filtro de status, alunos transferidos não aparecem.
- [ ] O filtro explícito **Transferido** mostra os transferidos.
- [ ] Status, categoria, modalidade e faixa funcionam separadamente.
- [ ] **Com conta** e **Sem conta** retornam grupos corretos.
- [ ] Combinar modalidade + faixa + categoria mantém somente alunos válidos.
- [ ] **Limpar filtros** restaura a lista padrão.

### Ordenação e ações

- [ ] **Nome** ordena alfabeticamente.
- [ ] **Presenças** coloca maior quantidade primeiro.
- [ ] **Faixa** respeita a ordem da modalidade selecionada.
- [ ] **Elegíveis primeiro** coloca elegíveis no topo e usa o maior progresso
  como desempate.
- [ ] Abrir, editar e voltar de um aluno filtrado não quebra a lista.
- [ ] Rolagem longa não duplica, perde ou troca cards de aluno.

## 4. Lista de turmas e chamada

### Turmas

- [ ] Buscar pelo nome encontra a turma correta.
- [ ] Limpar a busca restaura todas as turmas.
- [ ] Filtrar por categoria mantém apenas a categoria escolhida.
- [ ] Criar uma turma faz ela aparecer na lista.
- [ ] Editar uma turma atualiza o card correto.
- [ ] Excluir uma turma de teste remove somente aquela turma.

### Chamada

- [ ] Buscar aluno por nome e apelido funciona.
- [ ] **Todos**, **Presentes** e **Ausentes** exibem contagens corretas.
- [ ] Marcar um aluno como presente move-o para **Presentes**.
- [ ] Remover presença move-o novamente para **Ausentes**.
- [ ] A lista respeita os alunos matriculados quando a turma é restrita.
- [ ] **Marcar todos** e **Limpar** continuam funcionando.
- [ ] A busca não altera a lista original nem duplica presenças.

## 5. QR fixo da academia

### Geração pelo administrador

1. Entre como administrador.
2. Abra **Chamada por QR**.
3. Abra **QR fixo da academia**.

- [ ] A tela abre sem erro de função inexistente.
- [ ] Nome da academia e QR são exibidos.
- [ ] Fechar e abrir novamente devolve exatamente o mesmo QR.
- [ ] Criar uma nova turma não altera o QR.
- [ ] Instrutor/aluno não conseguem gerar ou substituir o QR.
- [ ] **Imprimir ou salvar em PDF** abre a impressão e gera um PDF legível.
- [ ] O PDF contém academia, QR e orientação de check-in.

### Leitura pelo aluno

1. Entre no celular com o primeiro aluno.
2. Abra **Check-in por QR** e leia o QR impresso/tela.

- [ ] O scanner reconhece o QR permanente.
- [ ] Aparecem apenas turmas dentro da janela atual.
- [ ] Se houver duas turmas válidas, o aluno pode escolher uma.
- [ ] Nome e horário exibidos correspondem à turma real.
- [ ] Selecionar a turma registra uma presença.
- [ ] A chamada administrativa mostra o aluno presente.
- [ ] `attendanceCount` aumenta uma única vez.
- [ ] Repetir o mesmo check-in não cria presença duplicada.

### Regras de matrícula e horário

- [ ] Turma aberta aceita aluno ativo da academia.
- [ ] Turma restrita aceita o aluno matriculado.
- [ ] O segundo aluno não matriculado não vê/entra na turma restrita.
- [ ] Turma fora da janela não aparece.
- [ ] Quando nenhuma turma é válida, aparece **Nenhuma turma disponível agora**.
- [ ] Aluno inativo ou sem vínculo correto é recusado.
- [ ] QR adulterado ou de outra academia é recusado.
- [ ] O QR rotativo antigo por turma continua funcionando.

## 6. Configuração de recebimento

Execute esta matriz e reabra a tela após salvar:

| Preferência | Mercado Pago | PIX pessoal | Resultado esperado |
| --- | --- | --- | --- |
| Mercado Pago | disponível | configurado | Mercado Pago |
| Mercado Pago | indisponível | configurado | PIX pessoal |
| Mercado Pago | indisponível | ausente | Sem pagamento |
| PIX pessoal | disponível | configurado | PIX pessoal |
| PIX pessoal | disponível | ausente | Mercado Pago |
| PIX pessoal | indisponível | ausente | Sem pagamento |
| Sem instrução | disponível | configurado | Sem pagamento |

Para cada linha:

- [ ] A explicação de principal e fallback está correta.
- [ ] A escolha permanece após fechar e abrir o app.
- [ ] Portal e cobrança WhatsApp resolvem o mesmo meio.
- [ ] Academia antiga sem preferência usa Mercado Pago como padrão e PIX
  pessoal como fallback.

## 7. Cobrança individual e em lote

### Individual

- [ ] **Cobrar aluno** abre para aluno com telefone.
- [ ] Mercado Pago usa o template do estágio, PIX copia-e-cola e botão/link.
- [ ] PIX pessoal usa `*_pix_manual`, mostra a chave e não possui botão.
- [ ] Sem pagamento usa `*_sempix`, sem chave, código ou botão.
- [ ] Nome, academia, valor e vencimento estão corretos.
- [ ] E-mail individual continua disponível e editável.

### Lote

- [ ] **Cobrar todos** mostra a quantidade correta.
- [ ] Cada cobrança recebe o template correspondente ao estágio e meio.
- [ ] Cada aluno recebe somente uma mensagem por execução.
- [ ] Aluno sem telefone falha isoladamente e não interrompe o lote.
- [ ] O resumo separa WhatsApp e e-mail, sucessos e falhas.
- [ ] Atualizar a tela não reenvia nem duplica cobranças.

### Meta e fallback

- [ ] Com a Meta saudável, o envio ocorre pela Cloud API.
- [ ] Baileys não é acionado quando a Meta aceita o envio.
- [ ] Em falha controlada da Meta, Baileys é usado somente como fallback.
- [ ] O fallback usa texto fixo, nunca template personalizado da academia.
- [ ] Logs não exibem chave PIX completa nem segredo de API.

Para a matriz completa de estágios, Firestore e webhooks, execute também
[`ROTEIRO_TESTES_COBRANCAS_META_PIX.md`](ROTEIRO_TESTES_COBRANCAS_META_PIX.md).

## 8. Confirmação do PIX pessoal

1. Crie uma cobrança pendente.
2. Entre como administrador.
3. Use **Confirmar PIX pessoal recebido**.

- [ ] O diálogo mostra aluno e valor corretos.
- [ ] O botão começa desabilitado.
- [ ] Marcar que o recebimento foi conferido habilita a confirmação.
- [ ] Confirmar remove a cobrança das pendências.
- [ ] Histórico administrativo mostra usuário e data/hora.
- [ ] Portal do aluno mostra **PIX confirmado pela academia**.
- [ ] Instrutor não vê a ação e não consegue forçar a chamada.
- [ ] Repetir a confirmação não cria outro evento nem muda a data original.

No Firestore:

- [ ] A cobrança ficou `paid`, `method: pix`, `paymentGateway: manual`.
- [ ] `manualPaymentAudit` contém tipo, nome e horário.
- [ ] Existe `paymentAuditLogs/manual_pix_{financialId}`.
- [ ] O evento não contém a chave PIX pessoal.
- [ ] Campos de uma transação Mercado Pago anterior foram removidos.

## 9. Mercado Pago e proteção contra duplicidade

- [ ] Pagamento Mercado Pago é baixado automaticamente pelo webhook.
- [ ] O histórico grava `paymentGateway: mercadopago` e o ID real.
- [ ] Um PIX Mercado Pago aberto é cancelado antes da baixa manual.
- [ ] Se o cancelamento for inconclusivo, a baixa manual é recusada.
- [ ] Se o Mercado Pago já aprovou, a baixa manual não sobrescreve o webhook.
- [ ] Reentregar o mesmo webhook não duplica baixa ou presença.
- [ ] Valor divergente não quita a cobrança e gera conciliação.

## 10. Portal do aluno

- [ ] Mercado Pago mostra checkout, sem exibir simultaneamente o PIX pessoal.
- [ ] PIX pessoal mostra a chave, copiar e orientação de comprovante.
- [ ] Sem pagamento orienta procurar a academia.
- [ ] O aluno não consegue marcar a própria cobrança como paga.
- [ ] Histórico mostra pagamentos manuais e Mercado Pago corretamente.
- [ ] Leitor de QR abre a câmera somente em dispositivo compatível.
- [ ] No Windows, a tela de QR orienta usar celular/catraca sem fechar o app.

## 11. Windows e distribuição

Execute se o desktop fizer parte desta liberação:

- [ ] Ícone do `.exe` e do instalador exibe corretamente a marca MyDojo.
- [ ] Instalação abre o app sem DLL ou asset ausente.
- [ ] Login e troca de academia funcionam.
- [ ] Telas de alunos, turmas, chamada e financeiro funcionam no desktop.
- [ ] Impressão/PDF do QR fixo funciona.
- [ ] A ausência de câmera mostra orientação, não erro.
- [ ] Atualização do app identifica a nova versão corretamente.

## 12. Registro de falhas

Para cada falha, anote:

| Campo | Preenchimento |
| --- | --- |
| Caso | Seção e item deste roteiro |
| Perfil | Admin, instrutor ou aluno |
| Academia | ID/nome da academia de teste |
| Objeto | ID da cobrança, turma, aluno ou presença |
| Horário | Data e hora com fuso |
| Esperado | Comportamento descrito no checklist |
| Obtido | Mensagem e estado observados |
| Evidência | Captura e log sem segredo/chave completa |
| Repetível | Sempre, intermitente ou uma vez |

## 13. Critério de liberação

### Bloqueadores

Não liberar se ocorrer qualquer um destes casos:

- [ ] App não inicia ou login falha.
- [ ] Aluno acessa dados/ações administrativas.
- [ ] Presença é registrada para aluno, turma ou dia errado.
- [ ] QR adulterado ou fora da janela registra presença.
- [ ] Cobrança usa o meio diferente da preferência/fallback esperado.
- [ ] Pagamento pode ser baixado duas vezes.
- [ ] Aluno consegue quitar a própria cobrança.
- [ ] Chave PIX completa ou segredo aparece em logs.

### Aprovação final

- [ ] Smoke test aprovado.
- [ ] Branding e navegação aprovados.
- [ ] Listas, filtros e chamada aprovados.
- [ ] QR fixo e regras de segurança aprovados.
- [ ] Matriz de pagamento aprovada.
- [ ] Envio individual e em lote aprovados.
- [ ] PIX manual, auditoria e antiduplidade aprovados.
- [ ] Webhooks Meta e Mercado Pago observados.
- [ ] Nenhum bloqueador aberto.

Resultado final: [ ] LIBERADO  [ ] NÃO LIBERADO
