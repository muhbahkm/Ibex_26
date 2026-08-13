import '../core/errors/domain_error.dart';

class AgentCommandRegistry {
  const AgentCommandRegistry(this.allowedCommands);

  final Set<String> allowedCommands;

  void requireRegistered(String commandName) {
    final normalized = commandName.trim();
    if (normalized.isEmpty || !allowedCommands.contains(normalized)) {
      throw const DomainError(
        'AGENT_COMMAND_NOT_REGISTERED',
        'Agent may invoke only registered application commands.',
      );
    }
  }
}
