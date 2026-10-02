class PersonnelFamilyMember {
  const PersonnelFamilyMember({
    this.id,
    required this.name,
    required this.relation,
    this.birthDate,
    this.isDependent = false,
  });

  final String? id;
  final String name;
  final String relation;
  final DateTime? birthDate;
  final bool isDependent;

  int? ageOn([DateTime? reference]) {
    final birth = birthDate;
    if (birth == null) return null;
    final now = reference ?? DateTime.now();
    var age = now.year - birth.year;
    final birthdayPassed =
        now.month > birth.month ||
        (now.month == birth.month && now.day >= birth.day);
    if (!birthdayPassed) age--;
    return age < 0 ? null : age;
  }

  Map<String, dynamic> toJson() => {
        if (id != null && id!.isNotEmpty) 'id': id,
        'name': name.trim(),
        'relation': relation.trim(),
        'birth_date': birthDate == null ? null : _dbDate(birthDate!),
        'is_dependent': isDependent,
      };

  factory PersonnelFamilyMember.fromJson(Map<String, dynamic> json) {
    return PersonnelFamilyMember(
      id: json['id']?.toString(),
      name: json['name']?.toString() ?? '',
      relation: json['relation']?.toString() ?? '',
      birthDate: DateTime.tryParse(json['birth_date']?.toString() ?? ''),
      isDependent: json['is_dependent'] == true,
    );
  }

  static String _dbDate(DateTime value) =>
      value.year.toString().padLeft(4, '0') +
      '-' +
      value.month.toString().padLeft(2, '0') +
      '-' +
      value.day.toString().padLeft(2, '0');
}

class EditableFamilyMember {
  EditableFamilyMember({
    String name = '',
    String relation = '',
    DateTime? birthDate,
    bool isDependent = false,
  })  : name = name,
        relation = relation,
        birthDate = birthDate,
        isDependent = isDependent;

  String name;
  String relation;
  DateTime? birthDate;
  bool isDependent;

  PersonnelFamilyMember toValue() => PersonnelFamilyMember(
        name: name,
        relation: relation,
        birthDate: birthDate,
        isDependent: isDependent,
      );

  factory EditableFamilyMember.fromValue(PersonnelFamilyMember value) =>
      EditableFamilyMember(
        name: value.name,
        relation: value.relation,
        birthDate: value.birthDate,
        isDependent: value.isDependent,
      );
}
