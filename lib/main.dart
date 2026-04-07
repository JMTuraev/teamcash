import 'package:teamcash/app/bootstrap/bootstrap.dart';

Future<void> main() async {
  await bootstrap();
}

Future<void> mainWithOverrides({required List overrides}) async {
  await bootstrap(overrides: overrides);
}
