# Documentação essencial

Somente documentos que orientam operação atual ou são consumidos pelo produto
permanecem nesta pasta. O código e seus testes são a fonte de verdade para
contratos internos.

| Documento | Uso |
|---|---|
| [Pagamentos](arquitetura-pagamentos/README.md) | Arquitetura vigente dos links públicos e limites de plataforma. |
| [Runbook de pagamentos](arquitetura-pagamentos/10_RUNBOOK_RELEASE_PRODUCAO.md) | Canário, rollout, rollback e pendências de WhatsApp. |
| [Windows](WINDOWS.md) | Instalação e build do aplicativo de balcão. |
| [`functions/access_control/README.md`](../functions/access_control/README.md) | Referência operacional das catracas, mantida junto do código. |

`windows_version.json` é consumido por `lib/services/app_update_service.dart` e
não deve ser removido.
