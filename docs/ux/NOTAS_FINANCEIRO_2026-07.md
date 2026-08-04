# Notas de UX — Financeiro admin (screenshot do dono, 2026-07-21)

Fonte: screenshot anotado (Drakkar, tela Financeiro) + feedback verbal do dono.
Princípios aplicáveis: "menos é mais", melhorias incrementais valem pra todo mundo,
nada de mudança radical "do nada". Ver memória `feedback-simplicidade-ativacao`.

## Reclamações (mapeadas no código)

1. **Título come ~1/5 da tela e é redundante** — o usuário JÁ sabe que está no
   Financeiro (bottom nav destacada). Bloco: `AcademyPageHeader` em
   `financial_screen.dart:264-300` (ícone + "Financeiro" + "Mensalidades e
   pagamentos" + chip "Academia" + 3 IconButtons).
   - `AcademyPageHeader` é COMPARTILHADO pelas telas admin → uma variante
     compacta melhora TODAS as telas de uma vez (incremental, global).

2. **Cards Recebido/Pendente/Atrasado + barra "Taxa: 62%" no topo**
   (`financial_screen.dart:~371-417`): junto com o título somam >50% da tela
   antes de qualquer conteúdo acionável.
   - Constatação-chave: essa informação JÁ EXISTE duplicada na aba Relatórios
     (`:779` mostra "Recebido" etc.) E na tela dedicada
     `AdminFinancialReportsScreen` (`:292`). Remover os cards do topo = ZERO
     perda de informação.

3. **"O user mal acha os botões que precisa"** — as ações primárias (cobrar,
   registrar pagamento, novo plano) ficam abaixo da dobra ou escondidas em
   ícones sem rótulo no header.

## Direção de redesign (a detalhar com o relatório do workflow)

- Header compacto: 1 linha (título pequeno + ações com rótulo quando couber);
  descrição/chip somem. Aplicar via variante do `AcademyPageHeader`
  (ex.: `compact: true`) — aditivo, opt-in por tela, sem quebrar as demais até
  serem migradas.
- Cards de resumo saem do topo → viram o conteúdo da aba Relatórios (onde já
  estão). No lugar: no máximo UMA linha de contexto (ex.: "16 em atraso —
  R$ 1.600" clicável, que É ação, não painel).
- Topo da tela = mês + ações primárias visíveis com rótulo.
- Persona: professor não-técnico; 1 ação óbvia por tela.

## COBRANÇA — "a feature mais importante do sistema, ESCONDIDA" (dono, 21/07)

Verificado no código:
- Acesso hoje: SÓ via aba Menu → seção Financeiro → "Cobrança" (nav_catalog.dart:268-276
  → rota /admin/cobranca, app.dart:1331). NÃO está na bottom nav.
- Pior: a tela Financeiro (aba da bottom nav) tem abas Planos|Pagamentos|Relatórios —
  a Cobrança NEM APARECE dentro do próprio Financeiro. O dono vê "R$1.600 em atraso"
  sem nenhum caminho direto pra agir.
- Dentro de billing_reminders_screen: cards por estágio "D+0/D+1/D+3/D+7/D+15/D+30" =
  jargão interno da régua exposto ao professor; cards de stats no topo (mesmo
  padrão come-espaço do Financeiro); funcionalidades confusas (dono).

Direção:
1. **Cobrança entra DENTRO do Financeiro** — ação primária visível: a linha
   "16 em atraso — R$ 1.600 → COBRAR" no topo do Financeiro leva direto à
   cobrança (a rota /admin/cobranca continua existindo — só ganha porta da
   frente; entrada do Menu permanece = aditivo).
2. **Tela de Cobrança sem jargão**: matar "D+N" da UI → lista única de
   devedores ordenada por dias de atraso ("João — 15 dias — R$ 100"),
   botão primário "Cobrar todos", e o status da automação em destaque
   ("Cobrança automática LIGADA — o sistema cobra sozinho" / botão de ligar).
   Com o aha da cobrança automática, esta tela vira sala de controle simples:
   automação ON = acompanhar + exceções; OFF = banner pra ligar + fluxo manual.
3. Stats/estágios detalhados → aba/área "detalhes" (progressive disclosure).

## DASHBOARD — screenshot 2 do dono (21/07, 10:46)

Circulado em verde como "widgets absurdos comendo espaço"
(lib/screens/admin/admin_dashboard_screen.dart, 900 linhas):
1. Card "HOJE" vazio — "Sem aulas na grade de hoje" (~:149): um card inteiro
   pra dizer que não tem nada. Vazio deve COLAPSAR (sumir ou virar 1 linha fina),
   não ocupar um bloco.
2. Stat cards "Alunos Ativos 53 de 53" (:374) + "Receita do Mes R$ 2.900" (:390):
   a Receita está DUPLICADA — o card preto "Mensalidades" logo abaixo mostra os
   MESMOS R$ 2.900. Alunos Ativos não é acionável (a aba Alunos já existe).
   Direção: REMOVER os dois stat cards (zero perda: receita já está no card
   Mensalidades; contagem de alunos na aba Alunos/Relatórios).
3. Diretriz geral do dono: "focar no que o pessoal quer ver". Mantêm-se: ações
   rápidas (Chamada/Novo Aluno/Financeiro — boas), Radar de Retenção (acionável),
   card Mensalidades (não circulado). Nada de widget novo.

## Restrições

- Nada de remover funcionalidade; só reposicionar/rebaixar.
- Mudança vale pra todas as academias (incremental) — não é radical: nenhuma
  função muda de comportamento, só a hierarquia visual.
- Validar resultado rodando no simulador iOS antes de aprovação do dono.
