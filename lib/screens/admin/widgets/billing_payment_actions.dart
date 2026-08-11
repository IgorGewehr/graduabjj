import 'package:flutter/material.dart';

/// Organiza as ações de uma cobrança sem estourar a largura do card.
///
/// O botão principal ocupa toda a largura e os atalhos ficam abaixo, mantendo
/// todos os cards consistentes mesmo quando algum aluno não possui e-mail.
class BillingPaymentActions extends StatelessWidget {
  const BillingPaymentActions({
    super.key,
    this.primaryAction,
    this.emailAction,
    this.secondaryActions = const [],
  });

  final Widget? primaryAction;
  final Widget? emailAction;
  final List<Widget> secondaryActions;

  @override
  Widget build(BuildContext context) {
    final iconActions = <Widget>[
      if (emailAction != null) emailAction!,
      ...secondaryActions,
    ];

    if (primaryAction == null) {
      return _iconWrap(iconActions);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: double.infinity, child: primaryAction),
        if (iconActions.isNotEmpty) ...[
          const SizedBox(height: 4),
          _iconWrap(iconActions),
        ],
      ],
    );
  }

  Widget _iconWrap(List<Widget> actions) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 0,
      runSpacing: 4,
      children: actions,
    );
  }
}
