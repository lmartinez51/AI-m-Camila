import 'package:aimcamila/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class UserProvider with ChangeNotifier {
  UserModel? _user;
  List<UserModel> _additionalUsers = [];

  UserModel? get user => _user;
  List<UserModel> get additionalUsers => _additionalUsers;
  // Método para devolver un UserModel vacío UserModel
  UserModel get emptyUser => UserModel(uid: '', email: '', name: '', nickname: '');

  // Método para establecer el usuario
  void setUser(UserModel user) {
    _user = user;
    notifyListeners();
    _saveUserToPrefs(); // Guardar en SharedPreferences
  }

  // Método para limpiar el usuario
  void clearUser() {
    _user = null;
    notifyListeners();
    _clearUserFromPrefs(); // Limpiar de SharedPreferences
  }

  // Guardar el usuario en SharedPreferences
  Future<void> _saveUserToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    String userJson = jsonEncode(_user?.toJson()); // Convertir a JSON
    await prefs.setString('user', userJson);
  }

  // Cargar el usuario desde SharedPreferences
  Future<void> loadUserFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    String? userJson = prefs.getString('user');
    if (userJson != null) {
      Map<String, dynamic> userMap = jsonDecode(userJson);
      _user = UserModel.fromJson(userMap); // Crear el modelo desde JSON
      notifyListeners();
    }
  }

  // Limpiar el usuario de SharedPreferences
  Future<void> _clearUserFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
  }

  void addAdditionalUser(UserModel user) {
    _additionalUsers.add(user);
    notifyListeners();
    _saveAdditionalUsersToPrefs(); // Guardar en SharedPreferences
  }

  Future<void> _saveAdditionalUsersToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> usersJsonList =
        _additionalUsers.map((user) => jsonEncode(user.toJson())).toList();
    await prefs.setStringList('additionalUsers', usersJsonList);
  }

  Future<void> loadAdditionalUsersFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? usersJsonList = prefs.getStringList('additionalUsers');
    if (usersJsonList != null) {
      _additionalUsers = usersJsonList
          .map((userJson) => UserModel.fromJson(jsonDecode(userJson)))
          .toList();
      notifyListeners();
    }
  }

  // Método para buscar un usuario por nickname o nombre en la lista de usuarios adicionales
  UserModel findUserByNicknameOrName(String keyword) {
    return _additionalUsers.firstWhere(
      (user) => user.nickname == keyword || user.name == keyword,
      orElse: () => emptyUser,
    );
  }
}
