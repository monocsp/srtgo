import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

part 'auth_repository_impl.g.dart';

@Riverpod(keepAlive: true)
AuthRepository authRepository(AuthRepositoryRef ref) {
  return AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider));
}

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _dataSource;

  AuthRepositoryImpl(this._dataSource);

  @override
  Future<User> login(String username, String password) async {
    final response = await _dataSource.login(username: username, password: password);
    final map = response.userMap;
    
    return User(
      membershipNumber: map['MB_CRD_NO'] ?? '',
      name: map['CUST_NM'] ?? '',
      phoneNumber: map['MBL_PHONE'] ?? '',
      email: map['EMAIL'] ?? '', // Assuming key, verify with actual API response dump if needed
    );
  }
}
