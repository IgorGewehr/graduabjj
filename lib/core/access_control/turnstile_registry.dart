/// Registro ÚNICO de fabricantes de catraca suportados (lado Flutter).
///
/// Espelha o registry de adapters do backend
/// (functions/access_control/ingest.js ADAPTER_LOADERS + adapters/<id>.js).
/// O `id` AQUI deve ser IDÊNTICO ao key do adapter lá (controlid/zkteco/...),
/// pois é o `vendor` gravado em devices/{id}.vendor e usado no dispatch.
///
/// ============================================================================
/// COMO ADICIONAR UM NOVO FABRICANTE (passo a passo — fonte única de verdade):
///   1. Backend: criar functions/access_control/adapters/<novo>.js exportando
///      parse(req, device) -> AccessEvent (ver canonical.js + o README HOW-TO).
///   2. Backend: registrar o id em ADAPTER_LOADERS (functions/access_control/
///      ingest.js) e em VENDORS (canonical.js).
///   3. Flutter: adicionar UMA entrada [TurnstileVendor] na lista abaixo.
///   Nada mais muda na UI — o seletor de marca em Settings → Funcionalidades →
///   Catraca lê desta lista automaticamente.
/// ============================================================================
class TurnstileVendor {
  /// Identidade estável — IGUAL ao key do adapter no backend.
  final String id;

  /// Nome exibido ao admin.
  final String label;

  /// Resumo da integração (protocolo) para o admin/dev.
  final String integration;

  /// Suporta a arquitetura C (push HTTP direto para a Cloud Function)?
  final bool pushCloud;

  const TurnstileVendor({
    required this.id,
    required this.label,
    required this.integration,
    this.pushCloud = true,
  });
}

/// Fabricantes suportados. Mantenha em sincronia com o backend (ver doc acima).
const List<TurnstileVendor> kTurnstileVendors = [
  TurnstileVendor(
    id: 'controlid',
    label: 'Control iD',
    integration: 'iDAccess/iDBlock + iDFace — push HTTP em JSON',
  ),
  TurnstileVendor(
    id: 'zkteco',
    label: 'ZKTeco',
    integration: 'Push/ADMS protocol — POST em /iclock/cdata (key=value)',
  ),
  TurnstileVendor(
    id: 'intelbras',
    label: 'Intelbras',
    integration: 'Controle de acesso REST + facial embarcado',
  ),
];

/// Resolve um fabricante pelo id (null se desconhecido/vazio).
TurnstileVendor? turnstileVendorById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final v in kTurnstileVendors) {
    if (v.id == id) return v;
  }
  return null;
}
