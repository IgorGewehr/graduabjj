/// Starter curriculum templates — seed opcional que a academia edita depois.
/// `order` é atribuído pelo índice dentro da faixa ao semear.
class SyllabusSeedItem {
  final String gradeId;
  final String category;
  final String name;
  const SyllabusSeedItem(this.gradeId, this.category, this.name);
}

/// Currículo básico de BJJ (faixa branca + azul). Curado e enxuto — ponto de
/// partida, não exaustivo.
const List<SyllabusSeedItem> bjjStarterTemplate = [
  // Faixa branca — fundamentos
  SyllabusSeedItem('white', 'Fundamentos', 'Quedas e amortecimento (ukemi)'),
  SyllabusSeedItem('white', 'Fundamentos', 'Fuga de quadril e upa'),
  SyllabusSeedItem('white', 'Guarda fechada', 'Postura e pegadas na guarda'),
  SyllabusSeedItem('white', 'Finalização', 'Armlock da guarda fechada'),
  SyllabusSeedItem('white', 'Finalização', 'Triângulo da guarda'),
  SyllabusSeedItem('white', 'Finalização', 'Kimura da guarda'),
  SyllabusSeedItem('white', 'Raspagem', 'Raspagem de gancho (flower sweep)'),
  SyllabusSeedItem('white', 'Passagem', 'Passagem de guarda ajoelhado'),
  SyllabusSeedItem('white', 'Controle', '100 kg (side control) e estabilização'),
  SyllabusSeedItem('white', 'Montada', 'Montada: estabilização e americana'),
  SyllabusSeedItem('white', 'Costas', 'Mata-leão pelas costas'),
  SyllabusSeedItem('white', 'Defesa', 'Defesa de mata-leão'),
  // Faixa azul
  SyllabusSeedItem('blue', 'Passagem', 'Passagem toreando'),
  SyllabusSeedItem('blue', 'Meia-guarda', 'Raspagem de meia-guarda'),
  SyllabusSeedItem('blue', 'Guarda', 'Berimbolo básico'),
  SyllabusSeedItem('blue', 'Finalização', 'Omoplata'),
  SyllabusSeedItem('blue', 'Finalização', 'Estrangulamento cruzado'),
];
