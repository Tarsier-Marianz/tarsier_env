import 'dart:io';

import 'package:tarsier_env/src/tarsier_env_base.dart';

/// Entry point for the `tarsier_env` command-line tool.
///
/// This tool provides commands to manage `.env` files and
/// automatically integrate them into your Flutter project.
///
/// Usage:
/// ```sh
/// dart run tarsier_env <command>
/// ```
///
/// Available commands:
/// - `generate`: Generates `env.dart` from the `.env` file and updates `main.dart`.
/// - `new`: Creates a default `.env` file and adds it to `.gitignore`.
void main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    return;
  }

  switch (args[0]) {
    case 'generate':
      String outputFilename = await _generateEnvFileCommand(args.skip(1).toList());
      await _updateMainDartWithEnv(outputFilename);
      await _addToGitignore('.env');
      break;
    case 'new':
      await _createNewEnvFile();
      await _addToGitignore('.env');
      break;
    default:
      print('Unknown command: ${args[0]}');
      _printUsage();
  }
}

/// Prints the usage guide for the `tarsier_env` CLI tool.
void _printUsage() {
  print('Usage: dart run tarsier_env:<command>');
  print('');
  print('Commands:');
  print('  generate    Generate env.dart from .env file.');
  print('  new         Create a default .env file.');
}

/// Generates `env.dart` from `.env` file.
///
/// This command reads environment variables from a `.env` file and generates
/// a Dart file that defines constants for each variable.
///
/// - [args]: Optional arguments specifying the output folder for `env.dart`.
Future<String> _generateEnvFileCommand(List<String> args) async {
  const inputFileName = '.env'; // Default .env file name
  const defaultMainFilePath = 'lib/main.dart'; // Default location of main.dart
  final defaultOutputFileName = 'env.dart'; // Default file name for generated env.dart

  // Determine output folder
  String outputFolderPath;
  if (args.isEmpty) {
    // If no argument is provided, use the location of main.dart
    final mainFile = File(defaultMainFilePath);
    if (!await mainFile.exists()) {
      throw Exception('main.dart not found at $defaultMainFilePath. '
          'Please provide a path as an argument.');
    }
    outputFolderPath = File(defaultMainFilePath).parent.path;
  } else {
    // Use the custom folder provided as an argument
    outputFolderPath = 'lib/${args[0]}';
  }

  final outputFileName = '$outputFolderPath/$defaultOutputFileName';

  // Ensure the output directory exists
  await _ensureDirectoryExists(outputFolderPath);

  // Load and parse the .env file
  final envVars = await loadEnvFile(inputFileName);

  // Generate the Dart file
  await _generateEnvFile(outputFileName, envVars);

  print('Successfully generated $outputFileName from $inputFileName');
  return outputFileName.replaceAll("lib/", "");
}

/// Generates a Dart file with getters for environment variables.
///
/// The generated file contains a static `Map<String, String>` with the parsed
/// variables, and a getter for each variable that retrieves its value from the map.
///
/// - [outputFileName]: The path where the Dart file will be created.
/// - [envVars]: A `Map<String, String>` containing the parsed environment variables.
Future<void> _generateEnvFile(String outputFileName, Map<String, String> envVars,
    {bool addValueOnMapVariables = false}) async {
  final buffer = StringBuffer();

  // Generate the Dart file content
  buffer.writeln('// AUTO-GENERATED FILE. DO NOT EDIT.');
  buffer.writeln('// Generated by tarsier_env script.');
  buffer.writeln('import \'dart:collection\';');
  buffer.writeln('import \'package:tarsier_env/tarsier_env.dart\';\n');
  buffer.writeln('/// A class to access environment variables.');
  buffer.writeln('///');
  buffer.writeln('/// Environment variables are stored in a static map and can be accessed using getters.');

  buffer.writeln('class Env {');
  buffer.writeln('  static Map<String, String> _variables = {};\n');

  // Add environment variables to the map
  if (addValueOnMapVariables) {
    envVars.forEach((key, value) {
      buffer.writeln('    \'$key\': \'$value\',');
    });
    buffer.writeln('  };\n');
  }

  buffer.writeln('  // This function must be called in the main function to');
  buffer.writeln('  // initialize first all environment variables');
  buffer.writeln('  static init() async {');
  buffer.writeln('    _variables = await loadEnvFile(\'.env\');');
  buffer.writeln('  }\n');

  buffer.writeln('  static Map<String, String> get vars => _variables;');
  // Generate getters
  envVars.forEach((key, _) {
    final getterName = _toCamelCase(key);
    buffer.writeln('  static String? get $getterName => _variables[\'$key\'];');
  });

  buffer.writeln('}\n');

  // Write to the output file
  final file = File(outputFileName);
  if (await file.exists()) {
    await file.delete(); // Delete the existing file
  }
  await file.writeAsString(buffer.toString());
}

