# 📋 Planejamento: Onboarding Interativo & Quiz em 2 Níveis

Este documento reúne a arquitetura, etapas e diretrizes para o novo fluxo de **Onboarding Interativo (Quiz em 2 Níveis)** do aplicativo **GraduaBJJ / MyDojo**.

---

## 1. 🎯 Objetivos e Proposta de Valor

* **Reduzir o "Time to Value" (TTV):** O novo usuário configura o essencial da academia em menos de 60 segundos.
* **Quiz em 2 Níveis com Ponte de Decisão:** 
  * Nível 1 rápido e essencial para começar a operar.
  * Tela de conquista convidando para o Nível 2 (Superpoderes).
* **Experiência "Aha! Moment":** Mini demonstração prática (3s) para o professor sentir a velocidade de chamada e graduação.
* **Modularidade & Skip UX:**
  * Cada etapa é independente e salva seu progresso na hora.
  * O usuário pode pular qualquer etapa individualmente ou sair do fluxo a qualquer momento.
  * Ao pular, recebe aviso claro de que tudo pode ser retomado em **Configurações > Central de Primeiros Passos**.
* **UI/UX Atraente:** Design moderno tipo *Typeform / Duolingo*, com cards selecionáveis, cores temáticas, haptics e transições suaves.

---

## 2. 🗺️ Arquitetura do Fluxo

```mermaid
graph TD
    A[Abertura do App] --> B[NÍVEL 1: Quiz Essencial <br> 'Comece em 60s']
    B --> C{Ponte de Decisão: <br> Quer ativar os Superpoderes?}
    
    C -->|'Sim, personalizar mais (+1 min)'| D[NÍVEL 2: Quiz de Superpoderes <br> 'Recursos Avançados']
    C -->|'Ir para o Painel agora'| E[🏠 Dashboard Principal]
    
    D --> E
    
    subgraph "A qualquer momento ao Pular"
        X[Botão 'Pular' / 'Depois'] --> F[💬 Feedback & Aviso: <br> 'Você pode retomar em Configurações']
        F --> E
    end
    
    subgraph "Acesso Futuro"
        E --> G[⚙️ Configurações > Central de Primeiros Passos]
    end
```

---

## 3. 🥋 NÍVEL 1: Quiz Essencial ("Setup Básico em 60s")

1. **Passo 1: Modalidades do Espaço**
   * *Pergunta:* "Quais modalidades e treinos você oferece?"
   * *Opções:* Jiu-Jitsu, Muay Thai, Musculação, Boxe, Judô, Kickboxing, Luta Livre, Karatê, MMA.
   * *Ação:* Salva `profile` e `sports` em `AcademySettings`.
2. **Passo 2: Método de Cobrança**
   * *Pergunta:* "Como prefere receber os pagamentos dos seus alunos?"
   * *Opções:* Mercado Pago (Automático) ou PIX Pessoal (Campo para chave).
   * *Ação:* Salva `billingPaymentPreference` e `pixKey`.
3. **Passo 3: Entrada dos Primeiros Alunos**
   * *Pergunta:* "Como prefere colocar seus alunos no sistema?"
   * *Opções:* Código de Convite/WhatsApp, Cadastro Rápido Manual ou Importação de Planilha.
4. **Passo 4: Registro de Presença**
   * *Pergunta:* "Como os alunos marcam presença no seu espaço?"
   * *Opções:* Chamada pelo app do professor, QR Code no tatame ou Catraca eletrônica.
5. **Passo 5: Mini Simulação Interativa (3s)**
   * Desafio prático rápido para registrar uma presença de teste com animação de celebração.

---

## 4. 🌉 A Ponte de Decisão (Transição Convidativa)

Após o Nível 1, surge a tela de conquista:
* **Título:** 🎉 *Sua academia já está pronta para operar!*
* **Subtítulo:** *A estrutura básica do seu espaço está configurada. Quer gastar mais 1 minutinho para ativar os superpoderes do seu app e encantar seus alunos?*
* **Ações:**
  * 🟢 `[ ⚡ Sim, ativar Superpoderes da Academia (+1 min) ]` ➔ Vai para o Nível 2.
  * ⚪ `[ 🏠 Ir direto para o Painel Principal ]` ➔ Vai para a Home com aviso amigável.

---

## 5. ⚡ NÍVEL 2: Quiz de Superpoderes ("Personalização Avançada")

1. **Superpoder 1: Radar de Retenção (Alunos Sumidos)**
   * *Pergunta:* "Quer que o app te avise quando um aluno ficar 7+ dias sem treinar?"
   * *Opções:* Sim (com botão de 1-toque no WhatsApp) ou Não por enquanto.
2. **Superpoder 2: Gamificação & Motivação**
   * *Pergunta:* "Quer incentivar seus alunos com ranking e metas?"
   * *Opções:* Ativar Ranking de Presença / Definir Meta Mensal de Treinos / Apenas Privado.
3. **Superpoder 3: Regras de Graduação & Faixas**
   * *Pergunta:* "Como funciona a evolução de faixas e graus dos alunos?"
   * *Opções:* Automática por presença / Manual pelo Mestre / Critério Misto (Presença + Técnicas).
4. **Superpoder 4: Módulos Extras (Multi-select)**
   * *Pergunta:* "Quais desses recursos você gostaria de deixar ativos?"
   * *Opções:* Loja da Academia, Galeria de Vídeos/Posições, Reserva de Vagas, Avaliação Física.

---

## 6. 💬 Skip UX & Central de Primeiros Passos

### Tratamento ao Pular
* Se o usuário clicar em *"Pular"* ou *"Configurar tudo mais tarde"* em qualquer tela:
  * Exibe diálogo amigável: *"Tudo bem! Você pode configurar cada detalhe quando quiser em **Configurações > Central de Primeiros Passos**."*
  * Direciona para o Dashboard com um banner sutil de retomada.

### Central de Primeiros Passos (Em `SettingsScreen`)
Permite reabrir e revisar módulos individualmente a qualquer momento:
1. 🥋 *Modalidades e Perfil do Espaço*
2. 💳 *Método de Pagamento & Chave PIX*
3. 📢 *Código de Convite & Compartilhar no WhatsApp*
4. 🏆 *Gamificação, Retenção & Superpoderes*
5. 🎓 *Simulador Interativo da Academia*
6. 🔄 *Refazer Quiz Completo*
