/// Texto, em português do dia a dia, de cada momento da régua de cobrança —
/// o que o dono vê no editor de mensagens em vez das chaves internas
/// (`CREATED`, `D+7`...), que continuam sendo só o identificador salvo no
/// Firestore e nos mapas de template de `BillingNotificationService`.
class BillingStageCopy {
  /// Chave interna (a mesma de `BillingNotificationService.default*Templates`).
  final String key;

  /// Rótulo curto do chip.
  final String label;

  /// Dias de atraso usados só no EXEMPLO mostrado ao dono (negativo = ainda
  /// vai vencer em N dias). Alimenta {dias} e {diasAteVencimento}.
  final int sampleDaysOverdue;

  const BillingStageCopy(this.key, this.label, this.sampleDaysOverdue);
}

const List<BillingStageCopy> kBillingStageCopies = [
  BillingStageCopy('CREATED', 'Parcela criada', -10),
  BillingStageCopy('UPCOMING', 'A vencer', -3),
  BillingStageCopy('D+0', 'Vence hoje', 0),
  BillingStageCopy('D+1', 'Atraso 1–2 dias', 1),
  BillingStageCopy('D+3', 'Atraso 3–6 dias', 3),
  BillingStageCopy('D+7', 'Atraso 7–14 dias', 7),
  BillingStageCopy('D+15', 'Atraso 15–29 dias', 15),
  BillingStageCopy('D+30', 'Atraso 30+ dias', 30),
];

/// Variáveis que o dono pode usar nos textos de e-mail, explicadas em
/// português. `{dias}`/`{diasAteVencimento}` só fazem sentido em momentos de
/// atraso/antes do vencimento, respectivamente.
String billingTemplateVariablesHint(BillingStageCopy stage) {
  final base = '{nome} (aluno), {valor}, {vencimento} e {academia}';
  if (stage.sampleDaysOverdue > 0) {
    return '$base — e {dias} para os dias de atraso.';
  }
  if (stage.sampleDaysOverdue < 0) {
    return '$base — e {diasAteVencimento} para quantos dias faltam.';
  }
  return '$base.';
}
