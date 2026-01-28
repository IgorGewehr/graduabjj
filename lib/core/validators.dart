/// Input validators for forms
class Validators {
  Validators._();

  /// Validate CPF format (000.000.000-00)
  static String? cpf(String? value) {
    if (value == null || value.isEmpty) {
      return 'CPF obrigatorio';
    }

    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length != 11) {
      return 'CPF invalido';
    }

    // Validate CPF algorithm
    if (!_isValidCpf(digitsOnly)) {
      return 'CPF invalido';
    }

    return null;
  }

  /// Validate CNPJ format (00.000.000/0000-00)
  static String? cnpj(String? value) {
    if (value == null || value.isEmpty) {
      return 'CNPJ obrigatorio';
    }

    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length != 14) {
      return 'CNPJ invalido';
    }

    // Validate CNPJ algorithm
    if (!_isValidCnpj(digitsOnly)) {
      return 'CNPJ invalido';
    }

    return null;
  }

  /// Validate email format
  static String? email(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email obrigatorio';
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(value)) {
      return 'Email invalido';
    }

    return null;
  }

  /// Validate phone format (Brazilian)
  static String? phone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Telefone obrigatorio';
    }

    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');

    // Brazilian phone: 10-11 digits (with area code)
    if (digitsOnly.length < 10 || digitsOnly.length > 11) {
      return 'Telefone invalido';
    }

    return null;
  }

  /// Validate PIX key based on type
  static String? pixKey(String? value, String pixKeyType) {
    if (value == null || value.isEmpty) {
      return 'Chave PIX obrigatoria';
    }

    switch (pixKeyType) {
      case 'cpf':
        return cpf(value);
      case 'cnpj':
        return cnpj(value);
      case 'email':
        return email(value);
      case 'phone':
        return phone(value);
      case 'random':
        // Random key is a UUID-like string
        if (value.length < 32) {
          return 'Chave aleatoria invalida';
        }
        return null;
      default:
        return 'Tipo de chave invalido';
    }
  }

  /// Validate card number using Luhn algorithm
  static String? cardNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Numero do cartao obrigatorio';
    }

    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 13 || digitsOnly.length > 19) {
      return 'Numero do cartao invalido';
    }

    if (!_isValidLuhn(digitsOnly)) {
      return 'Numero do cartao invalido';
    }

    return null;
  }

  /// Validate card expiration date (MM/YY)
  static String? cardExpiration(String? value) {
    if (value == null || value.isEmpty) {
      return 'Validade obrigatoria';
    }

    final parts = value.split('/');
    if (parts.length != 2) {
      return 'Formato invalido (MM/AA)';
    }

    final month = int.tryParse(parts[0]);
    final year = int.tryParse(parts[1]);

    if (month == null || year == null) {
      return 'Validade invalida';
    }

    if (month < 1 || month > 12) {
      return 'Mes invalido';
    }

    final now = DateTime.now();
    final currentYear = now.year % 100;
    final currentMonth = now.month;

    if (year < currentYear || (year == currentYear && month < currentMonth)) {
      return 'Cartao expirado';
    }

    return null;
  }

  /// Validate CVV (3-4 digits)
  static String? cvv(String? value) {
    if (value == null || value.isEmpty) {
      return 'CVV obrigatorio';
    }

    if (value.length < 3 || value.length > 4) {
      return 'CVV invalido';
    }

    if (!RegExp(r'^\d+$').hasMatch(value)) {
      return 'CVV invalido';
    }

    return null;
  }

  /// Validate required field
  static String? required(String? value, [String fieldName = 'Campo']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName obrigatorio';
    }
    return null;
  }

  /// Validate minimum length
  static String? minLength(String? value, int minLength, [String fieldName = 'Campo']) {
    if (value == null || value.length < minLength) {
      return '$fieldName deve ter no minimo $minLength caracteres';
    }
    return null;
  }

  /// Validate monetary amount
  static String? amount(String? value, {double? min, double? max}) {
    if (value == null || value.isEmpty) {
      return 'Valor obrigatorio';
    }

    final cleanValue = value.replaceAll(RegExp(r'[^\d,.]'), '');
    final normalized = cleanValue.replaceAll(',', '.');
    final amount = double.tryParse(normalized);

    if (amount == null) {
      return 'Valor invalido';
    }

    if (min != null && amount < min) {
      return 'Valor minimo: R\$ ${min.toStringAsFixed(2)}';
    }

    if (max != null && amount > max) {
      return 'Valor maximo: R\$ ${max.toStringAsFixed(2)}';
    }

    return null;
  }

  // ============================================
  // Private helper methods
  // ============================================

  static bool _isValidCpf(String cpf) {
    // Check if all digits are the same
    if (RegExp(r'^(\d)\1*$').hasMatch(cpf)) return false;

    // Validate first check digit
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      sum += int.parse(cpf[i]) * (10 - i);
    }
    var firstCheck = (sum * 10) % 11;
    if (firstCheck == 10) firstCheck = 0;
    if (firstCheck != int.parse(cpf[9])) return false;

    // Validate second check digit
    sum = 0;
    for (var i = 0; i < 10; i++) {
      sum += int.parse(cpf[i]) * (11 - i);
    }
    var secondCheck = (sum * 10) % 11;
    if (secondCheck == 10) secondCheck = 0;
    if (secondCheck != int.parse(cpf[10])) return false;

    return true;
  }

  static bool _isValidCnpj(String cnpj) {
    // Check if all digits are the same
    if (RegExp(r'^(\d)\1*$').hasMatch(cnpj)) return false;

    // Validate first check digit
    final weights1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(cnpj[i]) * weights1[i];
    }
    var firstCheck = sum % 11;
    firstCheck = firstCheck < 2 ? 0 : 11 - firstCheck;
    if (firstCheck != int.parse(cnpj[12])) return false;

    // Validate second check digit
    final weights2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    sum = 0;
    for (var i = 0; i < 13; i++) {
      sum += int.parse(cnpj[i]) * weights2[i];
    }
    var secondCheck = sum % 11;
    secondCheck = secondCheck < 2 ? 0 : 11 - secondCheck;
    if (secondCheck != int.parse(cnpj[13])) return false;

    return true;
  }

  static bool _isValidLuhn(String number) {
    var sum = 0;
    var isEven = false;

    for (var i = number.length - 1; i >= 0; i--) {
      var digit = int.parse(number[i]);

      if (isEven) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }

      sum += digit;
      isEven = !isEven;
    }

    return sum % 10 == 0;
  }
}
