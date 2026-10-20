import 'package:integration_test/integration_test.dart';

import '../test/recipe_builder_quick_plant_test.dart' as acceptance;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  acceptance.main();
}
