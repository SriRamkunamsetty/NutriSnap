class ValidationUtils {
  static String? validateWeight(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    final weight = double.tryParse(value);
    if (weight == null) return 'Invalid number';
    if (weight < 30 || weight > 300) return 'Range: 30-300kg';
    return null;
  }

  static String? validateHeight(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    final height = double.tryParse(value);
    if (height == null) return 'Invalid number';
    if (height < 100 || height > 250) return 'Range: 100-250cm';
    return null;
  }

  static String? validateAge(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    final age = int.tryParse(value);
    if (age == null) return 'Invalid number';
    if (age < 13 || age > 100) return 'Age: 13-100';
    return null;
  }

  static String? validateCalories(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    final cals = int.tryParse(value);
    if (cals == null) return 'Invalid';
    if (cals < 800 || cals > 8000) return 'Range: 800-8000';
    return null;
  }

  static String? validateMacro(String? value, String label, int min, int max) {
    if (value == null || value.isEmpty) return 'Required';
    final val = int.tryParse(value);
    if (val == null) return 'Invalid';
    if (val < min || val > max) return '\$label: \$min-\$max';
    return null;
  }
}
