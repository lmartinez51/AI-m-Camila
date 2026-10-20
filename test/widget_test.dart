import 'package:flutter_test/flutter_test.dart';
import 'package:aimcamila/models/user_model.dart';

void main() {
  group('UserModel Unit Tests', () {
    test('UserModel serializes and deserializes correctly', () {
      final user = UserModel(
        uid: 'user_123',
        email: 'test@example.com',
        name: 'Lorenzo',
        nickname: 'Boss',
        relationship: 'creator',
      );

      final json = user.toJson();
      expect(json['uid'], 'user_123');
      expect(json['email'], 'test@example.com');
      expect(json['name'], 'Lorenzo');

      final userFromJson = UserModel.fromJson(json);
      expect(userFromJson.uid, 'user_123');
      expect(userFromJson.email, 'test@example.com');
      expect(userFromJson.name, 'Lorenzo');
      expect(userFromJson.nickname, 'Boss');
      expect(userFromJson.relationship, 'creator');
    });
  });
}
