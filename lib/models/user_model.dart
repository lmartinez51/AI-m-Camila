class UserModel {
  final String uid;
  final String email;
  final String name;
  String? gender;
  String? personalBackground;
  String? nickname;
  String? interests;
  String? phoneNumber;
  String? relationship;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    this.gender,
    this.personalBackground,
    this.nickname,
    this.interests,
    this.phoneNumber,
    this.relationship,
  });

  // Convertir UserModel a JSON
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'gender': gender,
      'personalBackground': personalBackground,
      'nickname': nickname,
      'interests': interests,
      'phoneNumber': phoneNumber,
      'relationship': relationship,
    };
  }

  // Crear UserModel desde JSON
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'],
      email: json['email'],
      name: json['name'],
      gender: json['gender'] is List ? (json['gender'] as List).join(', ') : json['gender'],
      personalBackground: json['personalBackground'] is List ? (json['personalBackground'] as List).join(', ') : json['personalBackground'],
      nickname: json['nickname'] is List ? (json['nickname'] as List).join(', ') : json['nickname'],
      interests: json['interests'] is List ? (json['interests'] as List).join(', ') : json['interests'],
      phoneNumber: json['phoneNumber'] is List ? (json['phoneNumber'] as List).join(', ') : json['phoneNumber'],
      relationship: json['relationship'] is List ? (json['relationship'] as List).join(', ') : json['relationship'],
    );
  }
}
