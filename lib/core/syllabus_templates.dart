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

/// Currículo básico de **Karatê** (E4) — biblioteca de katas + kihon/kumite por
/// faixa (progressão estilo Shotokan). Curado, editável. As faixas seguem
/// `_karateGrades` (white..black).
const List<SyllabusSeedItem> karateStarterTemplate = [
  // Branca
  SyllabusSeedItem('white', 'Kihon', 'Posições (zenkutsu, kiba dachi)'),
  SyllabusSeedItem('white', 'Kihon', 'Soco (oi-zuki) e defesa (gedan barai)'),
  SyllabusSeedItem('white', 'Kata', 'Taikyoku Shodan'),
  // Amarela
  SyllabusSeedItem('yellow', 'Kata', 'Heian Shodan'),
  SyllabusSeedItem('yellow', 'Kumite', 'Gohon kumite (5 passos)'),
  // Laranja
  SyllabusSeedItem('orange', 'Kata', 'Heian Nidan'),
  // Verde
  SyllabusSeedItem('green', 'Kata', 'Heian Sandan'),
  SyllabusSeedItem('green', 'Kumite', 'Kihon ippon kumite (1 passo)'),
  // Azul
  SyllabusSeedItem('blue', 'Kata', 'Heian Yondan'),
  // Roxa
  SyllabusSeedItem('purple', 'Kata', 'Heian Godan'),
  SyllabusSeedItem('purple', 'Kata', 'Tekki Shodan'),
  // Marrom
  SyllabusSeedItem('brown', 'Kata', 'Bassai Dai'),
  SyllabusSeedItem('brown', 'Kumite', 'Jiyu ippon kumite'),
  // Preta
  SyllabusSeedItem('black', 'Kata', 'Kanku Dai'),
  SyllabusSeedItem('black', 'Kumite', 'Jiyu kumite (combate livre)'),
];

/// Currículo básico de **Judô** (E5) — nage-waza / katame-waza / ukemi por grau
/// (progressão estilo Gokyo). Curado, editável. Faixas seguem `_judoGrades`.
const List<SyllabusSeedItem> judoStarterTemplate = [
  // Branca
  SyllabusSeedItem('white', 'Ukemi', 'Amortecimentos (mae/ushiro/yoko ukemi)'),
  SyllabusSeedItem('white', 'Nage-waza', 'O-soto-gari'),
  SyllabusSeedItem('white', 'Nage-waza', 'O-goshi'),
  SyllabusSeedItem('white', 'Katame-waza', 'Kesa-gatame'),
  // Cinza
  SyllabusSeedItem('grey', 'Nage-waza', 'De-ashi-barai'),
  SyllabusSeedItem('grey', 'Nage-waza', 'Ippon-seoi-nage'),
  SyllabusSeedItem('grey', 'Katame-waza', 'Kata-gatame'),
  // Azul
  SyllabusSeedItem('blue', 'Nage-waza', 'Tai-otoshi'),
  SyllabusSeedItem('blue', 'Katame-waza', 'Yoko-shiho-gatame'),
  // Amarela
  SyllabusSeedItem('yellow', 'Nage-waza', 'Harai-goshi'),
  SyllabusSeedItem('yellow', 'Nage-waza', 'Uchi-mata'),
  // Laranja
  SyllabusSeedItem('orange', 'Katame-waza', 'Kami-shiho-gatame'),
  SyllabusSeedItem('orange', 'Nage-waza', 'Tsuri-komi-goshi'),
  // Verde
  SyllabusSeedItem('green', 'Katame-waza', 'Juji-gatame (chave de braço)'),
  SyllabusSeedItem('green', 'Nage-waza', 'Sumi-gaeshi'),
  // Marrom
  SyllabusSeedItem('brown', 'Katame-waza', 'Shime-waza (estrangulamentos)'),
  // Preta
  SyllabusSeedItem('black', 'Kata', 'Nage-no-kata'),
];

/// Template inicial para um esporte, ou null se não houver (BJJ/Karatê/Judô).
/// A chave é o `SportId.value`.
List<SyllabusSeedItem>? syllabusTemplateFor(String sportValue) {
  switch (sportValue) {
    case 'bjj':
      return bjjStarterTemplate;
    case 'karate':
      return karateStarterTemplate;
    case 'judo':
      return judoStarterTemplate;
    default:
      return null;
  }
}