/// Creates a default `.env` file with boilerplate content.
///
/// If a `.env` file already exists, no changes are made.
Future<void> _createNewEnvFile() async {
  const envFileName = '.env';

  // Check if the `.env` file already exists
  final envFile = File(envFileName);
  if (await envFile.exists()) {
    print('The .env file already exists.');
    return;
  }

  // Get the project folder name for `APP_NAME`
  final projectFolderName =
      Directory.current.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty, orElse: () => 'unknown_project');

  // Default content for the `.env` file
  const defaultEnvContent = '''
# AUTO-GENERATED FILE. 
# YOU CAN EDIT/ADD MORE KEYS AND ITS VALUE.
# Generated by tarsier_env script.

APP_NAME="<app name>"
APP_ENV=local
APP_KEY=null
APP_DEBUG=true
APP_URL=http://localhost

# REDIS configuration
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

# Email configuration
MAIL_DRIVER=smtp
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=bonfire.dev@gmail.com
MAIL_PASSWORD=null
MAIL_ENCRYPTION=tls

# AWS configuration
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=

# Configuration for Pusher
PUSHER_APP_ID=
PUSHER_APP_KEY=
PUSHER_APP_SECRET=
PUSHER_APP_CLUSTER=eu
''';
  final content = defaultEnvContent.replaceFirst('<app name>', projectFolderName);

  // Write the default content to the `.env` file
  await envFile.writeAsString(content);
  print('Created .env file with default content.');
}

/// Adds the given file name to `.gitignore` if not already present.
///
/// - [fileName]: The file name to add, typically `.env`.
Future<void> _addToGitignore(String fileName) async {
  const gitignorePath = '.gitignore';

  final gitignoreFile = File(gitignorePath);
  if (!await gitignoreFile.exists()) {
    print('$gitignorePath not found. Creating a new one.');
    await gitignoreFile.writeAsString('$fileName\n');
    print('Added $fileName to $gitignoreFile.');
    return;
  }

  final lines = await gitignoreFile.readAsLines();
  if (!lines.contains(fileName)) {
    await gitignoreFile.writeAsString('$fileName\n', mode: FileMode.append);
    print('Added $fileName to $gitignoreFile.');
  } else {
    print('$fileName is already in $gitignoreFile.');
  }
}

/// Inserts `Env.init()` and imports the dynamically generated `env.dart` into `main.dart`.
///
/// This method ensures that:
/// 1. The `env.dart` file is imported with the correct path.
/// 2. The `Env.init()` method is called inside the existing main() function.
///
/// - If no arguments are provided during the generation, the import will be `import 'env.dart';`
/// - If the generation uses a path like `common/environment`, the import will be `import 'common/environment/env.dart';`
Future<void> _updateMainDartWithEnv(String generatedEnvPath) async {
  // Construct the import path relative to the `main.dart` file
  final importPath = generatedEnvPath.endsWith('env.dart')
      ? generatedEnvPath
      : '$generatedEnvPath/env.dart';

  const envInitCall = 'await Env.init();';

  final mainFilePath = 'lib/main.dart';
  final mainFile = File(mainFilePath);
  if (!await mainFile.exists()) {
    print('$mainFilePath not found. Skipping Env.init() insertion.');
    return;
  }

  final lines = await mainFile.readAsLines();
  bool hasImport = false;
  bool hasEnvInit = false;
  bool hasMainFunction = false;
  final buffer = StringBuffer();
  bool importInserted = false;

  // Loop through each line to analyze and modify the content.
  for (var line in lines) {
    // Check if the import statement for env.dart already exists
    if (line.contains("import '$importPath';")) {
      hasImport = true;
    }

    // Check if Env.init() has already been added in the main function
    if (line.contains(envInitCall)) {
      hasEnvInit = true;
    }

    // Check for the main function to insert Env.init() inside it
    if (line.contains(' main(')) {
      hasMainFunction = true;
    }

    // Add the import statement for env.dart if not already present
    if (!hasImport && line.startsWith('import ') && !importInserted) {
      buffer.writeln("import '$importPath';");
      importInserted = true;  // Prevent inserting multiple times
    }

    // Add the line to the buffer
    buffer.writeln(line);

    // If the main function is found and Env.init() is not present, insert it.
    if (hasMainFunction && !hasEnvInit && line.contains(' main(')) {
      buffer.writeln('  $envInitCall'); // Add Env.init() inside the main function.
      hasEnvInit = true;
    }
  }

  // If the import statement was never added and the first line is not an import, insert it.
  if (!importInserted && !hasImport) {
    buffer.writeln("import '$importPath';");
  }

  // If the main function does not exist, log a warning and do not create a new one
  if (!hasMainFunction) {
    print('Warning: main function not found in $mainFilePath. Skipping Env.init() insertion.');
  } else {
    // Write back the modified content
    await mainFile.writeAsString(buffer.toString());
    print('Updated main.dart with Env.init() and import for $importPath');
  }
}

/// Ensures that the specified directory exists.
///
/// Creates the directory recursively if it does not already exist.
///
/// - [folderPath]: The path of the directory to check or create.
Future<void> _ensureDirectoryExists(String folderPath) async {
  final directory = Directory(folderPath);
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
}

/// Converts a string to camelCase for Dart property names.
///
/// - [key]: The key to convert.
/// Returns a camelCase version of the key.
String _toCamelCase(String key) {
  return key.toLowerCase().replaceAllMapped(RegExp(r'(_[a-z])'), (match) => match.group(0)!.substring(1).toUpperCase());
}
