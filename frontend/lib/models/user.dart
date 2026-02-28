class User {
  final String id;
  final String email;
  final int age;
  final bool isAdmin;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.email,
    required this.age,
    this.isAdmin = false,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      age: json['age'] as int,
      isAdmin: json['isAdmin'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'age': age,
        'isAdmin': isAdmin,
        'createdAt': createdAt.toIso8601String(),
      };
}
