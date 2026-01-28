/// App Constants
/// Constantes globais do aplicativo BJJEasy

class AppConstants {
  AppConstants._();

  // ===========================================
  // App Info
  // ===========================================
  static const String appName = 'BJJEasy';
  static const String appVersion = '1.0.0';

  // ===========================================
  // URLs - configured via dart-define at build time
  // flutter build appbundle --dart-define=APP_BASE_URL=https://bjjeasy.netlify.app
  // ===========================================
  static const String appBaseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: 'https://bjjeasy.netlify.app',
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://bjjeasy.netlify.app/api',
  );

  // ===========================================
  // Firebase Collections
  // ===========================================
  static const String academiesCollection = 'academies';
  static const String usersCollection = 'users';
  static const String studentsCollection = 'students';
  static const String classesCollection = 'classes';
  static const String attendanceCollection = 'attendance';
  static const String financialCollection = 'financial';
  static const String plansCollection = 'plans';
  static const String assessmentsCollection = 'assessments';
  static const String competitionsCollection = 'competitions';
  static const String enrollmentsCollection = 'enrollments';
  static const String resultsCollection = 'results';
  static const String achievementsCollection = 'achievements';
  static const String beltProgressionsCollection = 'beltProgressions';
  static const String linkCodesCollection = 'linkCodes';
  static const String notificationsCollection = 'notifications';
  static const String walletTransactionsCollection = 'walletTransactions';
  static const String storeProductsCollection = 'products';
  static const String storeOrdersCollection = 'orders';

  // ===========================================
  // Animation Durations
  // ===========================================
  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);

  // ===========================================
  // Pagination
  // ===========================================
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // ===========================================
  // Validation
  // ===========================================
  static const int minPasswordLength = 6;
  static const int maxNameLength = 100;
  static const int maxDescriptionLength = 500;

  // ===========================================
  // Date Formats
  // ===========================================
  static const String dateFormat = 'dd/MM/yyyy';
  static const String timeFormat = 'HH:mm';
  static const String dateTimeFormat = 'dd/MM/yyyy HH:mm';
  static const String monthYearFormat = 'MMMM yyyy';
  static const String shortDateFormat = 'dd/MM';

  // ===========================================
  // Currency
  // ===========================================
  static const String currencySymbol = 'R\$';
  static const String currencyCode = 'BRL';
  static const String currencyLocale = 'pt_BR';
}

/// Belt System Constants
class BeltConstants {
  BeltConstants._();

  // Adult Belts (in order)
  static const List<String> adultBelts = [
    'white',
    'blue',
    'purple',
    'brown',
    'black',
  ];

  // Kids Belts (in order)
  static const List<String> kidsBelts = [
    'white',
    'grey',
    'grey-white',
    'grey-black',
    'yellow',
    'yellow-white',
    'yellow-black',
    'orange',
    'orange-white',
    'orange-black',
    'green',
    'green-white',
    'green-black',
  ];

  // Belt Labels (Portuguese)
  static const Map<String, String> beltLabels = {
    'white': 'Branca',
    'blue': 'Azul',
    'purple': 'Roxa',
    'brown': 'Marrom',
    'black': 'Preta',
    'grey': 'Cinza',
    'grey-white': 'Cinza/Branca',
    'grey-black': 'Cinza/Preta',
    'yellow': 'Amarela',
    'yellow-white': 'Amarela/Branca',
    'yellow-black': 'Amarela/Preta',
    'orange': 'Laranja',
    'orange-white': 'Laranja/Branca',
    'orange-black': 'Laranja/Preta',
    'green': 'Verde',
    'green-white': 'Verde/Branca',
    'green-black': 'Verde/Preta',
  };

  // Max stripes per belt
  static const int maxStripes = 4;
}

/// Status Labels (Portuguese)
class StatusLabels {
  StatusLabels._();

  // Student Status
  static const Map<String, String> studentStatus = {
    'active': 'Ativo',
    'injured': 'Lesionado',
    'inactive': 'Inativo',
    'suspended': 'Suspenso',
  };

  // Payment Status
  static const Map<String, String> paymentStatus = {
    'paid': 'Pago',
    'pending': 'Pendente',
    'overdue': 'Atrasado',
    'cancelled': 'Cancelado',
  };

  // Payment Types
  static const Map<String, String> paymentTypes = {
    'monthly_tuition': 'Mensalidade',
    'uniform': 'Uniforme',
    'seminar': 'Seminario',
    'graduation': 'Graduacao',
    'competition': 'Competicao',
    'other': 'Outro',
  };

  // Payment Methods
  static const Map<String, String> paymentMethods = {
    'pix': 'PIX',
    'cash': 'Dinheiro',
    'credit_card': 'Cartao de Credito',
    'debit_card': 'Cartao de Debito',
    'bank_transfer': 'Transferencia',
  };

  // Competition Status
  static const Map<String, String> competitionStatus = {
    'upcoming': 'Em breve',
    'ongoing': 'Em andamento',
    'completed': 'Finalizado',
  };

  // Competition Positions
  static const Map<String, String> competitionPositions = {
    'gold': 'Ouro',
    'silver': 'Prata',
    'bronze': 'Bronze',
    'participant': 'Participante',
  };

  // Age Categories
  static const Map<String, String> ageCategories = {
    'kids': 'Infantil',
    'juvenile': 'Juvenil',
    'adult': 'Adulto',
    'master': 'Master',
  };

  // Transport Preferences
  static const Map<String, String> transportPreferences = {
    'need_transport': 'Precisa de transporte',
    'own_transport': 'Transporte proprio',
    'undecided': 'Ainda nao decidiu',
  };

  // Store Order Status
  static const Map<String, String> storeOrderStatus = {
    'pending_payment': 'Aguardando Pagamento',
    'paid': 'Pago',
    'preparing': 'Em Preparacao',
    'ready': 'Pronto para Retirada',
    'delivered': 'Entregue',
    'cancelled': 'Cancelado',
  };

  // Store Categories
  static const Map<String, String> storeCategories = {
    'uniform': 'Uniforme',
    'equipment': 'Equipamento',
    'accessory': 'Acessorio',
    'other': 'Outros',
  };
}

/// CBJJ Weight Categories
class WeightCategories {
  WeightCategories._();

  static const List<String> cbjj = [
    'Galo',
    'Pluma',
    'Pena',
    'Leve',
    'Medio',
    'Meio-Pesado',
    'Pesado',
    'Super-Pesado',
    'Pesadissimo',
    'Absoluto',
  ];
}

/// Day of Week Labels (Portuguese)
class DayOfWeekLabels {
  DayOfWeekLabels._();

  static const List<String> full = [
    'Domingo',
    'Segunda-feira',
    'Terca-feira',
    'Quarta-feira',
    'Quinta-feira',
    'Sexta-feira',
    'Sabado',
  ];

  static const List<String> short = [
    'Dom',
    'Seg',
    'Ter',
    'Qua',
    'Qui',
    'Sex',
    'Sab',
  ];

  static const List<String> abbreviated = [
    'D',
    'S',
    'T',
    'Q',
    'Q',
    'S',
    'S',
  ];
}
