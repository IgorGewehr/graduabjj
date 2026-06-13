import '../models/combo.dart';

/// Seed combinations offered when an academy bootstraps its striking library
/// (C2). Numbering follows the classic boxing notation (1=jab, 2=cross, 3=lead
/// hook, 4=rear hook, 5=lead uppercut, 6=rear uppercut). Muay Thai adds kicks/
/// knees/elbows. Staff can edit/extend afterwards.
List<Combo> comboTemplates({required String createdBy}) {
  Combo c(String sport, String level, int order, String name,
          List<String> strikes) =>
      Combo(
        id: '',
        name: name,
        sport: sport,
        level: level,
        strikes: strikes,
        order: order,
        createdBy: createdBy,
      );

  return [
    // --- Boxe ---
    c('boxing', 'iniciante', 1, '1-2', ['Jab', 'Direto']),
    c('boxing', 'iniciante', 2, '1-1-2', ['Jab', 'Jab', 'Direto']),
    c('boxing', 'iniciante', 3, '1-2-3', ['Jab', 'Direto', 'Cruzado de esquerda']),
    c('boxing', 'intermediario', 4, '1-2-3-2',
        ['Jab', 'Direto', 'Cruzado de esquerda', 'Direto']),
    c('boxing', 'intermediario', 5, '2-3-2',
        ['Direto', 'Cruzado de esquerda', 'Direto']),
    c('boxing', 'avancado', 6, '1-2-5-2',
        ['Jab', 'Direto', 'Uppercut de esquerda', 'Direto']),

    // --- Muay Thai ---
    c('muaythai', 'iniciante', 1, 'Jab + Low kick',
        ['Jab', 'Chute baixo (perna traseira)']),
    c('muaythai', 'iniciante', 2, '1-2 + Teep',
        ['Jab', 'Direto', 'Teep (empurrão frontal)']),
    c('muaythai', 'intermediario', 3, '1-2 + Middle kick',
        ['Jab', 'Direto', 'Chute médio (perna traseira)']),
    c('muaythai', 'intermediario', 4, 'Cotovelada de cima',
        ['Jab', 'Cotovelada diagonal']),
    c('muaythai', 'avancado', 5, 'Clinch + joelhada',
        ['Pescoçada (clinch)', 'Joelhada reta', 'Joelhada reta']),

    // --- Kickboxing ---
    c('kickboxing', 'iniciante', 1, 'Jab + Cross + Low',
        ['Jab', 'Direto', 'Chute baixo']),
    c('kickboxing', 'intermediario', 2, '1-2-3 + High kick',
        ['Jab', 'Direto', 'Cruzado', 'Chute alto']),
  ];
}
